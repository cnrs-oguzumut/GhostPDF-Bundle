import SwiftUI
import UniformTypeIdentifiers
import AppKit
import PDFKit

struct MergeThumbnailView: View {
    @Binding var files: [ContentView.PDFFile]
    @State private var draggingItem: ContentView.PDFFile?
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))]) {
                ForEach(files) { file in
                    VStack {
                        if let thumb = file.thumbnailURL, let image = NSImage(contentsOf: thumb) {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 140)
                                .cornerRadius(8)
                                .shadow(radius: 2)
                        } else {
                            ZStack {
                                Rectangle().fill(Color.gray.opacity(0.3))
                                Image(systemName: "doc.text")
                                    .font(.largeTitle)
                            }
                            .frame(height: 140)
                            .cornerRadius(8)
                        }
                        Text(file.url.lastPathComponent)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(8)
                    .background(draggingItem == file ? Color.blue.opacity(0.3) : Color.clear)
                    .cornerRadius(8)
                    .onDrag {
                        self.draggingItem = file
                        return NSItemProvider(object: file.id.uuidString as NSString)
                    }
                    .onDrop(of: [.text], delegate: DragRelocateDelegate(item: file, listData: $files, current: $draggingItem))
                }
            }
            .padding()
        }
    }
}

struct DragRelocateDelegate: DropDelegate {
    let item: ContentView.PDFFile
    @Binding var listData: [ContentView.PDFFile]
    @Binding var current: ContentView.PDFFile?
    
    func dropEntered(info: DropInfo) {
        if let current = current, current != item {
            let from = listData.firstIndex(of: current)!
            let to = listData.firstIndex(of: item)!
            if listData[to].id != current.id {
                withAnimation {
                    listData.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
                }
            }
        }
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
    
    func performDrop(info: DropInfo) -> Bool {
        self.current = nil
        return true
    }
}

struct SplitThumbnailView: View {
    let thumbnails: [URL]
    @Binding var selectedPages: Set<Int> // 1-based index
    let multiSelect: Bool
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))]) {
                ForEach(Array(thumbnails.enumerated()), id: \.offset) { index, url in
                    let pageNum = index + 1
                    let isSelected = selectedPages.contains(pageNum)
                    
                    VStack {
                        if let image = NSImage(contentsOf: url) {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 120)
                                .cornerRadius(4)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
                                )
                        }
                        Text("Page \(pageNum)")
                            .font(.caption)
                    }
                    .opacity(isSelected ? 1.0 : 0.8)
                    .onTapGesture {
                        if multiSelect {
                            if isSelected {
                                selectedPages.remove(pageNum)
                            } else {
                                selectedPages.insert(pageNum)
                            }
                        } else {
                            selectedPages = [pageNum]
                        }
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - Reorder Thumbnails using PDFKit (Faster, no GS dependency for UI)

struct ReorderablePage: Identifiable, Equatable {
    let id: Int // originalIndex
    let originalIndex: Int
    let page: PDFPage
    
    static func == (lhs: ReorderablePage, rhs: ReorderablePage) -> Bool {
        lhs.id == rhs.id
    }
}

struct ReorderThumbnailView: View {
    let pdfURL: URL
    @Binding var pageOrder: [Int]
    @State private var pdfDocument: PDFDocument?
    @State private var pages: [ReorderablePage] = []
    @State private var draggingItem: ReorderablePage?
    
    var body: some View {
        ScrollView {
            if pages.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading PDF...")
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))]) {
                    ForEach(pages) { page in
                        reorderPageCell(page: page)
                    }
                }
                .padding()
            }
        }
        .onAppear {
            initializePDF()
        }
    }
    
    @ViewBuilder
    private func reorderPageCell(page: ReorderablePage) -> some View {
        let isDragging = draggingItem?.id == page.id
        
        VStack {
            Image(nsImage: page.page.thumbnail(of: CGSize(width: 200, height: 200), for: .mediaBox))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 120)
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isDragging ? Color.blue : Color.gray.opacity(0.5), lineWidth: isDragging ? 3 : 1)
                )
            
            Text("Page \(page.originalIndex)")
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(4)
        .background(isDragging ? Color.blue.opacity(0.2) : Color.clear)
        .cornerRadius(8)
        .onDrag {
            self.draggingItem = page
            return NSItemProvider(object: String(page.originalIndex) as NSString)
        }
        .onDrop(of: [.text], delegate: PageReorderDelegate(item: page, pages: $pages, current: $draggingItem, pageOrder: $pageOrder))
    }
    
    private func initializePDF() {
        guard let doc = PDFDocument(url: pdfURL) else { return }
        self.pdfDocument = doc
        
        var newPages: [ReorderablePage] = []
        for i in 0..<doc.pageCount {
            if let page = doc.page(at: i) {
                newPages.append(ReorderablePage(id: i + 1, originalIndex: i + 1, page: page))
            }
        }
        
        // Respect existing pageOrder if valid
        if !pageOrder.isEmpty && pageOrder.count == newPages.count {
             var ordered: [ReorderablePage] = []
             for index in pageOrder {
                 if let page = newPages.first(where: { $0.originalIndex == index }) {
                     ordered.append(page)
                 }
             }
             if ordered.count == newPages.count {
                 pages = ordered
                 return
             }
        }
        
        pages = newPages
        updatePageOrder()
    }
    
    private func updatePageOrder() {
        let newOrder = pages.map { $0.originalIndex }
        if pageOrder != newOrder {
            pageOrder = newOrder
        }
    }
}

struct PageReorderDelegate: DropDelegate {
    let item: ReorderablePage
    @Binding var pages: [ReorderablePage]
    @Binding var current: ReorderablePage?
    @Binding var pageOrder: [Int]
    
    func dropEntered(info: DropInfo) {
        if let current = current, current != item {
            if let fromIndex = pages.firstIndex(where: { $0.id == current.id }),
               let toIndex = pages.firstIndex(where: { $0.id == item.id }) {
                if pages[toIndex].id != current.id {
                    withAnimation {
                        pages.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
                    }
                    // Update page order
                    pageOrder = pages.map { $0.originalIndex }
                }
            }
        }
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
    
    func performDrop(info: DropInfo) -> Bool {
        self.current = nil
        return true
    }
}
