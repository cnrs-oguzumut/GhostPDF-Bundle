import SwiftUI
import PDFKit

// Manual region selection for extracting specific areas from PDF pages
struct ManualRegionSelector: View {
    let pdfURL: URL
    let onSave: ([PageRegion]) -> Void
    
    @State private var pdfDocument: PDFDocument?
    @State private var selectedPage: Int = 0
    @State private var regions: [PageRegion] = []
    @State private var currentlyDrawing: CGRect? = nil
    @State private var dragStart: CGPoint? = nil
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Select Regions to Extract")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Extract \(regions.count) Region(s)") {
                    extractSelectedRegions()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(regions.isEmpty)
            }
            .padding()

            Divider()

            HSplitView {
                // Left: Page thumbnails
                ScrollView {
                    VStack(spacing: 8) {
                        if let document = pdfDocument {
                            ForEach(0..<document.pageCount, id: \.self) { pageIndex in
                                PageThumbnailButton(
                                    document: document,
                                    pageIndex: pageIndex,
                                    isSelected: pageIndex == selectedPage,
                                    regionCount: regions.filter { $0.page == pageIndex }.count
                                ) {
                                    selectedPage = pageIndex
                                }
                            }
                        }
                    }
                    .padding()
                }
                .frame(width: 150)

                // Right: Main canvas with region selection
                GeometryReader { geometry in
                    ZStack {
                        if let document = pdfDocument,
                           let page = document.page(at: selectedPage) {

                            // Page image
                            PDFPageView(page: page, geometry: geometry)

                            // Draw existing regions
                            ForEach(regions.filter { $0.page == selectedPage }) { region in
                                RegionOverlay(rect: region.rect, geometry: geometry)
                                    .onTapGesture {
                                        // Remove region on tap
                                        regions.removeAll { $0.id == region.id }
                                    }
                            }

                            // Draw current dragging region
                            if let drawing = currentlyDrawing {
                                RegionOverlay(rect: drawing, geometry: geometry, isDraft: true)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 5)
                            .onChanged { value in
                                if dragStart == nil {
                                    dragStart = value.startLocation
                                }

                                if let start = dragStart {
                                    let rect = CGRect(
                                        x: min(start.x, value.location.x),
                                        y: min(start.y, value.location.y),
                                        width: abs(value.location.x - start.x),
                                        height: abs(value.location.y - start.y)
                                    )
                                    currentlyDrawing = rect
                                }
                            }
                            .onEnded { value in
                                if let rect = currentlyDrawing, rect.width > 20, rect.height > 20 {
                                    // Normalize rect to [0,1] coordinate space relative to the view
                                    // We need to store rects relative to the PDF page bounds, not screen pixels
                                    // Logic will be handled during extraction, here we store screen coords?
                                    // Better to assume we store logical coordinates relative to the view, 
                                    // and we need to pass the view geometry to the save function to normalize?
                                    // No, the simplest is to store the rect as drawn on our scaled view:
                                    // But PDF page size != View size.
                                    
                                    // Let's store the raw drawn rect for now (in view coordinates).
                                    // Wait, we need to map view coords -> PDF coords immediately or store context.
                                    // Let's look at `PDFPageView`. It scales the page to fit `geometry`.
                                    // We can reverse that math. See extractSelectedRegions.
                                    
                                    regions.append(PageRegion(
                                        page: selectedPage,
                                        rect: rect,
                                        viewSize: geometry.size
                                    ))
                                }
                                currentlyDrawing = nil
                                dragStart = nil
                            }
                    )
                }
            }

            // Instructions
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
                Text("Drag to draw rectangles around plots/figures. Tap rectangles to remove them.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            if pdfDocument == nil {
                pdfDocument = PDFDocument(url: pdfURL)
            }
        }
    }

    func extractSelectedRegions() {
        onSave(regions)
        dismiss()
    }
}

struct PageRegion: Identifiable {
    let id = UUID()
    let page: Int
    let rect: CGRect
    let viewSize: CGSize
}

struct PageThumbnailButton: View {
    let document: PDFDocument
    let pageIndex: Int
    let isSelected: Bool
    let regionCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                if let page = document.page(at: pageIndex) {
                    let thumbnail = page.thumbnail(of: CGSize(width: 100, height: 140), for: .mediaBox)
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 120)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: isSelected ? 2 : 1)
                        )
                }

                HStack(spacing: 4) {
                    Text("Page \(pageIndex + 1)")
                        .font(.caption2)

                    if regionCount > 0 {
                        Text("(\(regionCount))")
                            .font(.caption2)
                            .foregroundColor(.accentColor)
                    }
                }
            }
            .padding(4)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
}

struct PDFPageView: View {
    let page: PDFPage
    let geometry: GeometryProxy

    var body: some View {
        let pageSize = page.bounds(for: .mediaBox).size
        let scale = min(geometry.size.width / pageSize.width, geometry.size.height / pageSize.height)
        let scaledSize = CGSize(width: pageSize.width * scale, height: pageSize.height * scale)

        let thumbnail = page.thumbnail(of: scaledSize, for: .mediaBox)

        Image(nsImage: thumbnail)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: geometry.size.width, height: geometry.size.height)
    }
}

struct RegionOverlay: View {
    let rect: CGRect
    let geometry: GeometryProxy
    var isDraft: Bool = false

    var body: some View {
        Rectangle()
            .stroke(isDraft ? Color.blue.opacity(0.6) : Color.green, lineWidth: 2)
            .background(
                Rectangle()
                    .fill(isDraft ? Color.blue.opacity(0.1) : Color.green.opacity(0.15))
            )
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }
}

#Preview {
    ManualRegionSelector(pdfURL: URL(fileURLWithPath: "/tmp/test.pdf")) { _ in }
}
