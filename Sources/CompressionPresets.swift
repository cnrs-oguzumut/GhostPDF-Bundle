import Foundation

enum CompressionPreset: String, CaseIterable, Identifiable {
    case light = "light"
    case medium = "medium"
    case heavy = "heavy"
    
    var id: String { rawValue }
    
    var name: String {
        switch self {
        case .light: return "Light"
        case .medium: return "Medium"
        case .heavy: return "Heavy"
        }
    }
    
    var description: String {
        switch self {
        case .light: return "Minimal compression, preserves quality (300 DPI)"
        case .medium: return "Balanced compression for sharing (150 DPI)"
        case .heavy: return "Maximum compression, smaller files (72 DPI)"
        }
    }
    
    var pdfSettings: String {
        switch self {
        case .light: return "/printer"
        case .medium: return "/ebook"
        case .heavy: return "/screen"
        }
    }
    
    var dpi: Int {
        switch self {
        case .light: return 300
        case .medium: return 150
        case .heavy: return 72
        }
    }
    
    func toGhostscriptArgs() -> [String] {
        return [
            "-dPDFSETTINGS=\(pdfSettings)",
            "-dDownsampleColorImages=true",
            "-dColorImageResolution=\(dpi)",
            "-dDownsampleGrayImages=true",
            "-dGrayImageResolution=\(dpi)",
            "-dDownsampleMonoImages=true",
            "-dMonoImageResolution=\(dpi)"
        ]
    }
}

enum ProPreset: String, CaseIterable, Identifiable {
    case web = "web"
    case email = "email"
    case print = "print"
    case archive = "archive"
    case grayscale = "grayscale"
    
    var id: String { rawValue }
    
    var name: String {
        switch self {
        case .web: return "Web"
        case .email: return "Email"
        case .print: return "Print"
        case .archive: return "Archive"
        case .grayscale: return "Grayscale"
        }
    }
    
    var icon: String {
        switch self {
        case .web: return "globe"
        case .email: return "envelope"
        case .print: return "printer"
        case .archive: return "archivebox"
        case .grayscale: return "square.fill"
        }
    }
    
    var description: String {
        switch self {
        case .web: return "Optimized for web viewing"
        case .email: return "Small files for email"
        case .print: return "High quality for printing"
        case .archive: return "PDF/A compatible archival"
        case .grayscale: return "Convert to grayscale"
        }
    }
    
    func toSettings() -> ProSettings {
        switch self {
        case .web:
            var s = ProSettings()
            s.colorDPI = 96; s.grayDPI = 96; s.monoDPI = 150
            s.jpegQuality = 75; s.colorStrategy = .rgb
            s.subsetFonts = true; s.compressFonts = true
            s.compatLevel = .v1_5; s.fastWebView = true
            return s
        case .email:
            var s = ProSettings()
            s.colorDPI = 120; s.grayDPI = 120; s.monoDPI = 200
            s.jpegQuality = 70; s.colorStrategy = .rgb
            s.subsetFonts = true; s.compressFonts = true
            s.compatLevel = .v1_4; s.fastWebView = false
            return s
        case .print:
            var s = ProSettings()
            s.colorDPI = 300; s.grayDPI = 300; s.monoDPI = 600
            s.jpegQuality = 95; s.colorStrategy = .unchanged
            s.subsetFonts = false; s.compressFonts = true
            s.compatLevel = .v1_4; s.fastWebView = false
            return s
        case .archive:
            var s = ProSettings()
            s.colorDPI = 300; s.grayDPI = 300; s.monoDPI = 600
            s.jpegQuality = 90; s.colorStrategy = .unchanged
            s.subsetFonts = false; s.compressFonts = false
            s.compatLevel = .v1_4; s.fastWebView = false
            return s
        case .grayscale:
            var s = ProSettings()
            s.colorDPI = 150; s.grayDPI = 150; s.monoDPI = 300
            s.jpegQuality = 80; s.colorStrategy = .gray
            s.subsetFonts = true; s.compressFonts = true
            s.compatLevel = .v1_4; s.fastWebView = false
            return s
        }
    }
}

enum ColorStrategy: String, CaseIterable, Identifiable {
    case unchanged = "LeaveColorUnchanged"
    case rgb = "RGB"
    case cmyk = "CMYK"
    case gray = "Gray"
    case deviceIndependent = "UseDeviceIndependentColor"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .unchanged: return "Leave Unchanged"
        case .rgb: return "RGB"
        case .cmyk: return "CMYK"
        case .gray: return "Grayscale"
        case .deviceIndependent: return "Device Independent"
        }
    }
}

enum ImageFilter: String, CaseIterable, Identifiable {
    case auto = "auto"
    case dct = "dct"
    case flate = "flate"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .auto: return "Auto (Recommended)"
        case .dct: return "DCTEncode (JPEG)"
        case .flate: return "FlateEncode (Lossless)"
        }
    }
}

enum CompatLevel: String, CaseIterable, Identifiable {
    case v1_4 = "1.4"
    case v1_5 = "1.5"
    case v1_6 = "1.6"
    case v1_7 = "1.7"
    case v2_0 = "2.0"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .v1_4: return "1.4 (Acrobat 5)"
        case .v1_5: return "1.5 (Acrobat 6)"
        case .v1_6: return "1.6 (Acrobat 7)"
        case .v1_7: return "1.7 (Acrobat 8+)"
        case .v2_0: return "2.0 (PDF 2.0)"
        }
    }
}

struct ProSettings {
    var colorDPI: Int = 120
    var grayDPI: Int = 120
    var monoDPI: Int = 200
    var jpegQuality: Int = 70
    var imageFilter: ImageFilter = .auto
    var colorStrategy: ColorStrategy = .rgb
    var preserveOverprint: Bool = true
    var embedFonts: Bool = true
    var subsetFonts: Bool = true
    var compressFonts: Bool = true
    var compatLevel: CompatLevel = .v1_4
    var fastWebView: Bool = false
    var detectDuplicates: Bool = true
    var removeMetadata: Bool = false
    var ascii85: Bool = false
    var customArgs: String = ""
    
    func toGhostscriptArgs() -> [String] {
        var args: [String] = []
        
        args.append("-dCompatibilityLevel=\(compatLevel.rawValue)")
        
        args.append("-dDownsampleColorImages=true")
        args.append("-dColorImageResolution=\(colorDPI)")
        args.append("-dDownsampleGrayImages=true")
        args.append("-dGrayImageResolution=\(grayDPI)")
        args.append("-dDownsampleMonoImages=true")
        args.append("-dMonoImageResolution=\(monoDPI)")
        
        args.append("-dJPEGQ=\(jpegQuality)")
        
        switch imageFilter {
        case .auto:
            args.append("-dAutoFilterColorImages=true")
            args.append("-dAutoFilterGrayImages=true")
        case .dct:
            args.append("-dAutoFilterColorImages=false")
            args.append("-dAutoFilterGrayImages=false")
            args.append("-dColorImageFilter=/DCTEncode")
            args.append("-dGrayImageFilter=/DCTEncode")
        case .flate:
            args.append("-dAutoFilterColorImages=false")
            args.append("-dAutoFilterGrayImages=false")
            args.append("-dColorImageFilter=/FlateEncode")
            args.append("-dGrayImageFilter=/FlateEncode")
        }
        
        args.append("-dColorConversionStrategy=/\(colorStrategy.rawValue)")
        
        if preserveOverprint {
            args.append("-dPreserveOverprintSettings=true")
        }
        if embedFonts {
            args.append("-dEmbedAllFonts=true")
        }
        if subsetFonts {
            args.append("-dSubsetFonts=true")
        }
        if compressFonts {
            args.append("-dCompressFonts=true")
        }
        if fastWebView {
            args.append("-dFastWebView=true")
        }
        if detectDuplicates {
            args.append("-dDetectDuplicateImages=true")
        }
        if ascii85 {
            args.append("-dASCII85EncodePages=true")
        }
        
        if !customArgs.isEmpty {
            args.append(contentsOf: customArgs.split(separator: " ").map(String.init))
        }
        
        return args
    }
}
