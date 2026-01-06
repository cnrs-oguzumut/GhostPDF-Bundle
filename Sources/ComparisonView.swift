import SwiftUI
import PDFKit

struct ComparisonView: View {
    let originalURL: URL
    let compressedURL: URL
    
    @State private var pdfView1 = PDFView()
    @State private var pdfView2 = PDFView()
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Header
                Text("Original")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color(hex: "1e293b"))
                    .foregroundColor(.white)
                
                Divider()
                    .background(Color.gray)
                
                Text("Compressed")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color(hex: "1e293b"))
                    .foregroundColor(.white)
            }
            .frame(height: 40)
            
            HStack(spacing: 0) {
                PDFViewWrapper(pdfView: pdfView1, url: originalURL)
                
                Divider()
                    .background(Color.gray)
                    .frame(width: 1)
                
                PDFViewWrapper(pdfView: pdfView2, url: compressedURL)
            }
        }
        .frame(minWidth: 1000, minHeight: 700)
        .onAppear {
            setupSync()
        }
    }
    
    private func setupSync() {
        // Simple page sync
        NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: pdfView1, queue: .main) { _ in
            if let page = pdfView1.currentPage, let index = pdfView1.document?.index(for: page) {
                if let destPage = pdfView2.document?.page(at: index) {
                     if pdfView2.currentPage != destPage {
                        pdfView2.go(to: destPage)
                    }
                }
            }
        }
        
        NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: pdfView2, queue: .main) { _ in
            if let page = pdfView2.currentPage, let index = pdfView2.document?.index(for: page) {
                if let destPage = pdfView1.document?.page(at: index) {
                    if pdfView1.currentPage != destPage {
                        pdfView1.go(to: destPage)
                    }
                }
            }
        }
        
        // Scale sync
        NotificationCenter.default.addObserver(forName: .PDFViewScaleChanged, object: pdfView1, queue: .main) { _ in
             if pdfView2.scaleFactor != pdfView1.scaleFactor {
                pdfView2.scaleFactor = pdfView1.scaleFactor
            }
        }
        NotificationCenter.default.addObserver(forName: .PDFViewScaleChanged, object: pdfView2, queue: .main) { _ in
             if pdfView1.scaleFactor != pdfView2.scaleFactor {
                pdfView1.scaleFactor = pdfView2.scaleFactor
            }
        }
    }
}

struct PDFViewWrapper: NSViewRepresentable {
    let pdfView: PDFView
    let url: URL
    
    func makeNSView(context: Context) -> PDFView {
        pdfView.document = PDFDocument(url: url)
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.backgroundColor = .lightGray
        return pdfView
    }
    
    func updateNSView(_ nsView: PDFView, context: Context) {
        // Updates handled via state/notifications
    }
}
