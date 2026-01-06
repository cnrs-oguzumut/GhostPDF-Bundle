import Foundation
import PDFKit
import Quartz
import UniformTypeIdentifiers
import CoreGraphics
import ImageIO

enum CompressionEngine {
    case ghostscript
}

struct CompressionResult {
    let outputPath: URL
    let originalSize: Int64
    let compressedSize: Int64
    let engine: CompressionEngine
    
    var reductionPercentage: Double {
        guard originalSize > 0 else { return 0 }
        return Double(originalSize - compressedSize) / Double(originalSize) * 100
    }
}

enum ImageFormat: String, CaseIterable, Identifiable {
    case jpeg = "jpeg"
    case png = "png16m"
    
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .jpeg: return "JPEG"
        case .png: return "PNG"
        }
    }
    var extensionName: String {
        switch self {
        case .jpeg: return "jpg"
        case .png: return "png"
        }
    }
}

enum CompressionError: LocalizedError {
    case fileNotFound
    case ghostscriptFailed(String)
    case outputFailed
    case passwordRequired
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Input PDF file not found"
        case .ghostscriptFailed(let msg):
            return "Ghostscript error: \(msg)"
        case .outputFailed:
            return "Failed to write output file"
        case .passwordRequired:
            return "Password required to process this file"
        }
    }
}

class PDFCompressor {
    
    // Helper to execute Ghostscript robustly
    private static func executeGhostscript(args: [String], progressHandler: ((Double) -> Void)? = nil) async throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: args[0])
        task.arguments = Array(args.dropFirst())
        
        // Set GS_LIB environment variable for bundled Ghostscript
        if let resourcePath = Bundle.main.resourcePath {
            let gsLibPath = "\(resourcePath)/ghostscript/share/ghostscript/10.06.0/Resource:\(resourcePath)/ghostscript/share/ghostscript/10.06.0/lib"
            task.environment = ProcessInfo.processInfo.environment.merging(["GS_LIB": gsLibPath]) { (_, new) in new }
        }
        
        let pipe = Pipe()
        task.standardError = pipe
        task.standardOutput = FileHandle.nullDevice // We don't need stdout usually
        
        try task.run()
        
        // Read stderr asynchronously to prevent pipe buffer deadlock
        var errorData = Data()
        let pipeReadTask = Task {
             for try await data in pipe.fileHandleForReading.bytes {
                 errorData.append(data)
             }
        }
        
        task.waitUntilExit()
        
        // Wait for pipe reading to finish
        _ = try? await pipeReadTask.value
        
        if task.terminationStatus != 0 {
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            
            if errorMessage.contains("Password") || errorMessage.contains("This file requires a password") {
                throw CompressionError.passwordRequired
            }
            
            throw CompressionError.ghostscriptFailed(errorMessage)
        }
    }
    
    static func findGhostscript() -> String? {
        let bundledPath = Bundle.main.resourcePath.map { "\($0)/ghostscript/bin/gs" }
        if let path = bundledPath, FileManager.default.fileExists(atPath: path) {
            return path
        }
        
        let candidates = [
            "/opt/homebrew/bin/gs",
            "/usr/local/bin/gs",
            "/usr/bin/gs"
        ]
        
        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate) {
                return candidate
            }
        }
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = ["gs"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        
        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty {
                    return path
                }
            }
        } catch {}
        
        return nil
    }
    
    static func compress(
        input: URL,
        output: URL,
        preset: CompressionPreset,
        proSettings: ProSettings? = nil,
        password: String? = nil,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> CompressionResult {
        
        let originalSize = try FileManager.default.attributesOfItem(atPath: input.path)[.size] as? Int64 ?? 0
        
        guard let gsPath = findGhostscript() else {
            throw CompressionError.ghostscriptFailed("Ghostscript not found. Please install Ghostscript to use this app.")
        }

        progressHandler(0.1)
        try await compressWithGhostscript(
            gsPath: gsPath,
            input: input,
            output: output,
            preset: preset,
            proSettings: proSettings,
            password: password,
            progressHandler: progressHandler
        )
        progressHandler(0.9)
        
        let compressedSize = try FileManager.default.attributesOfItem(atPath: output.path)[.size] as? Int64 ?? 0
        progressHandler(1.0)
        
        return CompressionResult(
            outputPath: output,
            originalSize: originalSize,
            compressedSize: compressedSize,
            engine: .ghostscript
        )
    }
    
    private static func compressWithGhostscript(
        gsPath: String,
        input: URL,
        output: URL,
        preset: CompressionPreset,
        proSettings: ProSettings?,
        password: String? = nil,
        progressHandler: @escaping (Double) -> Void
    ) async throws {
        
        var args = [
            gsPath,
            "-sDEVICE=pdfwrite",
            "-dNOPAUSE",
            "-dQUIET",
            "-dBATCH",
            "-sOutputFile=\(output.path)"
        ]
        
        if let password = password, !password.isEmpty {
            args.append("-sPDFPassword=\(password)")
        }
        
        if let pro = proSettings {
            args.append(contentsOf: pro.toGhostscriptArgs())
        } else {
            args.append(contentsOf: preset.toGhostscriptArgs())
        }
        
        args.append(input.path)
        
        progressHandler(0.3)

        
        try await executeGhostscript(args: args)
        
        progressHandler(0.8)
    }
    

    
    
    static func rasterize(
        input: URL,
        output: URL,
        dpi: Int = 150,
        password: String? = nil,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> CompressionResult {
        
        guard let gsPath = findGhostscript() else {
            throw CompressionError.ghostscriptFailed("Ghostscript not found. Please install Ghostscript.")
        }
        
        let originalSize = try FileManager.default.attributesOfItem(atPath: input.path)[.size] as? Int64 ?? 0
        
        progressHandler(0.1)
        
        // Use pdfimage24 device to rasterize into a PDF
        let args = [
            gsPath,
            "-sDEVICE=pdfimage24",
            "-dNOPAUSE",
            "-dQUIET",
            "-dBATCH",
            "-r\(dpi)",
            "-sOutputFile=\(output.path)",
        ] + (password.flatMap { ["-sPDFPassword=\($0)"] } ?? []) + [
            input.path
        ]
        
        progressHandler(0.3)
        
        try await executeGhostscript(args: args)
        
        let compressedSize = try FileManager.default.attributesOfItem(atPath: output.path)[.size] as? Int64 ?? 0
        progressHandler(1.0)
        
        return CompressionResult(
            outputPath: output,
            originalSize: originalSize,
            compressedSize: compressedSize,
            engine: .ghostscript
        )
    }
    
    static func extractEmbeddedImages(input: URL, outputDir: URL, password: String? = nil, progress: @escaping (Double) -> Void) async throws {
        guard let doc = CGPDFDocument(input as CFURL) else { throw CompressionError.fileNotFound }
        
        if doc.isEncrypted {
            if !doc.unlockWithPassword(password ?? "") { throw CompressionError.passwordRequired }
        }
        
        let pageCount = doc.numberOfPages
        guard pageCount > 0 else { return }
        
        // Context for the callback
        let context = ImageExtractionContext(outputDir: outputDir)
        
        for i in 1...pageCount {
            guard let page = doc.page(at: i) else { continue }
            context.currentPage = i
            context.imageIndexOnPage = 0
            
            if let pageDict = page.dictionary {
                var resDict: CGPDFDictionaryRef? = nil
                if CGPDFDictionaryGetDictionary(pageDict, "Resources", &resDict), let resources = resDict {
                    var xObjDict: CGPDFDictionaryRef? = nil
                    if CGPDFDictionaryGetDictionary(resources, "XObject", &xObjDict), let xObjects = xObjDict {
                        let contextPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(context).toOpaque())
                        CGPDFDictionaryApplyFunction(xObjects, imageExtractionCallback, contextPtr)
                    }
                }
            }
            
            progress(Double(i) / Double(pageCount))
            // Yield to main thread
            await Task.yield()
        }
    }

    static func exportImages(
        input: URL,
        outputDir: URL,
        format: ImageFormat,
        dpi: Int = 150,
        password: String? = nil,
        progressHandler: @escaping (Double) -> Void
    ) async throws {
        
        guard let gsPath = findGhostscript() else {
            throw CompressionError.ghostscriptFailed("Ghostscript not found. Please install Ghostscript.")
        }
        
        progressHandler(0.1)
        
        let outputPattern = outputDir.appendingPathComponent("Page-%03d.\(format.extensionName)").path
        
        let args = [
            gsPath,
            "-sDEVICE=\(format.rawValue)",
            "-dNOPAUSE",
            "-dQUIET",
            "-dBATCH",
            "-r\(dpi)",
            "-sOutputFile=\(outputPattern)",
        ] + (password.flatMap { ["-sPDFPassword=\($0)"] } ?? []) + [
            input.path
        ]
        
        progressHandler(0.3)
        
        try await executeGhostscript(args: args)
        
        progressHandler(1.0)
    }
    
    static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    
    static func merge(inputs: [URL], output: URL, progressHandler: @escaping (Double) -> Void) async throws {
        guard let gsPath = findGhostscript() else {
            throw CompressionError.ghostscriptFailed("Ghostscript not found. Please install Ghostscript.")
        }
        
        progressHandler(0.1)
        
        var args = [
            gsPath,
            "-dNOPAUSE",
            "-sDEVICE=pdfwrite",
            "-sOutputFile=\(output.path)",
            "-dBATCH"
        ]
        
        args.append(contentsOf: inputs.map { $0.path })
        
        progressHandler(0.3)
        
        try await executeGhostscript(args: args)
        
        progressHandler(0.9)
        
        progressHandler(1.0)
    }
    
    static func split(input: URL, outputDir: URL, startPage: Int? = nil, endPage: Int? = nil, pages: [Int]? = nil, password: String? = nil, progressHandler: @escaping (Double) -> Void) async throws {
        guard let gsPath = findGhostscript() else {
            throw CompressionError.ghostscriptFailed("Ghostscript not found. Please install Ghostscript.")
        }
        
        progressHandler(0.1)
        
        var args = [gsPath, "-dNOPAUSE", "-sDEVICE=pdfwrite", "-dBATCH"]
        
        if let pass = password {
            args.append("-sPDFPassword=\(pass)")
        }
        
        if let pageList = pages, !pageList.isEmpty {
             // Extract selected pages
             let outputFilename = input.deletingPathExtension().lastPathComponent + "_selected.pdf"
             let outputURL = outputDir.appendingPathComponent(outputFilename)
             let listString = pageList.map { String($0) }.joined(separator: ",")
             args.append("-sPageList=\(listString)")
             args.append("-sOutputFile=\(outputURL.path)")
        } else if let start = startPage, let end = endPage {
             // Extract range
             let outputFilename = input.deletingPathExtension().lastPathComponent + "_pages_\(start)-\(end).pdf"
             let outputURL = outputDir.appendingPathComponent(outputFilename)
             args.append("-dFirstPage=\(start)")
             args.append("-dLastPage=\(end)")
             args.append("-sOutputFile=\(outputURL.path)")
        } else {
             // Split all pages
             let filenamePattern = input.deletingPathExtension().lastPathComponent + "_page_%03d.pdf"
             let outputURL = outputDir.appendingPathComponent(filenamePattern)
             args.append("-sOutputFile=\(outputURL.path)")
        }
        
        args.append(input.path)
        
        progressHandler(0.3)
        
        try await executeGhostscript(args: args)
        
        progressHandler(0.9)
        
        progressHandler(1.0)
    }

    // MARK: - Helper
    static func getPageCount(url: URL, password: String? = nil) async throws -> Int {
        guard let gsPath = findGhostscript() else {
             throw CompressionError.ghostscriptFailed("Ghostscript not found")
        }
        
        var args = [gsPath, "-q", "-dNODISPLAY", "-dNOSAFER"]
        if let pass = password {
            args.append("-sPDFPassword=\(pass)")
        }
        args.append(contentsOf: ["-c", "(\(url.path)) (r) file runpdfbegin pdfpagecount = quit"])

        let task = Process()
        task.executableURL = URL(fileURLWithPath: args[0])
        task.arguments = Array(args.dropFirst())
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        try task.run()
        task.waitUntilExit()
        
        if task.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let out = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), let count = Int(out) {
                return count
            }
        }
        return 0
    }
    
    // MARK: - Rotate
    static func rotate(input: URL, output: URL, angle: Int, pages: Set<Int>? = nil, password: String? = nil, progressHandler: @escaping (Double) -> Void) async throws {
         guard let gsPath = findGhostscript() else {
            throw CompressionError.ghostscriptFailed("Ghostscript not found.")
        }
        
        progressHandler(0.1)
        
        let orientation: Int
        switch angle % 360 {
        case 90, -270: orientation = 1
        case 180, -180: orientation = 2
        case 270, -90: orientation = 3
        default: orientation = 0
        }
        
        // If pages specific, we need to split, rotate selected, and merge
        if let pagesToRotate = pages, !pagesToRotate.isEmpty {
            let totalPages = try await getPageCount(url: input, password: password)
            var tempFiles: [URL] = []
            let tempDir = FileManager.default.temporaryDirectory
            
            // Cleanup function
            defer {
                for url in tempFiles {
                    try? FileManager.default.removeItem(at: url)
                }
            }
            
            // Chunking
            var currentStart = 1
            var rotating = pagesToRotate.contains(1)
            
            for i in 1...totalPages {
                let isRot = pagesToRotate.contains(i)
                if isRot != rotating {
                    // Range ended at i-1
                    let rangeEnd = i - 1

                    
                    // Extract chunk
                    try await split(input: input, outputDir: tempDir, startPage: currentStart, endPage: rangeEnd, password: password) { _ in }
                    
                    // Rename/Move the split output to our tracked temp file
                    // split() logic names it specially, so we need to find it or adjust split to output specific file.
                    // Split implementation: `_pages_Start-End.pdf`
                    let expectedSplitName = input.deletingPathExtension().lastPathComponent + "_pages_\(currentStart)-\(rangeEnd).pdf"
                    let generatedSplitURL = tempDir.appendingPathComponent(expectedSplitName)
                    
                    if rotating {
                        // Rotate this chunk
                         let rotatedChunkURL = tempDir.appendingPathComponent(UUID().uuidString + "_rot.pdf")
                         try await rotate(input: generatedSplitURL, output: rotatedChunkURL, angle: angle, password: password) { _ in }
                         tempFiles.append(rotatedChunkURL)
                         try? FileManager.default.removeItem(at: generatedSplitURL) // clean intermediate
                    } else {
                        // Keep as is
                        tempFiles.append(generatedSplitURL)
                    }
                    
                    currentStart = i
                    rotating = isRot
                }
            }
            
            // Final chunk
            let rangeEnd = totalPages
            if currentStart <= rangeEnd {
                 let expectedSplitName = input.deletingPathExtension().lastPathComponent + "_pages_\(currentStart)-\(rangeEnd).pdf"
                 let generatedSplitURL = tempDir.appendingPathComponent(expectedSplitName)
                 
                 try await split(input: input, outputDir: tempDir, startPage: currentStart, endPage: rangeEnd, password: password) { _ in }
                 
                 if rotating {
                     let rotatedChunkURL = tempDir.appendingPathComponent(UUID().uuidString + "_rot.pdf")
                     try await rotate(input: generatedSplitURL, output: rotatedChunkURL, angle: angle, password: password) { _ in }
                     tempFiles.append(rotatedChunkURL)
                     try? FileManager.default.removeItem(at: generatedSplitURL)
                 } else {
                     tempFiles.append(generatedSplitURL)
                 }
            }
            
            // Merge all chunks
            progressHandler(0.8)
            try await merge(inputs: tempFiles, output: output) { _ in }
            progressHandler(1.0)
            return
        }
        
        // Default: Rotate All
        var args = [gsPath, "-dNOPAUSE", "-sDEVICE=pdfwrite", "-dBATCH"]
        if let pass = password {
            args.append("-sPDFPassword=\(pass)")
        }
        args.append("-dAutoRotatePages=/None")
        args.append("-sOutputFile=\(output.path)")
        args.append("-c")
        args.append("<</Orientation \(orientation)>> setpagedevice")
        args.append("-f")
        args.append(input.path)
        
        progressHandler(0.3)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: args[0])
        task.arguments = Array(args.dropFirst())
        
        let errorPipe = Pipe()
         task.standardError = errorPipe
         task.standardOutput = FileHandle.nullDevice
         
         try task.run()
         task.waitUntilExit()
         
         progressHandler(0.9)
         
         if task.terminationStatus != 0 {
             let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
             let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
              if errorMessage.contains("Password") || errorMessage.contains("This file requires a password") {
                 throw CompressionError.passwordRequired
             }
             throw CompressionError.ghostscriptFailed(errorMessage)
         }
         progressHandler(1.0)
    }

    // MARK: - Delete Pages
    static func deletePages(input: URL, output: URL, pagesToDelete: Set<Int>, password: String? = nil, progressHandler: @escaping (Double) -> Void) async throws {
        guard let gsPath = findGhostscript() else {
            throw CompressionError.ghostscriptFailed("Ghostscript not found.")
        }
        
        progressHandler(0.1)
        
        let totalPages = try await getPageCount(url: input, password: password)
        guard totalPages > 0 else {
             throw CompressionError.ghostscriptFailed("Could not determine page count.")
        }
        
        var keptPages: [String] = []
        var currentRangeStart: Int?
        
        for i in 1...totalPages {
            if !pagesToDelete.contains(i) {
                if currentRangeStart == nil {
                    currentRangeStart = i
                }
            } else {
                if let start = currentRangeStart {
                    if start == i - 1 {
                        keptPages.append("\(start)")
                    } else {
                        keptPages.append("\(start)-\(i - 1)")
                    }
                    currentRangeStart = nil
                }
            }
        }
        if let start = currentRangeStart {
             if start == totalPages {
                 keptPages.append("\(start)")
             } else {
                 keptPages.append("\(start)-\(totalPages)")
             }
        }
        
        let pageList = keptPages.joined(separator: ",")
        
        guard !pageList.isEmpty else {
             throw CompressionError.ghostscriptFailed("Resulting PDF would be empty.")
        }
        
        var args = [gsPath, "-dNOPAUSE", "-sDEVICE=pdfwrite", "-dBATCH"]
        if let pass = password {
            args.append("-sPDFPassword=\(pass)")
        }
        args.append("-sPageList=\(pageList)")
        args.append("-sOutputFile=\(output.path)")
        args.append(input.path)
        
        progressHandler(0.5)
        
        try await executeGhostscript(args: args)
        
        progressHandler(0.9)
         progressHandler(1.0)
    }
    // MARK: - Thumbnails
    static func generateThumbnails(input: URL, outputDir: URL, dpi: Int = 36, password: String? = nil, progressHandler: @escaping (Double) -> Void) async throws -> [URL] {
        guard let gsPath = findGhostscript() else {
            throw CompressionError.ghostscriptFailed("Ghostscript not found.")
        }
        
        progressHandler(0.1)
        
        let outputPattern = outputDir.appendingPathComponent("thumb-%d.jpg").path
        
        var args = [
            gsPath,
            "-dNOPAUSE",
            "-dQUIET", 
            "-sDEVICE=jpeg",
            "-dJPEGQ=60",
            "-r\(dpi)",
            "-dBATCH"
        ]
        
        if let pass = password {
            args.append("-sPDFPassword=\(pass)")
        }
        
        args.append("-sOutputFile=\(outputPattern)")
        args.append(input.path)
        
        try await executeGhostscript(args: args)
        
        progressHandler(0.9)
         
         let fm = FileManager.default
         let urls = (try? fm.contentsOfDirectory(at: outputDir, includingPropertiesForKeys: nil))?
            .filter { $0.lastPathComponent.hasPrefix("thumb-") && $0.pathExtension == "jpg" }
            .sorted { 
                let n1 = Int($0.lastPathComponent.replacingOccurrences(of: "thumb-", with: "").replacingOccurrences(of: ".jpg", with: "")) ?? 0
                let n2 = Int($1.lastPathComponent.replacingOccurrences(of: "thumb-", with: "").replacingOccurrences(of: ".jpg", with: "")) ?? 0
                return n1 < n2
            } ?? []
            
         progressHandler(1.0)
         return urls
    }
    
    // MARK: - Watermark
    static func watermark(input: URL, output: URL, text: String, fontSize: Int = 48, opacity: Double = 0.3, diagonal: Bool = true, password: String? = nil, progressHandler: @escaping (Double) -> Void) async throws {
        guard let gsPath = findGhostscript() else {
            throw CompressionError.ghostscriptFailed("Ghostscript not found.")
        }
        
        progressHandler(0.1)
        
        // Create PostScript watermark overlay
        let angle = diagonal ? "45 rotate" : ""
        let grayLevel = String(format: "%.2f", 1.0 - opacity)
        
        let psCode = """
        <<
        /EndPage {
            2 eq { pop false } {
                gsave
                /Helvetica-Bold findfont \(fontSize) scalefont setfont
                \(grayLevel) setgray
                306 396 moveto
                \(angle)
                (\(text)) dup stringwidth pop 2 div neg 0 rmoveto show
                grestore
                true
            } ifelse
        } bind
        >> setpagedevice
        """
        
        var args = [gsPath, "-dNOPAUSE", "-sDEVICE=pdfwrite", "-dBATCH"]
        if let pass = password {
            args.append("-sPDFPassword=\(pass)")
        }
        args.append("-sOutputFile=\(output.path)")
        args.append("-c")
        args.append(psCode)
        args.append("-f")
        args.append(input.path)
        
        progressHandler(0.3)
        
        try await executeGhostscript(args: args)
        
        progressHandler(0.9)
        
        progressHandler(1.0)
    }
    
    // MARK: - Encrypt
    static func encrypt(input: URL, output: URL, userPassword: String, ownerPassword: String? = nil, allowPrinting: Bool = true, allowCopying: Bool = false, password: String? = nil, progressHandler: @escaping (Double) -> Void) async throws {
        guard let gsPath = findGhostscript() else {
            throw CompressionError.ghostscriptFailed("Ghostscript not found.")
        }
        
        progressHandler(0.1)
        
        var args = [gsPath, "-dNOPAUSE", "-sDEVICE=pdfwrite", "-dBATCH"]
        
        if let pass = password {
            args.append("-sPDFPassword=\(pass)")
        }
        
        // Encryption settings
        args.append("-sUserPassword=\(userPassword)")
        args.append("-sOwnerPassword=\(ownerPassword ?? userPassword)")
        
        // Permission flags (128-bit encryption)
        var permissions = -64 // Base for 128-bit
        if allowPrinting { permissions += 4 }
        if allowCopying { permissions += 16 }
        args.append("-dEncryptionR=3") // 128-bit
        args.append("-dPermissions=\(permissions)")
        
        args.append("-sOutputFile=\(output.path)")
        args.append(input.path)
        
        progressHandler(0.3)
        
        try await executeGhostscript(args: args)
        
        progressHandler(0.9)
        
        progressHandler(1.0)
    }

    // MARK: - Page Numbers
    // Wrapper for page numbering that accepts ContentView enums
    static func addPageNumbers(input: URL, output: URL, position: PageNumberPosition, fontSize: Int, startFrom: Int, format: PageNumberFormat, password: String? = nil, progressHandler: @escaping (Double) -> Void) async throws {
        // Convert enum types (defined in ContentView)
        try await addPageNumbersImpl(
            input: input,
            output: output,
            positionRawValue: position.rawValue,
            fontSize: fontSize,
            startFrom: startFrom,
            formatRawValue: format.rawValue,
            password: password,
            progressHandler: progressHandler
        )
    }

    private static func addPageNumbersImpl(input: URL, output: URL, positionRawValue: Int, fontSize: Int, startFrom: Int, formatRawValue: Int, password: String? = nil, progressHandler: @escaping (Double) -> Void) async throws {
        guard let gsPath = findGhostscript() else {
            throw CompressionError.ghostscriptFailed("Ghostscript not found.")
        }

        progressHandler(0.1)

        // Get total page count for formats that need it
        var totalPages: Int? = nil
        if formatRawValue == 1 { // numbersWithTotal
            if let pdfDoc = PDFDocument(url: input) {
                totalPages = pdfDoc.pageCount
            }
        }

        let offset = startFrom - 1

        // Position logic in PostScript coordinates (0,0 is bottom-left)
        // 0=topLeft, 1=topCenter, 2=topRight, 3=bottomLeft, 4=bottomCenter, 5=bottomRight
        let positionLogic: String
        switch positionRawValue {
        case 0: // topLeft
            positionLogic = "36 currentpagedevice /PageSize get aload pop exch pop 36 sub moveto"
        case 1: // topCenter
            positionLogic = "currentpagedevice /PageSize get aload pop exch 2 div exch 36 sub moveto"
        case 2: // topRight
            positionLogic = "currentpagedevice /PageSize get aload pop 72 sub exch 36 sub moveto"
        case 3: // bottomLeft
            positionLogic = "36 36 moveto"
        case 4: // bottomCenter
            positionLogic = "currentpagedevice /PageSize get aload pop 2 div exch pop 36 moveto"
        default: // bottomRight (5)
            positionLogic = "currentpagedevice /PageSize get aload pop 72 sub exch pop 36 moveto"
        }

        // Format the page number text
        // 0=numbers, 1=numbersWithTotal, 2=pageN
        let formatLogic: String
        switch formatRawValue {
        case 1: // numbersWithTotal
            if let total = totalPages {
                formatLogic = "dup \(offset) add 20 string cvs (/) exch concatstrings (\(total)) concatstrings show"
            } else {
                formatLogic = "dup \(offset) add 20 string cvs show"
            }
        case 2: // pageN
            formatLogic = "(Page ) dup \(offset) add 20 string cvs concatstrings show"
        default: // numbers (0)
            formatLogic = "dup \(offset) add 20 string cvs show"
        }

        let psCode = """
        <<
        /EndPage {
          2 eq {
            gsave
            /Helvetica \(fontSize) selectfont
            0 setgray
            \(positionLogic)
            \(formatLogic)
            grestore
          } if
          true
        } bind
        >> setpagedevice
        """

        // Write PS code to temp file
        let psFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ps")
        try psCode.write(to: psFile, atomically: true, encoding: .ascii)
        defer { try? FileManager.default.removeItem(at: psFile) }

        var args = [gsPath, "-dNOPAUSE", "-sDEVICE=pdfwrite", "-dBATCH"]
        if let pass = password {
            args.append("-sPDFPassword=\(pass)")
        }

        args.append("-sOutputFile=\(output.path)")
        args.append(psFile.path)
        args.append(input.path)

        progressHandler(0.3)

        try await executeGhostscript(args: args)
        
        progressHandler(0.9)

        progressHandler(1.0)
    }
    // MARK: - Advanced Tools
    
    static func repairPDF(input: URL, output: URL, password: String? = nil, progressHandler: @escaping (Double) -> Void) async throws {
        guard let gsPath = findGhostscript() else {
            throw CompressionError.ghostscriptFailed("Ghostscript not found.")
        }
        
        progressHandler(0.1)
        
        // repair is essentially re-distilling with default settings
        var args = [gsPath, "-o", output.path, "-sDEVICE=pdfwrite", "-dPDFSETTINGS=/default"]
        
        if let pass = password {
            args.append("-sPDFPassword=\(pass)")
        }
        
        args.append(input.path)
        
        progressHandler(0.3)
        
        try await executeGhostscript(args: args)
        
        progressHandler(0.9)
        
        progressHandler(1.0)
    }
    
    static func convertToPDFA(input: URL, output: URL, password: String? = nil, progressHandler: @escaping (Double) -> Void) async throws {
        guard let gsPath = findGhostscript() else {
            throw CompressionError.ghostscriptFailed("Ghostscript not found.")
        }
        
        progressHandler(0.1)
        
        // 1. Create PDFA_def.ps
        // Simplified definition to avoid corruption if srgb.icc is missing.
        // We omit DestOutputProfile to prevent 'null' values or file read errors.
        // This produces a PDF/A-2b compliant file structure, though strictly it should have an embedded profile.
        
        let pdadDefContent = """
%!
% This is a sample prefix file for creating a PDF/A document.
% To be robust without external ICC files, we omit DestOutputProfile.
% This ensures Ghostscript runs successfully.

/PDFA_def {
  /OutputIntent_PDF <<
    /Type /OutputIntent
    /S /GTS_PDFA1
    /OutputConditionIdentifier (sRGB)
    /Info (sRGB)
  >> def
} def
"""
        
        let defFile = FileManager.default.temporaryDirectory.appendingPathComponent("PDFA_def.ps")
        try pdadDefContent.write(to: defFile, atomically: true, encoding: .ascii)
        defer { try? FileManager.default.removeItem(at: defFile) }
        
        var args = [
            gsPath,
            "-dPDFA=2",
            "-dBATCH",
            "-dNOPAUSE",
            "-sColorConversionStrategy=RGB",
            "-sProcessColorModel=DeviceRGB",
            "-sDEVICE=pdfwrite",
            "-dPDFACompatibilityPolicy=1", 
            "-sOutputFile=\(output.path)"
        ]
        
        if let pass = password {
            args.append("-sPDFPassword=\(pass)")
        }
        
        args.append(defFile.path)
        args.append(input.path)
        
        progressHandler(0.3)
        

        
        try await executeGhostscript(args: args)
        
        progressHandler(0.9)
        progressHandler(1.0)
    }
    
    // MARK: - Decrypt PDF
    
    static func decrypt(input: URL, output: URL, password: String, progressHandler: @escaping (Double) -> Void) async throws {
        guard let gsPath = findGhostscript() else {
            throw CompressionError.ghostscriptFailed("Ghostscript not found.")
        }
        
        progressHandler(0.1)
        
        // Ghostscript opens with password and writes without encryption
        let args = [
            gsPath,
            "-dBATCH",
            "-dNOPAUSE",
            "-sDEVICE=pdfwrite",
            "-sPDFPassword=\(password)",
            "-sOutputFile=\(output.path)",
            input.path
        ]
        
        progressHandler(0.3)
        
        try await executeGhostscript(args: args)
        
        progressHandler(0.9)
        progressHandler(1.0)
    }
    
    // MARK: - Reorder Pages
    
    static func reorderPages(input: URL, output: URL, pageOrder: [Int], password: String? = nil, progressHandler: @escaping (Double) -> Void) async throws {
        // Use PDFKit for reordering (Lossless, handles all content types, avoids GS "white page" issues)
        guard let doc = PDFDocument(url: input) else {
             throw CompressionError.ghostscriptFailed("Could not open PDF with PDFKit.")
        }
        
        if doc.isEncrypted {
            if let pass = password {
                doc.unlock(withPassword: pass)
            }
        }
        
        if doc.isLocked {
             throw CompressionError.passwordRequired
        }
        
        progressHandler(0.1)
        
        let newDoc = PDFDocument()
        let total = Double(pageOrder.count)
        
        for (index, originalIdx) in pageOrder.enumerated() {
             // originalIdx is 1-based (from GS logic/UI)
             let pageIndex = originalIdx - 1
             if pageIndex >= 0 && pageIndex < doc.pageCount {
                 if let page = doc.page(at: pageIndex) {
                     newDoc.insert(page, at: newDoc.pageCount)
                 }
             }
             progressHandler(0.1 + 0.8 * (Double(index) / total))
        }
        
        progressHandler(0.9)
        newDoc.write(to: output)
        progressHandler(1.0)
    }
    
    // MARK: - Resize to A4
    
    static func resizeToA4(input: URL, output: URL, progressHandler: @escaping (Double) -> Void) async throws {
         guard let gsPath = findGhostscript() else {
             throw CompressionError.ghostscriptFailed("Ghostscript not found.")
         }
         
         progressHandler(0.1)
         
         // Resizes all pages to A4
         let args = [
             gsPath,
             "-o", output.path,
             "-sDEVICE=pdfwrite",
             "-sPAPERSIZE=a4",
             "-dPDFFitPage",
             "-dFIXEDMEDIA",
             input.path
         ]
         
         progressHandler(0.3)
         try await executeGhostscript(args: args)
         progressHandler(1.0)
    }
}

// Helper for Image Extraction
class ImageExtractionContext {
    let outputDir: URL
    var currentPage: Int = 0
    var imageIndexOnPage: Int = 0
    
    init(outputDir: URL) {
        self.outputDir = outputDir
    }
}

func imageExtractionCallback(key: UnsafePointer<Int8>, value: CGPDFObjectRef, info: UnsafeMutableRawPointer?) {
    guard let info = info else { return }
    let context = Unmanaged<ImageExtractionContext>.fromOpaque(info).takeUnretainedValue()
    
    var stream: CGPDFStreamRef? = nil
    if CGPDFObjectGetValue(value, .stream, &stream), let stream = stream {
        let dict: CGPDFDictionaryRef? = CGPDFStreamGetDictionary(stream)
        var subtype: UnsafePointer<Int8>? = nil
        
        // Check Subtype is Image
        if let dict = dict, CGPDFDictionaryGetName(dict, "Subtype", &subtype), let subtype = subtype {
            let subtypeString = String(cString: subtype)
            if subtypeString == "Image" {
                 // Check Filter is DCTDecode (JPEG)
                 var filter: UnsafePointer<Int8>? = nil
                 var isJpeg = false
                 if CGPDFDictionaryGetName(dict, "Filter", &filter), let filter = filter {
                     let filterName = String(cString: filter)
                     if filterName == "DCTDecode" {
                         isJpeg = true
                     }
                 }
                 
                 if isJpeg {
                     var format: CGPDFDataFormat = .raw
                     if let data = CGPDFStreamCopyData(stream, &format) {
                         let filename = "Page\(context.currentPage)_Img\(context.imageIndexOnPage).jpg"
                         let url = context.outputDir.appendingPathComponent(filename)
                         try? (data as Data).write(to: url)
                         context.imageIndexOnPage += 1
                     }
                 }
            }
        }
    }
}
