import SwiftUI
import UniformTypeIdentifiers
import Network
import PDFKit
import FoundationModels

// MARK: - Network Monitor
@MainActor
class NetworkMonitor: ObservableObject {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    @Published var isConnected = true

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }
}

enum ExtractMode: String, CaseIterable, Identifiable {
    case renderPage = "Render Page as Image"
    case extractEmbedded = "Extract Embedded Images"
    case manualSelection = "Manual Region Selection"

    var id: String { rawValue }
}

enum SummaryType: String, CaseIterable, Identifiable {
    case tldr = "TL;DR"
    case keyPoints = "Key Points"
    case abstract = "Abstract"
    case fullSummary = "Full Summary"
    
    var id: String { self.rawValue }
    
    var icon: String {
        switch self {
        case .tldr: return "text.badge.minus"
        case .keyPoints: return "list.bullet.indent"
        case .abstract: return "doc.text.magnifyingglass"
        case .fullSummary: return "doc.text.fill"
        }
    }
    
    var name: String { self.rawValue }
    
    var description: String {
        switch self {
        case .tldr: return "The most important insights in 3-5 sentences."
        case .keyPoints: return "A bulleted list of 7-10 main takeaways."
        case .abstract: return "A formal academic summary of about 10 sentences."
        case .fullSummary: return "A comprehensive overview covering all sections (20 sentences)."
        }
    }
}

enum GrammarEnglishMode: String, CaseIterable, Identifiable {
    case american = "American English"
    case british = "British English"
    
    var id: String { self.rawValue }
    
    var icon: String {
        switch self {
        case .american: return "flag.fill"
        case .british: return "flag.fill"
        }
    }
}


struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedFiles: [PDFFile] = []
    @AppStorage("isDarkMode_v2") private var isDarkMode = true
    @State private var selectedTab = 0
    @State private var selectedMainMode: MainMode? = nil

    enum MainMode: String, CaseIterable, Identifiable {
        case compress = "Compress PDF"
        case tools = "PDF Tools"
        case researcher = "AI Researcher"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .compress: return "arrow.down.circle.fill"
            case .tools: return "wrench.and.screwdriver.fill"
            case .researcher: return "sparkles.rectangle.stack.fill"
            }
        }

        var color: Color {
            switch self {
            case .compress: return .blue
            case .tools: return .orange
            case .researcher: return .purple
            }
        }

        var description: String {
            switch self {
            case .compress: return "Reduce file size with customizable quality settings"
            case .tools: return "Extract images, split, merge, rotate, and more"
            case .researcher: return "AI-powered Q&A, summaries, and bibliography tools"
            }
        }
    }
    @State private var selectedPreset: CompressionPreset = .medium
    @State private var proSettings = ProSettings()
    @State private var selectedProPreset: ProPreset = .email
    @State private var isCompressing = false
    @State private var currentFileIndex = 0
    @State private var totalProgress: Double = 0
    @State private var statusMessage = ""
    @State private var statusIsError = false
    @State private var showingResult = false
    @State private var lastResults: [CompressionResult] = []
    @State private var showingGhostscriptAlert = false
    @State private var showingProModeRequirementAlert = false
    
    // Password handling
    @State private var showingPasswordAlert = false
    @State private var pendingFile: PDFFile?
    @State private var passwordInput = ""
    
    // Comparison
    @State private var showingComparison = false
    @State private var comparisonInputURL: URL?
    @State private var comparisonOutputURL: URL?

    // Tools State
    @State private var selectedTool: ToolMode = .rasterize
    @State private var rasterDPI: Int = 150
    @State private var imageFormat: ImageFormat = .jpeg
    @State private var extractMode: ExtractMode = .renderPage

    @State private var imageDPI: Int = 150
    @State private var showManualSelector: Bool = false
    @State private var splitMode: SplitMode = .extractSelected
    @State private var splitStartPage: Int = 1
    @State private var splitEndPage: Int = 1
    @State private var rotateOp: RotateOperation = .rotate
    @State private var rotationAngle: Int = 0 // 0, 90, 180, 270
    @State private var pagesToDelete: String = ""
    @State private var splitThumbnails: [URL] = []
    @State private var splitSelectedPages: Set<Int> = []
    @State private var thumbnailGenerationTask: Task<Void, Never>?
    
    // Security State
    @State private var securityMode: SecurityMode = .watermark
    @State private var watermarkText: String = "CONFIDENTIAL"
    @State private var watermarkOpacity: Double = 0.3
    @State private var watermarkDiagonal: Bool = true
    @State private var watermarkFontSize: Int = 48
    @State private var encryptPassword: String = ""
    @State private var encryptConfirmPassword: String = ""
    @State private var encryptAllowPrinting: Bool = true
    @State private var encryptAllowCopying: Bool = false
    @State private var decryptPassword: String = ""

    // Page Numbering State
    @State private var pageNumberPosition: PageNumberPosition = .bottomCenter
    @State private var pageNumberFontSize: Int = 12
    @State private var pageNumberStartFrom: Int = 1

    @State private var pageNumberFormat: PageNumberFormat = .numbers
    
    // Advanced State
    @State private var advancedMode: AdvancedMode = .repair
    
    // Reorder State
    @State private var reorderPageOrder: [Int] = []
    
    // AI Summary State
    @State private var summaryType: SummaryType = .keyPoints
    @State private var summaryText: String = ""
    @State private var isSummarizing: Bool = false
    
    // AI Chat State
    @State private var qnaInput: String = ""
    @State private var chatHistory: [(role: String, content: String)] = []
    @State private var isThinking: Bool = false
    
    // AI Grammar State
    @State private var grammarText: String = ""
    @State private var isGrammarChecking: Bool = false
    @AppStorage("grammarEnglishMode") private var grammarEnglishMode: GrammarEnglishMode = .american
    
    // Researcher Tab State (separate from AI tab)
    @SceneStorage("researcherOutputText") private var researcherOutputText: String = ""
    @State private var isResearcherProcessing: Bool = false
    @State private var previousTab: Int = 0
    @State private var savedResearcherOutput: String = "" // Preserve BibTeX when switching tabs

    // BibTeX Tab State (dedicated tab for .bib file formatting)
    @SceneStorage("bibFormatterOutputText") private var bibFormatterOutputText: String = ""
    @State private var isBibFormatterProcessing: Bool = false
    @State private var savedBibFiles: [PDFFile] = [] // Preserve .bib files when switching tabs
    
    // BibTeX Options
    @AppStorage("shortenAuthors") private var shortenAuthors = false
    @AppStorage("abbreviateJournals") private var abbreviateJournals = false
    @AppStorage("allowOnlineBibTeX") private var allowOnlineLookup = true
    @AppStorage("useLaTeXEscaping") private var useLaTeXEscaping = false
    @AppStorage("addDotsToInitials") private var addDotsToInitials = true
    @AppStorage("addDotsToJournals") private var addDotsToJournals = true
    
    struct PDFFile: Identifiable, Equatable {
        let id = UUID()
        let url: URL
        var outputURL: URL?
        var thumbnailURL: URL?
        var status: FileStatus = .pending
        var originalSize: Int64 = 0
        var compressedSize: Int64 = 0
        var isChecked: Bool = true
        
        enum FileStatus: Equatable {
            case pending
            case compressing(Double)
            case done
            case error(String)
        }
        
        static func == (lhs: PDFFile, rhs: PDFFile) -> Bool {
            lhs.id == rhs.id && lhs.isChecked == rhs.isChecked
        }
    }

    // MARK: - Mode Selection View

    @ViewBuilder
    private var modeSelectionView: some View {
        VStack(spacing: 48) {
            VStack(spacing: 12) {
                Text("Choose Your Workflow")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(isDarkMode ? .white : Color(red: 15/255, green: 23/255, blue: 42/255))

                Text("Select a mode to get started")
                    .font(.system(size: 16))
                    .foregroundColor(isDarkMode ? .white.opacity(0.6) : Color(red: 15/255, green: 23/255, blue: 42/255).opacity(0.6))
            }
            .padding(.top, 40)

            HStack(spacing: 24) {
                ForEach(MainMode.allCases) { mode in
                    ModeCard(
                        mode: mode,
                        isEmphasized: mode == .researcher,
                        isDarkMode: isDarkMode
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedMainMode = mode
                            // Set appropriate initial tab based on mode
                            switch mode {
                            case .compress:
                                selectedTab = 0 // Basic tab
                            case .tools:
                                selectedTab = 2 // Tools tab
                            case .researcher:
                                selectedTab = 5 // AI tab
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 48)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: isDarkMode ?
                    [Color(red: 15/255, green: 23/255, blue: 42/255), Color(red: 30/255, green: 41/255, blue: 59/255)] :
                    [Color(red: 248/255, green: 250/255, blue: 252/255), Color(red: 226/255, green: 232/255, blue: 240/255)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .preferredColorScheme(isDarkMode ? .dark : .light)

            VStack(spacing: 16) {
                HStack {
                    // Back button when in a mode
                    if selectedMainMode != nil {
                        Button(action: {
                            selectedMainMode = nil
                            statusMessage = ""
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.left")
                                Text("Home")
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(isDarkMode ? .white.opacity(0.8) : Color(red: 15/255, green: 23/255, blue: 42/255))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(isDarkMode ? Color.white.opacity(0.1) : Color.white)
                            .cornerRadius(8)
                            .shadow(radius: isDarkMode ? 0 : 2)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 24)
                    }

                    Spacer()

                    Button(action: { isDarkMode.toggle() }) {
                        Image(systemName: isDarkMode ? "sun.max.fill" : "moon.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(isDarkMode ? .yellow : .indigo)
                            .frame(width: 32, height: 32)
                            .background(isDarkMode ? Color.white.opacity(0.1) : Color.white)
                            .clipShape(Circle())
                            .shadow(radius: isDarkMode ? 0 : 2)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 24)
                    .padding(.top, 16)
                }
                .frame(height: 0)
                .zIndex(10)

                Text("GhostPDF+")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(isDarkMode ? .white : Color(red: 15/255, green: 23/255, blue: 42/255))
                    .padding(.top, 4)

                if !appState.ghostscriptAvailable {
                    WarningBanner()
                }

                if selectedMainMode == nil {
                    modeSelectionView
                } else {
                    fileListArea

                    // Show only relevant tabs based on selected mode
                    if let mode = selectedMainMode {
                        Picker("Mode", selection: $selectedTab) {
                            switch mode {
                            case .compress:
                                Text("Basic").tag(0)
                                Text("Pro").tag(1)
                            case .tools:
                                Text("Extract Images").tag(2)
                                Text("Security").tag(3)
                                Text("Advanced").tag(4)
                            case .researcher:
                                Text("AI").tag(5)
                                Text("Bibliography").tag(6)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 24)
                        .onChange(of: selectedTab) { newValue in
                    // Handle Researcher tab transitions (tab 6)
                    if previousTab == 6 && newValue != 6 {
                        // Leaving Researcher tab: save and clear BibTeX output
                        savedResearcherOutput = researcherOutputText
                        researcherOutputText = ""

                        // Don't remove files - filtering will hide .bib files in other tabs
                        // selectedFiles remain unchanged so .bib files persist
                        statusMessage = ""
                        totalProgress = 0
                        currentFileIndex = 0
                    } else if previousTab != 6 && newValue == 6 {
                        // Returning to Researcher tab: restore BibTeX output
                        if !savedResearcherOutput.isEmpty {
                            researcherOutputText = savedResearcherOutput
                        }
                    }

                    // Handle BibTeX tab transitions (tab 7)
                    if previousTab == 7 && newValue != 7 {
                        // Leaving BibTeX tab: save .bib files
                        savedBibFiles = selectedFiles.filter { $0.url.pathExtension.lowercased() == "bib" }

                        // Clear files and status
                        selectedFiles.removeAll()
                        statusMessage = ""
                        totalProgress = 0
                        currentFileIndex = 0
                    } else if previousTab != 7 && newValue == 7 {
                        // Returning to BibTeX tab: restore .bib files
                        if !savedBibFiles.isEmpty {
                            selectedFiles = savedBibFiles
                        }
                    }

                            previousTab = newValue

                            if (newValue == 1 || newValue == 2 || newValue == 3 || newValue == 4 || newValue == 5) && !appState.ghostscriptAvailable {
                                selectedTab = 0
                                showingProModeRequirementAlert = true
                            }
                        }
                    }

                    // Use ZStack with opacity to keep Researcher tab alive (preserves dropped bib content)
                    ZStack {
                        // Compress mode tabs
                        if selectedMainMode == .compress {
                            BasicTabView(selectedPreset: $selectedPreset)
                                .opacity(selectedTab == 0 ? 1 : 0)
                                .allowsHitTesting(selectedTab == 0)

                            proTabContent
                                .opacity(selectedTab == 1 ? 1 : 0)
                                .allowsHitTesting(selectedTab == 1)
                        }

                        // Tools mode tabs
                        if selectedMainMode == .tools {
                            toolsTabContent
                                .opacity(selectedTab == 2 ? 1 : 0)
                                .allowsHitTesting(selectedTab == 2)

                            securityTabContent
                                .opacity(selectedTab == 3 ? 1 : 0)
                                .allowsHitTesting(selectedTab == 3)

                            advancedTabContent
                                .opacity(selectedTab == 4 ? 1 : 0)
                                .allowsHitTesting(selectedTab == 4)
                        }

                        // Researcher mode tabs
                        if selectedMainMode == .researcher {
                            aiTabContent
                                .opacity(selectedTab == 5 ? 1 : 0)
                                .allowsHitTesting(selectedTab == 5)

                            ResearcherTabView(
                                selectedFiles: $selectedFiles,
                                outputText: $researcherOutputText,
                                isProcessing: $isResearcherProcessing
                            )
                            .opacity(selectedTab == 6 ? 1 : 0)
                            .allowsHitTesting(selectedTab == 6)
                        }

                        // BibTeX tab enabled
                        BibTeXFormatterView(
                            selectedFiles: $selectedFiles,
                            outputText: $bibFormatterOutputText,
                            isProcessing: $isBibFormatterProcessing
                        )
                        .opacity(selectedTab == 7 ? 1 : 0)
                        .allowsHitTesting(selectedTab == 7)
                    }
                
                // Hide compression progress bar in Researcher (6) and BibTeX (7) tabs
                if isCompressing && selectedTab != 6 && selectedTab != 7 {
                    VStack {
                        ProgressView(value: totalProgress)
                            .progressViewStyle(.linear)
                        Text("Processing file \(currentFileIndex + 1) of \(selectedFiles.count)")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal, 24)
                }

                // Hide status message in Researcher (6) and BibTeX (7) tabs
                if !statusMessage.isEmpty && selectedTab != 6 && selectedTab != 7 {
                    Text(statusMessage)
                        .font(.system(size: 13))
                        .foregroundColor(statusIsError ? Color(red: 248/255, green: 113/255, blue: 113/255) : Color(red: 74/255, green: 222/255, blue: 128/255))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                    // Hide the compress button on AI tab, Researcher tab, and BibTeX tab
                    if selectedTab != 5 && selectedTab != 6 && selectedTab != 7 {
                        Button(action: performAction) {
                            Text(actionButtonTitle)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(
                                    LinearGradient(
                                        colors: !selectedFiles.isEmpty && !isCompressing
                                            ? [Color(red: 34/255, green: 197/255, blue: 94/255), Color(red: 22/255, green: 163/255, blue: 74/255)]
                                            : [Color(red: 148/255, green: 163/255, blue: 184/255).opacity(0.3), Color(red: 148/255, green: 163/255, blue: 184/255).opacity(0.3)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .cornerRadius(14)
                        }
                        .disabled(selectedFiles.isEmpty || isCompressing)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                    }
                } // end of else block for selectedMainMode
            }
        }
        .sheet(isPresented: $showingComparison) {
            if let input = comparisonInputURL, let output = comparisonOutputURL {
                ComparisonView(originalURL: input, compressedURL: output)
                    .frame(minWidth: 800, minHeight: 600)
            }
        }
        .sheet(isPresented: $showManualSelector) {
            if let firstFile = selectedFiles.first(where: { $0.status == .pending }) {
                ManualRegionSelector(pdfURL: firstFile.url) { regions in
                    showManualSelector = false
                    // Process regions for this file
                    Task {
                        await saveManualRegions(for: firstFile, regions: regions)
                    }
                }
            }
        }

        .alert(selectedTab == 4 ? "Operation Complete" : "Batch Complete", isPresented: $showingResult) {
            Button("Reveal in Finder") {
                if let first = lastResults.first {
                    PDFCompressor.revealInFinder(first.outputPath)
                }
            }
            Button("OK", role: .cancel) {}
        } message: {
            if selectedTab == 4 {
                let action = advancedMode == .repair ? "repaired" : "converted"
                Text("Successfully \(action) \(lastResults.count) files.")
            } else {
                let totalSaved = lastResults.reduce(0) { $0 + ($1.originalSize - $1.compressedSize) }
                let totalMB = Double(totalSaved) / (1024 * 1024)
                Text("Processed \(lastResults.count) files.\nTotal space saved: \(String(format: "%.2f", totalMB)) MB")
            }
        }
        .alert("Pro Mode Requires Ghostscript", isPresented: $showingProModeRequirementAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Pro Mode requires Ghostscript to be installed. Install it using Homebrew:\n\nbrew install ghostscript")
        }
        .onAppear {
            if !appState.ghostscriptAvailable {
                showingGhostscriptAlert = true
            }
        }
    }
    
    var gsRequirementView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            Text("This Feature Requires Ghostscript")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
            Text("Install Ghostscript to use this feature.\n\nbrew install ghostscript")
                .font(.system(size: 13))
                .foregroundColor(Color(red: 148/255, green: 163/255, blue: 184/255))
                .multilineTextAlignment(.center)
                Spacer()
            Spacer()
        }
        .padding(24)
    }
    
    @ViewBuilder
    private var aiTabContent: some View {
        AITabView(
            selectedFiles: $selectedFiles,
            summaryType: $summaryType,
            summaryText: $summaryText,
            isSummarizing: $isSummarizing,
            qnaInput: $qnaInput,
            chatHistory: $chatHistory,
            isThinking: $isThinking,
            grammarText: $grammarText,
            isGrammarChecking: $isGrammarChecking,
            grammarEnglishMode: $grammarEnglishMode
        )
    }
    

    
    @ViewBuilder
    private var toolsTabContent: some View {
        if appState.ghostscriptAvailable {
            ToolsTabView(
                selectedTool: $selectedTool,
                rasterDPI: $rasterDPI,
                imageFormat: $imageFormat,
                extractMode: $extractMode,
                imageDPI: $imageDPI,
                showManualSelector: $showManualSelector,
                splitMode: $splitMode,
                splitStartPage: $splitStartPage,
                splitEndPage: $splitEndPage,
                rotateOp: $rotateOp,
                rotationAngle: $rotationAngle,
                pagesToDelete: $pagesToDelete,
                pageNumberPosition: $pageNumberPosition,
                pageNumberFontSize: $pageNumberFontSize,
                pageNumberStartFrom: $pageNumberStartFrom,
                pageNumberFormat: $pageNumberFormat,
                reorderPageOrder: $reorderPageOrder,
                splitSelectedPages: $splitSelectedPages,
                splitThumbnailsCount: splitThumbnails.count
            )
            .onChange(of: selectedTool) { _ in checkAndGenerateThumbnails() }
            .onChange(of: selectedFiles) { _ in checkAndGenerateThumbnails() }
        } else {
            gsRequirementView
        }
    }
    
    @ViewBuilder
    private var proTabContent: some View {
        if appState.ghostscriptAvailable {
            ProTabView(
                settings: $proSettings,
                selectedPreset: $selectedProPreset
            )
        } else {
            gsRequirementView
        }
    }
    
    @ViewBuilder
    private var securityTabContent: some View {
        if appState.ghostscriptAvailable {
            SecurityTabView(
                securityMode: $securityMode,
                watermarkText: $watermarkText,
                watermarkOpacity: $watermarkOpacity,
                watermarkDiagonal: $watermarkDiagonal,
                watermarkFontSize: $watermarkFontSize,
                encryptPassword: $encryptPassword,
                encryptConfirmPassword: $encryptConfirmPassword,
                encryptAllowPrinting: $encryptAllowPrinting,
                encryptAllowCopying: $encryptAllowCopying,
                decryptPassword: $decryptPassword
            )
        } else {
            gsRequirementView
        }
    }
    
    var actionButtonTitle: String {
        if selectedTab == 3 {
            switch securityMode {
            case .watermark: return "Add Watermark"
            case .encrypt: return "Encrypt PDF"
            case .decrypt: return "Decrypt PDF"
            }
        }
        if selectedTab == 2 {
            if selectedFiles.count > 1 {
                switch selectedTool {
                case .merge: return "Merge Files"
                case .split: return "Split Files"
                case .rotateDelete: return rotateOp == .rotate ? "Rotate Files" : "Delete Pages"
                case .rasterize: return "Rasterize Files"
                case .extractImages: return "Extract All Images"
                case .pageNumber: return "Add Page Numbers"
                case .reorder: return "Reorder Pages"
                case .resizeA4: return "Resize All to A4"
                }
            }
            switch selectedTool {
            case .merge: return "Merge PDF"
            case .split: return "Split PDF"
            case .rotateDelete: return rotateOp == .rotate ? "Rotate PDF" : "Delete Pages"
            case .rasterize: return "Rasterize PDF"
            case .extractImages: return "Extract Images"
            case .pageNumber: return "Add Page Numbers"
            case .reorder: return "Reorder Pages"
            case .resizeA4: return "Resize to A4"
            }
        }
        if selectedTab == 4 {
            return advancedMode == .repair ? "Repair PDF" : "Convert to PDF/A"
        }
        return selectedFiles.count > 1 ? "Compress Files" : "Compress PDF"
    }
    

    private func performAction() {

        if selectedTab == 3 {
            if securityMode == .watermark {
                applyWatermark()
            } else if securityMode == .encrypt {
                encryptPDF()
            } else {
                decryptPDF()
            }
        } else if selectedTab == 2 {
            switch selectedTool {
            case .rasterize:
                rasterizePDF()
            case .extractImages:
                extractImages()
            case .merge:
                merge()
            case .split:
                split()
            case .rotateDelete:
                rotateOrDelete()
            case .pageNumber:
                addPageNumbers()
            case .reorder:
                reorderPages()
            case .resizeA4:
                resizeToA4()
            }
        } else if selectedTab == 4 {
            performAdvancedAction()
        } else {
            compress()
        }
    }
    
    private func rasterizePDF() {
        let checkedFiles = selectedFiles.filter { $0.isChecked }
        guard !checkedFiles.isEmpty else { return }
        
        // Sandbox Compliance: Prompt
        var destinationDir: URL?
        var singleFileOutputURL: URL?
        
        if checkedFiles.count > 1 {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.prompt = "Select Output Folder"
            panel.message = "Choose where to save the rasterized files"
            if let first = checkedFiles.first {
                 panel.directoryURL = first.url.deletingLastPathComponent()
            }
            guard panel.runModal() == .OK, let url = panel.url else { return }
            destinationDir = url
        } else {
            let file = checkedFiles[0]
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = file.url.deletingPathExtension().lastPathComponent + "_rasterized.pdf"
            panel.directoryURL = file.url.deletingLastPathComponent()
            guard panel.runModal() == .OK, let url = panel.url else { return }
            singleFileOutputURL = url
        }
        
        startOperation(message: "Rasterizing files...")
        currentFileIndex = 0
        
        Task {
            for (index, file) in selectedFiles.enumerated() {
                guard file.isChecked else { continue }
                 await MainActor.run {
                    currentFileIndex = index
                    selectedFiles[index].status = .compressing(0)
                }
                
                var currentPassword: String? = nil
                var retryCount = 0
                let maxRetries = 3
                var success = false
                
                while !success && retryCount < maxRetries {
                    do {
                        let outputURL: URL
                        if let single = singleFileOutputURL {
                            outputURL = single
                        } else if let dir = destinationDir {
                            let filename = file.url.deletingPathExtension().lastPathComponent + "_rasterized.pdf"
                            outputURL = dir.appendingPathComponent(filename)
                        } else {
                            // Fallback
                            outputURL = file.url.deletingPathExtension().appendingPathExtension("rasterized.pdf")
                        }
                        
                        let result = try await PDFCompressor.rasterize(
                            input: file.url,
                            output: outputURL,
                            dpi: rasterDPI,
                            password: currentPassword
                        ) { prog in
                            Task { @MainActor in
                                selectedFiles[index].status = .compressing(prog)
                                let perFile = 1.0 / Double(checkedFiles.count)
                                totalProgress = (Double(lastResults.count) * perFile) + (prog * perFile)
                            }
                        }
                        
                        await MainActor.run {
                            var updatedFile = selectedFiles[index]
                            updatedFile.status = .done
                            updatedFile.compressedSize = result.compressedSize
                            updatedFile.outputURL = result.outputPath
                            selectedFiles[index] = updatedFile
                            lastResults.append(result)
                        }
                        success = true
                    } catch CompressionError.passwordRequired {
                        // Prompt for password
                        let password = await MainActor.run { () -> String? in
                            let alert = NSAlert()
                            alert.messageText = "Password Required"
                            alert.informativeText = "The file \"\(file.url.lastPathComponent)\" is encrypted. Please enter the password."
                            alert.addButton(withTitle: "Unlock")
                            alert.addButton(withTitle: "Skip")
                            let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
                            alert.accessoryView = input
                            alert.window.initialFirstResponder = input
                            if alert.runModal() == .alertFirstButtonReturn { return input.stringValue }
                            return nil
                        }
                        if let pass = password, !pass.isEmpty {
                            currentPassword = pass
                            retryCount += 1
                        } else {
                            await MainActor.run { selectedFiles[index].status = .error("Password skipped") }
                            break
                        }
                    } catch {
                         await MainActor.run { selectedFiles[index].status = .error(error.localizedDescription) }
                         break
                    }
                }
            }
            
            await MainActor.run {
                isCompressing = false
                showingResult = true
                statusMessage = "Batch rasterization complete!"
                
                if let single = singleFileOutputURL {
                    PDFCompressor.revealInFinder(single)
                } else if let dir = destinationDir {
                    PDFCompressor.revealInFinder(dir)
                }
            }
        }
    }
    
    private func extractImages() {
        let checkedFiles = selectedFiles.filter { $0.isChecked }
        guard !checkedFiles.isEmpty else { return }
        
        // Use NSOpenPanel to pick a FOLDER where subfolders for images will be created.
        // Granting access to this folder allows creating subdirectories inside it.
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Output Folder"
        panel.message = "Choose a location to save extracted images"
        if let first = checkedFiles.first {
             panel.directoryURL = first.url.deletingLastPathComponent()
        }
        
        guard panel.runModal() == .OK, let outputDir = panel.url else { return }
        
        startOperation(message: "Extracting images...")
        currentFileIndex = 0
        
        Task {
            var lastCreatedFolder: URL? = nil
            
            for (index, file) in selectedFiles.enumerated() {
                guard file.isChecked else { continue }
                await MainActor.run {
                    currentFileIndex = index
                    selectedFiles[index].status = .compressing(0)
                }
                
                do {
                    // Create subfolder for each PDF
                    let fileFolder = outputDir.appendingPathComponent(file.url.deletingPathExtension().lastPathComponent + "_Images")
                    try FileManager.default.createDirectory(at: fileFolder, withIntermediateDirectories: true)
                    lastCreatedFolder = fileFolder
                    
                    var currentPassword: String? = nil
                    var retryCount = 0
                    let maxRetries = 3
                    var success = false
                    
                    while !success && retryCount < maxRetries {
                        do {
                            if extractMode == .renderPage {
                                try await PDFCompressor.exportImages(
                                    input: file.url,
                                    outputDir: fileFolder,
                                    format: imageFormat,
                                    dpi: imageDPI,
                                    password: currentPassword
                                ) { prog in
                                     Task { @MainActor in
                                        selectedFiles[index].status = .compressing(prog)
                                        let perFile = 1.0 / Double(checkedFiles.count)
                                        totalProgress = (Double(lastResults.count) * perFile) + (prog * perFile)
                                    }
                                }
                            } else {
                                // 1. Extract Embedded Images (raster images in PDF)
                                try await PDFCompressor.extractEmbeddedImages(
                                    input: file.url,
                                    outputDir: fileFolder,
                                    password: currentPassword
                                ) { prog in
                                     Task { @MainActor in
                                        selectedFiles[index].status = .compressing(prog)
                                        let perFile = 1.0 / Double(checkedFiles.count)
                                        totalProgress = (Double(lastResults.count) * perFile) + (prog * perFile)
                                    }
                                }

                                // AI Extraction removed (User Request)
                            }
                            
                            await MainActor.run {
                                selectedFiles[index].status = .done
                                lastResults.append(CompressionResult(outputPath: fileFolder, originalSize: 0, compressedSize: 0, engine: .ghostscript))
                            }
                            success = true
                        } catch CompressionError.passwordRequired {
                            // Prompt for password
                            let password = await MainActor.run { () -> String? in
                                let alert = NSAlert()
                                alert.messageText = "Password Required"
                                alert.informativeText = "The file \"\(file.url.lastPathComponent)\" is encrypted. Please enter the password."
                                alert.addButton(withTitle: "Unlock")
                                alert.addButton(withTitle: "Skip")
                                let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
                                alert.accessoryView = input
                                alert.window.initialFirstResponder = input
                                if alert.runModal() == .alertFirstButtonReturn { return input.stringValue }
                                return nil
                            }
                            if let pass = password, !pass.isEmpty {
                                currentPassword = pass
                                retryCount += 1
                            } else {
                                await MainActor.run { selectedFiles[index].status = .error("Password skipped") }
                                break
                            }
                        } catch {
                             throw error
                        }
                    }
                } catch {
                     await MainActor.run { selectedFiles[index].status = .error(error.localizedDescription) }
                }
            }
            
            await MainActor.run {
                isCompressing = false
                statusMessage = "Batch extraction complete!"
                if checkedFiles.count == 1, let folder = lastCreatedFolder {
                    PDFCompressor.revealInFinder(folder)
                } else {
                    PDFCompressor.revealInFinder(outputDir)
                }
            }
        }
    }
    
    private func startOperation(message: String) {
        isCompressing = true
        totalProgress = 0
        statusMessage = message
        statusIsError = false
        lastResults = []
    }
    
    private func finishOperation(message: String) {
        isCompressing = false
        statusMessage = message
        statusIsError = false
    }
    
    private func handleError(_ error: Error) async {
        await MainActor.run {
            // Log error for specific file but continue?
            statusMessage = "Error: \(error.localizedDescription)"
            statusIsError = true
        }
    }
    
    private func formatSize(_ size: Int64) -> String {
        return String(format: "%.2f MB", Double(size) / (1024 * 1024))
    }

    private func compress() {
        let checkedFiles = selectedFiles.filter { $0.isChecked }
        guard !checkedFiles.isEmpty else { return }
        
        // Sandbox Compliance: Prompt for output location
        var destinationDir: URL?
        var singleFileOutputURL: URL?
        
        if checkedFiles.count > 1 {
            // Batch: Pick Output Folder
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.prompt = "Select Output Folder"
            panel.message = "Choose where to save the compressed files"
            if let first = checkedFiles.first {
                 panel.directoryURL = first.url.deletingLastPathComponent()
            }
            guard panel.runModal() == .OK, let url = panel.url else { return }
            destinationDir = url
        } else {
            // Single: Save Panel
            let file = checkedFiles[0]
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = file.url.deletingPathExtension().lastPathComponent + "_compressed.pdf"
            panel.directoryURL = file.url.deletingLastPathComponent()
            guard panel.runModal() == .OK, let url = panel.url else { return }
            singleFileOutputURL = url
        }
        
        isCompressing = true
        totalProgress = 0
        statusMessage = "Compressing..."
        statusIsError = false
        lastResults = []
        currentFileIndex = 0
        
        Task {
            for (index, file) in selectedFiles.enumerated() {
                guard file.isChecked else { continue }
                await MainActor.run {
                    currentFileIndex = index
                    selectedFiles[index].status = .compressing(0)
                }
                
                var currentPassword: String? = nil
                var retryCount = 0
                let maxRetries = 3
                var success = false
                
                while !success && retryCount < maxRetries {
                    do {
                        // Determine Output URL based on selection mode
                        let outputURL: URL
                        if let singleUrl = singleFileOutputURL {
                            outputURL = singleUrl
                        } else if let dir = destinationDir {
                            let filename = file.url.deletingPathExtension().lastPathComponent + "_compressed.pdf"
                            outputURL = dir.appendingPathComponent(filename)
                        } else {
                            // Fallback (should not happen)
                            outputURL = file.url.deletingPathExtension().appendingPathExtension("compressed.pdf")
                        }
                        
                        let proSet: ProSettings? = selectedTab == 1 ? proSettings : nil
                        let result = try await PDFCompressor.compress(
                            input: file.url,
                            output: outputURL,
                            preset: selectedPreset,
                            proSettings: proSet,
                            password: currentPassword
                        ) { prog in
                            Task { @MainActor in
                                selectedFiles[index].status = .compressing(prog)
                                let perFile = 1.0 / Double(checkedFiles.count)
                                totalProgress = (Double(lastResults.count) * perFile) + (prog * perFile)
                            }
                        }
                        
                        await MainActor.run {
                            var updatedFile = selectedFiles[index]
                            updatedFile.status = .done
                            updatedFile.compressedSize = result.compressedSize
                            updatedFile.outputURL = result.outputPath
                            selectedFiles[index] = updatedFile
                            lastResults.append(result)
                        }
                        success = true
                        
                    } catch CompressionError.passwordRequired {
                        // Prompt for password
                        let password = await MainActor.run { () -> String? in
                            let alert = NSAlert()
                            alert.messageText = "Password Required"
                            alert.informativeText = "The file \"\(file.url.lastPathComponent)\" is encrypted. Please enter the password."
                            alert.addButton(withTitle: "Unlock")
                            alert.addButton(withTitle: "Skip")
                            
                            let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
                            alert.accessoryView = input
                            alert.window.initialFirstResponder = input
                            
                            if alert.runModal() == .alertFirstButtonReturn {
                                return input.stringValue
                            }
                            return nil
                        }
                        
                        if let pass = password, !pass.isEmpty {
                            currentPassword = pass
                            retryCount += 1
                        } else {
                            // User skipped
                            await MainActor.run {
                                selectedFiles[index].status = .error("Password skipped")
                            }
                            break
                        }
                        
                    } catch {
                         await MainActor.run {
                            selectedFiles[index].status = .error(error.localizedDescription)
                         }
                         break
                    }
                }
            }
            
            await MainActor.run {
                isCompressing = false
                showingResult = true
                statusMessage = "Batch processing complete!"
                
                // If single file, reveal it
                if let single = singleFileOutputURL {
                    PDFCompressor.revealInFinder(single)
                } else if let dir = destinationDir {
                    PDFCompressor.revealInFinder(dir)
                }
            }
        }
    }
    
    
    private func merge() {
        guard selectedFiles.count > 1 else { return }
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "Merged.pdf"
        panel.prompt = "Merge"
        if let first = selectedFiles.first {
             panel.directoryURL = first.url.deletingLastPathComponent()
        }
        
        guard panel.runModal() == .OK, let outputURL = panel.url else { return }
        
        startOperation(message: "Merging files...")
        
        Task {
            do {
                try await PDFCompressor.merge(
                    inputs: selectedFiles.filter { $0.isChecked }.map { $0.url },
                    output: outputURL
                ) { prog in
                    Task { @MainActor in totalProgress = prog }
                }
                
                await MainActor.run {
                     finishOperation(message: "Merge complete!")
                     PDFCompressor.revealInFinder(outputURL)
                }
            } catch {
                await handleError(error)
            }
        }
        }

    
    private func split() {
        guard !selectedFiles.isEmpty else { return }
        
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Output Folder"
        panel.message = "Choose where to save the split files"
        if let first = selectedFiles.first {
             panel.directoryURL = first.url.deletingLastPathComponent()
        }
        
        guard panel.runModal() == .OK, let outputDir = panel.url else { return }
        
        startOperation(message: "Splitting files...")
        currentFileIndex = 0
        
        Task {
            let checkedFiles = selectedFiles.filter { $0.isChecked }
            var lastCreatedFolder: URL? = nil
            
            for (index, file) in selectedFiles.enumerated() {
                guard file.isChecked else { continue }
                await MainActor.run {
                    currentFileIndex = index
                    selectedFiles[index].status = .compressing(0)
                }
                
                do {
                    // Create subfolder for cleanliness if handling multiple files or many pages
                    let fileFolder = outputDir.appendingPathComponent(file.url.deletingPathExtension().lastPathComponent + "_Split")
                    try FileManager.default.createDirectory(at: fileFolder, withIntermediateDirectories: true)
                    lastCreatedFolder = fileFolder
                    
                    var currentPassword: String? = nil
                    var retryCount = 0
                    let maxRetries = 3
                    var success = false
                    
                    while !success && retryCount < maxRetries {
                        do {
                            // Extract specific pages or range or all?
                            // Depends on splitMode
                            if splitMode == .extractSelected {
                                try await PDFCompressor.split(
                                    input: file.url,
                                    outputDir: fileFolder,
                                    pages: Array(splitSelectedPages),
                                    password: currentPassword
                                ) { prog in
                                     Task { @MainActor in
                                        selectedFiles[index].status = .compressing(prog)
                                        let perFile = 1.0 / Double(checkedFiles.count)
                                        totalProgress = (Double(index) * perFile) + (prog * perFile)
                                    }
                                }
                            } else if splitMode == .extractRange { // Range
                                try await PDFCompressor.split(
                                    input: file.url,
                                    outputDir: fileFolder,
                                    startPage: splitStartPage,
                                    endPage: splitEndPage,
                                    password: currentPassword
                                ) { prog in
                                     Task { @MainActor in
                                        selectedFiles[index].status = .compressing(prog)
                                        let perFile = 1.0 / Double(checkedFiles.count)
                                        totalProgress = (Double(index) * perFile) + (prog * perFile)
                                    }
                                }
                            } else { // Split All
                                try await PDFCompressor.split(
                                    input: file.url,
                                    outputDir: fileFolder,
                                    password: currentPassword
                                ) { prog in
                                    Task { @MainActor in
                                        selectedFiles[index].status = .compressing(prog)
                                        let perFile = 1.0 / Double(checkedFiles.count)
                                        totalProgress = (Double(index) * perFile) + (prog * perFile)
                                    }
                                }
                            }
                            
                            await MainActor.run {
                                selectedFiles[index].status = .done
                            }
                            success = true
                        } catch CompressionError.passwordRequired {
                             let password = await MainActor.run { () -> String? in
                                let alert = NSAlert()
                                alert.messageText = "Password Required"
                                alert.informativeText = "The file \"\(file.url.lastPathComponent)\" is encrypted."
                                alert.addButton(withTitle: "Unlock")
                                alert.addButton(withTitle: "Skip")
                                let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
                                alert.accessoryView = input
                                alert.window.initialFirstResponder = input
                                if alert.runModal() == .alertFirstButtonReturn { return input.stringValue }
                                return nil
                            }
                            if let pass = password, !pass.isEmpty {
                                currentPassword = pass
                                retryCount += 1
                            } else {
                                await MainActor.run { selectedFiles[index].status = .error("Password skipped") }
                                break
                            }
                        } catch {
                            throw error
                        }
                    }
                } catch {
                     await MainActor.run { selectedFiles[index].status = .error(error.localizedDescription) }
                }
            }
            
            await MainActor.run {
                finishOperation(message: "Split complete!")
                if checkedFiles.count == 1, let folder = lastCreatedFolder {
                    PDFCompressor.revealInFinder(folder)
                } else {
                    PDFCompressor.revealInFinder(outputDir)
                }
                showingResult = true
            }
        }
    }


    private func rotateOrDelete() {
        let checkedFiles = selectedFiles.filter { $0.isChecked }
        guard !checkedFiles.isEmpty else { return }
        
        let pagesSet = splitSelectedPages
        if pagesSet.isEmpty && rotateOp == .delete { 
            return 
        }
        
        // Sandbox Compliance: Prompt
        var destinationDir: URL?
        var singleFileOutputURL: URL?
        let suffix = rotateOp == .rotate ? "_rotated" : "_edited"
        
        if checkedFiles.count > 1 {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.prompt = "Select Output Folder"
            panel.message = "Choose where to save the processed files"
            if let first = checkedFiles.first {
                 panel.directoryURL = first.url.deletingLastPathComponent()
            }
            guard panel.runModal() == .OK, let url = panel.url else { return }
            destinationDir = url
        } else {
            let file = checkedFiles[0]
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = file.url.deletingPathExtension().lastPathComponent + suffix + ".pdf"
            panel.directoryURL = file.url.deletingLastPathComponent()
            guard panel.runModal() == .OK, let url = panel.url else { return }
            singleFileOutputURL = url
        }
        
        Task {
            await MainActor.run {
                let opName = rotateOp == .rotate ? "Rotating..." : "Deleting pages..."
                startOperation(message: opName)
                currentFileIndex = 0
            }
            
            for (index, file) in selectedFiles.enumerated() {
                guard file.isChecked else { continue }
                await MainActor.run {
                    currentFileIndex = index
                    selectedFiles[index].status = .compressing(0)
                }
                
                var currentPassword: String? = nil
                var retryCount = 0
                let maxRetries = 3
                var success = false
                
                while !success && retryCount < maxRetries {
                    do {
                        let outputURL: URL
                        if let single = singleFileOutputURL {
                            outputURL = single
                        } else if let dir = destinationDir {
                            let filename = file.url.deletingPathExtension().lastPathComponent + suffix + ".pdf"
                            outputURL = dir.appendingPathComponent(filename)
                        } else {
                            outputURL = file.url.deletingPathExtension().appendingPathExtension(suffix + ".pdf")
                        }
                        
                        if rotateOp == .rotate {
                            try await PDFCompressor.rotate(
                                input: file.url,
                                output: outputURL,
                                angle: rotationAngle,
                                pages: pagesSet.isEmpty ? nil : pagesSet,
                                password: currentPassword
                            ) { prog in
                                Task { @MainActor in
                                    selectedFiles[index].status = .compressing(prog)
                                    let perFile = 1.0 / Double(checkedFiles.count)
                                    totalProgress = (Double(lastResults.count) * perFile) + (prog * perFile)
                                }
                            }
                        } else {
                            try await PDFCompressor.deletePages(
                                input: file.url,
                                output: outputURL,
                                pagesToDelete: pagesSet,
                                password: currentPassword
                            ) { prog in
                                 Task { @MainActor in
                                    selectedFiles[index].status = .compressing(prog)
                                    let perFile = 1.0 / Double(checkedFiles.count)
                                    totalProgress = (Double(lastResults.count) * perFile) + (prog * perFile)
                                }
                            }
                        }
                        
                        await MainActor.run {
                            var updatedFile = selectedFiles[index]
                            updatedFile.status = .done
                            updatedFile.outputURL = outputURL 
                            if let attr = try? FileManager.default.attributesOfItem(atPath: outputURL.path),
                               let size = attr[.size] as? Int64 {
                                updatedFile.compressedSize = size
                            }
                            selectedFiles[index] = updatedFile
                            lastResults.append(CompressionResult(outputPath: outputURL, originalSize: file.originalSize, compressedSize: updatedFile.compressedSize, engine: .ghostscript))
                        }
                        success = true
                    } catch CompressionError.passwordRequired {
                        let password = await MainActor.run { () -> String? in
                            let alert = NSAlert()
                            alert.messageText = "Password Required"
                            alert.informativeText = "The file \"\(file.url.lastPathComponent)\" is encrypted."
                            alert.addButton(withTitle: "Unlock")
                            alert.addButton(withTitle: "Skip")
                            let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
                            alert.accessoryView = input
                            alert.window.initialFirstResponder = input
                            if alert.runModal() == .alertFirstButtonReturn { return input.stringValue }
                            return nil
                        }
                        if let pass = password, !pass.isEmpty {
                            currentPassword = pass
                            retryCount += 1
                        } else {
                            await MainActor.run { selectedFiles[index].status = .error("Password skipped") }
                            break
                        }
                    } catch {
                         await MainActor.run { selectedFiles[index].status = .error(error.localizedDescription) }
                         break
                    }
                }
            }
            
            await MainActor.run {
                finishOperation(message: "Operation complete!")
                if let first = selectedFiles.first?.outputURL {
                     PDFCompressor.revealInFinder(first)
                }
            }
            }
            }

    private func applyWatermark() {
        let checkedFiles = selectedFiles.filter { $0.isChecked }
        guard !checkedFiles.isEmpty else { return }
        guard !watermarkText.isEmpty else { return }
        
        // Sandbox Compliance: Prompt
        var destinationDir: URL?
        var singleFileOutputURL: URL?
        
        if checkedFiles.count > 1 {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.prompt = "Select Output Folder"
            panel.message = "Choose where to save the watermarked files"
            if let first = checkedFiles.first {
                 panel.directoryURL = first.url.deletingLastPathComponent()
            }
            guard panel.runModal() == .OK, let url = panel.url else { return }
            destinationDir = url
        } else {
            let file = checkedFiles[0]
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = file.url.deletingPathExtension().lastPathComponent + "_watermarked.pdf"
            panel.directoryURL = file.url.deletingLastPathComponent()
            guard panel.runModal() == .OK, let url = panel.url else { return }
            singleFileOutputURL = url
        }
        
        Task {
            await MainActor.run {
                startOperation(message: "Adding watermark...")
                currentFileIndex = 0
            }
            
            for (index, file) in selectedFiles.enumerated() {
                guard file.isChecked else { continue }
                await MainActor.run {
                    currentFileIndex = index
                    selectedFiles[index].status = .compressing(0)
                }
                
                do {
                    let outputURL: URL
                    if let single = singleFileOutputURL {
                        outputURL = single
                    } else if let dir = destinationDir {
                        let filename = file.url.deletingPathExtension().lastPathComponent + "_watermarked.pdf"
                        outputURL = dir.appendingPathComponent(filename)
                    } else {
                        outputURL = file.url.deletingPathExtension().appendingPathExtension("_watermarked.pdf")
                    }
                    
                    try await PDFCompressor.watermark(
                        input: file.url,
                        output: outputURL,
                        text: watermarkText,
                        fontSize: watermarkFontSize,
                        opacity: watermarkOpacity,
                        diagonal: watermarkDiagonal,
                        password: nil
                    ) { prog in
                        Task { @MainActor in
                            selectedFiles[index].status = .compressing(prog)
                            let perFile = 1.0 / Double(checkedFiles.count)
                            totalProgress = (Double(index) * perFile) + (prog * perFile)
                        }
                    }
                    
                    await MainActor.run {
                        var updatedFile = selectedFiles[index]
                        updatedFile.status = .done
                        updatedFile.outputURL = outputURL
                        if let attr = try? FileManager.default.attributesOfItem(atPath: outputURL.path),
                           let size = attr[.size] as? Int64 {
                            updatedFile.compressedSize = size
                        }
                        selectedFiles[index] = updatedFile
                    }
                } catch {
                    await handleError(error)
                }
            }
            
            await MainActor.run {
                finishOperation(message: "Watermark added!")
                if let single = singleFileOutputURL {
                    PDFCompressor.revealInFinder(single)
                } else if let dir = destinationDir {
                    PDFCompressor.revealInFinder(dir)
                }
            }
        }
    }
    
    private func encryptPDF() {
        let checkedFiles = selectedFiles.filter { $0.isChecked }
        guard !checkedFiles.isEmpty else { return }
        guard !encryptPassword.isEmpty && encryptPassword == encryptConfirmPassword else { return }
        
        // Sandbox Compliance: Prompt
        var destinationDir: URL?
        var singleFileOutputURL: URL?
        
        if checkedFiles.count > 1 {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.prompt = "Select Output Folder"
            panel.message = "Choose where to save the encrypted files"
            if let first = checkedFiles.first {
                 panel.directoryURL = first.url.deletingLastPathComponent()
            }
            guard panel.runModal() == .OK, let url = panel.url else { return }
            destinationDir = url
        } else {
            let file = checkedFiles[0]
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = file.url.deletingPathExtension().lastPathComponent + "_encrypted.pdf"
            panel.directoryURL = file.url.deletingLastPathComponent()
            guard panel.runModal() == .OK, let url = panel.url else { return }
            singleFileOutputURL = url
        }
        
        Task {
            await MainActor.run {
                startOperation(message: "Encrypting...")
                currentFileIndex = 0
            }
            
            for (index, file) in selectedFiles.enumerated() {
                guard file.isChecked else { continue }
                await MainActor.run {
                    currentFileIndex = index
                    selectedFiles[index].status = .compressing(0)
                }
                
                do {
                    let outputURL: URL
                    if let single = singleFileOutputURL {
                        outputURL = single
                    } else if let dir = destinationDir {
                        let filename = file.url.deletingPathExtension().lastPathComponent + "_encrypted.pdf"
                        outputURL = dir.appendingPathComponent(filename)
                    } else {
                        outputURL = file.url.deletingPathExtension().appendingPathExtension("_encrypted.pdf")
                    }
                    
                    try await PDFCompressor.encrypt(
                        input: file.url,
                        output: outputURL,
                        userPassword: encryptPassword,
                        ownerPassword: nil,
                        allowPrinting: encryptAllowPrinting,
                        allowCopying: encryptAllowCopying,
                        password: nil
                    ) { prog in
                        Task { @MainActor in
                            selectedFiles[index].status = .compressing(prog)
                            let perFile = 1.0 / Double(checkedFiles.count)
                            totalProgress = (Double(index) * perFile) + (prog * perFile)
                        }
                    }
                    
                    await MainActor.run {
                        var updatedFile = selectedFiles[index]
                        updatedFile.status = .done
                        updatedFile.outputURL = outputURL
                        if let attr = try? FileManager.default.attributesOfItem(atPath: outputURL.path),
                           let size = attr[.size] as? Int64 {
                            updatedFile.compressedSize = size
                        }
                        selectedFiles[index] = updatedFile
                    }
                } catch {
                    await handleError(error)
                }
            }
            
            await MainActor.run {
                finishOperation(message: "Encryption complete!")
                if let single = singleFileOutputURL {
                    PDFCompressor.revealInFinder(single)
                } else if let dir = destinationDir {
                    PDFCompressor.revealInFinder(dir)
                }
            }
        }
    }

    private func decryptPDF() {
        let checkedFiles = selectedFiles.filter { $0.isChecked }
        guard !checkedFiles.isEmpty else { return }
        guard !decryptPassword.isEmpty else { return }
        
        // Sandbox Compliance: Prompt
        var destinationDir: URL?
        var singleFileOutputURL: URL?
        
        if checkedFiles.count > 1 {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.prompt = "Select Output Folder"
            panel.message = "Choose where to save the decrypted files"
            if let first = checkedFiles.first {
                 panel.directoryURL = first.url.deletingLastPathComponent()
            }
            guard panel.runModal() == .OK, let url = panel.url else { return }
            destinationDir = url
        } else {
            let file = checkedFiles[0]
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = file.url.deletingPathExtension().lastPathComponent + "_decrypted.pdf"
            panel.directoryURL = file.url.deletingLastPathComponent()
            guard panel.runModal() == .OK, let url = panel.url else { return }
            singleFileOutputURL = url
        }
        
        Task {
            await MainActor.run {
                startOperation(message: "Decrypting...")
                currentFileIndex = 0
            }
            
            for (index, file) in selectedFiles.enumerated() {
                guard file.isChecked else { continue }
                await MainActor.run {
                    currentFileIndex = index
                    selectedFiles[index].status = .compressing(0)
                }
                
                do {
                    let outputURL: URL
                    if let single = singleFileOutputURL {
                        outputURL = single
                    } else if let dir = destinationDir {
                        let filename = file.url.deletingPathExtension().lastPathComponent + "_decrypted.pdf"
                        outputURL = dir.appendingPathComponent(filename)
                    } else {
                        outputURL = file.url.deletingPathExtension().appendingPathExtension("_decrypted.pdf")
                    }
                    
                    try await PDFCompressor.decrypt(
                        input: file.url,
                        output: outputURL,
                        password: decryptPassword
                    ) { prog in
                        Task { @MainActor in
                            selectedFiles[index].status = .compressing(prog)
                            let perFile = 1.0 / Double(checkedFiles.count)
                            totalProgress = (Double(index) * perFile) + (prog * perFile)
                        }
                    }
                    
                    await MainActor.run {
                        var updatedFile = selectedFiles[index]
                        updatedFile.status = .done
                        updatedFile.outputURL = outputURL
                        if let attr = try? FileManager.default.attributesOfItem(atPath: outputURL.path),
                           let size = attr[.size] as? Int64 {
                            updatedFile.compressedSize = size
                        }
                        selectedFiles[index] = updatedFile
                    }
                } catch {
                    await handleError(error)
                }
            }
            
            await MainActor.run {
                finishOperation(message: "Decryption complete!")
                if let single = singleFileOutputURL {
                    PDFCompressor.revealInFinder(single)
                } else if let dir = destinationDir {
                    PDFCompressor.revealInFinder(dir)
                }
            }
        }
    }

    private func addPageNumbers() {
        let checkedFiles = selectedFiles.filter { $0.isChecked }
        guard !checkedFiles.isEmpty else { return }
        
        // Sandbox Compliance: Prompt
        var destinationDir: URL?
        var singleFileOutputURL: URL?
        
        if checkedFiles.count > 1 {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.prompt = "Select Output Folder"
            panel.message = "Choose where to save the files with page numbers"
            if let first = checkedFiles.first {
                 panel.directoryURL = first.url.deletingLastPathComponent()
            }
            guard panel.runModal() == .OK, let url = panel.url else { return }
            destinationDir = url
        } else {
            let file = checkedFiles[0]
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = file.url.deletingPathExtension().lastPathComponent + "_numbered.pdf"
            panel.directoryURL = file.url.deletingLastPathComponent()
            guard panel.runModal() == .OK, let url = panel.url else { return }
            singleFileOutputURL = url
        }
        
        Task {
            await MainActor.run {
                startOperation(message: "Adding page numbers...")
                currentFileIndex = 0
            }
            
            for (index, file) in selectedFiles.enumerated() {
                guard file.isChecked else { continue }
                await MainActor.run {
                    currentFileIndex = index
                    selectedFiles[index].status = .compressing(0)
                }
                
                do {
                    let outputURL: URL
                    if let single = singleFileOutputURL {
                        outputURL = single
                    } else if let dir = destinationDir {
                        let filename = file.url.deletingPathExtension().lastPathComponent + "_numbered.pdf"
                        outputURL = dir.appendingPathComponent(filename)
                    } else {
                        outputURL = file.url.deletingPathExtension().appendingPathExtension("_numbered.pdf")
                    }
                    
                    try await PDFCompressor.addPageNumbers(
                        input: file.url,
                        output: outputURL,
                        position: pageNumberPosition,
                        fontSize: pageNumberFontSize,
                        startFrom: pageNumberStartFrom,
                        format: pageNumberFormat,
                        password: nil
                    ) { prog in
                        Task { @MainActor in
                            selectedFiles[index].status = .compressing(prog)
                            let perFile = 1.0 / Double(checkedFiles.count)
                            totalProgress = (Double(index) * perFile) + (prog * perFile)
                        }
                    }
                    
                    await MainActor.run {
                        var updatedFile = selectedFiles[index]
                        updatedFile.status = .done
                        updatedFile.outputURL = outputURL
                        if let attr = try? FileManager.default.attributesOfItem(atPath: outputURL.path),
                           let size = attr[.size] as? Int64 {
                            updatedFile.compressedSize = size
                        }
                        selectedFiles[index] = updatedFile
                    }
                } catch {
                    await handleError(error)
                }
            }
            
            await MainActor.run {
                finishOperation(message: "Page numbers added!")
                if let single = singleFileOutputURL {
                    PDFCompressor.revealInFinder(single)
                } else if let dir = destinationDir {
                    PDFCompressor.revealInFinder(dir)
                }
            }
        }
    }

    private func reorderPages() {
        guard selectedFiles.count == 1, let file = selectedFiles.first else { return }
        guard !reorderPageOrder.isEmpty else { return }
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = file.url.deletingPathExtension().lastPathComponent + "_reordered.pdf"
        panel.directoryURL = file.url.deletingLastPathComponent()
        guard panel.runModal() == .OK, let outputURL = panel.url else { return }
        
        Task {
            await MainActor.run {
                startOperation(message: "Reordering pages...")
                currentFileIndex = 0
                selectedFiles[0].status = .compressing(0)
            }
            
            do {
                try await PDFCompressor.reorderPages(
                    input: file.url,
                    output: outputURL,
                    pageOrder: reorderPageOrder,
                    password: nil
                ) { prog in
                    Task { @MainActor in
                        selectedFiles[0].status = .compressing(prog)
                        totalProgress = prog
                    }
                }
                
                await MainActor.run {
                    var updatedFile = selectedFiles[0]
                    updatedFile.status = .done
                    updatedFile.outputURL = outputURL
                    if let attr = try? FileManager.default.attributesOfItem(atPath: outputURL.path),
                       let size = attr[.size] as? Int64 {
                        updatedFile.compressedSize = size
                    }
                    selectedFiles[0] = updatedFile
                }
            } catch {
                await handleError(error)
            }
            
            await MainActor.run {
                finishOperation(message: "Reorder complete!")
                PDFCompressor.revealInFinder(outputURL)
            }
        }
    }

    private func resizeToA4() {
        let checkedFiles = selectedFiles.filter { $0.isChecked }
        guard !checkedFiles.isEmpty else { return }
        
        // Sandbox Compliance: Prompt
        var destinationDir: URL?
        var singleFileOutputURL: URL?
        
        if checkedFiles.count > 1 {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.prompt = "Select Output Folder"
            panel.message = "Choose where to save the resized files"
            if let first = checkedFiles.first {
                 panel.directoryURL = first.url.deletingLastPathComponent()
            }
            guard panel.runModal() == .OK, let url = panel.url else { return }
            destinationDir = url
        } else {
            let file = checkedFiles[0]
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = file.url.deletingPathExtension().lastPathComponent + "_A4.pdf"
            panel.directoryURL = file.url.deletingLastPathComponent()
            guard panel.runModal() == .OK, let url = panel.url else { return }
            singleFileOutputURL = url
        }
        
        Task {
            await MainActor.run {
                startOperation(message: "Resizing to A4...")
                currentFileIndex = 0
                totalProgress = 0
            }
            
            var results: [CompressionResult] = []
            
            for (index, file) in selectedFiles.enumerated() {
                guard file.isChecked else { continue }
                await MainActor.run {
                    currentFileIndex = index
                    selectedFiles[index].status = .compressing(0)
                }
                
                do {
                    let outputURL: URL
                    if let single = singleFileOutputURL {
                        outputURL = single
                    } else if let dir = destinationDir {
                        let filename = file.url.deletingPathExtension().lastPathComponent + "_A4.pdf"
                        outputURL = dir.appendingPathComponent(filename)
                    } else {
                        outputURL = file.url.deletingPathExtension().appendingPathExtension("_A4.pdf")
                    }
                    
                    let startBytes = try FileManager.default.attributesOfItem(atPath: file.url.path)[.size] as? Int64 ?? 0
                    
                    try await PDFCompressor.resizeToA4(
                        input: file.url,
                        output: outputURL
                    ) { prog in
                        Task { @MainActor in
                            selectedFiles[index].status = .compressing(prog)
                            let perFile = 1.0 / Double(checkedFiles.count)
                            totalProgress = (Double(index) * perFile) + (prog * perFile)
                        }
                    }
                    
                    let endBytes = try FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int64 ?? 0
                    
                    await MainActor.run {
                        selectedFiles[index].status = .done
                        selectedFiles[index].outputURL = outputURL
                        selectedFiles[index].compressedSize = endBytes
                        
                        results.append(CompressionResult(
                            outputPath: outputURL,
                            originalSize: startBytes,
                            compressedSize: endBytes,
                            engine: .ghostscript
                        ))
                    }
                    
                } catch {
                     await MainActor.run {
                         selectedFiles[index].status = .error(error.localizedDescription)
                     }
                }
            }
            
            await MainActor.run {
                isCompressing = false
                totalProgress = 1.0
                lastResults = results
                showingResult = true
                
                if let single = singleFileOutputURL {
                    PDFCompressor.revealInFinder(single)
                } else if let dir = destinationDir {
                    PDFCompressor.revealInFinder(dir)
                }
            }
        }
    }

    private func generateMergeThumbnails() {
        thumbnailGenerationTask?.cancel()
        
        thumbnailGenerationTask = Task {
            for index in selectedFiles.indices {
                if selectedFiles[index].thumbnailURL == nil {
                    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                    
                    do {
                        let thumbs = try await PDFCompressor.generateThumbnails(
                            input: selectedFiles[index].url,
                            outputDir: tempDir,
                            dpi: 36
                        ) { _ in }
                        
                        if let first = thumbs.first {
                            await MainActor.run {
                                if index < selectedFiles.count {
                                    selectedFiles[index].thumbnailURL = first
                                }
                            }
                        }
                    } catch {
                        print("Thumbnail generation failed: \(error)")
                    }
                }
            }
        }
    }
    
    private func checkAndGenerateThumbnails() {
        if selectedTab == 2 && (selectedTool == .split || selectedTool == .rotateDelete) && selectedFiles.count == 1 {
            generateSplitThumbnails()
        }
    }

    private func generateSplitThumbnails() {
        guard selectedFiles.count == 1 else { return }
        let file = selectedFiles[0]
        
        thumbnailGenerationTask?.cancel()
        splitThumbnails = []
        splitSelectedPages = []
        
        thumbnailGenerationTask = Task {
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            
            do {
                let thumbs = try await PDFCompressor.generateThumbnails(
                    input: file.url,
                    outputDir: tempDir,
                    dpi: 50
                ) { _ in }
                
                await MainActor.run {
                    splitThumbnails = thumbs
                }
            } catch {
                print("Split thumbnail generation failed: \(error)")
            }
        }
    }

    @ViewBuilder
    private var fileListArea: some View {
        // Check if there are visible files after filtering
        let visibleFiles = selectedTab == 6 
            ? selectedFiles  // Research tab: show all files
            : selectedFiles.filter { $0.url.pathExtension.lowercased() == "pdf" }  // Other tabs: only PDFs
        
        if visibleFiles.isEmpty {
            DropZoneView(selectedFiles: $selectedFiles, selectedTab: selectedTab)
                .padding(.horizontal, 24)
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    handleDrop(providers: providers)
                }
        } else {
            VStack(spacing: 16) {
                if selectedTab == 2 && selectedTool == .merge {
                    MergeThumbnailView(files: $selectedFiles)
                        .frame(height: 250)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(12)
                        .onAppear { generateMergeThumbnails() }
                        .onChange(of: selectedFiles.count) { _ in generateMergeThumbnails() }
                } else if selectedTab == 2 && selectedTool == .reorder && selectedFiles.count == 1 {
                     ReorderThumbnailView(
                         pdfURL: selectedFiles[0].url,
                         pageOrder: $reorderPageOrder
                     )
                     .frame(height: 250)
                     .background(Color.black.opacity(0.3))
                     .cornerRadius(12)
                } else if selectedTab == 2 && (selectedTool == .split || selectedTool == .rotateDelete) && selectedFiles.count == 1 {
                     SplitThumbnailView(
                         thumbnails: splitThumbnails,
                         selectedPages: $splitSelectedPages,
                         multiSelect: selectedTool == .split ? (splitMode == .extractSelected) : true
                     )
                     .frame(height: 250)
                     .background(Color.black.opacity(0.3))
                     .cornerRadius(12)
                     .onAppear { generateSplitThumbnails() }
                     .onChange(of: selectedFiles) { _ in generateSplitThumbnails() }
                     .onChange(of: splitSelectedPages) { pages in
                          let sorted = pages.sorted()
                          if selectedTool == .rotateDelete && rotateOp == .delete {
                              // No specific range update needed for delete, just selection
                          } else if !sorted.isEmpty {
                              let min = sorted.first!
                              let max = sorted.last!
                              if splitMode == .extractRange {
                                  splitStartPage = min
                                  splitEndPage = max
                              }
                          }
                     }
                } else {
                    FileListView(
                        files: $selectedFiles,
                        onDelete: { indexSet in
                            selectedFiles.remove(atOffsets: indexSet)
                            statusMessage = ""
                        },
                        onCompare: { file in
                            if let out = file.outputURL {
                                comparisonInputURL = file.url
                                comparisonOutputURL = out
                                showingComparison = true
                            }
                        },
                        selectedTab: selectedTab
                    )
                    .frame(height: 200)
                }
                
                HStack {
                     Button("Clear All") {
                        selectedFiles.removeAll()
                        lastResults.removeAll()
                        statusMessage = ""
                        currentFileIndex = 0
                        totalProgress = 0
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.red)
                    
                    Spacer()
                }
            }
            .padding(.horizontal, 24)
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                handleDrop(providers: providers)
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        // Check if any provider has a .bib file
        let hasBibWithURL = providers.contains { provider in
            provider.canLoadObject(ofClass: URL.self)
        }
        
        if hasBibWithURL {
             // We can't synchronously check extension easily for all, so we'll load generic URL
             // If we find a .bib, we delegate.
             // Strategy: process all. If .bib found, handle via handleBibFileDrop. If PDF found, add to list.
        }

        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                guard let data = data as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                
                let ext = url.pathExtension.lowercased()
                
                if ext == "pdf" {
                    DispatchQueue.main.async {
                        if !selectedFiles.contains(where: { $0.url == url }) {
                            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
                            selectedFiles.append(ContentView.PDFFile(url: url, originalSize: size))
                        }
                    }
                } else if ext == "bib" {
                    // Add .bib files to the file list (just like PDFs)
                    DispatchQueue.main.async {
                        if !selectedFiles.contains(where: { $0.url == url }) {
                            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
                            // Auto-check .bib files when dropped
                            selectedFiles.append(ContentView.PDFFile(url: url, originalSize: size, isChecked: true))
                        }
                    }
                }
            }
        }
        return true
    }
}





struct FileListView: View {
    @Binding var files: [ContentView.PDFFile]
    let onDelete: (IndexSet) -> Void
    let onCompare: (ContentView.PDFFile) -> Void
    var selectedTab: Int = 0
    @AppStorage("isDarkMode_v2") private var isDarkMode = true

    // Filter files based on selected tab
    var filteredIndices: [Int] {
        // Researcher tab (6) shows both PDF and .bib files
        // BibTeX tab (7) shows only .bib files
        // All other tabs show only PDFs
        if selectedTab == 6 {
            return Array(files.indices)
        } else if selectedTab == 7 {
            return files.indices.filter { files[$0].url.pathExtension.lowercased() == "bib" }
        } else {
            return files.indices.filter { files[$0].url.pathExtension.lowercased() == "pdf" }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(filteredIndices, id: \.self) { index in
                    HStack {
                        FileRowView(file: $files[index], onCompare: onCompare)
                        
                        Spacer()

                        Button(action: {
                            onDelete(IndexSet(integer: index))
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isDarkMode ? Color(red: 30/255, green: 41/255, blue: 59/255).opacity(0.3) : Color.white.opacity(0.5))
                    
                    Divider()
                }
            }
        }
        .background(isDarkMode ? Color(red: 30/255, green: 41/255, blue: 59/255).opacity(0.5) : Color.white.opacity(0.6))
        .cornerRadius(12)
    }
}

struct WarningBanner: View {
    @AppStorage("isDarkMode_v2") private var isDarkMode = true

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)
            Text("Ghostscript not found. Using Apple compression (less effective).")
                .font(.system(size: 12))
                .foregroundColor(isDarkMode ? .white.opacity(0.9) : .black.opacity(0.8))
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color.orange.opacity(isDarkMode ? 0.2 : 0.1))
        .cornerRadius(8)
        .padding(.horizontal, 24)
    }
}

struct DropZoneView: View {
    @Binding var selectedFiles: [ContentView.PDFFile]
    @State private var isTargeted = false
    var selectedTab: Int = 0
    @AppStorage("isDarkMode_v2") private var isDarkMode = true

    var dropText: String {
        if selectedTab == 6 {
            return "Drop PDFs or .bib files here\nor click to browse"
        } else if selectedTab == 7 {
            return "Drop .bib files here\nor click to browse"
        } else {
            return "Drop PDFs here\nor click to browse"
        }
    }

    var textColor: Color {
        isDarkMode ? Color(red: 148/255, green: 163/255, blue: 184/255) : Color(red: 100/255, green: 116/255, blue: 139/255)
    }

    var backgroundColor: Color {
        if isTargeted {
            return Color.blue.opacity(0.1)
        } else if isDarkMode {
            return Color(red: 30/255, green: 41/255, blue: 59/255).opacity(0.6)
        } else {
            return Color.white.opacity(0.6)
        }
    }

    var strokeColor: Color {
        if isTargeted {
            return Color.blue
        } else if isDarkMode {
            return Color(red: 148/255, green: 163/255, blue: 184/255).opacity(0.4)
        } else {
            return Color(red: 203/255, green: 213/255, blue: 225/255)
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 48))
                .foregroundColor(textColor)

            Text(dropText)
                .font(.system(size: 14))
                .foregroundColor(textColor)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(strokeColor, style: StrokeStyle(lineWidth: 2, dash: [8]))
                )
        )
        .onTapGesture {
            let panel = NSOpenPanel()
            // Allow .bib files in Researcher tab (6)
            if selectedTab == 6 {
                panel.allowedContentTypes = [.pdf, UTType(filenameExtension: "bib") ?? .plainText]
            } else {
                panel.allowedContentTypes = [.pdf]
            }
            panel.allowsMultipleSelection = true
            if panel.runModal() == .OK {
                for url in panel.urls {
                     if !selectedFiles.contains(where: { $0.url == url }) {
                        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
                        selectedFiles.append(ContentView.PDFFile(url: url, originalSize: size))
                    }
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            for provider in providers {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                    guard let data = data as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }

                    let ext = url.pathExtension.lowercased()

                    // Only allow .bib files in Researcher tab (6) and BibTeX tab (7)
                    if ext == "bib" && selectedTab != 6 && selectedTab != 7 {
                        return
                    }

                    guard ext == "pdf" || ext == "bib" else { return }

                    DispatchQueue.main.async {
                         if !selectedFiles.contains(where: { $0.url == url }) {
                            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
                            selectedFiles.append(ContentView.PDFFile(url: url, originalSize: size))
                        }
                    }
                }
            }
            return true
        }
    }
}

struct BasicTabView: View {
    @Binding var selectedPreset: CompressionPreset
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Choose Compression Level")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
            
            ForEach(CompressionPreset.allCases) { preset in
                BasicPresetButton(preset: preset, selectedPreset: $selectedPreset)
            }
            
            Spacer()
        }
        .padding(20)
    }
}

struct BasicPresetButton: View {
    let preset: CompressionPreset
    @Binding var selectedPreset: CompressionPreset
    @AppStorage("isDarkMode_v2") private var isDarkMode = true
    
    var body: some View {
        Button(action: { selectedPreset = preset }) {
            VStack(spacing: 4) {
                Text(preset.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(selectedPreset == preset ? .white : .primary)
                Text(preset.description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        selectedPreset == preset
                            ? LinearGradient(colors: [
                                Color(red: 59/255, green: 130/255, blue: 246/255),
                                Color(red: 37/255, green: 99/255, blue: 235/255)
                              ], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: isDarkMode ? [
                                Color(red: 30/255, green: 41/255, blue: 59/255).opacity(0.8),
                                Color(red: 30/255, green: 41/255, blue: 59/255).opacity(0.8)
                              ] : [
                                Color.white,
                                Color.white
                              ], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(red: 148/255, green: 163/255, blue: 184/255).opacity(0.2), lineWidth: selectedPreset == preset ? 0 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct ProTabView: View {
    @Binding var settings: ProSettings
    @Binding var selectedPreset: ProPreset
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ProPresetsView(selectedPreset: $selectedPreset, settings: $settings)
                ProImageSettingsView(settings: $settings)
                ProColorSettingsView(settings: $settings)
                ProFontSettingsView(settings: $settings)
                ProPDFSettingsView(settings: $settings)
                ProAdvancedSettingsView(settings: $settings)
                ProCustomArgsView(settings: $settings)
                
                Button("Reset to Defaults") {
                    selectedPreset = .email
                    settings = ProPreset.email.toSettings()
                }
                .foregroundColor(.secondary)
            }
            .padding(16)
        }
    }
}

struct ProPresetsView: View {
    @Binding var selectedPreset: ProPreset
    @Binding var settings: ProSettings
    @AppStorage("isDarkMode_v2") private var isDarkMode = true
    
    var body: some View {
        GroupBox("Quick Presets") {
            HStack(spacing: 8) {
                ForEach(ProPreset.allCases) { preset in
                    Button(action: {
                        selectedPreset = preset
                        settings = preset.toSettings()
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: preset.icon)
                                .font(.system(size: 16))
                            Text(preset.name)
                                .font(.system(size: 10))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedPreset == preset
                                    ? Color.blue
                                    : (isDarkMode ? Color(red: 30/255, green: 41/255, blue: 59/255).opacity(0.8) : Color.white))
                        )
                        .foregroundColor(selectedPreset == preset ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct ProImageSettingsView: View {
    @Binding var settings: ProSettings
    
    var body: some View {
        GroupBox("Image Settings") {
            VStack(spacing: 12) {
                SliderRow(label: "Color DPI", value: $settings.colorDPI, range: 36...600, suffix: " dpi")
                SliderRow(label: "Gray DPI", value: $settings.grayDPI, range: 36...600, suffix: " dpi")
                SliderRow(label: "Mono DPI", value: $settings.monoDPI, range: 36...1200, suffix: " dpi")
                SliderRow(label: "JPEG Quality", value: $settings.jpegQuality, range: 10...100, suffix: "%")
                
                HStack {
                    Text("Compression")
                        .frame(width: 100, alignment: .leading)
                    Picker("", selection: $settings.imageFilter) {
                        ForEach(ImageFilter.allCases) { filter in
                            Text(filter.displayName).tag(filter)
                        }
                    }
                    .labelsHidden()
                }
            }
        }
    }
}

struct ProColorSettingsView: View {
    @Binding var settings: ProSettings
    
    var body: some View {
        GroupBox("Color Settings") {
            VStack(spacing: 12) {
                HStack {
                    Text("Color Mode")
                        .frame(width: 100, alignment: .leading)
                    Picker("", selection: $settings.colorStrategy) {
                        ForEach(ColorStrategy.allCases) { strategy in
                            Text(strategy.displayName).tag(strategy)
                        }
                    }
                    .labelsHidden()
                }
                
                Toggle("Preserve overprint settings", isOn: $settings.preserveOverprint)
            }
        }
    }
}

struct ProFontSettingsView: View {
    @Binding var settings: ProSettings
    
    var body: some View {
        GroupBox("Font Settings") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Embed all fonts", isOn: $settings.embedFonts)
                Toggle("Subset fonts (only used characters)", isOn: $settings.subsetFonts)
                Toggle("Compress fonts", isOn: $settings.compressFonts)
            }
        }
    }
}

struct ProPDFSettingsView: View {
    @Binding var settings: ProSettings
    
    var body: some View {
        GroupBox("PDF Settings") {
            VStack(spacing: 12) {
                HStack {
                    Text("Compatibility")
                        .frame(width: 100, alignment: .leading)
                    Picker("", selection: $settings.compatLevel) {
                        ForEach(CompatLevel.allCases) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                    .labelsHidden()
                }
                
                Toggle("Optimize for fast web view", isOn: $settings.fastWebView)
            }
        }
    }
}

struct ProAdvancedSettingsView: View {
    @Binding var settings: ProSettings
    
    var body: some View {
        GroupBox("Advanced Options") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Detect duplicate images", isOn: $settings.detectDuplicates)
                Toggle("Remove document metadata", isOn: $settings.removeMetadata)
                Toggle("Use ASCII85 encoding", isOn: $settings.ascii85)
            }
        }
    }
}

struct ProCustomArgsView: View {
    @Binding var settings: ProSettings
    
    var body: some View {
        GroupBox("Custom Arguments") {
            TextField("Additional gs arguments", text: $settings.customArgs)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
        }
    }
}

struct SliderRow: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let suffix: String
    
    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .frame(width: 100, alignment: .leading)
            Slider(value: Binding(
                get: { Double(value) },
                set: { value = Int($0) }
            ), in: Double(range.lowerBound)...Double(range.upperBound))
            Text("\(value)\(suffix)")
                .font(.system(.body, design: .monospaced))
                .frame(width: 70, alignment: .trailing)
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}


enum SplitMode: Int, CaseIterable, Identifiable {
    case splitAll
    case extractRange
    case extractSelected
    
    var id: Int { rawValue }
    var description: String {
        switch self {
        case .splitAll: return "Split into single pages"
        case .extractRange: return "Extract page range"
        case .extractSelected: return "Extract selected pages"
        }
    }
}

enum RotateOperation: Int, CaseIterable, Identifiable {
    case rotate
    case delete
    
    var id: Int { rawValue }
    var description: String {
        switch self {
        case .rotate: return "Rotate Pages"
        case .delete: return "Delete Pages"
        }
    }
}

enum ToolMode: String, CaseIterable, Identifiable {
    case rasterize
    case extractImages
    case merge
    case split
    case rotateDelete
    case pageNumber
    case reorder
    case resizeA4
    
    var id: String { rawValue }

    var name: String {
        switch self {
        case .rasterize: return "Rasterize"
        case .extractImages: return "Extract Imgs"
        case .merge: return "Merge PDF"
        case .split: return "Split PDF"
        case .rotateDelete: return "Rotate/Delete"
        case .pageNumber: return "Page Numbers"
        case .reorder: return "Reorder"
        case .resizeA4: return "Resize to A4"
        }
    }

    var icon: String {
        switch self {
        case .rasterize: return "photo.on.rectangle"
        case .extractImages: return "photo.on.rectangle.angled"
        case .merge: return "doc.on.doc"
        case .split: return "scissors"
        case .rotateDelete: return "rotate.right"
        case .pageNumber: return "number.circle"
        case .reorder: return "arrow.up.arrow.down"
        case .resizeA4: return "doc.viewfinder"
        }
    }
    var description: String {
        switch self {
        case .rasterize: return "Convert pages to bitmaps to prevent editing/copying."
        case .extractImages: return "Save each page as a high-quality image file."
        case .pageNumber: return "Add page numbers to your PDF documents."
        case .merge: return "Combine multiple PDF files into a single document."
        case .split: return "Split PDF into multiple files or extract specific pages."
        case .rotateDelete: return "Rotate pages or delete specific pages."
        case .reorder: return "Reorder pages via drag-and-drop."
        case .resizeA4: return "Scale all pages to standard A4 size (210x297mm)."
        }
    }
}

enum SecurityMode: Int, CaseIterable, Identifiable {
    case watermark
    case encrypt
    case decrypt

    var id: Int { rawValue }
    var description: String {
        switch self {
        case .watermark: return "Add Watermark"
        case .encrypt: return "Encrypt PDF"
        case .decrypt: return "Decrypt PDF"
        }
    }
}

enum PageNumberPosition: Int, CaseIterable, Identifiable {
    case topLeft, topCenter, topRight
    case bottomLeft, bottomCenter, bottomRight

    var id: Int { rawValue }
    var description: String {
        switch self {
        case .topLeft: return "Top Left"
        case .topCenter: return "Top Center"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomCenter: return "Bottom Center"
        case .bottomRight: return "Bottom Right"
        }
    }
}

enum PageNumberFormat: Int, CaseIterable, Identifiable {
    case numbers           // 1, 2, 3
    case numbersWithTotal  // 1/10, 2/10
    case pageN             // Page 1, Page 2

    var id: Int { rawValue }
    var description: String {
        switch self {
        case .numbers: return "1, 2, 3..."
        case .numbersWithTotal: return "1/10, 2/10..."
        case .pageN: return "Page 1, Page 2..."
        }
    }
}

struct ToolsTabView: View {
    @Binding var selectedTool: ToolMode
    @Binding var rasterDPI: Int
    @Binding var imageFormat: ImageFormat
    @Binding var extractMode: ExtractMode
    @Binding var imageDPI: Int
    @Binding var showManualSelector: Bool
    @Binding var splitMode: SplitMode
    @Binding var splitStartPage: Int
    @Binding var splitEndPage: Int
    @Binding var rotateOp: RotateOperation
    @Binding var rotationAngle: Int
    @Binding var pagesToDelete: String
    @Binding var pageNumberPosition: PageNumberPosition
    @Binding var pageNumberFontSize: Int
    @Binding var pageNumberStartFrom: Int
    @Binding var pageNumberFormat: PageNumberFormat
    @Binding var reorderPageOrder: [Int]
    @Binding var splitSelectedPages: Set<Int>
    var splitThumbnailsCount: Int
    @AppStorage("isDarkMode_v2") private var isDarkMode = true


    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ToolSelectionView(selectedTool: $selectedTool)

                if selectedTool == .rasterize {
                    RasterizeSettingsView(rasterDPI: $rasterDPI)
                } else if selectedTool == .extractImages {
                    ExtractImagesSettingsView(imageFormat: $imageFormat, imageDPI: $imageDPI, extractMode: $extractMode, showManualSelector: $showManualSelector)
                } else if selectedTool == .split {
                    SplitSettingsView(splitMode: $splitMode, splitStartPage: $splitStartPage, splitEndPage: $splitEndPage)
                } else if selectedTool == .rotateDelete {
                    RotateDeleteSettingsView(rotateOp: $rotateOp, rotationAngle: $rotationAngle, pagesToDelete: $pagesToDelete, selectedPages: $splitSelectedPages, totalPages: splitThumbnailsCount)
                } else if selectedTool == .pageNumber {
                    PageNumberSettingsView(
                        pageNumberPosition: $pageNumberPosition,
                        pageNumberFontSize: $pageNumberFontSize,
                        pageNumberStartFrom: $pageNumberStartFrom,
                        pageNumberFormat: $pageNumberFormat
                    )
                } else if selectedTool == .reorder {
                    ReorderSettingsView(pageOrder: $reorderPageOrder)
                } else {
                    MergeSettingsView()
                }
            }
            .padding(16)
        }
    }
}

struct ToolSelectionView: View {
    @Binding var selectedTool: ToolMode
    @AppStorage("isDarkMode_v2") private var isDarkMode = true
    
    var body: some View {
        GroupBox("Select Tool") {
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach(ToolMode.allCases) { tool in
                    Button(action: { selectedTool = tool }) {
                        VStack(spacing: 6) {
                            Image(systemName: tool.icon)
                                .font(.system(size: 18))
                            Text(tool.name)
                                .font(.system(size: 10, weight: .medium))
                                .multilineTextAlignment(.center)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedTool == tool
                                    ? Color.blue
                                    : (isDarkMode ? Color(red: 30/255, green: 41/255, blue: 59/255).opacity(0.8) : Color.white))
                        )
                        .foregroundColor(selectedTool == tool ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct RasterizeSettingsView: View {
    @Binding var rasterDPI: Int
    
    var body: some View {
        GroupBox("Rasterization Settings") {
            VStack(spacing: 12) {
                Text("This will flatten the PDF into images, making text unselectable and vector graphics uneditable.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Divider().background(Color(red: 51/255, green: 65/255, blue: 85/255))
                
                SliderRow(label: "Resolution", value: $rasterDPI, range: 72...600, suffix: " dpi")
            }
        }
    }
}

struct ExtractImagesSettingsView: View {
    @Binding var imageFormat: ImageFormat
    @Binding var imageDPI: Int
    @Binding var extractMode: ExtractMode
    @Binding var showManualSelector: Bool
    
    var body: some View {
        GroupBox("Extraction Settings") {
            VStack(spacing: 12) {
                Picker("Mode", selection: $extractMode) {
                    ForEach(ExtractMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                
                if extractMode == .renderPage {
                    HStack {
                        Text("Format")
                            .frame(width: 100, alignment: .leading)
                        Picker("", selection: $imageFormat) {
                            ForEach(ImageFormat.allCases) { format in
                                Text(format.displayName).tag(format)
                            }
                        }
                        .labelsHidden()
                        Spacer()
                    }
                    
                    SliderRow(label: "Resolution", value: $imageDPI, range: 72...600, suffix: " dpi")
                } else if extractMode == .manualSelection {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Manually select specific regions (plots, figures, tables) from PDF pages by drawing rectangles.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Divider()

                        Button("Open Region Selector...") {
                            showManualSelector = true
                        }
                        .padding(.top, 4)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Extracts embedded images from the PDF (supports JPEG, PNG & CMYK). CMYK images are converted to RGB PNGs.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)


                        Divider()
                        
                        Text("(No AI Mode)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                }
            }
        }
    }
}


struct SplitSettingsView: View {
    @Binding var splitMode: SplitMode
    @Binding var splitStartPage: Int
    @Binding var splitEndPage: Int
    
    var body: some View {
        GroupBox("Split Settings") {
            VStack(spacing: 12) {
                Picker("Mode", selection: $splitMode) {
                    ForEach(SplitMode.allCases) { mode in
                        Text(mode.description).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                
                if splitMode == .extractRange {
                    HStack {
                        Text("Page Range:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        TextField("Start", value: $splitStartPage, formatter: NumberFormatter())
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 50)
                        Text("to")
                        TextField("End", value: $splitEndPage, formatter: NumberFormatter())
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 50)
                    }
                } else if splitMode == .extractSelected {
                    Text("Select pages to extract from the thumbnail view above.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Each page will be saved as a separate PDF file.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

struct FileRowView: View {
    @Binding var file: ContentView.PDFFile
    let onCompare: (ContentView.PDFFile) -> Void
    
    var body: some View {
        HStack {
            Image(systemName: file.isChecked ? "checkmark.square.fill" : "square")
                .foregroundColor(file.isChecked ? .blue : .secondary)
                .font(.system(size: 20))
                .onTapGesture {
                    file.isChecked.toggle()
                }
                .padding(.trailing, 8)

            VStack(alignment: .leading) {
                Text(file.url.lastPathComponent)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                Text(formatSize(file.originalSize))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            switch file.status {
            case .pending:
                Text("Pending")
                    .font(.caption)
                    .foregroundColor(.secondary)
            case .compressing(let progress):
                ProgressView(value: progress)
                    .progressViewStyle(.circular)
                    .scaleEffect(0.5)
            case .done:
                HStack(spacing: 12) {
                    if file.outputURL != nil {
                        Button(action: { onCompare(file) }) {
                            Image(systemName: "arrow.left.and.right.circle")
                                .foregroundColor(.blue)
                                .font(.system(size: 16))
                        }
                        .buttonStyle(.plain)
                        .help("Compare Original vs Compressed")
                    }
                    
                    VStack(alignment: .trailing) {
                        Text(formatSize(file.compressedSize))
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                        let reduction = Double(file.originalSize - file.compressedSize) / Double(file.originalSize) * 100
                        Text("-\(String(format: "%.0f", reduction))%")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            case .error(let msg):
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.red)
                    .help(msg)
            }
        }
        .contextMenu {
            Button("Reveal in Finder") {
                PDFCompressor.revealInFinder(file.url)
            }
            if let output = file.outputURL {
                Button("Reveal Output in Finder") {
                    PDFCompressor.revealInFinder(output)
                }
            }
        }
    }
    
    private func formatSize(_ size: Int64) -> String {
        return String(format: "%.2f MB", Double(size) / (1024 * 1024))
    }
}

struct RotateDeleteSettingsView: View {
    @Binding var rotateOp: RotateOperation
    @Binding var rotationAngle: Int
    @Binding var pagesToDelete: String
    @Binding var selectedPages: Set<Int>
    var totalPages: Int
    
    var body: some View {
        GroupBox("Rotate / Delete Settings") {
            VStack(spacing: 12) {
                Picker("Operation", selection: $rotateOp) {
                    ForEach(RotateOperation.allCases) { op in
                        Text(op.description).tag(op)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                
                if rotateOp == .rotate {
                    Text("Select pages to rotate from the thumbnail view above.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    HStack {
                        Button(action: { rotationAngle = (rotationAngle - 90 + 360) % 360 }) {
                            Label("Left", systemImage: "rotate.left")
                        }
                        .buttonStyle(.bordered)
                        
                        Spacer()
                        
                        Text("\(rotationAngle)°")
                            .font(.headline)
                            .frame(minWidth: 50)
                        
                        Spacer()
                        
                        Button(action: { rotationAngle = (rotationAngle + 90) % 360 }) {
                                Label("Right", systemImage: "rotate.right")
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    // Quick select for rotate
                    if totalPages > 0 {
                        HStack(spacing: 8) {
                            Button("Select Odd") {
                                selectedPages = Set((1...totalPages).filter { $0 % 2 == 1 })
                            }
                            .buttonStyle(.bordered)
                            
                            Button("Select Even") {
                                selectedPages = Set((1...totalPages).filter { $0 % 2 == 0 })
                            }
                            .buttonStyle(.bordered)
                            
                            Button("Select All") {
                                selectedPages = Set(1...totalPages)
                            }
                            .buttonStyle(.bordered)
                            
                            Button("Clear") {
                                selectedPages = []
                            }
                            .buttonStyle(.bordered)
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    Text("Select pages to delete from the thumbnail view above.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Quick select for delete
                    if totalPages > 0 {
                        HStack(spacing: 8) {
                            Button("Select Odd") {
                                selectedPages = Set((1...totalPages).filter { $0 % 2 == 1 })
                            }
                            .buttonStyle(.bordered)
                            
                            Button("Select Even") {
                                selectedPages = Set((1...totalPages).filter { $0 % 2 == 0 })
                            }
                            .buttonStyle(.bordered)
                            
                            Button("Select All") {
                                selectedPages = Set(1...totalPages)
                            }
                            .buttonStyle(.bordered)
                            
                            Button("Clear") {
                                selectedPages = []
                            }
                            .buttonStyle(.bordered)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}

struct MergeSettingsView: View {
    var body: some View {
        GroupBox("Merge Settings") {
            VStack(spacing: 12) {
                Text("Drag and drop files in the main list to reorder them before merging.")
                    .font(.system(size: 12))
                    .foregroundColor(Color(red: 148/255, green: 163/255, blue: 184/255))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct ReorderSettingsView: View {
    @Binding var pageOrder: [Int]
    @State private var text: String = ""
    @State private var isEditing: Bool = false
    
    var body: some View {
        GroupBox("Reorder Pages") {
            VStack(spacing: 12) {
                Text("Enter the new page order as comma-separated numbers.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                TextField("e.g., 3,1,2,4", text: $text, onEditingChanged: { editing in
                    isEditing = editing
                    if !editing {
                        parseText()
                    }
                })
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    parseText()
                }
                .onChange(of: pageOrder) { newValue in
                    if !isEditing {
                        text = formatPageOrder(newValue)
                    }
                }
                .onAppear {
                    text = formatPageOrder(pageOrder)
                }
                
                HStack(spacing: 12) {
                    Button(action: {
                        withAnimation {
                            pageOrder.reverse()
                        }
                    }) {
                        Label("Reverse", systemImage: "arrow.up.arrow.down")
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: {
                        withAnimation {
                            pageOrder.sort()
                        }
                    }) {
                        Label("Sort (1-N)", systemImage: "arrow.up")
                    }
                    .buttonStyle(.bordered)
                    
                    if !pageOrder.isEmpty {
                        Button(action: {
                            withAnimation {
                                // Odd pages first, then even
                                let odds = pageOrder.filter { $0 % 2 == 1 }.sorted()
                                let evens = pageOrder.filter { $0 % 2 == 0 }.sorted()
                                pageOrder = odds + evens
                            }
                        }) {
                            Label("Odd First", systemImage: "number")
                        }
                        .buttonStyle(.bordered)
                        
                        Button(action: {
                            withAnimation {
                                pageOrder = Array(1...pageOrder.count)
                            }
                        }) {
                            Label("Reset", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity)
                
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                    Text("Example: '3,1,2' outputs page 3 first, then page 1, then page 2.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Image(systemName: "hand.draw.fill")
                        .foregroundColor(.blue)
                    Text("You can also reorder pages by dragging the thumbnails above.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private func parseText() {
        let components = text.split(separator: ",")
        var newOrder: [Int] = []
        for component in components {
            let trimmed = component.trimmingCharacters(in: .whitespacesAndNewlines)
            if let val = Int(trimmed) {
                newOrder.append(val)
            } else if trimmed.contains("-") {
                // Handle ranges like 1-5
                let parts = trimmed.split(separator: "-")
                if parts.count == 2, let start = Int(parts[0]), let end = Int(parts[1]) {
                    if start <= end {
                        newOrder.append(contentsOf: start...end)
                    } else {
                        newOrder.append(contentsOf: (end...start).reversed())
                    }
                }
            }
        }
        
        // Basic validation: ensure no duplicates? Or just let it be (allows duplicating pages)
        // Reordering usually implies permutation, but sometimes users want duplication.
        // However, ReorderThumbnailView assumes permutation for dragging. 
        // If the user enters a non-permutation, the thumbnail view might behave oddly but likely handles mismatched IDs by reloading.
        if !newOrder.isEmpty {
            pageOrder = newOrder
        }
    }
    
    private func formatPageOrder(_ order: [Int]) -> String {
        // Show all page numbers individually
        return order.map { String($0) }.joined(separator: ", ")
    }
}

struct SecurityTabView: View {
    @Binding var securityMode: SecurityMode
    @Binding var watermarkText: String
    @Binding var watermarkOpacity: Double
    @Binding var watermarkDiagonal: Bool
    @Binding var watermarkFontSize: Int
    @Binding var encryptPassword: String
    @Binding var encryptConfirmPassword: String
    @Binding var encryptAllowPrinting: Bool
    @Binding var encryptAllowCopying: Bool
    @Binding var decryptPassword: String

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Security Mode", selection: $securityMode) {
                    ForEach(SecurityMode.allCases) { mode in
                        Text(mode.description).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if securityMode == .watermark {
                    WatermarkSettingsView(
                        watermarkText: $watermarkText,
                        watermarkOpacity: $watermarkOpacity,
                        watermarkDiagonal: $watermarkDiagonal,
                        watermarkFontSize: $watermarkFontSize
                    )
                } else if securityMode == .encrypt {
                    EncryptSettingsView(
                        encryptPassword: $encryptPassword,
                        encryptConfirmPassword: $encryptConfirmPassword,
                        encryptAllowPrinting: $encryptAllowPrinting,
                        encryptAllowCopying: $encryptAllowCopying
                    )
                } else {
                    DecryptSettingsView(decryptPassword: $decryptPassword)
                }
            }
            .padding(.horizontal, 24)
        }
    }
}

struct WatermarkSettingsView: View {
    @Binding var watermarkText: String
    @Binding var watermarkOpacity: Double
    @Binding var watermarkDiagonal: Bool
    @Binding var watermarkFontSize: Int
    
    var body: some View {
        GroupBox("Watermark Settings") {
            VStack(spacing: 12) {
                HStack {
                    Text("Text:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Watermark text", text: $watermarkText)
                        .textFieldStyle(.roundedBorder)
                }
                
                HStack {
                    Text("Opacity: \(Int(watermarkOpacity * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Slider(value: $watermarkOpacity, in: 0.1...1.0)
                }
                
                HStack {
                    Text("Font Size:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Stepper("\(watermarkFontSize) pt", value: $watermarkFontSize, in: 12...120, step: 6)
                }
                
                Toggle("Diagonal", isOn: $watermarkDiagonal)
                    .font(.caption)
                
                Text("Watermark will appear on all pages of the PDF.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct EncryptSettingsView: View {
    @Binding var encryptPassword: String
    @Binding var encryptConfirmPassword: String
    @Binding var encryptAllowPrinting: Bool
    @Binding var encryptAllowCopying: Bool
    
    var passwordsMatch: Bool {
        !encryptPassword.isEmpty && encryptPassword == encryptConfirmPassword
    }
    
    var body: some View {
        GroupBox("Encryption Settings") {
            VStack(spacing: 12) {
                SecureField("Password", text: $encryptPassword)
                    .textFieldStyle(.roundedBorder)
                
                SecureField("Confirm Password", text: $encryptConfirmPassword)
                    .textFieldStyle(.roundedBorder)
                
                if !encryptPassword.isEmpty && !passwordsMatch {
                    Text("Passwords do not match")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                
                Divider()
                
                Text("Permissions")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Toggle("Allow Printing", isOn: $encryptAllowPrinting)
                    .font(.caption)
                Toggle("Allow Copying", isOn: $encryptAllowCopying)
                    .font(.caption)
                
                Text("The password will be required to open the PDF.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct DecryptSettingsView: View {
    @Binding var decryptPassword: String
    
    var body: some View {
        GroupBox("Decrypt Settings") {
            VStack(spacing: 12) {
                SecureField("Enter PDF Password", text: $decryptPassword)
                    .textFieldStyle(.roundedBorder)
                
                Text("Enter the password of the protected PDF. The output will be an unprotected copy.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct PageNumberSettingsView: View {
    @Binding var pageNumberPosition: PageNumberPosition
    @Binding var pageNumberFontSize: Int
    @Binding var pageNumberStartFrom: Int
    @Binding var pageNumberFormat: PageNumberFormat

    var body: some View {
        GroupBox("Page Numbering Settings") {
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Position:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker("Position", selection: $pageNumberPosition) {
                        ForEach(PageNumberPosition.allCases) { position in
                            Text(position.description).tag(position)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Format:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker("Format", selection: $pageNumberFormat) {
                        ForEach(PageNumberFormat.allCases) { format in
                            Text(format.description).tag(format)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                HStack {
                    Text("Font Size:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Stepper("\(pageNumberFontSize) pt", value: $pageNumberFontSize, in: 8...24, step: 2)
                }

                HStack {
                    Text("Start From:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Stepper("Page \(pageNumberStartFrom)", value: $pageNumberStartFrom, in: 1...100)
                }

                Text("Page numbers will be added to all pages of the PDF.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Advanced Tools

enum AdvancedMode: Int, CaseIterable, Identifiable {
    case repair
    case pdfa
    
    var id: Int { rawValue }
    var name: String {
        switch self {
        case .repair: return "Repair & Sanitize"
        case .pdfa: return "Convert to PDF/A"
        }
    }
    
    var icon: String {
        switch self {
        case .repair: return "hammer"
        case .pdfa: return "archivebox"
        }
    }
    
    var description: String {
        switch self {
        case .repair: return "Fix corrupted files by rebuilding the PDF structure."
        case .pdfa: return "Convert to PDF/A-2b standard for long-term preservation."
        }
    }
}

struct AdvancedToolsView: View {
    @Binding var advancedMode: AdvancedMode
    
    var body: some View {
        GroupBox("Advanced Tools") {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    ForEach(AdvancedMode.allCases) { mode in
                        Button(action: { advancedMode = mode }) {
                            VStack(spacing: 8) {
                                Image(systemName: mode.icon)
                                    .font(.system(size: 24))
                                Text(mode.name)
                                    .font(.system(size: 13, weight: .medium))
                                Text(mode.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 4)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(advancedMode == mode ? Color.blue.opacity(0.1) : Color.primary.opacity(0.05))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(advancedMode == mode ? Color.blue : Color.clear, lineWidth: 2)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                // Info text depending on selection
                if advancedMode == .pdfa {
                     HStack {
                         Image(systemName: "info.circle")
                         Text("PDF/A-2b ensures document appearance is preserved over time. This process will embed standard fonts.")
                             .font(.caption)
                     }
                     .foregroundColor(.secondary)
                     .padding(.top, 8)
                }
            }
            .padding(12)
        }
    }
}

extension ContentView {
    
    @ViewBuilder
    var advancedTabContent: some View {
        if appState.ghostscriptAvailable {
            ScrollView {
                VStack(spacing: 16) {
                    AdvancedToolsView(advancedMode: $advancedMode)
                }
                .padding(16)
            }
        } else {
            gsRequirementView
        }
    }
    
    func performAdvancedAction() {
         let checkedFiles = selectedFiles.filter { $0.isChecked }
         guard !checkedFiles.isEmpty else { return }
         
         let opName = advancedMode == .repair ? "Repairing..." : "Converting to PDF/A..."
         let suffix = advancedMode == .repair ? "_repaired" : "_pdfa"
         
         // Sandbox Compliance: Prompt
         var destinationDir: URL?
         var singleFileOutputURL: URL?
         
         if checkedFiles.count > 1 {
             let panel = NSOpenPanel()
             panel.canChooseDirectories = true
             panel.canChooseFiles = false
             panel.allowsMultipleSelection = false
             panel.prompt = "Select Output Folder"
             panel.message = "Choose where to save the converted files"
             if let first = checkedFiles.first {
                  panel.directoryURL = first.url.deletingLastPathComponent()
             }
             guard panel.runModal() == .OK, let url = panel.url else { return }
             destinationDir = url
         } else {
             let file = checkedFiles[0]
             let panel = NSSavePanel()
             panel.allowedContentTypes = [.pdf]
             panel.nameFieldStringValue = file.url.deletingPathExtension().lastPathComponent + suffix + ".pdf"
             panel.directoryURL = file.url.deletingLastPathComponent()
             guard panel.runModal() == .OK, let url = panel.url else { return }
             singleFileOutputURL = url
         }
         
         startOperation(message: opName)
         
         Task {
             var results: [CompressionResult] = []
             
             for (index, file) in selectedFiles.enumerated() {
                 guard file.isChecked else { continue }
                 await MainActor.run {
                     currentFileIndex = index
                     selectedFiles[index].status = .compressing(0)
                 }
                 
                 do {
                     let outputURL: URL
                     if let single = singleFileOutputURL {
                         outputURL = single
                     } else if let dir = destinationDir {
                         let filename = file.url.deletingPathExtension().lastPathComponent + suffix + ".pdf"
                         outputURL = dir.appendingPathComponent(filename)
                     } else {
                         outputURL = file.url.deletingPathExtension().appendingPathExtension(suffix + ".pdf")
                     }
                     
                     if advancedMode == .repair {
                         try await PDFCompressor.repairPDF(
                             input: file.url,
                             output: outputURL,
                             password: nil
                         ) { prog in
                             Task { @MainActor in
                                 selectedFiles[index].status = .compressing(prog)
                                 totalProgress = (Double(results.count) / Double(checkedFiles.count)) + (prog / Double(checkedFiles.count))
                             }
                         }
                     } else {
                         try await PDFCompressor.convertToPDFA(
                             input: file.url,
                             output: outputURL,
                             password: nil
                         ) { prog in
                             Task { @MainActor in
                                 selectedFiles[index].status = .compressing(prog)
                                 totalProgress = (Double(results.count) / Double(checkedFiles.count)) + (prog / Double(checkedFiles.count))
                             }
                         }
                     }
                     
                     let originalSize = (try? FileManager.default.attributesOfItem(atPath: file.url.path)[.size] as? Int64) ?? 0
                     let compressedSize = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int64) ?? 0
                     
                     let result = CompressionResult(
                        outputPath: outputURL,
                        originalSize: originalSize,
                        compressedSize: compressedSize,
                        engine: .ghostscript
                     )
                     results.append(result)
                     
                     await MainActor.run {
                         var updatedFile = selectedFiles[index]
                         updatedFile.status = .done
                         updatedFile.outputURL = outputURL
                         updatedFile.compressedSize = compressedSize
                         selectedFiles[index] = updatedFile
                     }
                     
                 } catch {
                     await MainActor.run {
                         selectedFiles[index].status = .error(error.localizedDescription)
                     }
                 }
             }
             
             await MainActor.run {
                 lastResults = results
                 finishOperation(message: "Done!")
                 showingResult = true
                 
                 if let single = singleFileOutputURL {
                     PDFCompressor.revealInFinder(single)
                 } else if let dir = destinationDir {
                     PDFCompressor.revealInFinder(dir)
                 }
             }
         }
    }
}

struct AITabView: View {
    @Binding var selectedFiles: [ContentView.PDFFile]
    @Binding var summaryType: SummaryType
    @Binding var summaryText: String
    @Binding var isSummarizing: Bool
    @Binding var qnaInput: String
    @Binding var chatHistory: [(role: String, content: String)]
    @Binding var isThinking: Bool
    @Binding var grammarText: String
    @Binding var isGrammarChecking: Bool
    @Binding var grammarEnglishMode: GrammarEnglishMode

    @AppStorage("isDarkMode_v2") private var isDarkMode = true
    @AppStorage("allowOnlineBibTeX") private var allowOnlineLookup = true
    @AppStorage("shortenAuthors") private var shortenAuthors = false
    @AppStorage("abbreviateJournals") private var abbreviateJournals = false
    @AppStorage("useLaTeXEscaping") private var useLaTeXEscaping = false

    @State private var activeAction: AIAction? = nil
    @State private var currentSummaryTask: Task<Void, Never>? = nil // Handle for cancellation
    @State private var extractedText: String = ""
    @State private var showWritingToolsHelp: Bool = false
    @State private var relatedWorkTopic: String = ""
    @State private var relatedWorkOutput: String = ""
    @State private var isSearchingRelatedWork: Bool = false
    @State private var relatedWorkAutoMode: Bool = true // Auto-detect vs manual topic
    @State private var currentGrammarTask: Task<Void, Never>? = nil // Handle for cancellation

    // Grammar check enhancements
    @AppStorage("grammarTemperature") private var grammarTemperature: Double = 0.2
    @State private var grammarProgress: String = ""
    @State private var grammarCurrentPage: Int = 0
    @State private var grammarTotalPages: Int = 0
    @State private var grammarCorrectionsCount: Int = 0
    @State private var isWarmingUp: Bool = false
    @State private var warmedUpSession: Any? = nil // Store warmed session
    @State private var grammarPageSelection: String = "" // Page selection input (e.g., "1-5" or "1,3,5")
    @State private var grammarCheckAllPages: Bool = true // Toggle for all pages vs custom

    // Cover letter state
    @State private var coverLetterJournal: String = ""
    @State private var coverLetterAuthor: String = ""
    @State private var coverLetterText: String = ""
    @State private var isGeneratingCoverLetter: Bool = false

    enum AIAction: String, CaseIterable, Identifiable {
        case summary = "Summarize"
        case chat = "AI Chat"
        case finder = "Finder"
        case grammar = "Grammar"
        case coverLetter = "Cover Letter"

        var id: String { self.rawValue }
    }

    // Multi-document chunk structure
    struct DocumentChunk {
        let pdfURL: URL
        let fileName: String
        let text: String
        let pageRange: String
        let charCount: Int
    }

    private var isTahoeAvailable: Bool {
        if #available(macOS 26.0, *) {
            return true
        } else {
            return false
        }
    }

    @ViewBuilder
    private var tahoeWarningView: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.orange)

                VStack(alignment: .leading, spacing: 6) {
                    Text("macOS Tahoe Required")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("AI-powered features require macOS 15.1 (Tahoe) or later with Apple Foundation Models.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
            )

            Text("This tab cannot be used on your current macOS version. Please upgrade to macOS Tahoe to access AI features.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.horizontal)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                HStack {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.purple)
                    Text("AI Features")
                        .font(.title2.bold())
                    Spacer()
                }
                .padding(.horizontal)

                // Tahoe Required Warning
                if !isTahoeAvailable {
                    tahoeWarningView
                    Spacer()
                } else {
                    // Action Grid (Unified with Bibliography mode)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 16)], spacing: 16) {
                        
                        // 1. Summarization
                        SquareActionCard(
                            title: "Summarize",
                            icon: "wand.and.stars",
                            color: .purple,
                            isActive: activeAction == .summary,
                            isProcessing: isSummarizing && activeAction == .summary,
                            isDisabled: selectedFiles.filter { $0.isChecked }.isEmpty
                        ) {
                            if isSummarizing && activeAction == .summary {
                                self.currentSummaryTask?.cancel()
                                self.isSummarizing = false
                                self.activeAction = nil
                            } else {
                                activeAction = .summary
                            }
                        }
                        
                        // 2. Chat
                        SquareActionCard(
                            title: "AI Chat",
                            icon: "bubble.left.and.bubble.right.fill",
                            color: .blue,
                            isActive: activeAction == .chat,
                            isProcessing: isThinking && activeAction == .chat,
                            isDisabled: selectedFiles.filter { $0.isChecked }.isEmpty
                        ) {
                            activeAction = .chat
                        }
                        
                        // 3. Related Work Finder
                        SquareActionCard(
                            title: "Finder",
                            icon: "link.circle.fill",
                            color: .orange,
                            isActive: activeAction == .finder,
                            isProcessing: isSearchingRelatedWork && activeAction == .finder,
                            isDisabled: selectedFiles.filter { $0.isChecked }.isEmpty
                        ) {
                            activeAction = .finder
                        }
                        
                        // 4. Grammar Check
                        SquareActionCard(
                            title: "Grammar",
                            icon: "checkmark.seal.fill",
                            color: .green,
                            isActive: activeAction == .grammar,
                            isProcessing: isGrammarChecking && activeAction == .grammar,
                            isDisabled: selectedFiles.filter { $0.isChecked }.isEmpty
                        ) {
                            if isGrammarChecking && activeAction == .grammar {
                                self.currentGrammarTask?.cancel()
                                self.isGrammarChecking = false
                            } else {
                                activeAction = .grammar
                            }
                        }

                        // 5. Cover Letter Generator
                        SquareActionCard(
                            title: "Cover Letter",
                            icon: "envelope.fill",
                            color: .purple,
                            isActive: activeAction == .coverLetter,
                            isProcessing: isGeneratingCoverLetter && activeAction == .coverLetter,
                            isDisabled: selectedFiles.filter { $0.isChecked }.isEmpty
                        ) {
                            activeAction = .coverLetter
                        }
                    }
                    .padding(.horizontal)

                    // Detailed Detailed Views (Conditional)
                    VStack(spacing: 16) {
                        if activeAction == .summary {
                            summaryCardView
                            outputAreaView
                        }
                        
                        if activeAction == .chat {
                            chatInterfaceView
                        }
                        
                        if activeAction == .finder {
                            relatedWorkView
                        }
                        
                        if activeAction == .grammar {
                            grammarCheckView
                            outputAreaView
                        }

                        if activeAction == .coverLetter {
                            coverLetterView
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .onAppear {
            // Pre-warm the AI session when tab appears
            if isTahoeAvailable && warmedUpSession == nil {
                if #available(macOS 26.0, *) {
                    Task {
                        await warmUpAISession()
                    }
                }
            }
        }
    }

    // MARK: - Session Warm-up
    @available(macOS 26.0, *)
    private func warmUpAISession() async {
        guard !isWarmingUp else { return }

        isWarmingUp = true
        grammarProgress = "Warming up AI model..."

        do {
            let session = LanguageModelSession()
            // Send a simple test prompt to warm up the session
            let _ = try await session.respond(to: "Test: The cat sat on the mat.")
            // Store the warmed session
            warmedUpSession = session
            print("AI Session warmed up successfully")
        } catch {
            print("Failed to warm up AI session: \(error)")
        }

        isWarmingUp = false
        grammarProgress = ""
    }

    @ViewBuilder
    private var summaryCardView: some View {
        // Summary Card
        GroupBox {
            VStack(spacing: 12) {
                HStack {
                    Text("Summary Type:")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                    Spacer()
                }

                // Summary Type Grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(SummaryType.allCases) { type in
                        Button(action: {
                            summaryType = type
                        }) {
                            VStack(spacing: 6) {
                                Image(systemName: type.icon)
                                    .font(.system(size: 18))
                                Text(type.name)
                                    .font(.caption)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(summaryType == type ? Color.purple.opacity(0.2) : Color.clear)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(summaryType == type ? Color.purple : Color.secondary.opacity(0.3), lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                        .help(type.description)
                    }
                }

                if isSummarizing && activeAction == .summary {
                    Button(action: {
                        self.currentSummaryTask?.cancel()
                        self.isSummarizing = false
                        self.activeAction = nil
                    }) {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Stop Generating")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    Button(action: {
                        activeAction = .summary
                        extractTextFromPDF()
                    }) {
                        HStack {
                            Image(systemName: "sparkles")
                            Text("Generate AI Summary")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(selectedFiles.filter { $0.isChecked }.isEmpty || isSummarizing)
                }
            }
            .padding(12)
        }
        .alert("AI Summarization", isPresented: $showWritingToolsHelp) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("This feature uses intelligent text analysis to extract the most important sentences from your PDF based on position and keyword scoring. It processes everything locally - no internet required, completely private.\n\nChoose from 4 summary formats:\n• TL;DR - Ultra-short (3-5 sentences)\n• Key Points - Main findings (7-10 bullets)\n• Abstract - Academic summary (10 sentences)\n• Full Summary - Comprehensive overview (20 sentences)")
        }
    }

    @ViewBuilder
    private var chatInterfaceView: some View {
        // Advanced AI Tools Card
        // Smart Q&A Chat Interface
        GroupBox {
            VStack(spacing: 0) {
                // Multi-doc mode indicator
                let checkedCount = selectedFiles.filter { $0.isChecked }.count
                if checkedCount > 1 {
                    HStack {
                        Image(systemName: "doc.on.doc.fill")
                            .foregroundColor(.orange)
                        Text("Multi-Document Mode: Analyzing \(checkedCount) papers")
                            .font(.subheadline.bold())
                            .foregroundColor(.primary)
                        Spacer()
                        Text("Context-aware synthesis")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(6)
                    .padding(.bottom, 8)
                }

                if !chatHistory.isEmpty {
                    HStack {
                        Spacer()
                        Button("Save Chat") {
                            saveConversation()
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundColor(.blue)

                        Button("Clear") {
                            chatHistory.removeAll()
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 8)
                }

                // Chat Area
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if chatHistory.isEmpty {
                                Text("Ask questions about your PDF. The AI will analyze the text to provide answers.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.top, 40)
                            } else {
                                ForEach(0..<chatHistory.count, id: \.self) { i in
                                    let msg = chatHistory[i]
                                    HStack(alignment: .top, spacing: 8) {
                                        if msg.role == "System" {
                                            Image(systemName: "sparkles")
                                                .foregroundColor(.purple)
                                                .font(.system(size: 14))
                                                .padding(.top, 4)
                                        }

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(msg.content)
                                                .textSelection(.enabled)
                                                .padding(10)
                                                .background(msg.role == "User" ? Color.blue.opacity(0.1) : Color(NSColor.textBackgroundColor))
                                                .cornerRadius(12)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                                )

                                            Button(action: {
                                                NSPasteboard.general.clearContents()
                                                NSPasteboard.general.setString(msg.content, forType: .string)
                                            }) {
                                                Label("Copy", systemImage: "doc.on.doc")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                            .buttonStyle(.plain)
                                            .padding(.leading, 10)
                                        }

                                        if msg.role == "User" {
                                            Image(systemName: "person.circle.fill")
                                                .foregroundColor(.blue)
                                                .font(.system(size: 14))
                                                .padding(.top, 4)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: msg.role == "User" ? .trailing : .leading)
                                    .id(i)
                                }
                            }
                        }
                        .padding()
                    }
                    .frame(height: 300)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                    .onChange(of: chatHistory.count) { _ in
                        if let last = chatHistory.indices.last {
                            withAnimation {
                                scrollProxy.scrollTo(last, anchor: .bottom)
                            }
                        }
                    }
                }
                
                // Input Area
                HStack {
                    TextField("Ask a question...", text: $qnaInput)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isThinking || selectedFiles.isEmpty)
                        .onSubmit {
                            Task {
                                await performQnA()
                            }
                        }
                    
                    Button(action: {
                        Task {
                            await performQnA()
                        }
                    }) {
                        if isThinking {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(qnaInput.isEmpty || isThinking || selectedFiles.isEmpty)
                }
                .padding(.top, 8)
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private var relatedWorkView: some View {
        // Related Work Finder
        GroupBox {
            VStack(spacing: 12) {
                // Mode Toggle
                HStack {
                    Text("Find papers related to:")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                    Spacer()
                }

                Picker("Mode", selection: $relatedWorkAutoMode) {
                    Text("This paper's topics").tag(true)
                    Text("Specific topic").tag(false)
                }
                .pickerStyle(.segmented)

                // Manual topic input (only shown in manual mode)
                if !relatedWorkAutoMode {
                    HStack {
                        TextField("Enter topic (e.g., 'deep learning', 'climate change')", text: $relatedWorkTopic)
                            .textFieldStyle(.roundedBorder)
                            .disabled(isSearchingRelatedWork || selectedFiles.isEmpty)
                    }
                }

                // Action button
                Button(action: {
                    Task {
                        await findRelatedWork()
                    }
                }) {
                    HStack {
                        if isSearchingRelatedWork {
                            ProgressView().controlSize(.small)
                            Text("Analyzing...")
                        } else {
                            Image(systemName: "link.circle.fill")
                            if relatedWorkAutoMode {
                                Text("Find Related Papers")
                            } else {
                                Text("Search References")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(isSearchingRelatedWork || selectedFiles.isEmpty || (!relatedWorkAutoMode && relatedWorkTopic.isEmpty))

                Text(relatedWorkAutoMode
                    ? "Automatically analyzes your paper and finds related work from the references"
                    : "Search for papers on a specific topic in the references section")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                // Output display
                if !relatedWorkOutput.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Results")
                                .font(.subheadline.bold())
                                .foregroundColor(.primary)
                            Spacer()
                            Button("Clear") {
                                relatedWorkOutput = ""
                                relatedWorkTopic = ""
                            }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundColor(.secondary)
                        }

                        ScrollView {
                            Text(relatedWorkOutput)
                                .textSelection(.enabled)
                                .font(.system(.body))
                                .lineSpacing(4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        }
                        .frame(height: 250)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                    }
                }
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private var coverLetterView: some View {
        GroupBox {
            VStack(spacing: 12) {
                // Instructions
                Text("Generate a tailored cover letter for journal submission")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Journal Name Input
                VStack(alignment: .leading, spacing: 4) {
                    Text("Journal Name:")
                        .font(.subheadline.bold())
                    TextField("e.g., Nature Materials, Physical Review Letters", text: $coverLetterJournal)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isGeneratingCoverLetter)
                }

                // Author Name Input
                VStack(alignment: .leading, spacing: 4) {
                    Text("Corresponding Author:")
                        .font(.subheadline.bold())
                    TextField("e.g., Dr. Jane Smith", text: $coverLetterAuthor)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isGeneratingCoverLetter)
                }

                // Generate Button
                Button(action: {
                    Task {
                        await generateCoverLetter()
                    }
                }) {
                    HStack {
                        if isGeneratingCoverLetter {
                            ProgressView().controlSize(.small)
                            Text("Generating...")
                        } else {
                            Image(systemName: "envelope.fill")
                            Text("Generate Cover Letter")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(coverLetterJournal.isEmpty || coverLetterAuthor.isEmpty || isGeneratingCoverLetter || selectedFiles.filter { $0.isChecked }.isEmpty)

                // Output Display
                if !coverLetterText.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Generated Cover Letter")
                                .font(.subheadline.bold())
                                .foregroundColor(.primary)
                            Spacer()
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(coverLetterText, forType: .string)
                            }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundColor(.blue)

                            Button("Save as TXT") {
                                saveCoverLetter()
                            }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundColor(.blue)

                            Button("Clear") {
                                coverLetterText = ""
                                coverLetterJournal = ""
                                coverLetterAuthor = ""
                            }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundColor(.secondary)
                        }

                        ScrollView {
                            Text(coverLetterText)
                                .textSelection(.enabled)
                                .font(.system(.body))
                                .lineSpacing(4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        }
                        .frame(height: 350)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                    }
                }
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private var outputAreaView: some View {
        let isActiveGrammar = activeAction == .grammar
        let currentOutputText = isActiveGrammar ? grammarText : summaryText
        let isProcessingCurrent = isActiveGrammar ? isGrammarChecking : isSummarizing
        let headerTitle = isActiveGrammar ? "Grammar Check Output" : "AI Summary Output"
        let emptyMessage = isActiveGrammar ? "AI-powered grammar corrections will appear here" : "AI-powered summary will appear here"
        let initialActionMessage = isActiveGrammar ? "Click 'Check Grammar' to begin" : "Click 'Generate AI Summary' to begin"
        let processingMessage = isActiveGrammar ? "AI is proofreading your document..." : "AI is analyzing your document..."
        GroupBox(headerTitle) {
            VStack(alignment: .trailing, spacing: 8) {
                HStack {
                    if !currentOutputText.isEmpty && !isProcessingCurrent {
                        Button(action: {
                            if isActiveGrammar {
                                grammarText = ""
                            } else {
                                summaryText = ""
                                extractedText = ""
                            }
                            activeAction = nil
                        }) {
                            Label("Clear", systemImage: "trash")
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(.red)
                        .font(.caption)

                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(currentOutputText, forType: .string)
                        }) {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                    Spacer()
                }

                // Main output display
                ZStack {
                    if currentOutputText.isEmpty || (isProcessingCurrent && currentOutputText.contains("Starting") || currentOutputText.contains("Analyzing Grammar")) {
                        // Empty or Initial Processing state
                        VStack(spacing: 12) {
                            if isProcessingCurrent {
                                // Processing state
                                VStack(spacing: 16) {
                                    ProgressView()
                                        .scaleEffect(1.5)
                                        .progressViewStyle(.circular)

                                    Text(processingMessage)
                                        .font(.headline)
                                        .foregroundColor(isActiveGrammar ? .green : .purple)

                                    if isActiveGrammar {
                                        Text(currentOutputText) // Show "Page X of Y"
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("This may take a few moments")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            } else {
                                // Initial empty state
                                Image(systemName: isActiveGrammar ? "checkmark.seal" : "sparkles")
                                    .font(.system(size: 40))
                                    .foregroundColor((isActiveGrammar ? Color.green : Color.purple).opacity(0.3))
                                Text(initialActionMessage)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                Text(emptyMessage)
                                    .font(.caption)
                                    .foregroundColor(.secondary.opacity(0.7))
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 320)
                    } else {
                        // Result display
                        ScrollView {
                            Text(currentOutputText)
                                .textSelection(.enabled)
                                .font(.system(.body))
                                .lineSpacing(6)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: 320)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                    }
                }

            }
        }
    }

    @ViewBuilder
    private var grammarCheckView: some View {
        GroupBox {
            VStack(spacing: 12) {
                HStack {
                    Text("Regional English Preference:")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                    Spacer()
                }

                Picker("English Mode", selection: $grammarEnglishMode) {
                    ForEach(GrammarEnglishMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                // Page Selection
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Pages to check:")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                        Spacer()
                    }

                    Picker("Page Selection", selection: $grammarCheckAllPages) {
                        Text("All pages").tag(true)
                        Text("Custom range").tag(false)
                    }
                    .pickerStyle(.segmented)

                    if !grammarCheckAllPages {
                        TextField("e.g., 1-5 or 1,3,5,10-15", text: $grammarPageSelection)
                            .textFieldStyle(.roundedBorder)
                            .disabled(isGrammarChecking)

                        Text("Formats: Single (5), Range (1-5), Mixed (1,3,5-10)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)

                // Temperature Slider
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("AI Creativity:")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                        Spacer()
                        Text("\(grammarTemperature, specifier: "%.1f")")
                            .foregroundColor(.primary)
                            .font(.subheadline.monospacedDigit())
                    }

                    Slider(value: $grammarTemperature, in: 0.0...1.0, step: 0.1) {
                        Text("Temperature")
                    } minimumValueLabel: {
                        VStack(spacing: 2) {
                            Text("0.0")
                                .font(.caption2)
                            Text("Precise")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    } maximumValueLabel: {
                        VStack(spacing: 2) {
                            Text("1.0")
                                .font(.caption2)
                            Text("Creative")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .accentColor(grammarTemperature < 0.3 ? .green : grammarTemperature < 0.7 ? .orange : .red)

                    Text("Lower = More consistent corrections. Higher = More varied suggestions. Recommended: 0.0-0.3 for grammar.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                .padding(.vertical, 4)

                // Progress Indicator
                if isGrammarChecking && activeAction == .grammar {
                    VStack(spacing: 8) {
                        if grammarTotalPages > 0 {
                            ProgressView(value: Double(grammarCurrentPage), total: Double(grammarTotalPages)) {
                                HStack {
                                    Text(grammarProgress)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("Page \(grammarCurrentPage)/\(grammarTotalPages)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        } else {
                            HStack {
                                ProgressView().controlSize(.small)
                                Text(grammarProgress)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        if grammarCorrectionsCount > 0 {
                            Text("Found \(grammarCorrectionsCount) correction\(grammarCorrectionsCount == 1 ? "" : "s") so far")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if isGrammarChecking && activeAction == .grammar {
                    Button(action: {
                        self.currentGrammarTask?.cancel()
                        self.isGrammarChecking = false
                    }) {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Stop Checking")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    Button(action: {
                        activeAction = .grammar
                        performGrammarCheck()
                    }) {
                        HStack {
                            Image(systemName: "checkmark.seal.fill")
                            Text("Check Grammar (Local AI)")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(selectedFiles.filter { $0.isChecked }.isEmpty || isGrammarChecking)
                }
                
                Text("Processes text page-by-page using Apple Foundation Models. Works entirely offline.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(12)
        }
    }

    // Parse page selection string (e.g., "1-5" or "1,3,5,10-15")
    private func parsePageSelection(_ input: String, maxPages: Int) -> [Int] {
        guard !input.isEmpty else { return [] }

        var pages = Set<Int>()
        let components = input.components(separatedBy: ",")

        for component in components {
            let trimmed = component.trimmingCharacters(in: .whitespaces)

            if trimmed.contains("-") {
                // Range (e.g., "1-5")
                let rangeParts = trimmed.components(separatedBy: "-")
                if rangeParts.count == 2,
                   let start = Int(rangeParts[0].trimmingCharacters(in: .whitespaces)),
                   let end = Int(rangeParts[1].trimmingCharacters(in: .whitespaces)) {
                    for page in start...end {
                        if page >= 1 && page <= maxPages {
                            pages.insert(page - 1) // Convert to 0-indexed
                        }
                    }
                }
            } else {
                // Single page (e.g., "3")
                if let page = Int(trimmed), page >= 1 && page <= maxPages {
                    pages.insert(page - 1) // Convert to 0-indexed
                }
            }
        }

        return Array(pages).sorted()
    }

    private func performGrammarCheck() {
        let checkedFiles = selectedFiles.filter { $0.isChecked }
        guard let file = checkedFiles.first else { return }

        isGrammarChecking = true
        grammarText = ""
        grammarCorrectionsCount = 0

        self.currentGrammarTask = Task {
            if Task.isCancelled { return }

            guard let pdfDoc = PDFDocument(url: file.url) else {
                await MainActor.run {
                    grammarText = "Error: Could not open PDF file."
                    isGrammarChecking = false
                }
                return
            }

            let pageCount = pdfDoc.pageCount

            // Determine which pages to check
            let pagesToCheck: [Int]
            if grammarCheckAllPages {
                pagesToCheck = Array(0..<pageCount)
            } else {
                let parsed = parsePageSelection(grammarPageSelection, maxPages: pageCount)
                if parsed.isEmpty {
                    await MainActor.run {
                        grammarText = "Error: Invalid page selection. Use format like '1-5' or '1,3,5,10-15'"
                        isGrammarChecking = false
                    }
                    return
                }
                pagesToCheck = parsed
            }

            await MainActor.run {
                grammarTotalPages = pagesToCheck.count
                grammarCurrentPage = 0
            }

            var allCorrections: [(original: String, suggested: String, errorType: String)] = []

            if #available(macOS 26.0, *) {
                // Create a fresh session for each grammar check
                let session = LanguageModelSession()

                for (index, pageIndex) in pagesToCheck.enumerated() {
                    if Task.isCancelled { break }

                    await MainActor.run {
                        grammarCurrentPage = index + 1
                        grammarProgress = "Analyzing page \(pageIndex + 1) of \(pageCount)... (\(index + 1)/\(pagesToCheck.count))"
                    }

                    // Use Ghostscript for high-quality text extraction
                    if let pageText = await extractTextWithGS(url: file.url, pageIndex: pageIndex),
                       !pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {

                        let regionalInstruction = grammarEnglishMode == .british
                            ? "UK English spelling (e.g., -ise, -our, -re) and punctuation (single quotes)"
                            : "US English spelling (e.g., -ize, -or, -er) and punctuation (double quotes)"

                        // Split text into chunks if too large (context limit ~4096 tokens = ~3000 chars)
                        let maxChunkSize = 3000
                        var textChunks: [String] = []

                        if pageText.count > maxChunkSize {
                            // Split by sentences to avoid breaking mid-sentence
                            let sentences = pageText.components(separatedBy: ". ")
                            var currentChunk = ""

                            for sentence in sentences {
                                if (currentChunk + sentence).count > maxChunkSize && !currentChunk.isEmpty {
                                    textChunks.append(currentChunk)
                                    currentChunk = sentence + ". "
                                } else {
                                    currentChunk += sentence + ". "
                                }
                            }
                            if !currentChunk.isEmpty {
                                textChunks.append(currentChunk)
                            }
                        } else {
                            textChunks = [pageText]
                        }

                        // Process each chunk
                        var allChunkCorrections: [GrammarCorrection] = []

                        for (chunkIndex, chunk) in textChunks.enumerated() {
                            if Task.isCancelled { break }

                            if textChunks.count > 1 {
                                await MainActor.run {
                                    grammarProgress = "Analyzing page \(pageIndex + 1) chunk \(chunkIndex + 1)/\(textChunks.count)..."
                                }
                            }

                            let systemPrompt = """
                            You are a meticulous academic editor. Find and fix EVERY grammar, spelling, and punctuation error.
                            Focus on: structural grammar (subject-verb agreement), spelling errors, merged/glued words (missing spaces), and punctuation.

                            Use \(regionalInstruction).

                            Analyze this text and return ALL corrections found. If no errors exist, return an empty corrections array.

                            TEXT:
                            \(chunk)
                            """

                            // Retry logic with structured output
                            var chunkCorrections: GrammarCheckResult? = nil
                            let maxRetries = 3

                            for attempt in 1...maxRetries {
                                if Task.isCancelled { break }

                                if attempt > 1 {
                                    await MainActor.run {
                                        grammarProgress = "Retrying page \(pageIndex + 1) chunk \(chunkIndex + 1)... (Attempt \(attempt)/\(maxRetries))"
                                    }
                                }

                                do {
                                    // Use structured output for reliable parsing
                                    let response = try await session.respond(to: systemPrompt, generating: GrammarCheckResult.self)
                                    chunkCorrections = response.content
                                    break // Success - break retry loop
                                } catch {
                                    print("AI Grammar check attempt \(attempt) failed for page \(pageIndex + 1) chunk \(chunkIndex + 1): \(error)")
                                    if attempt == maxRetries {
                                        await MainActor.run {
                                            grammarProgress = "Failed to analyze page \(pageIndex + 1) chunk \(chunkIndex + 1) after \(maxRetries) attempts"
                                        }
                                    } else {
                                        // Small delay before retry
                                        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                                    }
                                }
                            }

                            // Collect corrections from this chunk
                            if let corrections = chunkCorrections?.corrections {
                                allChunkCorrections.append(contentsOf: corrections)
                            }
                        } // End of chunk loop

                        // Process all corrections from all chunks of this page
                        if !allChunkCorrections.isEmpty {
                            for correction in allChunkCorrections {
                                // Validate that original and suggested are actually different
                                if correction.original.lowercased() != correction.suggested.lowercased() {
                                    allCorrections.append((
                                        original: correction.original,
                                        suggested: correction.suggested,
                                        errorType: correction.errorType
                                    ))
                                }
                            }

                            // Update UI with accumulated corrections
                            await MainActor.run {
                                grammarCorrectionsCount = allCorrections.count
                                grammarProgress = "Found \(allChunkCorrections.count) error(s) on page \(pageIndex + 1)"
                                var outputText = ""
                                for correction in allCorrections {
                                    outputText += "Original: \(correction.original)\n"
                                    outputText += "Suggested: \(correction.suggested)\n\n"
                                }
                                grammarText = outputText
                            }
                        }
                    }
                } // End of page loop
            } else {
                await MainActor.run {
                    grammarText = "AI Grammar Check requires macOS 15.1 (Tahoe) or later."
                }
            }

            await MainActor.run {
                isGrammarChecking = false
                grammarProgress = "Completed"
                grammarCurrentPage = grammarTotalPages

                if allCorrections.isEmpty {
                    grammarText = "✓ Grammar check completed. No errors found! Your document looks great."
                } else {
                    // Final summary at the top
                    var summaryText = "Grammar Check Complete\n"
                    summaryText += "Found \(allCorrections.count) correction\(allCorrections.count == 1 ? "" : "s")\n"
                    summaryText += String(repeating: "=", count: 50) + "\n\n"

                    for correction in allCorrections {
                        summaryText += "Original: \(correction.original)\n"
                        summaryText += "Suggested: \(correction.suggested)\n\n"
                    }

                    grammarText = summaryText
                }
            }
        }
    }

    @available(macOS 26.0, *)
    private func proofreadChunk(prompt: String) async -> String? {
        // This helper is now redundant as we reuse the session in the loop above
        return nil
    }


    private func extractTextFromPDF() {
        let checkedFiles = selectedFiles.filter { $0.isChecked }
        guard let file = checkedFiles.first else { return }

        isSummarizing = true
        extractedText = ""
        summaryText = ""

        summaryText = ""

        self.currentSummaryTask = Task {
            // Check for cancellation at start
            if Task.isCancelled { return }
            
            // Extract full text from PDF first
            guard let pdfDoc = PDFDocument(url: file.url) else {
                await MainActor.run {
                    summaryText = "Error: Could not open PDF file."
                    isSummarizing = false
                }
                return
            }

            var fullText = ""
            for pageIndex in 0..<pdfDoc.pageCount {
                if Task.isCancelled { return }
                if let page = pdfDoc.page(at: pageIndex) {
                    if let pageText = page.string {
                        fullText += pageText + "\n\n"
                    }
                }
            }

            guard !fullText.isEmpty else {
                await MainActor.run {
                    summaryText = "Could not extract text from this PDF. It might be a scanned image without OCR."
                    isSummarizing = false
                }
                return
            }

            // Try AI-powered summarization first (macOS 26+)
            if #available(macOS 26.0, *) {
                if let aiSummary = await generateAISummary(text: fullText, type: summaryType) {
                    await MainActor.run {
                        summaryText = aiSummary
                        isSummarizing = false
                    }
                    return
                }
            }

            // Fallback to extractive summarization for older macOS
            let sentenceCount: Int
            switch summaryType {
            case .tldr:
                sentenceCount = 4
            case .keyPoints:
                sentenceCount = 8
            case .abstract:
                sentenceCount = 10
            case .fullSummary:
                sentenceCount = 20
            }

            if let summary = summarizePDF(url: file.url, maxSentences: sentenceCount, password: nil) {
                await MainActor.run {
                    summaryText = formatSummary(summary, type: summaryType)
                    isSummarizing = false
                }
            } else {
                await MainActor.run {
                    summaryText = "Could not generate summary."
                    isSummarizing = false
                }
            }
        }
    }

    @available(macOS 26.0, *)
    private func generateAISummary(text: String, type: SummaryType) async -> String? {
        do {
            print("DEBUG - generateAISummary: Creating prompt...")
            // Create prompt based on summary type
            let prompt = createSummarizationPrompt(for: type, text: text)
            print("DEBUG - generateAISummary: Prompt created, length: \(prompt.count)")

            // Use Apple's Foundation Models API
            print("DEBUG - generateAISummary: Creating LanguageModelSession...")
            let session = LanguageModelSession()
            print("DEBUG - generateAISummary: Session created, calling respond...")
            let response = try await session.respond(to: prompt)
            print("DEBUG - generateAISummary: Got response!")

            return response.content
        } catch {
            print("AI Summarization failed: \(error)")
            print("AI Summarization error description: \(error.localizedDescription)")
            return nil
        }
    }

    private func createSummarizationPrompt(for type: SummaryType, text: String) -> String {
        // Clean text: remove citations and references
        let cleanedText = cleanTextForSummarization(text)

        // Limit text length (Foundation Models have token limits)
        let limitedText = String(cleanedText.prefix(8000))

        switch type {
        case .tldr:
            return """
            Summarize the following academic paper in 3-5 sentences. Focus on the main findings and conclusions. Be concise and clear.

            Text:
            \(limitedText)

            TL;DR Summary:
            """

        case .keyPoints:
            return """
            Extract 7-10 key points from the following academic paper. Present them as bullet points. Focus on main findings, methodology, and conclusions.

            Text:
            \(limitedText)

            Key Points:
            """

        case .abstract:
            return """
            Write an academic abstract (10 sentences) for the following paper. Include: background, methodology, key findings, and conclusions. Use formal academic tone.

            Text:
            \(limitedText)

            Abstract:
            """

        case .fullSummary:
            return """
            Create a comprehensive summary of the following academic paper. Include:
            - Introduction and background
            - Methodology
            - Key findings and results
            - Discussion and implications
            - Conclusions

            Write in clear, flowing paragraphs. Make it readable and informative.

            Text:
            \(limitedText)

            Summary:
            """
        }
    }

    private func cleanTextForSummarization(_ text: String) -> String {
        var cleaned = text

        // Remove URLs
        cleaned = cleaned.replacingOccurrences(of: #"https?://[^\s]+"#, with: "", options: .regularExpression)

        // Remove email addresses
        cleaned = cleaned.replacingOccurrences(of: #"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}"#, with: "", options: .regularExpression)

        // Remove DOI references
        cleaned = cleaned.replacingOccurrences(of: #"doi\.org/[^\s]+"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"dx\.doi\.org/[^\s]+"#, with: "", options: .regularExpression)

        // Remove bracket citations [1], [14], etc.
        cleaned = cleaned.replacingOccurrences(of: #"\[\d+\]"#, with: "", options: .regularExpression)

        // Remove "et al."
        cleaned = cleaned.replacingOccurrences(of: "et al.", with: "")

        // Remove excessive whitespace
        cleaned = cleaned.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func formatSummary(_ text: String, type: SummaryType) -> String {
        // Split into sentences and filter out citations and references
        let allSentences = text.components(separatedBy: ". ").filter { sentence in
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)

            // Filter out empty sentences
            guard !trimmed.isEmpty else { return false }

            // Filter out citations (contains http://, doi.org, [numbers], etc.)
            if trimmed.contains("http://") || trimmed.contains("https://") ||
               trimmed.contains("doi.org") || trimmed.contains("dx.doi.org") {
                return false
            }

            // Filter out journal citations (J Mech Phys, etc.)
            if trimmed.range(of: #"J\s+\w+\s+\w+\s+\w+"#, options: .regularExpression) != nil &&
               trimmed.contains(";") {
                return false
            }

            // Filter out sentences with bracket citations [1], [14], etc.
            if trimmed.range(of: #"\[\d+\]"#, options: .regularExpression) != nil {
                return false
            }

            // Filter out reference-style sentences (starts with author names and years)
            if trimmed.range(of: #"^\w+\s+[A-Z]\w*\s+\d{4}"#, options: .regularExpression) != nil {
                return false
            }

            // Filter out sentences with "et al."
            if trimmed.contains("et al.") {
                return false
            }

            // Filter out sentences that are mostly citations (contain multiple years in brackets)
            let yearMatches = trimmed.components(separatedBy: CharacterSet.decimalDigits.inverted)
                .filter { $0.count == 4 && Int($0) != nil && Int($0)! > 1900 && Int($0)! < 2100 }
            if yearMatches.count > 2 {
                return false
            }

            // Filter out very short section headers
            if trimmed.count < 20 {
                return false
            }

            return true
        }

        let sentences = Array(allSentences)

        switch type {
        case .tldr:
            // Ultra-short, casual format
            return "TL;DR:\n\n" + sentences.joined(separator: ". ") + "."

        case .keyPoints:
            // Bullet points format
            return "Key Points:\n\n" + sentences.enumerated().map { "• \($0.element.trimmingCharacters(in: .whitespacesAndNewlines))." }.joined(separator: "\n\n")

        case .abstract:
            // Academic paragraph format with better flow
            let cleanedSentences = sentences.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            return "Abstract:\n\n" + cleanedSentences.joined(separator: ". ") + "."

        case .fullSummary:
            // Comprehensive multi-paragraph format with natural flow
            var result = "Summary:\n\n"

            let cleanedSentences = sentences.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

            // Varied transition words for more natural flow
            let transitions = [
                "Additionally,", "Moreover,", "Furthermore,", "In addition,",
                "Building on this,", "Consequently,", "As a result,", "Similarly,",
                "This approach", "The study also", "Research shows that", "It was found that"
            ]

            // Group sentences into meaningful paragraphs with varied transitions
            let paragraphSize = 4
            var paragraphs: [String] = []
            var transitionIndex = 0

            for i in stride(from: 0, to: cleanedSentences.count, by: paragraphSize) {
                let end = min(i + paragraphSize, cleanedSentences.count)
                let paragraphSentences = Array(cleanedSentences[i..<end])

                var paragraph = ""
                for (idx, sentence) in paragraphSentences.enumerated() {
                    if idx == 0 {
                        paragraph += sentence
                    } else {
                        // Add varied, natural transitions
                        let startsWithThe = sentence.starts(with: "The ")
                        let startsWithThis = sentence.starts(with: "This ")

                        if !startsWithThe && !startsWithThis && idx % 2 == 1 {
                            // Use transition words occasionally
                            let transition = transitions[transitionIndex % transitions.count]
                            transitionIndex += 1
                            paragraph += ". " + transition + " " + sentence.prefix(1).lowercased() + sentence.dropFirst()
                        } else {
                            // Simple connection
                            paragraph += ". " + sentence
                        }
                    }
                }
                paragraph += "."
                paragraphs.append(paragraph)
            }

            result += paragraphs.joined(separator: "\n\n")
            return result
        }
    }

    // MARK: - Multi-Document Extraction
    func extractMultiDocumentText() async -> [DocumentChunk] {
        let checkedFiles = selectedFiles.filter { $0.isChecked }
        guard checkedFiles.count > 1 else { return [] }

        // Calculate character budget per document
        let totalBudget = 2500 // Leave room for prompt and output
        let budgetPerDoc = min(totalBudget / checkedFiles.count, 1200)

        var chunks: [DocumentChunk] = []

        for file in checkedFiles {
            guard let doc = PDFDocument(url: file.url) else { continue }

            var extractedText = ""
            var pagesExtracted: [Int] = []

            // Strategy: Extract first 2 pages + last page (abstract, intro, conclusion)
            let pagesToExtract = [0, 1, max(0, doc.pageCount - 1)]

            for pageIndex in pagesToExtract where pageIndex < doc.pageCount {
                if let pageText = await extractTextWithGS(url: file.url, pageIndex: pageIndex) {
                    extractedText += pageText + "\n\n"
                    pagesExtracted.append(pageIndex + 1) // 1-indexed for display

                    // Stop if we've exceeded budget
                    if extractedText.count >= budgetPerDoc {
                        break
                    }
                }
            }

            // Trim to budget
            if extractedText.count > budgetPerDoc {
                extractedText = String(extractedText.prefix(budgetPerDoc)) + "..."
            }

            if !extractedText.isEmpty {
                let pageRangeStr = pagesExtracted.sorted().map { String($0) }.joined(separator: ", ")
                chunks.append(DocumentChunk(
                    pdfURL: file.url,
                    fileName: file.url.lastPathComponent,
                    text: extractedText,
                    pageRange: "pages \(pageRangeStr)",
                    charCount: extractedText.count
                ))
            }
        }

        return chunks
    }

    // MARK: - Q&A Function
    func performQnA() async {
        guard !qnaInput.isEmpty, !selectedFiles.isEmpty else { return }

        let question = qnaInput
        qnaInput = ""
        chatHistory.append((role: "User", content: question))
        isThinking = true

        let checkedFiles = selectedFiles.filter { $0.isChecked }

        // Multi-document mode
        if checkedFiles.count > 1 {
            if #available(macOS 26.0, *) {
                // Extract text from all checked PDFs
                let chunks = await extractMultiDocumentText()

                guard !chunks.isEmpty else {
                    chatHistory.append((role: "System", content: "Error: Could not extract text from any PDF"))
                    isThinking = false
                    return
                }

                do {
                    let session = LanguageModelSession()

                    // Build multi-document prompt
                    var prompt = "Answer this question by synthesizing information from multiple academic papers below.\n\n"

                    for (index, chunk) in chunks.enumerated() {
                        prompt += "Document \(index + 1) (\(chunk.fileName), \(chunk.pageRange)):\n"
                        prompt += chunk.text + "\n\n"
                    }

                    prompt += "Question: \(question)\n\n"
                    prompt += "Provide a comprehensive answer and cite which documents support each point."

                    let response = try await session.respond(to: prompt, generating: MultiDocAnswer.self)

                    // Format answer with sources
                    var formattedAnswer = response.content.answer + "\n\n"
                    formattedAnswer += "📚 Sources: " + response.content.sources.joined(separator: ", ")

                    if !response.content.documentContributions.isEmpty {
                        formattedAnswer += "\n\n📄 Per-Document Insights:\n"
                        for contrib in response.content.documentContributions {
                            if contrib.insight.lowercased() != "not applicable" {
                                formattedAnswer += "• \(contrib.fileName): \(contrib.insight)\n"
                            }
                        }
                    }

                    chatHistory.append((role: "Assistant", content: formattedAnswer))
                } catch {
                    chatHistory.append((role: "System", content: "Error: \(error.localizedDescription)"))
                }
            } else {
                chatHistory.append((role: "System", content: "Multi-document Q&A requires macOS 26+"))
            }
        } else {
            // Single document mode (existing behavior)
            guard let pdfURL = selectedFiles.first?.url,
                  let doc = PDFDocument(url: pdfURL) else {
                chatHistory.append((role: "System", content: "Error: Could not load PDF"))
                isThinking = false
                return
            }

            var fullText = ""
            // Limit to first 5 pages and 6000 chars to stay within context window
            for i in 0..<min(5, doc.pageCount) {
                if let page = doc.page(at: i), let pageText = page.string {
                    fullText += pageText + "\n\n"
                    if fullText.count > 6000 { break }
                }
            }

            // Use FoundationModels for Q&A
            if #available(macOS 26.0, *) {
                do {
                    let session = LanguageModelSession()
                    // Keep prompt minimal to avoid context overflow
                    let limitedText = String(fullText.prefix(6000))
                    let prompt = """
                    Answer this question based on the PDF text below. Be concise.

                    Text: \(limitedText)

                    Q: \(question)
                    A:
                    """

                    let response = try await session.respond(to: prompt)
                    chatHistory.append((role: "Assistant", content: response.content))
                } catch {
                    chatHistory.append((role: "System", content: "Error: \(error.localizedDescription)"))
                }
            } else {
                chatHistory.append((role: "System", content: "Q&A requires macOS 26+"))
            }
        }

        isThinking = false
    }

    // MARK: - Save Conversation
    func saveConversation() {
        guard !chatHistory.isEmpty else { return }

        // Format conversation as text
        var conversationText = "PDF Q&A Conversation\n"
        conversationText += "Generated: \(Date().formatted())\n"
        conversationText += String(repeating: "=", count: 50) + "\n\n"

        for msg in chatHistory {
            conversationText += "[\(msg.role)]:\n"
            conversationText += msg.content + "\n\n"
        }

        // Show save dialog
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.nameFieldStringValue = "PDF_QA_Chat.txt"
        savePanel.message = "Save conversation as text file"

        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    try conversationText.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    print("Failed to save conversation: \(error)")
                }
            }
        }
    }

    // MARK: - Related Work Finder
    func findRelatedWork() async {
        // Auto mode doesn't need manual topic
        guard relatedWorkAutoMode || !relatedWorkTopic.isEmpty else { return }
        guard !selectedFiles.isEmpty else { return }

        isSearchingRelatedWork = true
        relatedWorkOutput = ""

        // Extract text from PDF
        guard let pdfURL = selectedFiles.first?.url,
              let doc = PDFDocument(url: pdfURL) else {
            relatedWorkOutput = "Error: Could not load PDF"
            isSearchingRelatedWork = false
            return
        }

        // Extract different sections
        var abstractText = ""
        var introductionText = ""
        var referencesText = ""
        var fullText = ""

        for i in 0..<doc.pageCount {
            if let page = doc.page(at: i), let pageText = page.string {
                fullText += pageText + "\n\n"

                let lowerText = pageText.lowercased()

                // Extract abstract (usually on first 2 pages)
                if i < 2 && (lowerText.contains("abstract") || lowerText.contains("summary")) {
                    abstractText += pageText + "\n\n"
                }

                // Extract introduction
                if lowerText.contains("introduction") || lowerText.contains("1.") && i < 5 {
                    introductionText += pageText + "\n\n"
                }

                // Extract references section
                if lowerText.contains("references") || lowerText.contains("bibliography") ||
                   lowerText.contains("works cited") {
                    referencesText += pageText + "\n\n"
                }
            }
        }

        // Use FoundationModels to find related work
        if #available(macOS 26.0, *) {
            do {
                let session = LanguageModelSession()

                let prompt: String
                if relatedWorkAutoMode {
                    // Auto mode: analyze the paper to find related work
                    let contextText = !abstractText.isEmpty ? String(abstractText.prefix(3000)) :
                                     !introductionText.isEmpty ? String(introductionText.prefix(3000)) :
                                     String(fullText.prefix(3000))

                    let refsText = !referencesText.isEmpty ? String(referencesText.prefix(8000)) : String(fullText.suffix(8000))

                    prompt = """
                    Based on this research paper's content, identify and list the most relevant papers from its references.

                    PAPER CONTEXT (Abstract/Introduction):
                    \(contextText)

                    REFERENCES SECTION:
                    \(refsText)

                    TASK:
                    1. First, identify the main research topics/themes of this paper (2-3 key areas)
                    2. Then, from the references, find 5-8 papers that are most relevant to these topics
                    3. For each paper, provide:
                       - Authors and year
                       - Title
                       - Why it's relevant (1 sentence explaining its connection to this paper's research)

                    Format your response clearly with the main topics at the top, then the relevant papers below.
                    """
                } else {
                    // Manual mode: search for specific topic
                    let refsText = !referencesText.isEmpty ? String(referencesText.prefix(10000)) : String(fullText.suffix(10000))

                    prompt = """
                    Find and list papers from the references below that are related to "\(relatedWorkTopic)".

                    For each relevant paper, provide:
                    - Authors and year
                    - Title
                    - Brief explanation of how it relates to \(relatedWorkTopic)

                    REFERENCES:
                    \(refsText)
                    """
                }

                let response = try await session.respond(to: prompt)
                relatedWorkOutput = response.content
            } catch {
                relatedWorkOutput = "Error: \(error.localizedDescription)"
            }
        } else {
            relatedWorkOutput = "Related Work Finder requires macOS 26+"
        }

        isSearchingRelatedWork = false
    }

    // MARK: - Cover Letter Generator
    func generateCoverLetter() async {
        guard !coverLetterJournal.isEmpty, !coverLetterAuthor.isEmpty else { return }
        guard !selectedFiles.isEmpty else { return }

        isGeneratingCoverLetter = true
        coverLetterText = ""

        // Extract text from first checked PDF
        guard let pdfURL = selectedFiles.filter({ $0.isChecked }).first?.url,
              let doc = PDFDocument(url: pdfURL) else {
            coverLetterText = "Error: Could not load PDF"
            isGeneratingCoverLetter = false
            return
        }

        // Extract abstract and key sections
        var paperText = ""
        for i in 0..<min(3, doc.pageCount) {
            if let page = doc.page(at: i), let pageText = page.string {
                paperText += pageText + "\n\n"
                if paperText.count > 5000 { break }
            }
        }

        let limitedText = String(paperText.prefix(5000))

        // Use FoundationModels to generate cover letter
        if #available(macOS 26.0, *) {
            do {
                let session = LanguageModelSession()

                let prompt = """
                You are an academic writing assistant. Generate a professional cover letter template for submitting a research paper to a journal.

                Target Journal: \(coverLetterJournal)

                Paper Content (Abstract/Introduction):
                \(limitedText)

                Generate a professional, persuasive cover letter that:
                1. Introduces the paper and its significance
                2. Highlights the novelty and key contributions
                3. Explains why it's suitable for \(coverLetterJournal)
                4. Mentions the impact and potential readership
                5. States that the work is original and not under consideration elsewhere
                6. Thanks the editor

                Format requirements:
                - Start with: [Date]
                - Salutation: "Dear Editor-in-Chief," or "Dear Editors,"
                - Body paragraphs (3-4 paragraphs)
                - Closing: "Sincerely,"
                - End with: [Your Name]

                Use formal academic tone. Keep it concise (300-400 words).
                Do NOT fill in the author name - leave [Your Name] as a placeholder.
                """

                let response = try await session.respond(to: prompt)

                // Replace [Your Name] placeholder with actual author name
                var finalLetter = response.content
                finalLetter = finalLetter.replacingOccurrences(of: "[Your Name]", with: coverLetterAuthor)
                finalLetter = finalLetter.replacingOccurrences(of: "[Date]", with: Date().formatted(date: .long, time: .omitted))

                coverLetterText = finalLetter
            } catch {
                coverLetterText = "Error generating cover letter: \(error.localizedDescription)"
            }
        } else {
            coverLetterText = "Cover Letter Generator requires macOS 26+"
        }

        isGeneratingCoverLetter = false
    }

    func saveCoverLetter() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "CoverLetter_\(coverLetterJournal.replacingOccurrences(of: " ", with: "_")).txt"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    try coverLetterText.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    print("Failed to save cover letter: \(error)")
                }
            }
        }
    }
}

// MARK: - Researcher Tab View
struct ResearcherTabView: View {
    @Binding var selectedFiles: [ContentView.PDFFile]
    @Binding var outputText: String
    @Binding var isProcessing: Bool
    @AppStorage("isDarkMode_v2") private var isDarkMode = true
    @AppStorage("referenceLookupMode") private var referenceLookupMode: ReferenceLookupMode = .hybrid
    @AppStorage("shortenAuthors") private var shortenAuthors = false  // NEW
    @AppStorage("abbreviateJournals") private var abbreviateJournals = false // NEW
    @AppStorage("useLaTeXEscaping") private var useLaTeXEscaping = false // NEW
    @AppStorage("addDotsToInitials") private var addDotsToInitials = true // NEW
    @AppStorage("addDotsToJournals") private var addDotsToJournals = true // NEW
    @StateObject private var networkMonitor = NetworkMonitor()

    @State private var activeAction: ResearcherAction? = nil
    @State private var selectedCitationStyle: CitationStyle = .apa
    @State private var showCitationPreview: Bool = false
    @State private var extractionTask: Task<Void, Never>? = nil
    @State private var isCancelled: Bool = false

    enum ResearcherAction {
        case bibtex
        case references
        case lookup
        case rename
        case metadata // NEW
    }
    
    @State private var doiInput: String = ""
    @State private var showRenamePreview: Bool = false
    @State private var renameCandidates: [RenameCandidate] = []
    
    // Metadata Editor State
    @State private var metaTitle: String = ""
    @State private var metaAuthor: String = ""
    @State private var metaSubject: String = ""
    @State private var metaKeywords: String = ""
    @State private var metaCreator: String = ""
        
    struct RenameCandidate: Identifiable {
        let id = UUID()
        let originalURL: URL
        let newName: String
        var isSelected: Bool = true
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                HStack {
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.orange)
                    Text("Researcher Tools")
                        .font(.title2.bold())
                    
                    Spacer()
                    
                    // Reference Lookup Mode Picker
                    Picker("Lookup Mode", selection: $referenceLookupMode) {
                        ForEach(ReferenceLookupMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                    .help("Select reference extraction mode: Offline, Online Only, or Hybrid")
                }
                .padding(.horizontal)

                // Tahoe Warning Banner
                if #available(macOS 26.0, *) {
                    // Tahoe available - no warning needed
                } else {
                    VStack(spacing: 8) {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.orange)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("macOS Tahoe Not Detected")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.primary)

                                if referenceLookupMode != .offline {
                                    Text("AI extraction unavailable. Using heuristic parsing with online lookup.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("AI extraction unavailable. Switched to offline heuristic mode. Consider enabling Hybrid Mode for better results.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()
                        }
                        .padding()
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .padding(.horizontal)
                }

                // MAIN ACTION GRID
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 16)], spacing: 16) {
                    
                    // 1. BibTeX Extraction
                    SquareActionCard(
                        title: "Extract BibTeX",
                        icon: "doc.text",
                        color: .blue,
                        isActive: activeAction == .bibtex,
                        isProcessing: isProcessing && activeAction == .bibtex,
                        isDisabled: selectedFiles.filter { $0.isChecked }.isEmpty
                    ) {
                         if isProcessing && activeAction == .bibtex {
                            // Stop action
                             isCancelled = true
                             extractionTask?.cancel()
                        } else {
                            activeAction = .bibtex
                            generateBibEntry()
                        }
                    }
                    
                    // 2. References Extraction
                    SquareActionCard(
                        title: "Extract Refs",
                        icon: "list.bullet.rectangle",
                        color: .orange,
                        isActive: activeAction == .references,
                        isProcessing: isProcessing && activeAction == .references,
                        isDisabled: selectedFiles.filter { $0.isChecked }.isEmpty
                    ) {
                         if isProcessing && activeAction == .references {
                             // Stop action
                             isCancelled = true
                             extractionTask?.cancel()
                         } else {
                            activeAction = .references
                            extractReferencesAction()
                         }
                    }
                    
                    // 3. DOI Lookup (NEW)
                    SquareActionCard(
                        title: "DOI Lookup",
                        icon: "magnifyingglass",
                        color: .green,
                        isActive: activeAction == .lookup,
                        isProcessing: isProcessing && activeAction == .lookup,
                        isDisabled: referenceLookupMode == .offline
                    ) {
                        activeAction = .lookup
                        // Logic handled in detailed view below
                    }
                    
                    // 4. Rename PDF
                    SquareActionCard(
                        title: "Rename PDF",
                        icon: "pencil",
                        color: .purple,
                        isActive: activeAction == .rename,
                        isProcessing: isProcessing && activeAction == .rename,
                        isDisabled: selectedFiles.filter { $0.isChecked }.isEmpty
                    ) {
                        activeAction = .rename
                        analyzeAndRenameAction()
                    }
                    
                    // 5. Metadata Editor
                    SquareActionCard(
                        title: "Metadata",
                        icon: "tag.fill",
                        color: .indigo,
                        isActive: activeAction == .metadata,
                        isProcessing: isProcessing && activeAction == .metadata,
                        isDisabled: selectedFiles.filter { $0.isChecked }.count != 1
                    ) {
                        activeAction = .metadata
                        if let file = selectedFiles.first(where: { $0.isChecked }) {
                            readMetadata(from: file.url)
                        }
                    }
                }
                .padding(.horizontal)
                
                // DETAILED ACTION VIEWS (Expandable Areas based on selection)
                
                // DOI Lookup Input Area
                if activeAction == .lookup {
                    GroupBox(label: Label("Extract from DOI", systemImage: "link")) {
                        HStack {
                            TextField("Enter DOI (e.g. 10.1103/PhysRevB.99.014406)", text: $doiInput)
                                .textFieldStyle(.roundedBorder)
                            
                            Button("Extract") {
                                Task {
                                    await lookupDOIAction()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(doiInput.isEmpty || isProcessing)
                        }
                        .padding(8)
                    }
                    .padding(.horizontal)
                }
                
                // Metadata Editor View
                if activeAction == .metadata {
                     GroupBox(label: Label("Metadata Editor", systemImage: "tag.fill")) {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("Title", text: $metaTitle)
                            TextField("Author", text: $metaAuthor)
                            TextField("Subject", text: $metaSubject)
                            TextField("Keywords", text: $metaKeywords)
                            TextField("Creator", text: $metaCreator)
                            
                            HStack {
                                Spacer()
                                Button(action: {
                                    Task {
                                        await writeMetadataAction()
                                    }
                                }) {
                                    if isProcessing {
                                        ProgressView().scaleEffect(0.5)
                                    } else {
                                        Text("Apply Changes")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(isProcessing)

                                Button(action: {
                                    activeAction = nil
                                }) {
                                    Text("Cancel Changes")
                                }
                                .buttonStyle(.bordered)
                                .disabled(isProcessing)
                            }
                        }
                        .padding(12)
                        .textFieldStyle(.roundedBorder)
                    }
                    .padding(.horizontal)
                }
                
                // Output Area
                    GroupBox("Output") {
                    VStack(alignment: .trailing, spacing: 8) {
                        HStack {
                            if isProcessing {
                                Button(action: {
                                    isCancelled = true
                                    extractionTask?.cancel()
                                    isProcessing = false
                                }) {
                                    HStack(spacing: 4) {
                                        ProgressView().controlSize(.small)
                                        Text("Stop Processing")
                                    }
                                    .foregroundColor(.red)
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)
                            }
                            
                            if !outputText.isEmpty {
                                Button(action: { outputText = ""; activeAction = nil }) {
                                    Label("Clear", systemImage: "trash")
                                }
                                .buttonStyle(.borderless)
                                .foregroundColor(.red)
                                .font(.caption)
                                
                                if outputText.contains("@article") || outputText.contains("@book") || outputText.contains("@inproceedings") || outputText.contains("@misc") {
                                    Button(action: cleanOutput) {
                                        Label("Clean", systemImage: "wand.and.rays")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.green)
                                    .font(.caption)
                                    .help("Remove unnecessary fields (abstract, language, etc.), clean braces in names, and remove duplicates")

                                    Button(action: exportBibFile) {
                                        Label("Save .bib", systemImage: "square.and.arrow.down")
                                            .fontWeight(.medium)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.blue)
                                    .font(.caption)
                                }
                            }
                            Spacer()
                        }


                        // Formatting options - show whenever output is generated (BibTeX or References)
                        // Formatting Controls
                        if !outputText.isEmpty {
                            GroupBox {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Formatting Operations")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.secondary)
                                    
                                    HStack(alignment: .top, spacing: 20) {
                                        // Authors Group
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("Authors")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                            
                                            HStack(spacing: 8) {
                                                Button(action: applyStandardAuthorFormat) {
                                                    Text("Standard (O. U. Salman)")
                                                        .font(.caption)
                                                }
                                                .buttonStyle(.bordered)
                                                .help("Reformat authors with dots: O. U. Salman")
                                                
                                                Button(action: applyMinimalistAuthorFormat) {
                                                    Text("Minimalist (O U Salman)")
                                                        .font(.caption)
                                                }
                                                .buttonStyle(.bordered)
                                                .help("Reformat authors without dots: O U Salman")
                                            }
                                        }
                                        
                                        Divider()
                                        
                                        // Journals Group
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("Journals")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                            
                                            HStack(spacing: 8) {
                                                Button(action: applyStandardJournalFormat) {
                                                    Text("Standard (Phys. Rev.)")
                                                        .font(.caption)
                                                }
                                                .buttonStyle(.bordered)
                                                .help("Abbreviate journals with dots: Phys. Rev.")
                                                
                                                Button(action: applyMinimalistJournalFormat) {
                                                    Text("Minimalist (Phys Rev)")
                                                        .font(.caption)
                                                }
                                                .buttonStyle(.bordered)
                                                .help("Abbreviate journals without dots: Phys Rev")
                                            }
                                        }
                                        
                                        Divider()
                                        
                                        // LaTeX Group
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("LaTeX")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                            
                                            Button(action: applyLatexEscaping) {
                                                Label("Escape Special Chars", systemImage: "character.cursor.ibeam")
                                                    .font(.caption)
                                            }
                                            .buttonStyle(.bordered)
                                            .help("Apply LaTeX escaping to special characters")
                                        }
                                    }
                                }
                                .padding(4)
                            }
                            .padding(.bottom, 4)
                        }


                        ZStack(alignment: .topTrailing) {
                            if outputText.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "books.vertical")
                                        .font(.system(size: 40))
                                        .foregroundColor(.orange.opacity(0.3))
                                    Text("Choose an action above to extract references")
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity, minHeight: 280)
                            } else {
                                TextEditor(text: $outputText)
                                    .font(.system(.body, design: .monospaced))
                                    .lineSpacing(4)
                                    .padding(4)
                                    .frame(minHeight: 280, maxHeight: 400) // Constrained height with native scrolling
                                
                                Button(action: {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(outputText, forType: .string)
                                }) {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 14))
                                }
                                .buttonStyle(.borderless)
                                .padding(8)
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(NSColor.textBackgroundColor).opacity(0.5))
                        )

                        // Citation Preview Section
                        if !outputText.isEmpty && outputText.contains("@") {
                            Divider()
                                .padding(.vertical, 8)

                            VStack(spacing: 12) {
                                HStack {
                                    Text("Citation Preview")
                                        .font(.subheadline.bold())
                                        .foregroundColor(.secondary)

                                    Spacer()

                                    Picker("Style", selection: $selectedCitationStyle) {
                                        ForEach(CitationStyle.allCases) { style in
                                            Text(style.rawValue).tag(style)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                    .frame(width: 200)

                                    Button(action: { showCitationPreview.toggle() }) {
                                        Image(systemName: showCitationPreview ? "eye.slash" : "eye")
                                            .font(.system(size: 14))
                                    }
                                    .buttonStyle(.borderless)
                                }
                                
                                // Quick Copy Buttons
                                if showCitationPreview {
                                    HStack(spacing: 8) {
                                        ForEach([CitationStyle.apa, .mla, .chicago], id: \.self) { style in
                                            Button("Copy \(style.rawValue)") {
                                                let text = CitationFormatter.formatMultiple(outputText, style: style)
                                                NSPasteboard.general.clearContents()
                                                NSPasteboard.general.setString(text, forType: .string)
                                            }
                                            .font(.caption)
                                            .buttonStyle(.bordered)
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 4)
                                }

                                if showCitationPreview {
                                    ScrollView {
                                        Text(CitationFormatter.formatMultiple(outputText, style: selectedCitationStyle))
                                            .textSelection(.enabled)
                                            .font(.system(.body))
                                            .lineSpacing(6)
                                            .padding()
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .frame(minHeight: 150, maxHeight: 300)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color(NSColor.controlBackgroundColor))
                                    )
                                }
                            }
                        }
                    }
                    .padding(8)
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 20)
        }

        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleBibFileDrop(providers: providers)
        }
        .sheet(isPresented: $showRenamePreview) {
            RenamePreviewView(candidates: $renameCandidates) {
                performRenameAction()
            }
        }
    }

    private func handleBibFileDrop(providers: [NSItemProvider]) -> Bool {
        // Filter providers first
        let validProviders = providers.filter { $0.canLoadObject(ofClass: URL.self) }
        guard !validProviders.isEmpty else { return false }
        
        Task {
            var contents: [String] = []
            
            for provider in validProviders {
                if let url = await loadURL(from: provider) {
                    if url.pathExtension.lowercased() == "bib",
                       let content = try? String(contentsOf: url, encoding: .utf8) {
                        contents.append(content)
                    }
                }
            }
            
            await MainActor.run {
                if !contents.isEmpty {
                    let newContent = contents.joined(separator: "\n\n")
                    // Append to existing output if it looks like BibTeX
                    let existing = outputText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !existing.isEmpty && (existing.contains("@article") || existing.contains("@book") || existing.contains("@inproceedings") || existing.contains("@misc")) {
                        // Append and clean the combined result to ensure consistency and deduplication
                        outputText = cleanBibTeX(existing + "\n\n" + newContent)
                    } else {
                        outputText = cleanBibTeX(newContent)
                    }
                }
            }
        }
        
        return true
    }
    
    private func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }

    private func generateBibEntry() {
        let checkedFiles = selectedFiles.filter { $0.isChecked }
        guard !checkedFiles.isEmpty else { return }

        isProcessing = true
        outputText = "Processing \(checkedFiles.count) file(s)..."
        
        let filesToProcess = checkedFiles
                let opts = BibTeXFormatOptions(shortenAuthors: shortenAuthors, abbreviateJournals: abbreviateJournals, useLaTeXEscaping: useLaTeXEscaping)
        let isOnlineAllowed = referenceLookupMode != .offline // Capture value to avoid self capture in Task
        
        extractionTask = Task {
            if Task.isCancelled { 
                await MainActor.run { isProcessing = false }
                return 
            }
            var extractedEntries: [String] = []
            
            await withTaskGroup(of: String?.self) { group in
                for file in filesToProcess {
                    if Task.isCancelled { break }
                    group.addTask {
                        // If it's a .bib file, read content directly
                        if file.url.pathExtension.lowercased() == "bib" {
                            return try? String(contentsOf: file.url, encoding: .utf8)
                        } else {
                            // Extract from PDF
                            return await extractBibTeX(url: file.url, allowOnline: isOnlineAllowed, options: opts)
                        }
                    }
                }
                
                for await result in group {
                    if let content = result, !content.isEmpty {
                        extractedEntries.append(content)
                    }
                }
            }
            
            await MainActor.run {
                if extractedEntries.isEmpty {
                    outputText = "Unable to extract BibTeX from selected files."
                } else {
                    let combined = extractedEntries.joined(separator: "\n\n")
                    // Automatically clean/format the combined result to remove duplicates from the merge
                    outputText = cleanBibTeX(combined)
                }
                isProcessing = false
            }
        }
    }
    
    private func extractReferencesAction() {
        let checkedFiles = selectedFiles.filter { $0.isChecked }
        guard !checkedFiles.isEmpty else { return }

        isProcessing = true
        isCancelled = false
        // Capture existing content to preserve
        let preservedOutput = outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasPreservedContent = !preservedOutput.isEmpty && (preservedOutput.contains("@article") || preservedOutput.contains("@book") || preservedOutput.contains("@inproceedings") || preservedOutput.contains("@misc"))

        isProcessing = true
        isCancelled = false
        
        // Initial status message
        if hasPreservedContent {
            outputText = preservedOutput + "\n\n// Starting extraction from \(checkedFiles.count) PDF(s)..."
        } else {
            outputText = "Processing \(checkedFiles.count) PDF(s) for reference extraction..."
        }

        extractionTask = Task {
                    let opts = BibTeXFormatOptions(shortenAuthors: shortenAuthors, abbreviateJournals: abbreviateJournals, useLaTeXEscaping: useLaTeXEscaping)
            var allReferences: [String] = []
            var currentFile = 0
            
            let pdfCount = checkedFiles.filter { $0.url.pathExtension.lowercased() == "pdf" }.count
            let bibCount = checkedFiles.filter { $0.url.pathExtension.lowercased() == "bib" }.count

            // Process each file sequentially
            for file in checkedFiles {
                currentFile += 1
                let isBib = file.url.pathExtension.lowercased() == "bib"
                let fileType = isBib ? "BibTeX" : "PDF"

                await MainActor.run {
                    let statusMsg = "Processing \(fileType) \(currentFile) of \(checkedFiles.count): \(file.url.lastPathComponent)..."
                    if hasPreservedContent {
                        outputText = preservedOutput + "\n\n// " + statusMsg
                    } else {
                        outputText = statusMsg
                    }
                }

                if isCancelled { break }
                
                if isBib {
                    // Handle .bib file
                    if let content = try? String(contentsOf: file.url, encoding: .utf8) {
                        // Simple splitting of entries to allow deduplication
                        // We assume standard formatting where entries start with @
                        // Use regex to split safely? Or simple split.
                        // Let's try splitting by "\n@" and repairing.
                        // A more robust way: use the same regex we use for deduplication detection?
                        // For now, let's treat the whole file content as a source of entries.
                        // We can use a regex to find all matches of @type{...}
                        // Or just append the whole block if deduplicateReferences can handle it?
                        // deduplicateReferences expects [String] where each string is ONE entry.
                        
                        // Heuristic split:
                        let rawEntries = content.components(separatedBy: "@")
                        for entry in rawEntries {
                            let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
                            if trimmed.isEmpty { continue }
                            // Re-prepends @ if it looks like an entry type
                            if let firstWord = trimmed.components(separatedBy: "{").first,
                               ["article", "book", "misc", "inproceedings", "phdthesis", "techreport"].contains(firstWord.lowercased()) {
                                allReferences.append("@" + trimmed)
                            }
                        }
                    }
                } else {
                    // Handle PDF
                    let references = await extractReferences(url: file.url, options: opts, mode: referenceLookupMode, isCancelledCheck: { [self] in
                        return isCancelled
                    }) { current, total in
                        // Update progress on main thread
                        Task { @MainActor in
                            let progressMsg = "\(fileType) \(currentFile)/\(checkedFiles.count) - Reference \(current)/\(total): \(file.url.lastPathComponent)"
                            if hasPreservedContent {
                                outputText = preservedOutput + "\n\n// " + progressMsg
                            } else {
                                outputText = progressMsg
                            }
                        }
                    }
                    allReferences.append(contentsOf: references)
                }
            }

            await MainActor.run {
                if isCancelled {
                    if hasPreservedContent {
                        // Restore preserved content and append cancellation note
                        outputText = preservedOutput + "\n\n// Extraction cancelled by user"
                    } else {
                        if allReferences.count > 1 {
                            let deduplicated = deduplicateReferences(allReferences)
                            let duplicateCount = allReferences.count - deduplicated.count
                            let header = "// Extraction stopped - \(deduplicated.count) unique reference(s) found (\(duplicateCount) duplicates removed)\n\n"
                            outputText = header + deduplicated.joined(separator: "\n\n")
                        } else {
                            outputText = "// Extraction cancelled by user"
                        }
                    }
                } else if allReferences.isEmpty {
                    if hasPreservedContent {
                         outputText = preservedOutput + "\n\n// No new references found in \(checkedFiles.count) file(s)."
                    } else {
                         outputText = "No references found in \(checkedFiles.count) file(s)."
                    }
                } else {
                    // Start with what we had (if any)
                    var combinedReferences: [String] = []
                    
                    if hasPreservedContent {
                         // Parse existing references to include in deduplication not trivial as they are a string block.
                         // But we can just join strings and let cleanBibTeX/deduplicate handle it if we passed parsed entries?
                         // deduplicateReferences takes [String].
                         // existingOutput is a String.
                         // Simple approach: Strings concatenation, then cleanBibTeX (which seems to do some cleanup/formatting).
                         // BUT deduplicateReferences is local helper.
                         // Let's rely on cleanBibTeX for global cleanup if possible, or manually split preservedOutput?
                         
                         // Better: append new raw references to preserved output string, then run a deduplication pass?
                         // Re-using deduplicateReferences requires splitting the string.
                         
                         // Let's assume we want to append and then clean.
                         // But existing entries in `preservedOutput` might not be in the same format as `allReferences`.
                         
                         // Setup for merging:
                         // Setup for merging:
                         // let separator = "\n\n" // Unused

                         // var finalOutput = preservedOutput + separator + allReferences.joined(separator: separator) // Unused
                         
                         // Try to split preserved output more robustly?
                         // For now, rely on \n\n. If that fails, existingEntries might be one huge block.
                         // But we must NOT drop it. deduplicateReferences usage now protects us.
                         let existingEntries = preservedOutput.components(separatedBy: "\n\n").filter { $0.contains("@") }
                         combinedReferences = existingEntries + allReferences
                         // Note: cleanBibTeX might not deduplicate based on semantic equality, but it formats.
                         // Let's try to deduplicate strictly newly added vs existing?
                         // Or just append.
                         
                         // User said "merge them".
                         // cleanBibTeX (in PDFCompressor) doesn't seem to deduplicate deeply.
                         // But `deduplicateReferences` (local private func) does logic.
                         
                         // Let's try to run deduplicateReferences on EVERYTHING.
                         // We need to split `preservedOutput` back into entries.
                    } else {
                        combinedReferences = allReferences
                    }

                    // Deduplicate merged references
                    let deduplicated = deduplicateReferences(combinedReferences)
                    let duplicateCount = combinedReferences.count - deduplicated.count

                    var header = ""
                    if !hasPreservedContent {
                         header = "// Extracted \(deduplicated.count) unique reference(s) from \(pdfCount) PDF(s) and \(bibCount) Bib file(s)"
                         if duplicateCount > 0 {
                             header += " (\(duplicateCount) duplicates removed)"
                         }
                          header += "\n// Verified entries fetched from \(referenceLookupMode.rawValue) mode\n\n"
                    } else {
                        // Brief header for new batch
                        header = "// Added \(allReferences.count) new reference(s) from \(checkedFiles.count) file(s). Total: \(deduplicated.count).\n\n"
                    }

                    outputText = (hasPreservedContent ? "" : header) + deduplicated.joined(separator: "\n\n")
                }
                isProcessing = false
                extractionTask = nil
            }
        }
    }

    private func deduplicateReferences(_ references: [String]) -> [String] {
        var seen = Set<String>()
        var unique: [String] = []

        for ref in references {
            // Skip cancelled markers
            if ref.contains("cancelled") { continue }

            // Extract DOI for deduplication key
            var dedupeKey = ""
            if let doiMatch = ref.range(of: #"doi = \{([^}]+)\}"#, options: .regularExpression) {
                dedupeKey = String(ref[doiMatch])
            } else {
                // Fallback: use title + year as key
                var titleKey = ""
                var yearKey = ""

                if let titleMatch = ref.range(of: #"title = \{([^}]+)\}"#, options: .regularExpression) {
                    titleKey = String(ref[titleMatch]).lowercased()
                }
                if let yearMatch = ref.range(of: #"year = \{(\d{4})\}"#, options: .regularExpression) {
                    yearKey = String(ref[yearMatch])
                }

                dedupeKey = titleKey + yearKey
            }

            // Only add if not seen before
            // If key is empty (parsing failed), use the content itself as key to avoid dropping it!
            if dedupeKey.isEmpty {
                 dedupeKey = "UNKNOWN-" + String(ref.hashValue)
            }

            if !seen.contains(dedupeKey) {
                seen.insert(dedupeKey)
                unique.append(ref)
            }
        }

        return unique
    }

    private func lookupDOIAction() {
        guard !doiInput.isEmpty else { return }
        
        activeAction = .lookup
        isProcessing = true
        outputText = "Fetching BibTeX for DOI: \(doiInput)..."
        
        Task {
            let cleanDOI = doiInput.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                .replacingOccurrences(of: "https://doi.org/", with: "")
                .replacingOccurrences(of: "doi:", with: "")
            
            if let bib = await fetchBibTeXFromCrossRef(doi: cleanDOI) {
                await MainActor.run {
                    // Check if we need formatting
                    var finalBib = bib
                    if shortenAuthors || abbreviateJournals {
                               let opts = BibTeXFormatOptions(shortenAuthors: shortenAuthors, abbreviateJournals: abbreviateJournals, useLaTeXEscaping: useLaTeXEscaping)
                       finalBib = reformatBibTeX(bib, options: opts)
                    }
                    
                    outputText = finalBib
                    isProcessing = false
                    activeAction = nil
                }
            } else {
                await MainActor.run {
                    outputText = "Error: Could not fetch BibTeX for DOI '\(cleanDOI)'"
                    isProcessing = false
                    activeAction = nil
                }
            }
        }
    }

    // MARK: - Formatting Helpers
    
    private func applyStandardAuthorFormat() {
        // Author Action: Process Authors (True), Skip Journals (false to avoid side effects)
        let opts = BibTeXFormatOptions(shortenAuthors: true, abbreviateJournals: false, useLaTeXEscaping: self.useLaTeXEscaping, addDotsToInitials: true, addDotsToJournals: self.addDotsToJournals, processAuthors: true)
        outputText = reformatBibTeX(outputText, options: opts)
        
        self.shortenAuthors = true
        self.addDotsToInitials = true
    }

    private func applyMinimalistAuthorFormat() {
        // Author Action: Process Authors (True), Skip Journals
        let opts = BibTeXFormatOptions(shortenAuthors: true, abbreviateJournals: false, useLaTeXEscaping: self.useLaTeXEscaping, addDotsToInitials: false, addDotsToJournals: self.addDotsToJournals, processAuthors: true)
        outputText = reformatBibTeX(outputText, options: opts)
        
        self.shortenAuthors = true
        self.addDotsToInitials = false
    }

    private func applyStandardJournalFormat() {
        // Journal Action: Process Journals (True), Skip Authors (False to avoid side effects)
        let opts = BibTeXFormatOptions(shortenAuthors: self.shortenAuthors, abbreviateJournals: true, useLaTeXEscaping: self.useLaTeXEscaping, addDotsToInitials: self.addDotsToInitials, addDotsToJournals: true, processAuthors: false)
        outputText = reformatBibTeX(outputText, options: opts)
        
        self.abbreviateJournals = true
        self.addDotsToJournals = true
    }

    private func applyMinimalistJournalFormat() {
        // Journal Action: Process Journals (True), Skip Authors
        let opts = BibTeXFormatOptions(shortenAuthors: self.shortenAuthors, abbreviateJournals: true, useLaTeXEscaping: self.useLaTeXEscaping, addDotsToInitials: self.addDotsToInitials, addDotsToJournals: false, processAuthors: false)
        outputText = reformatBibTeX(outputText, options: opts)
        
        self.abbreviateJournals = true
        self.addDotsToJournals = false
    }

    private func applyLatexEscaping() {
        // LaTeX Action: Apply escaping, but don't reformat authors/journals structure
        let opts = BibTeXFormatOptions(shortenAuthors: self.shortenAuthors, abbreviateJournals: self.abbreviateJournals, useLaTeXEscaping: true, addDotsToInitials: self.addDotsToInitials, addDotsToJournals: self.addDotsToJournals, processAuthors: false)
        outputText = reformatBibTeX(outputText, options: opts)
        self.useLaTeXEscaping = true
    }





    private func cleanOutput() {
        guard !outputText.isEmpty else { return }
        outputText = cleanBibTeX(outputText)
    }

    private func exportBibFile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "references.bib"
        panel.allowedContentTypes = [UTType(filenameExtension: "bib") ?? .plainText]
        
        if panel.runModal() == .OK, let url = panel.url {
            try? outputText.write(to: url, atomically: true, encoding: .utf8)
        }
    }
    
    private func analyzeAndRenameAction() {
        let files = selectedFiles.filter { $0.isChecked }
        guard !files.isEmpty else { return }
        
        isProcessing = true
        renameCandidates = []
        
        Task {
            var candidates: [RenameCandidate] = []
            
            for file in files {
                // Reuse extractReferences logic but just one at a time for safety
                // We use PDFCompressor's fetchBibTeXFromCrossRef if we have DOI, or local extraction.
                // For renaming, local extraction is safer/faster if metadata exists.
                // We'll use PDFCompressor.shared.extractBibTeX
                
                // Pass allowOnlineLookup setting to enable CrossRef fallback if DOI is found
                        let opts = BibTeXFormatOptions(shortenAuthors: shortenAuthors, abbreviateJournals: abbreviateJournals, useLaTeXEscaping: useLaTeXEscaping)
                if let bib = await extractBibTeX(url: file.url, allowOnline: self.referenceLookupMode != .offline, options: opts) {
                    if let entry = parseBibTeXToMetadata(bib) {
                        let newName = generateFilename(author: entry.author, year: entry.year, title: entry.title, journal: entry.journal)
                        // Only add if different
                        if newName != file.url.lastPathComponent {
                             candidates.append(RenameCandidate(originalURL: file.url, newName: newName))
                        }
                    }
                }
            }
            
            await MainActor.run {
                self.renameCandidates = candidates
                self.isProcessing = false
                if !candidates.isEmpty {
                    self.showRenamePreview = true
                } else {
                    self.outputText = "Could not extract sufficient metadata (Author/Year/Title) from the selected files to suggest names."
                }
            }
        }
    }
    
    private func parseBibTeXToMetadata(_ bib: String) -> (author: String, year: String, title: String, journal: String?)? {
        // Simple regex parsing using helper
        func extract(_ key: String) -> String? {
            let pattern = "\(key)\\s*=\\s*\\{([^\\}]+)\\}"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: bib, range: NSRange(bib.startIndex..., in: bib)),
                  let range = Range(match.range(at: 1), in: bib) else { return nil }
            return String(bib[range])
        }
        
        guard let author = extract("author"),
              let year = extract("year"),
              let title = extract("title") else { return nil }
        
        let journal = extract("journal") ?? extract("booktitle")
              
        return (author, year, title, journal)
    }
    
    private func generateFilename(author: String, year: String, title: String, journal: String?) -> String {
        // Requested Format: Name_Journal_Year
        // Fallbacks: Name_Year_Title, Name_Title
        
        // Get surname of first author
        let firstAuthor = author.components(separatedBy: " and ").first ?? author
        let surname = firstAuthor.components(separatedBy: ", ").first ?? firstAuthor.components(separatedBy: " ").last ?? firstAuthor
        
        // Clean strings
        let cleanSurname = surname.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanYear = year.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let illegalChars = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        
        // Strategy 1: Name_Journal_Year
        if let journal = journal, !journal.isEmpty {
             let cleanJournal = journal.prefix(40).components(separatedBy: illegalChars).joined(separator: "").trimmingCharacters(in: .whitespacesAndNewlines)
             // Use underscore as requested
             return "\(cleanSurname)_\(cleanJournal)_\(cleanYear).pdf"
        }
        
        // Strategy 2: Name_Year_Title (fallback if no journal)
        let safeTitle = title.components(separatedBy: illegalChars).joined(separator: " ")
                             .trimmingCharacters(in: .whitespacesAndNewlines)
                             .prefix(50)
        
        if !cleanYear.isEmpty {
             return "\(cleanSurname)_\(cleanYear)_\(safeTitle).pdf"
        }
        
        // Strategy 3: Name_Title (fallback if no year)
        return "\(cleanSurname)_\(safeTitle).pdf"
    }
    
    private func performRenameAction() {
        for candidate in renameCandidates where candidate.isSelected {
            let fileManager = FileManager.default
            let folder = candidate.originalURL.deletingLastPathComponent()
            let destination = folder.appendingPathComponent(candidate.newName)
            
            // Basic collision handling
            var finalDestination = destination
            var counter = 1
            while fileManager.fileExists(atPath: finalDestination.path) {
                let name = destination.deletingPathExtension().lastPathComponent
                let ext = destination.pathExtension
                finalDestination = folder.appendingPathComponent("\(name) (\(counter)).\(ext)")
                counter += 1
            }
            
            do {
                try fileManager.moveItem(at: candidate.originalURL, to: finalDestination)
                // Update selected file URL in list
                if let index = selectedFiles.firstIndex(where: { $0.url == candidate.originalURL }) {
                    let size = (try? fileManager.attributesOfItem(atPath: finalDestination.path)[.size] as? Int64) ?? 0
                    selectedFiles[index] = ContentView.PDFFile(url: finalDestination, originalSize: size, isChecked: true)
                }
            } catch {
                print("Error renaming: \(error)")
            }
        }
        outputText = "Renamed \(renameCandidates.filter{$0.isSelected}.count) file(s)."
    }
    
    private func readMetadata(from url: URL) {
        guard let doc = PDFDocument(url: url) else { return }
        let attrs = doc.documentAttributes
        
        metaTitle = attrs?[PDFDocumentAttribute.titleAttribute] as? String ?? ""
        metaAuthor = attrs?[PDFDocumentAttribute.authorAttribute] as? String ?? ""
        metaSubject = attrs?[PDFDocumentAttribute.subjectAttribute] as? String ?? ""
        metaKeywords = attrs?[PDFDocumentAttribute.keywordsAttribute] as? String ?? ""
        
        if let creator = attrs?[PDFDocumentAttribute.creatorAttribute] as? String {
            metaCreator = creator
        } else if let creatorStr = attrs?["Creator"] as? String {
            metaCreator = creatorStr
        } else {
            metaCreator = ""
        }
        
        // Auto-select text
        activeAction = .metadata
    }
    
    private func writeMetadataAction() async {
        guard let file = selectedFiles.first(where: { $0.isChecked }) else { return }
        
        isProcessing = true
        activeAction = .metadata
        
        // Call PDFCompressor.writeMetadata
        // Assumes PDFCompressor.writeMetadata is available (it is now)
        let success = await PDFCompressor.writeMetadata(
            url: file.url,
            title: metaTitle,
            author: metaAuthor,
            subject: metaSubject,
            keywords: metaKeywords,
            creator: metaCreator
        )
        
        await MainActor.run {
            isProcessing = false
            if success {
                // Update file size in list
                if let idx = selectedFiles.firstIndex(where: { $0.id == file.id }) {
                    let newSize = (try? FileManager.default.attributesOfItem(atPath: file.url.path)[.size] as? Int64) ?? file.originalSize
                    selectedFiles[idx] = ContentView.PDFFile(url: file.url, originalSize: newSize, isChecked: true)
                }
                outputText = "Metadata successfully updated for \(file.url.lastPathComponent)"
            } else {
                outputText = "Failed to update metadata. Ensure Ghostscript is available."
            }
        }
    }
    
    private func lookupDOIAction() async {
        let trimmedDOI = doiInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDOI.isEmpty else { return }
        
        isProcessing = true
        outputText = "Fetching BibTeX for DOI: \(trimmedDOI)..."
        
        // Call backend function
        if let bib = await fetchBibTeXFromCrossRef(doi: trimmedDOI) {
            // Apply default reformatting to clean up MathML/tags using defaults
            let cleanBib = reformatBibTeX(bib, options: BibTeXFormatOptions())
            
            await MainActor.run {
                outputText = cleanBib
                isProcessing = false
            }
        } else {
            await MainActor.run {
                outputText = "Failed to fetch BibTeX for DOI: \(trimmedDOI).\nPlease check the DOI and your internet connection."
                isProcessing = false
            }
        }
    }

    private func getPreviewText() -> String {
        return outputText
    }
}

struct RenamePreviewView: View {
    @Binding var candidates: [ResearcherTabView.RenameCandidate]
    var onConfirm: () -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Preview Renaming Changes")
                .font(.headline)
                .padding(.top)
                
            List($candidates) { $candidate in
                HStack {
                    Toggle("", isOn: $candidate.isSelected)
                        .labelsHidden()
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(candidate.originalURL.lastPathComponent)
                            .font(.caption)
                            .strikethrough()
                            .foregroundColor(.red)
                        
                        HStack {
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(candidate.newName)
                                .font(.body)
                                .fontWeight(.medium)
                                .foregroundColor(.green)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(minHeight: 200, maxHeight: 400)
            .border(Color.secondary.opacity(0.2))
            
            HStack(spacing: 20) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Rename Selected (\(candidates.filter{$0.isSelected}.count))") {
                    onConfirm()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(candidates.filter{$0.isSelected}.isEmpty)
            }
            .padding(.bottom)
        }
        .padding()
        .frame(minWidth: 500)
    }
}

// MARK: - BibTeX Formatter Tab View
struct BibTeXFormatterView: View {
    @Binding var selectedFiles: [ContentView.PDFFile]
    @Binding var outputText: String
    @Binding var isProcessing: Bool
    @AppStorage("isDarkMode_v2") private var isDarkMode = true
    @AppStorage("shortenAuthors") private var shortenAuthors = false
    @AppStorage("abbreviateJournals") private var abbreviateJournals = false
    @AppStorage("useLaTeXEscaping") private var useLaTeXEscaping = false
    @State private var cleanBibTeX: Bool = true
    @State private var removeDuplicates: Bool = true
    @State private var sortEntries: Bool = false
    @State private var showCitationPreview: Bool = false
    @State private var selectedCitationStyle: CitationStyle = .apa

    enum CitationStyle: String, CaseIterable, Identifiable {
        case apa = "APA"
        case mla = "MLA"
        case chicago = "Chicago"
        case harvard = "Harvard"
        case ieee = "IEEE"

        var id: String { rawValue }
    }

    // Raw preview of first 5 entries from files (before formatting)
    var rawPreviewText: String {
        guard !selectedFiles.isEmpty else { return "" }

        var previewEntries: [String] = []
        var count = 0

        for file in selectedFiles where file.url.pathExtension.lowercased() == "bib" && count < 5 {
            if let content = try? String(contentsOf: file.url, encoding: .utf8) {
                let entries = parseBibTeXEntries(content)
                for entry in entries.prefix(5 - count) {
                    previewEntries.append(entry.content)
                    count += 1
                    if count >= 5 { break }
                }
            }
            if count >= 5 { break }
        }

        if !previewEntries.isEmpty {
            return "// Raw BibTeX (first 5 entries)\n// Click 'Format BibTeX Files' to apply formatting options\n\n" + previewEntries.joined(separator: "\n\n")
        }
        return ""
    }

    // Display text for output box (first 5 entries only)
    var displayText: String {
        if !outputText.isEmpty {
            // Already formatted - show first 5 entries only
            let entries = parseBibTeXEntries(outputText)
            let first5 = entries.prefix(5)
            let preview = first5.map { $0.content }.joined(separator: "\n\n")

            if entries.count > 5 {
                return preview + "\n\n// ... and \(entries.count - 5) more entries.\n// Click 'Save All' to export all \(entries.count) entries."
            }
            return preview
        } else if !selectedFiles.isEmpty {
            // Files loaded but not formatted yet - show raw preview
            return rawPreviewText
        } else {
            return ""
        }
    }

    // Generate citation preview (first 5 entries)
    var citationPreviewText: String {
        guard !outputText.isEmpty else { return "" }

        let entries = parseBibTeXEntries(outputText)
        let first5 = entries.prefix(5)
        var citations: [String] = []

        for (index, entry) in first5.enumerated() {
            let citation = formatCitation(entry.content, style: selectedCitationStyle, index: index + 1)
            citations.append(citation)
        }

        var result = citations.joined(separator: "\n\n")
        if entries.count > 5 {
            result += "\n\n// ... and \(entries.count - 5) more citations.\n// Click 'Save All Citations' to export all \(entries.count) citations."
        }
        return result
    }

    // Format a single BibTeX entry as a citation
    func formatCitation(_ bibEntry: String, style: CitationStyle, index: Int) -> String {
        // Extract basic fields
        let author = extractField("author", from: bibEntry) ?? "Unknown Author"
        let title = extractField("title", from: bibEntry) ?? "Untitled"
        let year = extractField("year", from: bibEntry) ?? "n.d."
        let journal = extractField("journal", from: bibEntry)
        let volume = extractField("volume", from: bibEntry)
        let pages = extractField("pages", from: bibEntry)

        switch style {
        case .apa:
            var citation = "\(author) (\(year)). \(title)."
            if let j = journal {
                citation += " \(j)"
                if let v = volume {
                    citation += ", \(v)"
                }
                if let p = pages {
                    citation += ", \(p)"
                }
                citation += "."
            }
            return citation

        case .mla:
            var citation = "\(author). \"\(title).\""
            if let j = journal {
                citation += " \(j)"
                if let v = volume, let p = pages {
                    citation += ", vol. \(v), \(year), pp. \(p)."
                } else if let v = volume {
                    citation += ", vol. \(v), \(year)."
                } else {
                    citation += ", \(year)."
                }
            }
            return citation

        case .chicago:
            var citation = "\(author). \"\(title).\""
            if let j = journal {
                citation += " \(j)"
                if let v = volume {
                    citation += " \(v)"
                }
                if let p = pages {
                    citation += " (\(year)): \(p)."
                } else {
                    citation += " (\(year))."
                }
            }
            return citation

        case .harvard:
            var citation = "\(author) \(year), '\(title)'"
            if let j = journal {
                citation += ", \(j)"
                if let v = volume, let p = pages {
                    citation += ", vol. \(v), pp. \(p)."
                } else {
                    citation += "."
                }
            }
            return citation

        case .ieee:
            var citation = "[\(index)] \(author), \"\(title),\""
            if let j = journal {
                citation += " \(j)"
                if let v = volume, let p = pages {
                    citation += ", vol. \(v), pp. \(p), \(year)."
                } else if let v = volume {
                    citation += ", vol. \(v), \(year)."
                } else {
                    citation += ", \(year)."
                }
            }
            return citation
        }
    }

    // Extract a field from BibTeX entry
    func extractField(_ field: String, from bibEntry: String) -> String? {
        let pattern = field + #"\s*=\s*\{([^}]+)\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: bibEntry, options: [], range: NSRange(bibEntry.startIndex..., in: bibEntry)),
              let range = Range(match.range(at: 1), in: bibEntry) else {
            return nil
        }
        return String(bibEntry[range])
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                HStack {
                    Image(systemName: "text.book.closed.fill")
                        .font(.title)
                        .foregroundColor(.purple)
                    Text("BibTeX Formatter")
                        .font(.title)
                        .bold()
                    Spacer()
                }
                .padding(.horizontal)

                // Info card
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                        Text("Drop .bib files to format and view")
                            .font(.headline)
                    }
                    Text("This tab accepts BibTeX (.bib) files for formatting and viewing. Use the Researcher tab for extracting BibTeX from PDFs.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(isDarkMode ? Color(NSColor.controlBackgroundColor) : Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .padding(.horizontal)

                // Formatting options
                VStack(alignment: .leading, spacing: 12) {
                    Text("Format Options")
                        .font(.headline)
                        .padding(.horizontal)

                    VStack(spacing: 8) {
                        Toggle(isOn: $shortenAuthors) {
                            HStack(spacing: 6) {
                                Image(systemName: "person.2.fill")
                                Text("Shorten Authors")
                                    .font(.subheadline)
                            }
                        }
                        .toggleStyle(.checkbox)

                        Toggle(isOn: $abbreviateJournals) {
                            HStack(spacing: 6) {
                                Image(systemName: "book.fill")
                                Text("Abbreviate Journals")
                                    .font(.subheadline)
                            }
                        }
                        .toggleStyle(.checkbox)

                        Toggle(isOn: $useLaTeXEscaping) {
                            HStack(spacing: 6) {
                                Image(systemName: "textformat")
                                Text("Use LaTeX Escaping")
                                    .font(.subheadline)
                            }
                        }
                        .toggleStyle(.checkbox)

                        Divider()
                            .padding(.vertical, 4)

                        Toggle(isOn: $cleanBibTeX) {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                Text("Clean & Normalize")
                                    .font(.subheadline)
                            }
                        }
                        .toggleStyle(.checkbox)

                        Toggle(isOn: $removeDuplicates) {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.on.doc.fill")
                                Text("Remove Duplicates")
                                    .font(.subheadline)
                            }
                        }
                        .toggleStyle(.checkbox)

                        Toggle(isOn: $sortEntries) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.up.arrow.down")
                                Text("Sort by Year")
                                    .font(.subheadline)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                    .padding()
                    .background(isDarkMode ? Color(NSColor.controlBackgroundColor) : Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    .padding(.horizontal)
                }

                // Format and Reset buttons
                HStack(spacing: 12) {
                    Button(action: formatBibFiles) {
                        HStack {
                            if isProcessing {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "wand.and.stars")
                            }
                            Text(isProcessing ? "Formatting..." : "Format BibTeX Files")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(selectedFiles.isEmpty || isProcessing)

                    Button(action: { outputText = "" }) {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset")
                        }
                        .padding()
                    }
                    .buttonStyle(.bordered)
                    .disabled(outputText.isEmpty)
                }
                .padding(.horizontal)

                // Output area - always visible
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(outputText.isEmpty && !selectedFiles.isEmpty ? "BibTeX Preview (first 5 entries)" : "Formatted BibTeX (first 5 entries)")
                            .font(.headline)
                        Spacer()

                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(displayText, forType: .string)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.doc")
                                Text("Copy")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(displayText.isEmpty)

                        if !outputText.isEmpty {
                            Button(action: saveBibTeXFile) {
                                HStack(spacing: 4) {
                                    Image(systemName: "square.and.arrow.down")
                                    Text("Save All")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.purple)
                        }
                    }

                    ScrollView {
                        if displayText.isEmpty {
                            Text("Drop .bib files to see preview")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                        } else {
                            Text(displayText)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        }
                    }
                    .frame(height: 400)
                    .background(isDarkMode ? Color(NSColor.textBackgroundColor) : Color.white)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                }
                .padding(.horizontal)

                // Citation Preview - show only AFTER formatting
                if !outputText.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Citation Preview")
                            .font(.headline)
                            .padding(.horizontal)

                        VStack(spacing: 8) {
                            HStack {
                                Text("Style:")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Picker("", selection: $selectedCitationStyle) {
                                    ForEach(CitationStyle.allCases) { style in
                                        Text(style.rawValue).tag(style)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 120)

                                Spacer()

                                Button(action: { showCitationPreview.toggle() }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: showCitationPreview ? "eye.slash" : "eye")
                                        Text(showCitationPreview ? "Hide" : "Show")
                                    }
                                }
                                .buttonStyle(.bordered)
                            }

                            if showCitationPreview {
                                Divider()
                                    .padding(.vertical, 4)

                                HStack {
                                    Spacer()
                                    Button(action: {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(citationPreviewText, forType: .string)
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "doc.on.doc")
                                            Text("Copy")
                                        }
                                    }
                                    .buttonStyle(.bordered)

                                    Button(action: saveCitationsFile) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "square.and.arrow.down")
                                            Text("Save All Citations")
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.orange)
                                }
                                .padding(.bottom, 4)

                                ScrollView {
                                    Text(citationPreviewText)
                                        .font(.system(.body))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(height: 250)
                                .padding(12)
                                .background(isDarkMode ? Color(NSColor.textBackgroundColor).opacity(0.5) : Color.white.opacity(0.5))
                                .cornerRadius(6)
                            }
                        }
                        .padding()
                        .background(isDarkMode ? Color(NSColor.controlBackgroundColor) : Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                        .padding(.horizontal)
                    }
                }

                Spacer()
            }
            .padding(.vertical)
        }
    }

    private func formatBibFiles() {
        isProcessing = true
        outputText = ""

        Task {
            var combinedBib = ""
            var allEntries: [BibEntry] = []

            // Read and parse all files
            for file in selectedFiles where file.url.pathExtension.lowercased() == "bib" {
                do {
                    let bibContent = try String(contentsOf: file.url, encoding: .utf8)
                    let entries = parseBibTeXEntries(bibContent)
                    allEntries.append(contentsOf: entries)
                } catch {
                    combinedBib += "// Error reading \(file.url.lastPathComponent): \(error.localizedDescription)\n\n"
                }
            }

            // Remove duplicates if requested
            if removeDuplicates {
                allEntries = deduplicateBibEntries(allEntries)
            }

            // Sort entries if requested
            if sortEntries {
                allEntries.sort { entry1, entry2 in
                    let year1 = extractYear(from: entry1.content)
                    let year2 = extractYear(from: entry2.content)
                    return year1 > year2 // Newest first
                }
            }

            // Format each entry
            let opts = BibTeXFormatOptions(
                shortenAuthors: shortenAuthors,
                abbreviateJournals: abbreviateJournals,
                useLaTeXEscaping: useLaTeXEscaping
            )

            for entry in allEntries {
                var formatted = entry.content

                // Apply formatting options
                formatted = reformatBibTeX(formatted, options: opts)
                combinedBib += formatted + "\n\n"
            }

            // Clean if requested (removes abstract, keywords, url, etc.)
            let shouldClean = self.cleanBibTeX
            if shouldClean {
                // Call the global cleanBibTeX function from PDFCompressor.swift
                combinedBib = GhostPDF_.cleanBibTeX(combinedBib)
            }

            await MainActor.run {
                let finalOutput = combinedBib.trimmingCharacters(in: .whitespacesAndNewlines)
                outputText = finalOutput.isEmpty ? "No BibTeX entries found" : finalOutput
                isProcessing = false
            }
        }
    }

    private struct BibEntry: Hashable {
        let key: String
        let content: String

        func hash(into hasher: inout Hasher) {
            hasher.combine(key)
        }

        static func == (lhs: BibEntry, rhs: BibEntry) -> Bool {
            lhs.key == rhs.key
        }
    }

    private func parseBibTeXEntries(_ text: String) -> [BibEntry] {
        var entries: [BibEntry] = []
        let pattern = #"@\w+\{([^,]+),[\s\S]*?\n\}"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return entries
        }

        let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))

        for match in matches {
            if let fullRange = Range(match.range, in: text),
               let keyRange = Range(match.range(at: 1), in: text) {
                let content = String(text[fullRange])
                let key = String(text[keyRange]).trimmingCharacters(in: .whitespaces)
                entries.append(BibEntry(key: key, content: content))
            }
        }

        return entries
    }

    private func deduplicateBibEntries(_ entries: [BibEntry]) -> [BibEntry] {
        var seen = Set<String>()
        var unique: [BibEntry] = []

        for entry in entries {
            let normalizedKey = entry.key.lowercased().trimmingCharacters(in: .whitespaces)
            if !seen.contains(normalizedKey) {
                seen.insert(normalizedKey)
                unique.append(entry)
            }
        }

        return unique
    }

    private func extractYear(from bibEntry: String) -> Int {
        let yearPattern = #"year\s*=\s*\{?(\d{4})\}?"#
        guard let regex = try? NSRegularExpression(pattern: yearPattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: bibEntry, options: [], range: NSRange(bibEntry.startIndex..., in: bibEntry)),
              let yearRange = Range(match.range(at: 1), in: bibEntry) else {
            return 0
        }
        return Int(String(bibEntry[yearRange])) ?? 0
    }

    // Save all BibTeX entries to file
    private func saveBibTeXFile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "formatted.bib"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try outputText.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                print("Error saving BibTeX: \(error)")
            }
        }
    }

    // Save all citations to file
    private func saveCitationsFile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "citations_\(selectedCitationStyle.rawValue.lowercased()).txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            // Generate all citations, not just first 5
            let entries = parseBibTeXEntries(outputText)
            var allCitations: [String] = []

            for (index, entry) in entries.enumerated() {
                let citation = formatCitation(entry.content, style: selectedCitationStyle, index: index + 1)
                allCitations.append(citation)
            }

            let fullText = allCitations.joined(separator: "\n\n")

            do {
                try fullText.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                print("Error saving citations: \(error)")
            }
        }
    }

}

struct SquareActionCard: View {
    let title: String
    let icon: String
    let color: Color
    let isActive: Bool
    let isProcessing: Bool
    let isDisabled: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                if isProcessing {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Stop") // Change label to Stop when processing
                        .font(.caption.bold())
                        .foregroundColor(.red)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 24))
                        .foregroundColor(isActive ? .white : color)
                    
                    Text(title)
                        .font(.caption.bold())
                        .foregroundColor(isActive ? .white : .primary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 100)
            .background(isActive ? color : Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isActive ? color : Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.6 : 1.0)
    }
}

// MARK: - AI Q&A Logic

extension ContentView {
    @MainActor
    func performQnA() async {
        guard !qnaInput.isEmpty else { return }
        guard let file = selectedFiles.first else { return }
        
        // 1. Add User Message
        let question = qnaInput
        chatHistory.append((role: "User", content: question))
        qnaInput = ""
        isThinking = true
        
        // 2. Extract Text Context (reuse existing logic or helper)
        // We'll extract text on the fly if not already available in a state, 
        // or just re-extract to be safe/simple for this MVP.
        // Using `PDFCompressor.extractText`
        
        var context = ""
        if let doc = PDFDocument(url: file.url) {
            context = doc.string ?? ""
        }
        
        if context.isEmpty {
            chatHistory.append((role: "System", content: "Error: Could not extract text from this PDF. It might be scanned or encrypted."))
            isThinking = false
            return
        }
        
        // 3. Call AI Backend
        do {
            if #available(macOS 26.0, *) {
                let answer = try await answerQuestionWithAI(question: question, context: context)
                chatHistory.append((role: "System", content: answer))
            } else {
                chatHistory.append((role: "System", content: "AI Chat requires macOS 26.0 or later."))
            }
        } catch {
            chatHistory.append((role: "System", content: "Error: \(error.localizedDescription)"))
        }
        
        isThinking = false
    }
}

// MARK: - Manual Region Extraction Logic

extension ContentView {
    @MainActor
    func saveManualRegions(for file: PDFFile, regions: [PageRegion]) async {
        guard !regions.isEmpty else { return }
        
        // 1. Ask for output directory
        await MainActor.run {
             // Ensure this runs on Main Thread
        }
        
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Save Images"
        panel.message = "Choose a folder to save extracted images"
        
        let response = await panel.beginSheetModal(for: NSApp.keyWindow ?? NSWindow())
        guard response == .OK, let outputDir = panel.url else { return }
        
        // 2. Process
        let pdfURL = file.url
        // Use PDFDocument to extract
        guard let document = PDFDocument(url: pdfURL) else { return }
        
        for (index, region) in regions.enumerated() {
            guard let page = document.page(at: region.page) else { continue }
            
            // Coordinate Conversion
            let pdfBox = page.bounds(for: PDFDisplayBox.mediaBox)
            let pdfW = pdfBox.width
            let pdfH = pdfBox.height
            
            let viewW = region.viewSize.width
            let viewH = region.viewSize.height
            
            // Calculate how the page was scaled/positioned in the view
            let scale = min(viewW / pdfW, viewH / pdfH)
            let renderedW = pdfW * scale
            let renderedH = pdfH * scale
            
            let offsetX = (viewW - renderedW) / 2.0
            let offsetY = (viewH - renderedH) / 2.0
            
            // Region in View Coords (Origin Top-Left)
            let rect = region.rect
            
            // Convert to Rendered Space (relative to actual image area top-left)
            let rectX_rendered = rect.origin.x - offsetX
            let rectY_rendered = rect.origin.y - offsetY
            
            // Convert to Normalized PDF Space (0..1)
            let normX = rectX_rendered / renderedW
            let normY = rectY_rendered / renderedH
            let normW = rect.width / renderedW
            let normH = rect.height / renderedH
            
            // Render High Resolution Image
            // Target 300 DPI (approx 4.17x 72 DPI)
            let renderScale: CGFloat = 4.17 
            let highResW = pdfW * renderScale
            let highResH = pdfH * renderScale
            let highResSize = CGSize(width: highResW, height: highResH)
            
            let fullImage = page.thumbnail(of: highResSize, for: PDFDisplayBox.mediaBox)
            
            // Calculate Crop Rect in High Res Image
            let cropX = normX * highResW
            let cropY = normY * highResH
            let cropW = normW * highResW
            let cropH = normH * highResH
            
            let cropRect = CGRect(x: cropX, y: cropY, width: cropW, height: cropH)
            
            if let cgImage = fullImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
               let cropped = cgImage.cropping(to: cropRect) {
                
                let filename = "Page\(region.page + 1)_Region\(index + 1).png"
                let fileURL = outputDir.appendingPathComponent(filename)
                
                if let destination = CGImageDestinationCreateWithURL(fileURL as CFURL, "public.png" as CFString, 1, nil) {
                    CGImageDestinationAddImage(destination, cropped, nil)
                    CGImageDestinationFinalize(destination)
                }
            }
        }
        
        // Notify
        await MainActor.run {
            let alert = NSAlert()
            alert.messageText = "Extraction Complete"
            alert.informativeText = "Saved \(regions.count) images to \(outputDir.lastPathComponent)"
            alert.runModal()
        }
    }
}

// MARK: - Mode Card Component

struct ModeCard: View {
    let mode: ContentView.MainMode
    let isEmphasized: Bool
    let isDarkMode: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 20) {
                // Icon with glow effect for emphasized card
                ZStack {
                    if isEmphasized {
                        Circle()
                            .fill(mode.color.opacity(0.2))
                            .frame(width: 100, height: 100)
                            .blur(radius: 20)
                            .scaleEffect(isHovered ? 1.2 : 1.0)
                    }

                    Image(systemName: mode.icon)
                        .font(.system(size: isEmphasized ? 52 : 44, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: isEmphasized
                                    ? [mode.color, mode.color.opacity(0.7)]
                                    : [mode.color.opacity(0.9), mode.color.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: isEmphasized ? mode.color.opacity(0.3) : .clear, radius: 10)
                }
                .frame(height: 100)

                VStack(spacing: 8) {
                    Text(mode.rawValue)
                        .font(.system(size: isEmphasized ? 24 : 20, weight: .bold))
                        .foregroundColor(isDarkMode ? .white : Color(red: 15/255, green: 23/255, blue: 42/255))

                    Text(mode.description)
                        .font(.system(size: 14))
                        .foregroundColor(isDarkMode ? .white.opacity(0.6) : Color(red: 15/255, green: 23/255, blue: 42/255).opacity(0.6))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                // "Get Started" indicator
                HStack(spacing: 4) {
                    Text(isEmphasized ? "Explore AI" : "Get Started")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(mode.color)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(mode.color)
                }
                .opacity(isHovered ? 1 : 0.7)
            }
            .padding(32)
            .frame(width: isEmphasized ? 340 : 300, height: isEmphasized ? 400 : 360)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(isDarkMode ? Color.white.opacity(0.05) : Color.white)
                    .shadow(
                        color: isEmphasized && isHovered
                            ? mode.color.opacity(0.3)
                            : (isDarkMode ? Color.black.opacity(0.3) : Color.black.opacity(0.1)),
                        radius: isEmphasized && isHovered ? 20 : (isHovered ? 12 : 8),
                        x: 0,
                        y: isHovered ? 8 : 4
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(
                        isEmphasized
                            ? LinearGradient(
                                colors: [mode.color.opacity(0.5), mode.color.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(
                                colors: [Color.clear, Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                        lineWidth: isEmphasized ? 2 : 0
                    )
            )
            .scaleEffect(isHovered ? 1.05 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
