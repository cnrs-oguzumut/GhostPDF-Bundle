import SwiftUI

@main
struct GhostPDFApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 500, minHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
    }
}

class AppState: ObservableObject {
    @Published var ghostscriptAvailable: Bool = false
    @Published var ghostscriptPath: String?
    @Published var showingGhostscriptWarning: Bool = false
    
    init() {
        checkGhostscript()
    }
    
    func checkGhostscript() {
        ghostscriptPath = PDFCompressor.findGhostscript()
        ghostscriptAvailable = ghostscriptPath != nil
        showingGhostscriptWarning = !ghostscriptAvailable
    }
}
