import SwiftUI
import UniformTypeIdentifiers

enum ExtractMode: String, CaseIterable, Identifiable {
    case renderPage = "Render Page as Image"
    case extractEmbedded = "Extract Embedded Images"
    
    var id: String { rawValue }
}

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedFiles: [PDFFile] = []
    @AppStorage("isDarkMode_v2") private var isDarkMode = true
    @State private var selectedTab = 0
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
    @State private var reorderPageOrderText: String = ""
    
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
                .frame(height: 0) // Pull up into ZStack alignment if needed, or just let it stack
                .zIndex(10)

                Text("GhostPDF+")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(isDarkMode ? .white : Color(red: 15/255, green: 23/255, blue: 42/255))
                    .padding(.top, 4)
                
                if !appState.ghostscriptAvailable {
                    WarningBanner()
                }
                
                fileListArea

                Picker("Mode", selection: $selectedTab) {
                    Text("Basic").tag(0)
                    Text("Pro").tag(1)
                    Text("Tools").tag(2)
                    Text("Security").tag(3)
                    Text("Advanced").tag(4)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 24)
                .onChange(of: selectedTab) { newValue in
                    if (newValue == 1 || newValue == 2 || newValue == 3 || newValue == 4) && !appState.ghostscriptAvailable {
                        selectedTab = 0
                        showingProModeRequirementAlert = true
                    }
                }
                
                if selectedTab == 0 {
                    BasicTabView(selectedPreset: $selectedPreset)
                } else if selectedTab == 2 {
                    toolsTabContent
                } else if selectedTab == 3 {
                    securityTabContent
                } else if selectedTab == 4 {
                    advancedTabContent
                } else {
                    proTabContent
                }
                
                if isCompressing {
                    VStack {
                        ProgressView(value: totalProgress)
                            .progressViewStyle(.linear)
                        Text("Processing file \(currentFileIndex + 1) of \(selectedFiles.count)")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal, 24)
                }
                
                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.system(size: 13))
                        .foregroundColor(statusIsError ? Color(red: 248/255, green: 113/255, blue: 113/255) : Color(red: 74/255, green: 222/255, blue: 128/255))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                
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
        }
        .sheet(isPresented: $showingComparison) {
            if let input = comparisonInputURL, let output = comparisonOutputURL {
                ComparisonView(originalURL: input, compressedURL: output)
                    .frame(minWidth: 800, minHeight: 600)
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
        }
        .padding(24)
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
                reorderPageOrderText: $reorderPageOrderText
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
        guard !selectedFiles.isEmpty else { return }
        
        // For batch, we'll save to the same directory with _rasterized suffix
        // If single file, we could prompt, but for consistency let's auto-name or prompt folder?
        // Let's stick to auto-naming for batch to avoid 10 popups.
        

        if selectedFiles.count == 1 {
            let inputURL = selectedFiles[0].url
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = inputURL.deletingPathExtension().lastPathComponent + "_rasterized.pdf"
            panel.directoryURL = inputURL.deletingLastPathComponent()
            
            guard panel.runModal() == .OK, let url = panel.url else { return }
            // We'll use this single URL logic specially or just handle it below
            // To keep logic unified, let's just make a "plan" of inputs/outputs
             startOperation(message: "Rasterizing...")
             
             Task {
                 await MainActor.run {
                     selectedFiles[0].status = .compressing(0)
                 }
                 do {
                     let result = try await PDFCompressor.rasterize(
                         input: inputURL,
                         output: url,
                         dpi: rasterDPI
                     ) { prog in
                         Task { @MainActor in 
                            totalProgress = prog
                            selectedFiles[0].status = .compressing(prog)
                         }
                     }
                     
                     await MainActor.run {
                        selectedFiles[0].status = .done
                        selectedFiles[0].compressedSize = result.compressedSize
                        selectedFiles[0].outputURL = result.outputPath
                        lastResults = [result]
                        finishOperation(message: "Rasterized! Size: \(formatSize(result.compressedSize))")
                        showingResult = true
                     }
                 } catch {
                     await handleError(error)
                     await MainActor.run { selectedFiles[0].status = .error(error.localizedDescription) }
                 }
             }
             return
        }
        
        // Batch Mode
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
                        let outputURL = file.url.deletingPathExtension().appendingPathExtension("rasterized.pdf")
                        
                        let result = try await PDFCompressor.rasterize(
                            input: file.url,
                            output: outputURL,
                            dpi: rasterDPI,
                            password: currentPassword
                        ) { prog in
                            Task { @MainActor in
                                selectedFiles[index].status = .compressing(prog)
                                let perFile = 1.0 / Double(selectedFiles.count)
                                totalProgress = (Double(index) * perFile) + (prog * perFile)
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
            }
        }
    }
    
    private func extractImages() {
        guard !selectedFiles.isEmpty else { return }
        
        // Prompt for a single output directory for ALL images
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Output Folder"
        if let first = selectedFiles.first {
             panel.directoryURL = first.url.deletingLastPathComponent()
        }
        
        guard panel.runModal() == .OK, let outputDir = panel.url else { return }
        
        startOperation(message: "Extracting images...")
        currentFileIndex = 0
        
        Task {
            var lastCreatedFolder: URL? = nil
            let checkedFilesCount = selectedFiles.filter { $0.isChecked }.count
            
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
                                        let perFile = 1.0 / Double(selectedFiles.count)
                                        totalProgress = (Double(index) * perFile) + (prog * perFile)
                                    }
                                }
                            } else {
                                try await PDFCompressor.extractEmbeddedImages(
                                    input: file.url,
                                    outputDir: fileFolder,
                                    password: currentPassword
                                ) { prog in
                                     Task { @MainActor in
                                        selectedFiles[index].status = .compressing(prog)
                                        let perFile = 1.0 / Double(selectedFiles.count)
                                        totalProgress = (Double(index) * perFile) + (prog * perFile)
                                    }
                                }
                            }
                            
                            await MainActor.run {
                                selectedFiles[index].status = .done
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
                if checkedFilesCount == 1, let folder = lastCreatedFolder {
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
        guard !selectedFiles.isEmpty else { return }
        
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
                        let outputURL = file.url.deletingPathExtension().appendingPathExtension("compressed.pdf")
                        
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
                                let perFile = 1.0 / Double(selectedFiles.count)
                                totalProgress = (Double(index) * perFile) + (prog * perFile)
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
        
        // Prompt for output directory
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Output Folder"
        if let first = selectedFiles.first {
             panel.directoryURL = first.url.deletingLastPathComponent()
        }
        
        guard panel.runModal() == .OK, let outputDir = panel.url else { return }
        
        startOperation(message: "Splitting PDF...")
        
        Task {
            currentFileIndex = 0
            for (index, file) in selectedFiles.enumerated() {
                guard file.isChecked else { continue }
                await MainActor.run {
                    currentFileIndex = index
                    selectedFiles[index].status = .compressing(0)
                }
                
                if splitMode == .extractSelected {
                    // Use selected pages from thumbnails
                    let pages = Array(splitSelectedPages).sorted()
                    if pages.isEmpty {
                         // Fallback if nothing selected? Or maybe just splitting fails/warns?
                         // For now let's skip or handle error.
                         // Actually, let's assume if nothing selected, we do nothing or split all?
                         // Better to just return if empty, but for robust UX let's proceed and let backend handle or warn.
                         // But we should probably warn user before starting if empty.
                    }
                    
                    try await PDFCompressor.split(
                        input: file.url,
                        outputDir: outputDir,
                        pages: pages
                    ) { prog in
                        Task { @MainActor in
                            selectedFiles[index].status = .compressing(prog)
                            let perFile = 1.0 / Double(selectedFiles.count)
                            totalProgress = (Double(index) * perFile) + (prog * perFile)
                        }
                    }
                } else {
                    // If specific range, start/end provided
                    let start: Int? = splitMode == .extractRange ? splitStartPage : nil
                    let end: Int? = splitMode == .extractRange ? splitEndPage : nil
                    
                    try await PDFCompressor.split(
                        input: file.url,
                        outputDir: outputDir,
                        startPage: start,
                        endPage: end
                    ) { prog in
                        Task { @MainActor in
                            selectedFiles[index].status = .compressing(prog)
                            let perFile = 1.0 / Double(selectedFiles.count)
                            totalProgress = (Double(index) * perFile) + (prog * perFile)
                        }
                    }
                }
                
                // Success
                await MainActor.run { 
                    selectedFiles[index].status = .done 
                    finishOperation(message: "Split complete!")
                }

            }
            
            await MainActor.run {
                finishOperation(message: "Split complete!")
                PDFCompressor.revealInFinder(outputDir)
            }
        }
    }


    private func rotateOrDelete() {
        guard !selectedFiles.isEmpty else { return }
        
        // Use selected pages from thumbnails
        let pagesSet = splitSelectedPages
        if pagesSet.isEmpty && rotateOp == .delete { 
            // For delete, we need at least one page selected
            return 
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
                
                do {
                    let suffix = rotateOp == .rotate ? "_rotated" : "_edited"
                    let outputURL = file.url.deletingPathExtension().appendingPathExtension(suffix + ".pdf")
                     
                    if rotateOp == .rotate {
                        try await PDFCompressor.rotate(
                            input: file.url,
                            output: outputURL,
                            angle: rotationAngle,
                            pages: pagesSet.isEmpty ? nil : pagesSet,
                            password: nil
                        ) { prog in
                            Task { @MainActor in
                                selectedFiles[index].status = .compressing(prog)
                                totalProgress = prog
                            }
                        }
                    } else {
                        try await PDFCompressor.deletePages(
                            input: file.url,
                            output: outputURL,
                            pagesToDelete: pagesSet,
                            password: nil
                        ) { prog in
                             Task { @MainActor in
                                selectedFiles[index].status = .compressing(prog)
                                totalProgress = prog
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
                } catch {
                     await handleError(error)
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
        guard !selectedFiles.isEmpty else { return }
        guard !watermarkText.isEmpty else { return }
        
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
                    let outputURL = file.url.deletingPathExtension().appendingPathExtension("_watermarked.pdf")
                    
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
                            totalProgress = prog
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
                if let first = selectedFiles.first?.outputURL {
                    PDFCompressor.revealInFinder(first)
                }
            }
        }
    }
    
    private func encryptPDF() {
        guard !selectedFiles.isEmpty else { return }
        guard !encryptPassword.isEmpty && encryptPassword == encryptConfirmPassword else { return }
        
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
                    let outputURL = file.url.deletingPathExtension().appendingPathExtension("_encrypted.pdf")
                    
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
                            totalProgress = prog
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
                if let first = selectedFiles.first?.outputURL {
                    PDFCompressor.revealInFinder(first)
                }
            }
        }
    }

    private func decryptPDF() {
        guard !selectedFiles.isEmpty else { return }
        guard !decryptPassword.isEmpty else { return }
        
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
                    let outputURL = file.url.deletingPathExtension().appendingPathExtension("_decrypted.pdf")
                    
                    try await PDFCompressor.decrypt(
                        input: file.url,
                        output: outputURL,
                        password: decryptPassword
                    ) { prog in
                        Task { @MainActor in
                            selectedFiles[index].status = .compressing(prog)
                            totalProgress = prog
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
                if let first = selectedFiles.first?.outputURL {
                    PDFCompressor.revealInFinder(first)
                }
            }
        }
    }

    private func addPageNumbers() {
        guard !selectedFiles.isEmpty else { return }

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
                    let outputURL = file.url.deletingPathExtension().appendingPathExtension("_numbered.pdf")

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
                            totalProgress = prog
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
                if let first = selectedFiles.first?.outputURL {
                    PDFCompressor.revealInFinder(first)
                }
            }
        }
    }

    private func reorderPages() {
        guard selectedFiles.count == 1, let file = selectedFiles.first else { return }
        guard !reorderPageOrder.isEmpty else { return }
        
        Task {
            await MainActor.run {
                startOperation(message: "Reordering pages...")
                currentFileIndex = 0
                selectedFiles[0].status = .compressing(0)
            }
            
            do {
                let outputURL = file.url.deletingPathExtension().appendingPathExtension("_reordered.pdf")
                
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
                if let first = selectedFiles.first?.outputURL {
                    PDFCompressor.revealInFinder(first)
                }
            }
        }
    }

    private func resizeToA4() {
        guard !selectedFiles.isEmpty else { return }
        
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
                    let outputURL = file.url.deletingPathExtension().appendingPathExtension("_A4.pdf")
                    let startBytes = try FileManager.default.attributesOfItem(atPath: file.url.path)[.size] as? Int64 ?? 0
                    
                    try await PDFCompressor.resizeToA4(
                        input: file.url,
                        output: outputURL
                    ) { prog in
                        Task { @MainActor in
                            selectedFiles[index].status = .compressing(prog)
                            totalProgress = (Double(index) + prog) / Double(selectedFiles.count)
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
        if selectedFiles.isEmpty {
            DropZoneView(selectedFiles: $selectedFiles)
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
                        }
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
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                guard let data = data as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil),
                      url.pathExtension.lowercased() == "pdf" else { return }
                
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





struct FileListView: View {
    @Binding var files: [ContentView.PDFFile]
    let onDelete: (IndexSet) -> Void
    let onCompare: (ContentView.PDFFile) -> Void
    @AppStorage("isDarkMode_v2") private var isDarkMode = true
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach($files) { $file in
                    HStack {
                        FileRowView(file: $file, onCompare: onCompare)
                        
                        Spacer()
                        
                        Button(action: {
                            if let idx = files.firstIndex(where: { $0.id == file.id }) {
                                onDelete(IndexSet(integer: idx))
                            }
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
    @AppStorage("isDarkMode_v2") private var isDarkMode = true
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 48))
                .foregroundColor(isDarkMode ? Color(red: 148/255, green: 163/255, blue: 184/255) : Color(red: 100/255, green: 116/255, blue: 139/255))
            
            Text("Drop PDFs here\nor click to browse")
                .font(.system(size: 14))
                .foregroundColor(isDarkMode ? Color(red: 148/255, green: 163/255, blue: 184/255) : Color(red: 100/255, green: 116/255, blue: 139/255))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(isTargeted ? Color.blue.opacity(0.1) : (isDarkMode ? Color(red: 30/255, green: 41/255, blue: 59/255).opacity(0.6) : Color.white.opacity(0.6)))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            isTargeted ? Color.blue : (isDarkMode ? Color(red: 148/255, green: 163/255, blue: 184/255).opacity(0.4) : Color(red: 203/255, green: 213/255, blue: 225/255)),            
                            style: StrokeStyle(lineWidth: 2, dash: [8])
                        )
                )
        )
        .onTapGesture {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.pdf]
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
                          let url = URL(dataRepresentation: data, relativeTo: nil),
                          url.pathExtension.lowercased() == "pdf" else { return }
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
    @Binding var reorderPageOrderText: String
    @AppStorage("isDarkMode_v2") private var isDarkMode = true

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ToolSelectionView(selectedTool: $selectedTool)

                if selectedTool == .rasterize {
                    RasterizeSettingsView(rasterDPI: $rasterDPI)
                } else if selectedTool == .extractImages {
                    ExtractImagesSettingsView(imageFormat: $imageFormat, imageDPI: $imageDPI, extractMode: $extractMode)
                } else if selectedTool == .split {
                    SplitSettingsView(splitMode: $splitMode, splitStartPage: $splitStartPage, splitEndPage: $splitEndPage)
                } else if selectedTool == .rotateDelete {
                    RotateDeleteSettingsView(rotateOp: $rotateOp, rotationAngle: $rotationAngle, pagesToDelete: $pagesToDelete)
                } else if selectedTool == .pageNumber {
                    PageNumberSettingsView(
                        pageNumberPosition: $pageNumberPosition,
                        pageNumberFontSize: $pageNumberFontSize,
                        pageNumberStartFrom: $pageNumberStartFrom,
                        pageNumberFormat: $pageNumberFormat
                    )
                } else if selectedTool == .reorder {
                    ReorderSettingsView(pageOrderText: $reorderPageOrderText)
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
                } else {
                    Text("Extracts original images from the PDF without re-compression.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                } else {
                    Text("Select pages to delete from the thumbnail view above.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
    @Binding var pageOrderText: String
    
    var body: some View {
        GroupBox("Reorder Pages") {
            VStack(spacing: 12) {
                Text("Enter the new page order as comma-separated numbers.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                TextField("e.g., 3,1,2,4", text: $pageOrderText)
                    .textFieldStyle(.roundedBorder)
                
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
         guard !selectedFiles.isEmpty else { return }
         
         let opName = advancedMode == .repair ? "Repairing..." : "Converting to PDF/A..."
         let suffix = advancedMode == .repair ? "_repaired" : "_pdfa"
         
         startOperation(message: opName)
         
         Task {
             var results: [CompressionResult] = []
             
             for (index, file) in selectedFiles.enumerated() {
                 guard file.isChecked else { continue }
                 await MainActor.run {
                     currentFileIndex = index
                     selectedFiles[index].status = .compressing(0)
                 }
                 
                 let outputURL = file.url.deletingPathExtension().appendingPathExtension(suffix + ".pdf")
                 
                 do {
                     if advancedMode == .repair {
                         try await PDFCompressor.repairPDF(
                             input: file.url,
                             output: outputURL,
                             password: nil
                         ) { prog in
                             Task { @MainActor in
                                 selectedFiles[index].status = .compressing(prog)
                                 totalProgress = prog
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
                                 totalProgress = prog
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
             }
         }
    }
}
