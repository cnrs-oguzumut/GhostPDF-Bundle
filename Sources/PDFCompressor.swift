import Foundation
import PDFKit
import Quartz
import UniformTypeIdentifiers
import CoreGraphics
import ImageIO
import NaturalLanguage


// Helper for Image Extraction
class ImageExtractionContext {
    let outputDir: URL
    var currentPage: Int = 0
    var imageIndexOnPage: Int = 0
    
    init(outputDir: URL) {
        self.outputDir = outputDir
    }
}

func scanXObjects(resources: CGPDFDictionaryRef, context: ImageExtractionContext) {
    var xObjDict: CGPDFDictionaryRef? = nil
    if CGPDFDictionaryGetDictionary(resources, "XObject", &xObjDict), let xObjects = xObjDict {
        let contextPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(context).toOpaque())
        CGPDFDictionaryApplyFunction(xObjects, formAndImageCallback, contextPtr)
    }
}

func formAndImageCallback(key: UnsafePointer<Int8>, value: CGPDFObjectRef, info: UnsafeMutableRawPointer?) {
    guard let info = info else { return }
    let context = Unmanaged<ImageExtractionContext>.fromOpaque(info).takeUnretainedValue()
    
    var stream: CGPDFStreamRef? = nil
    if CGPDFObjectGetValue(value, .stream, &stream), let stream = stream {
        let dict: CGPDFDictionaryRef? = CGPDFStreamGetDictionary(stream)
        var subtype: UnsafePointer<Int8>? = nil
        
        if let dict = dict, CGPDFDictionaryGetName(dict, "Subtype", &subtype), let subtype = subtype {
            let subtypeString = String(cString: subtype)
            
            if subtypeString == "Image" {
                // Delegate to imageExtractionCallback
                imageExtractionCallback(key: key, value: value, info: info)
            } else if subtypeString == "Form" {
                // This is a Form XObject - scan its resources for more images
                var formResDict: CGPDFDictionaryRef? = nil
                if CGPDFDictionaryGetDictionary(dict, "Resources", &formResDict), let formResources = formResDict {
                    scanXObjects(resources: formResources, context: context)
                }
            }
        }
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
                 // Check Filter
                 var isJpeg = false
                 var isJpx = false
                 
                 // Try as name first
                 var filter: UnsafePointer<Int8>? = nil
                 if CGPDFDictionaryGetName(dict, "Filter", &filter), let filter = filter {
                     let filterName = String(cString: filter)
                     if filterName == "DCTDecode" { isJpeg = true }
                     else if filterName == "JPXDecode" { isJpx = true }
                 } else {
                     // Try as array
                     var filterArray: CGPDFArrayRef? = nil
                     if CGPDFDictionaryGetArray(dict, "Filter", &filterArray), let arr = filterArray {
                         var firstFilter: UnsafePointer<Int8>? = nil
                         if CGPDFArrayGetCount(arr) > 0, CGPDFArrayGetName(arr, 0, &firstFilter), let ff = firstFilter {
                             let filterName = String(cString: ff)
                             if filterName == "DCTDecode" { isJpeg = true }
                             else if filterName == "JPXDecode" { isJpx = true }
                         }
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
                 } else if isJpx {
                     // JPEG 2000 - save as .jp2
                     var format: CGPDFDataFormat = .raw
                     if let data = CGPDFStreamCopyData(stream, &format) {
                         let filename = "Page\(context.currentPage)_Img\(context.imageIndexOnPage).jp2"
                         let url = context.outputDir.appendingPathComponent(filename)
                         try? (data as Data).write(to: url)
                         context.imageIndexOnPage += 1
                     }
                 } else {
                     // All other formats (Flate, LZW, CCITT, etc.)
                     // Now handled robustly by createImageFromStream
                     if let image = createImageFromStream(stream: stream, dict: dict) {
                         let filename = "Page\(context.currentPage)_Img\(context.imageIndexOnPage).png"
                         let url = context.outputDir.appendingPathComponent(filename)
                         if let data = imageTiffData(image), let bitmap = NSBitmapImageRep(data: data) {
                             var finalBitmap = bitmap
                             if bitmap.colorSpace.colorSpaceModel == .cmyk {
                                 if let converted = bitmap.converting(to: NSColorSpace.sRGB, renderingIntent: .default) {
                                     finalBitmap = converted
                                 }
                             }
                             if let png = finalBitmap.representation(using: .png, properties: [:]) {
                                 try? png.write(to: url)
                                 context.imageIndexOnPage += 1
                             }
                         }
                     }
                 }
            }
        }
    }
}

func createImageFromStream(stream: CGPDFStreamRef, dict: CGPDFDictionaryRef) -> CGImage? {
    var width: CGPDFInteger = 0
    var height: CGPDFInteger = 0
    var bpc: CGPDFInteger = 8 // Default to 8 bits per component
    
    guard CGPDFDictionaryGetInteger(dict, "Width", &width),
          CGPDFDictionaryGetInteger(dict, "Height", &height) else { return nil }
    
    // BitsPerComponent - may be missing for image masks
    if !CGPDFDictionaryGetInteger(dict, "BitsPerComponent", &bpc) {
        // Check if this is an image mask
        var imageMask: CGPDFBoolean = 0
        if CGPDFDictionaryGetBoolean(dict, "ImageMask", &imageMask), imageMask != 0 {
            bpc = 1 // Image masks are 1-bit
        } else {
            bpc = 8 // Default fallback
        }
    }
    
    // ColorSpace
    var csObj: CGPDFObjectRef? = nil
    var colorSpace: CGColorSpace? = nil
    var componentCount = 0
    
    // Check if this is an image mask first
    var imageMask: CGPDFBoolean = 0
    if CGPDFDictionaryGetBoolean(dict, "ImageMask", &imageMask), imageMask != 0 {
        // Image masks are grayscale with inverted decode
        colorSpace = CGColorSpace(name: CGColorSpace.linearGray)
        componentCount = 1
    } else if CGPDFDictionaryGetObject(dict, "ColorSpace", &csObj), let csObj = csObj {
        // Try getting name first (DeviceRGB, DeviceGray, DeviceCMYK)
        var name: UnsafePointer<Int8>? = nil
        if CGPDFObjectGetValue(csObj, .name, &name), let name = name {
            let csName = String(cString: name)
            if csName == "DeviceRGB" {
                colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
                componentCount = 3
            } else if csName == "DeviceGray" {
                colorSpace = CGColorSpace(name: CGColorSpace.linearGray)
                componentCount = 1
            } else if csName == "DeviceCMYK" {
                 colorSpace = CGColorSpace(name: CGColorSpace.genericCMYK)
                 componentCount = 4
            }
        } else {
            // ColorSpace is often an Array
            var csArray: CGPDFArrayRef? = nil
            if CGPDFObjectGetValue(csObj, .array, &csArray), let arr = csArray, CGPDFArrayGetCount(arr) >= 1 {
                var csTypeName: UnsafePointer<Int8>? = nil
                if CGPDFArrayGetName(arr, 0, &csTypeName), let csType = csTypeName {
                    let typeName = String(cString: csType)
                    if typeName == "ICCBased" {
                        var iccStream: CGPDFStreamRef? = nil
                        if CGPDFArrayGetCount(arr) >= 2, CGPDFArrayGetStream(arr, 1, &iccStream), let iccS = iccStream {
                            if let iccDict = CGPDFStreamGetDictionary(iccS) {
                                var n: CGPDFInteger = 0
                                if CGPDFDictionaryGetInteger(iccDict, "N", &n) {
                                    componentCount = Int(n)
                                    if componentCount == 1 { colorSpace = CGColorSpace(name: CGColorSpace.linearGray) }
                                    else if componentCount == 3 { colorSpace = CGColorSpace(name: CGColorSpace.sRGB) }
                                    else if componentCount == 4 { colorSpace = CGColorSpace(name: CGColorSpace.genericCMYK) }
                                }
                            }
                        }
                    } else if typeName == "Indexed" {
                        // For indexed, we need to expand to base color space
                        // Get the base color space component count
                        if CGPDFArrayGetCount(arr) >= 2 {
                             var baseName: UnsafePointer<Int8>? = nil
                             if CGPDFArrayGetName(arr, 1, &baseName), let base = baseName {
                                 let baseCS = String(cString: base)
                                 if baseCS == "DeviceRGB" {
                                     colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
                                     componentCount = 1 // Indexed uses 1 byte per pixel
                                 } else if baseCS == "DeviceGray" {
                                     colorSpace = CGColorSpace(name: CGColorSpace.linearGray)
                                     componentCount = 1
                                 } else if baseCS == "DeviceCMYK" {
                                     colorSpace = CGColorSpace(name: CGColorSpace.genericCMYK)
                                     componentCount = 1
                                 }
                             } else {
                                 // Nested base (e.g. ICCBased array) - use sRGB fallback
                                 componentCount = 1
                                 colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
                             }
                        }
                    } else if typeName == "CalRGB" {
                        colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
                        componentCount = 3
                    } else if typeName == "CalGray" {
                        colorSpace = CGColorSpace(name: CGColorSpace.linearGray)
                        componentCount = 1
                    } else if typeName == "Separation" || typeName == "DeviceN" {
                        // Separation and DeviceN - treat as grayscale for extraction
                        colorSpace = CGColorSpace(name: CGColorSpace.linearGray)
                        componentCount = 1
                    }
                }
            }
        }
    }
    
    // Fallback: If no color space detected, assume RGB (most common)
    if colorSpace == nil {
        colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        componentCount = 3
    }
    
    // Get Data
    var format: CGPDFDataFormat = .raw
    guard let rawCFData = CGPDFStreamCopyData(stream, &format) else { return nil }
    var data = rawCFData as Data
    
    // Check filter type for decompression
    var filterName = ""
    var filter: UnsafePointer<Int8>? = nil
    if CGPDFDictionaryGetName(dict, "Filter", &filter), let f = filter {
        filterName = String(cString: f)
    } else {
        var filterArray: CGPDFArrayRef? = nil
        if CGPDFDictionaryGetArray(dict, "Filter", &filterArray), let arr = filterArray {
             var firstFilter: UnsafePointer<Int8>? = nil
             if CGPDFArrayGetCount(arr) > 0, CGPDFArrayGetName(arr, 0, &firstFilter), let ff = firstFilter {
                 filterName = String(cString: ff)
             }
        }
    }
    
    // Decompress based on filter
    if filterName == "FlateDecode" {
        if let decompressed = try? (data as NSData).decompressed(using: .zlib) {
            data = decompressed as Data
        }
    } else if filterName == "LZWDecode" {
        // LZW not natively supported - try using the raw data
        // CGPDFStreamCopyData may have already decoded it
    } else if filterName == "CCITTFaxDecode" || filterName == "JBIG2Decode" {
        // CCITT/JBIG2 - CGPDFStreamCopyData should decode these
        // If format returned is .raw, it's already decoded
    }
    
    guard let provider = CGDataProvider(data: data as CFData) else { return nil }

    let finalCS = colorSpace ?? CGColorSpace(name: CGColorSpace.linearGray)!
    if componentCount == 0 { componentCount = 1 }
    
    let bpp = Int(bpc) * componentCount
    let bytesPerRow = (Int(width) * bpp + 7) / 8
    
    // Be more lenient with data size - some PDFs have extra padding
    let expectedSize = Int(height) * bytesPerRow
    if data.count < expectedSize {
        // Try to proceed anyway if we have at least some data
        if data.count < bytesPerRow {
            return nil // Not enough data for even one row
        }
    }
    
    let bitmapInfo: CGBitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
    
    return CGImage(
        width: Int(width),
        height: Int(height),
        bitsPerComponent: Int(bpc),
        bitsPerPixel: bpp,
        bytesPerRow: bytesPerRow,
        space: finalCS,
        bitmapInfo: bitmapInfo,
        provider: provider,
        decode: nil,
        shouldInterpolate: true,
        intent: .defaultIntent
    )
}

func imageTiffData(_ image: CGImage) -> Data? {
    let rep = NSBitmapImageRep(cgImage: image)
    return rep.representation(using: .tiff, properties: [:])
}

// MARK: - AI Text Extraction & Summarization
import NaturalLanguage

/// Extract all text content from a PDF
func extractTextFromPDF(url: URL, password: String? = nil) -> String? {
    guard let doc = PDFDocument(url: url) else { return nil }
    
    if doc.isEncrypted {
        if let pass = password {
            doc.unlock(withPassword: pass)
        }
    }
    
    if doc.isLocked { return nil }
    
    var fullText = ""
    for i in 0..<doc.pageCount {
        if let page = doc.page(at: i), let pageText = page.string {
            fullText += pageText + "\n\n"
        }
    }
    
    return fullText.isEmpty ? nil : fullText
}

/// Fetch metadata from CrossRef JSON API (requires internet)
struct CrossRefMetadata {
    let authors: String?
    let title: String?
    let journal: String?
    let volume: String?
    let issue: String?
    let pages: String?
}

func fetchMetadataFromDOI(_ doi: String) async -> CrossRefMetadata? {
    // Use JSON API instead of BibTeX for cleaner parsing
    let urlString = "https://api.crossref.org/works/\(doi)"
    guard let url = URL(string: urlString) else { return nil }

    do {
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil
        }

        // Parse JSON to extract metadata
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = json["message"] as? [String: Any] {

            // Extract authors
            var authorNames: [String] = []
            if let authors = message["author"] as? [[String: Any]] {
                for author in authors {
                    var name = ""
                    if let given = author["given"] as? String,
                       let family = author["family"] as? String {
                        name = "\(given) \(family)"
                    } else if let family = author["family"] as? String {
                        name = family
                    }

                    if !name.isEmpty {
                        authorNames.append(name)
                    }
                }
            }

            // Extract title (it's an array, take first element)
            var titleString: String? = nil
            if let titleArray = message["title"] as? [String], let firstTitle = titleArray.first {
                titleString = firstTitle
            }

            // Extract volume
            var volumeString: String? = nil
            if let volume = message["volume"] as? String {
                volumeString = volume
            }

            // Extract issue number
            var issueString: String? = nil
            if let issue = message["issue"] as? String {
                issueString = issue
            }

            // Extract page range
            var pagesString: String? = nil
            if let page = message["page"] as? String {
                pagesString = page
            }

            // Extract journal name (container-title is an array)
            var journalString: String? = nil
            if let containerTitle = message["container-title"] as? [String], let firstJournal = containerTitle.first {
                journalString = firstJournal
            }

            return CrossRefMetadata(
                authors: authorNames.isEmpty ? nil : authorNames.joined(separator: " and "),
                title: titleString,
                journal: journalString,
                volume: volumeString,
                issue: issueString,
                pages: pagesString
            )
        }
    } catch {
        // Network error - silently return nil
        return nil
    }

    return nil
}

/// Extract BibTeX metadata from PDF with optional online lookup
func extractBibTeX(url: URL, allowOnline: Bool = false) async -> String? {
    guard let doc = PDFDocument(url: url) else { return nil }

    // First, try to extract DOI (works offline)
    var doi = ""
    if let firstPage = doc.page(at: 0), let text = firstPage.string {
        let doiPattern = #"10\.\d{4,9}/[-._;()/:A-Z0-9]+"#
        if let range = text.range(of: doiPattern, options: [.regularExpression, .caseInsensitive]) {
            doi = String(text[range])
        }
    }

    // Always do offline extraction first (your clean format)
    var offlineBib = extractBibTeXOffline(url: url, doc: doc, extractedDOI: doi)

    // If online lookup is allowed and we have a DOI, enhance with metadata from CrossRef
    if !doi.isEmpty && allowOnline, let bib = offlineBib {
        if let metadata = await fetchMetadataFromDOI(doi) {
            var enhancedBib = bib

            // Check if offline title looks suspicious (common bad patterns)
            let suspiciousTitlePatterns = [
                #"J\. Mech\. Phys\. Solids \d+"#,     // Citation line extracted as title
                #"Comput\. Methods Appl\. Mech"#,      // Another citation line pattern
                #"journal homepage"#,                  // Includes webpage text
                #"www\."#,                             // Contains URL
                #"elsevier\.com"#,                     // Contains publisher URL
                #"Received date"#,                     // Includes metadata
                #"^\d{3,}"#,                           // Starts with page number
                #"\(\d{4}\)\s+\d{5,}"#                 // Contains (year) followed by article number
            ]

            var titleIsSuspicious = false
            for pattern in suspiciousTitlePatterns {
                if bib.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                    titleIsSuspicious = true
                    break
                }
            }

            // Replace title if it's suspicious and we have a good online title
            if titleIsSuspicious, let onlineTitle = metadata.title {
                let titlePattern = #"title = \{\{[^}]+\}\}"#
                if enhancedBib.range(of: titlePattern, options: .regularExpression) != nil {
                    enhancedBib = enhancedBib.replacingOccurrences(
                        of: titlePattern,
                        with: "title = {\(onlineTitle)}",
                        options: .regularExpression
                    )
                }
            }

            // Always replace authors with complete list from CrossRef
            if let onlineAuthors = metadata.authors {
                let authorPattern = #"author = \{[^}]+\}"#
                if enhancedBib.range(of: authorPattern, options: .regularExpression) != nil {
                    enhancedBib = enhancedBib.replacingOccurrences(
                        of: authorPattern,
                        with: "author = {\(onlineAuthors)}",
                        options: .regularExpression
                    )
                }
            }

            // Always replace journal name with correct one from CrossRef
            if let onlineJournal = metadata.journal {
                let journalPattern = #"journal = \{[^}]+\}"#
                if enhancedBib.range(of: journalPattern, options: .regularExpression) != nil {
                    enhancedBib = enhancedBib.replacingOccurrences(
                        of: journalPattern,
                        with: "journal = {\(onlineJournal)}",
                        options: .regularExpression
                    )
                }
            }

            // Add or replace volume, pages, and issue if available from CrossRef
            if let volume = metadata.volume {
                if enhancedBib.contains("volume = ") {
                    // Replace existing volume
                    let volumePattern = #"volume = \{[^}]*\}"#
                    enhancedBib = enhancedBib.replacingOccurrences(
                        of: volumePattern,
                        with: "volume = {\(volume)}",
                        options: .regularExpression
                    )
                } else {
                    // Add volume field after journal
                    if let journalRange = enhancedBib.range(of: #"journal = \{[^}]+\}"#, options: .regularExpression) {
                        let insertPos = journalRange.upperBound
                        enhancedBib.insert(contentsOf: ",\n    volume = {\(volume)}", at: insertPos)
                    }
                }
            }

            if let pages = metadata.pages {
                if enhancedBib.contains("pages = ") {
                    // Replace existing pages
                    let pagesPattern = #"pages = \{[^}]*\}"#
                    enhancedBib = enhancedBib.replacingOccurrences(
                        of: pagesPattern,
                        with: "pages = {\(pages)}",
                        options: .regularExpression
                    )
                } else {
                    // Add pages field after volume (or journal if no volume)
                    if let volumeRange = enhancedBib.range(of: #"volume = \{[^}]+\}"#, options: .regularExpression) {
                        let insertPos = volumeRange.upperBound
                        enhancedBib.insert(contentsOf: ",\n    pages = {\(pages)}", at: insertPos)
                    } else if let journalRange = enhancedBib.range(of: #"journal = \{[^}]+\}"#, options: .regularExpression) {
                        let insertPos = journalRange.upperBound
                        enhancedBib.insert(contentsOf: ",\n    pages = {\(pages)}", at: insertPos)
                    }
                }
            }

            if let issue = metadata.issue {
                if enhancedBib.contains("number = ") {
                    // Replace existing number (issue)
                    let numberPattern = #"number = \{[^}]*\}"#
                    enhancedBib = enhancedBib.replacingOccurrences(
                        of: numberPattern,
                        with: "number = {\(issue)}",
                        options: .regularExpression
                    )
                } else {
                    // Add number field after volume
                    if let volumeRange = enhancedBib.range(of: #"volume = \{[^}]+\}"#, options: .regularExpression) {
                        let insertPos = volumeRange.upperBound
                        enhancedBib.insert(contentsOf: ",\n    number = {\(issue)}", at: insertPos)
                    } else if let journalRange = enhancedBib.range(of: #"journal = \{[^}]+\}"#, options: .regularExpression) {
                        let insertPos = journalRange.upperBound
                        enhancedBib.insert(contentsOf: ",\n    number = {\(issue)}", at: insertPos)
                    }
                }
            }

            // Update note to indicate online enhancement
            return enhancedBib.replacingOccurrences(
                of: "Extracted from",
                with: "Metadata enhanced via CrossRef API from"
            )
        }
    }

    return offlineBib
}

/// Extract BibTeX metadata from PDF (offline version)
private func extractBibTeXOffline(url: URL, doc: PDFDocument, extractedDOI: String) -> String? {
    let attrs = doc.documentAttributes

    var title = attrs?[PDFDocumentAttribute.titleAttribute] as? String
    var author = attrs?[PDFDocumentAttribute.authorAttribute] as? String
    let creationDate = attrs?[PDFDocumentAttribute.creationDateAttribute] as? Date
    var year = Calendar.current.component(.year, from: creationDate ?? Date())

    // Strategy 1: Trust Metadata if it looks high quality
    var authorFromMetadata = false
    if let metaAuthor = author,
       metaAuthor.count > 5,
       metaAuthor.split(separator: " ").contains(where: { $0.count > 2 }),
       !metaAuthor.lowercased().contains("unknown") {
        authorFromMetadata = true
    } else {
        author = nil // Force text extraction if metadata is poor
    }

    var journal = "Unknown Journal"
    var volume = ""
    var number = ""
    var pages = ""
    var doi = extractedDOI // Use the DOI already extracted
    
    if let firstPage = doc.page(at: 0), let text = firstPage.string {
        let allLines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let lines = allLines.filter { $0.count > 2 }

        // DOI already extracted and passed in as parameter
        
        // 1. Identify Journal / Citation Line
        let citationLinePattern = #"^([\w\s&]+)\s+(\d+)\s*\((\d{4})\)\s*(\d+)"#
        for line in lines.prefix(10) {
            if let _ = line.range(of: citationLinePattern, options: .regularExpression) {
                let nsLine = line as NSString
                let regex = try? NSRegularExpression(pattern: citationLinePattern)
                if let firstMatch = regex?.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16.count)) {
                    journal = nsLine.substring(with: firstMatch.range(at: 1)).trimmingCharacters(in: .whitespaces)
                    volume = nsLine.substring(with: firstMatch.range(at: 2))
                    if let y = Int(nsLine.substring(with: firstMatch.range(at: 3))) { year = y }
                    pages = nsLine.substring(with: firstMatch.range(at: 4))
                    break
                }
            }
        }
        
        if journal == "Unknown Journal" {
            let jPatterns = [#"Journal of [\w\s&]+"#, #"Int\.? J\.? of [\w\s&]+"#, #"Nature [\w\s]*"#, #"Science"#]
            for p in jPatterns {
                if let r = text.range(of: p, options: [.regularExpression, .caseInsensitive]) {
                    journal = String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                    break
                }
            }
        }
        
        // 2. Score lines to find the Title
        var titleCandidates: [(line: String, score: Int, index: Int)] = []
        let noise = ["Contents lists", "homepage", "www.", "Research Article", "Full Length", "ScienceDirect",
                     "article info", "a r t i c l e", "abstract", "keywords", "Polish Academy"]

        for (i, line) in lines.prefix(20).enumerated() {
            var score = 0
            if line.count > 30 && line.count < 250 { score += 10 }
            if line == line.uppercased() { score += 5 }
            if line.contains(journal) { score -= 25 }
            if noise.contains(where: { line.localizedCaseInsensitiveContains($0) }) { score -= 30 }

            if let mt = attrs?[PDFDocumentAttribute.titleAttribute] as? String {
                let cleanMT = mt.replacingOccurrences(of: "[formula omitted]", with: "").trimmingCharacters(in: .whitespaces)
                if !cleanMT.isEmpty && line.lowercased().contains(cleanMT.lowercased()) { score += 20 }
            }

            if score > 0 { titleCandidates.append((line, score, i)) }
        }
        
        let bestTitle = titleCandidates.sorted(by: { $0.score > $1.score }).first
        if let bt = bestTitle {
            var mergedTitle = bt.line
            var lastIdx = bt.index
            
            // Multi-line Title Merging
            let prepositions = ["of", "in", "and", "on", "at", "for", "with", "by"]
            let stopWords = ["article", "info", "abstract", "keywords", "polish academy", "institute",
                           "university", "department", "ippt", "received", "revised", "accepted"]

            while lastIdx + 1 < lines.count {
                let current = lines[lastIdx].lowercased()
                let next = lines[lastIdx + 1]
                let nextLower = next.lowercased()

                // Stop if next line looks like metadata/affiliation
                if stopWords.contains(where: { nextLower.contains($0) }) {
                    break
                }

                // Stop if next line contains author-like patterns (initials with dots)
                if next.range(of: #"\b[A-Z]\.\s*[A-Z]\."#, options: .regularExpression) != nil {
                    break
                }

                let endsWithPreposition = prepositions.contains { current.hasSuffix(" " + $0) || current.hasSuffix($0) }
                let endsWithHyphen = current.hasSuffix("-")
                let nextStartsLower = next.first?.isLowercase ?? false

                // Only merge if it's clearly a continuation
                if endsWithPreposition || endsWithHyphen || nextStartsLower {
                    mergedTitle += (endsWithHyphen ? "" : " ") + next
                    lastIdx += 1
                    if lastIdx > bt.index + 2 { break }  // Max 3 lines for title
                } else {
                    break
                }
            }

            // Clean up title: Remove author names and affiliations that may have been captured
            // Look for author-like patterns (initials) within the title and truncate there
            if let authorPattern = mergedTitle.range(of: #"\s+[A-Z]\.\s+[A-Z][a-z]+"#, options: .regularExpression) {
                // Found something like " K. Tůma" - truncate before it
                mergedTitle = String(mergedTitle[..<authorPattern.lowerBound])
            }

            // Also remove common metadata that might have been appended
            let metadataPatterns = ["Institute of", "IPPT", "Polish Academy", "article info", "a r t i c l e"]
            for pattern in metadataPatterns {
                if let range = mergedTitle.range(of: pattern, options: .caseInsensitive) {
                    mergedTitle = String(mergedTitle[..<range.lowerBound])
                    break
                }
            }

            title = mergedTitle.trimmingCharacters(in: .whitespaces)

            // 3. Find Authors (look for lines following the title) if metadata was poor
            if !authorFromMetadata {
                var authorCandidates: [(line: String, score: Int)] = []
                for i in (lastIdx + 1)...min(lastIdx + 6, lines.count - 1) {
                    let line = lines[i]
                    let capitalCount = line.filter { $0.isUppercase }.count
                    if capitalCount < 2 { continue }
                    
                    var score = 0
                    if line.contains(",") || line.contains(" and ") || line.contains("&") { score += 15 }
                    if line.contains("*") || line.contains("†") || line.contains("‡") { score += 5 }
                    score += min(capitalCount * 2, 20)
                    
                    if line.contains("@") { score -= 10 }
                    if line.count < 8 { score -= 10 }
                    if (line.contains("University") || line.contains("Department") || line.contains("Institute")) && !line.contains(",") {
                        score -= 20
                    }
                    if line.first?.isNumber == true { score -= 15 }
                    
                    if score > 0 { authorCandidates.append((line, score)) }
                }
                
                if !authorCandidates.isEmpty {
                    let sortedCandidates = authorCandidates.sorted(by: { $0.score > $1.score })
                    let topScore = sortedCandidates[0].score
                    
                    // Merge lines with scores within 10 points of top score (likely continuation lines)
                    let authorLines = authorCandidates
                        .filter { $0.score >= topScore - 10 }
                        .map { $0.line }
                    
                    author = authorLines.joined(separator: " ")
                }
            }
        }
        
        let cy = Calendar.current.component(.year, from: Date())
        if year == cy {
            let yPat = #"\b(19\d{2}|20[0-2]\d)\b"#
            if let r = text.range(of: yPat, options: .regularExpression), let yInt = Int(text[r]) { year = yInt }
        }
    }
    
    // Final Cleanup & Assembly
    var finalTitle = (title ?? url.deletingPathExtension().lastPathComponent)
        .replacingOccurrences(of: "[formula omitted]", with: "Formula")
        .replacingOccurrences(of: "  ", with: " ")
        .trimmingCharacters(in: .whitespaces)

    if finalTitle.lowercased().starts(with: journal.lowercased()) {
        finalTitle = String(finalTitle.dropFirst(journal.count)).trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
    }

    // Clean up journal name (remove common webpage artifacts)
    var finalJournal = journal
        .replacingOccurrences(of: #"\s*journal homepage.*$"#, with: "", options: [.regularExpression, .caseInsensitive])
        .replacingOccurrences(of: #"\s*Received date.*$"#, with: "", options: [.regularExpression, .caseInsensitive])
        .replacingOccurrences(of: #"\s*www\..*$"#, with: "", options: [.regularExpression, .caseInsensitive])
        .trimmingCharacters(in: .whitespacesAndNewlines)
    
    var finalAuthor = author ?? "Unknown Author"
    if finalAuthor != "Unknown Author" {
        // Step 1: Clean markers and extra whitespace
        finalAuthor = finalAuthor
            .replacingOccurrences(of: #"[\*†‡§\d]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        // Step 2: Remove obvious affiliation text BEFORE splitting
        // Common affiliation keywords that shouldn't be in author names
        let affiliationKeywords = ["University", "Department", "College", "Institute", "Laboratory",
                                  "School", "Center", "Faculty", "Division", "Research",
                                  "Hospital", "Clinic", "Foundation", "Society", "Academy",
                                  "National", "International", "Japan", "USA", "China", "UK",
                                  "Canada", "Germany", "France", "Australia", "Korea",
                                  "Engineering", "Science", "Physics", "Chemistry", "Biology",
                                  "Medicine", "Technology", "Medical", "Clinical"]

        // Find where affiliations start by detecting affiliation keywords
        var cutoffIndex = finalAuthor.endIndex
        for keyword in affiliationKeywords {
            if let range = finalAuthor.range(of: keyword, options: .caseInsensitive) {
                if range.lowerBound < cutoffIndex {
                    cutoffIndex = range.lowerBound
                }
            }
        }

        // If we found affiliations, cut them off
        if cutoffIndex != finalAuthor.endIndex {
            finalAuthor = String(finalAuthor[..<cutoffIndex]).trimmingCharacters(in: .whitespaces)
        }

        // Step 3: Normalize multi-author separators (don't touch spaces within names)
        finalAuthor = finalAuthor
            .replacingOccurrences(of: ";", with: " and ")
            .replacingOccurrences(of: " & ", with: " and ")
            .replacingOccurrences(of: ",", with: " and ")
            .replacingOccurrences(of: #"\s+and\s+"#, with: " and ", options: .regularExpression)

        // Step 4: Split by "and" and validate each author name
        let authorParts = finalAuthor.components(separatedBy: " and ")
        var cleanedAuthors: [String] = []

        for part in authorParts {
            let words = part.components(separatedBy: " ")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { word in
                    // Keep words that start with uppercase and don't look like affiliations
                    guard word.count > 0 && word.first?.isUppercase == true else { return false }

                    // Filter out common affiliation words that might have slipped through
                    let lowerWord = word.lowercased()
                    if affiliationKeywords.contains(where: { $0.lowercased() == lowerWord }) {
                        return false
                    }

                    return true
                }

            // A valid author name should have 1-4 words typically
            if !words.isEmpty && words.count <= 4 {
                let cleanedName = words.joined(separator: " ")
                // Should be at least 2 chars and not be a single initial
                if cleanedName.count >= 2 {
                    cleanedAuthors.append(cleanedName)
                }
            }
        }

        finalAuthor = cleanedAuthors.joined(separator: " and ")
    }

    if finalAuthor.isEmpty { finalAuthor = "Unknown Author" }
    
    let authorLast = finalAuthor.components(separatedBy: " ").last?.filter { $0.isLetter } ?? "Author"
    let titleFirst = finalTitle.components(separatedBy: " ").filter { $0.count > 3 }.first?.filter { $0.isLetter } ?? "Title"
    let citeKey = "\(authorLast)\(year)\(titleFirst)".lowercased()
    
    var bib = "@article{\(citeKey),\n"
    bib += "    author = {\(finalAuthor)},\n"
    bib += "    title = {\(finalTitle)},\n"
    bib += "    year = {\(year)},\n"
    bib += "    journal = {\(finalJournal)}"
    
    if !volume.isEmpty { bib += ",\n    volume = {\(volume)}" }
    if !number.isEmpty { bib += ",\n    number = {\(number)}" }
    if !pages.isEmpty { bib += ",\n    pages = {\(pages)}" }
    if !doi.isEmpty { bib += ",\n    doi = {\(doi)}" }
    
    bib += ",\n    note = {Extracted from \(url.lastPathComponent) by GhostPDF}\n"
    bib += "}"
    
    return bib
}

/// Extract Abstract section from academic PDF text
func extractAbstract(from text: String) -> String? {
    // Strategy 1: Look for explicit Abstract section
    let abstractPattern = #"(?:Abstract|ABSTRACT)[:\s\n]+([\s\S]+?)(?=\n\s*\n\s*[A-Z1]|\nIntroduction|\n1\.|\nKeywords|©|\nReceived)"#

    if let range = text.range(of: abstractPattern, options: .regularExpression) {
        var abstract = String(text[range])
        // Remove "Abstract" header
        abstract = abstract.replacingOccurrences(of: #"^Abstract[:\s]*"#, with: "", options: [.regularExpression, .caseInsensitive])
        abstract = abstract.trimmingCharacters(in: .whitespacesAndNewlines)

        // Quality check: abstracts are usually 50-500 words
        let wordCount = abstract.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
        if wordCount >= 20 && wordCount <= 600 {
            return abstract
        }
    }

    return nil
}

/// Summarize text using improved position + keyword-based scoring for academic papers
func summarizeText(_ text: String, maxSentences: Int = 5) -> String {
    // Strategy 1: Try to extract abstract first (best for academic papers)
    if let abstract = extractAbstract(from: text) {
        // If abstract is short enough, return it directly
        let sentences = abstract.components(separatedBy: .newlines).filter { !$0.isEmpty }
        if sentences.count <= maxSentences {
            return abstract
        }
        // Otherwise, summarize the abstract itself
    }

    // Strategy 2: Position + Keyword-based extractive summarization
    var lines = text.components(separatedBy: .newlines)

    // Count line occurrences to find repeated headers/footers
    var lineCounts: [String: Int] = [:]
    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed.count > 5 {
            lineCounts[trimmed, default: 0] += 1
        }
    }

    // Filter out repeated lines and noise
    let probabilityThreshold = max(3, lines.count / 40)
    lines = lines.filter { line in
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.count < 10 { return false }

        // Remove page numbers
        if Int(trimmed) != nil || trimmed.range(of: #"^(Page )?\d+$"#, options: .regularExpression) != nil {
            return false
        }

        // Remove repeated headers/footers
        if let count = lineCounts[trimmed], count > probabilityThreshold {
            return false
        }

        return true
    }

    let cleanText = lines.joined(separator: " ")

    // Tokenize sentences
    let tokenizer = NLTokenizer(unit: .sentence)
    tokenizer.string = cleanText

    var sentences: [String] = []
    var seenSentences: Set<String> = []

    tokenizer.enumerateTokens(in: cleanText.startIndex..<cleanText.endIndex) { range, _ in
        let sentence = String(cleanText[range]).trimmingCharacters(in: .whitespacesAndNewlines)

        // Quality filter
        if sentence.count > 40 && sentence.count < 500,
           sentence.first?.isUppercase == true,
           !seenSentences.contains(sentence) {
            sentences.append(sentence)
            seenSentences.insert(sentence)
        }
        return true
    }

    if sentences.isEmpty { return text }
    if sentences.count <= maxSentences { return sentences.joined(separator: "\n\n") }

    // Score sentences based on position + keywords (better for academic papers than centroid)
    var scoredSentences: [(sentence: String, score: Double)] = []

    // Academic paper importance keywords
    let highValueKeywords = ["results", "findings", "conclude", "demonstrate", "show that", "found that",
                             "significant", "novel", "propose", "present", "contribute", "discover"]
    let mediumValueKeywords = ["method", "approach", "study", "research", "analyze", "investigate",
                               "measure", "evaluate", "compare", "develop"]
    let lowValueKeywords = ["however", "moreover", "furthermore", "therefore", "thus", "consequently"]

    // Boilerplate phrases to penalize
    let boilerplate = ["all rights reserved", "corresponding author", "copyright", "published by",
                       "available online", "received", "revised", "accepted"]

    for (i, sentence) in sentences.enumerated() {
        var score = 0.0
        let lowerSentence = sentence.lowercased()

        // Position-based scoring (academic papers front-load important info)
        if i < 5 {
            score += 15.0  // First 5 sentences (likely abstract/intro)
        } else if i < 15 {
            score += 8.0   // Next 10 sentences
        } else if i > sentences.count - 10 {
            score += 10.0  // Last 10 sentences (conclusion)
        } else {
            score += 2.0   // Middle content
        }

        // Keyword scoring
        for keyword in highValueKeywords {
            if lowerSentence.contains(keyword) {
                score += 5.0
            }
        }

        for keyword in mediumValueKeywords {
            if lowerSentence.contains(keyword) {
                score += 2.0
            }
        }

        for keyword in lowValueKeywords {
            if lowerSentence.contains(keyword) {
                score += 1.0
            }
        }

        // Length preference (not too short, not too long)
        if sentence.count > 80 && sentence.count < 250 {
            score += 3.0
        }

        // Penalize boilerplate
        for phrase in boilerplate {
            if lowerSentence.contains(phrase) {
                score -= 20.0
            }
        }

        // Penalize references to figures/tables without context
        if lowerSentence.range(of: #"\b(fig\.|figure|table)\s+\d+"#, options: .regularExpression) != nil {
            score -= 3.0
        }

        scoredSentences.append((sentence, score))
    }

    // Sort by score and take top N
    let topSentences = scoredSentences
        .sorted { $0.score > $1.score }
        .prefix(maxSentences)
        .map { $0.sentence }

    // Return in original order for coherence
    var result: [String] = []
    for sentence in sentences {
        if topSentences.contains(sentence) {
            result.append(sentence)
            if result.count >= maxSentences { break }
        }
    }

    return result.joined(separator: "\n\n")
}

/// Convenience: Summarize a PDF file directly
func summarizePDF(url: URL, maxSentences: Int = 5, password: String? = nil) -> String? {
    guard let text = extractTextFromPDF(url: url, password: password) else {
        return nil
    }
    return summarizeText(text, maxSentences: maxSentences)
}

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
            let gsBase = "\(resourcePath)/ghostscript/share/ghostscript"
            // Dynamically find the version directory (e.g. "10.06.0")
            if let items = try? FileManager.default.contentsOfDirectory(atPath: gsBase),
               let versionDir = items.first(where: { $0.range(of: "^\\d+\\.\\d+(\\.\\d+)?$", options: .regularExpression) != nil }) {
                
                let baseVer = "\(gsBase)/\(versionDir)"
                // Include Init, lib, flags, fonts. Critical: Resource/Init is where gs_init.ps lives.
                let gsLibPath = "\(baseVer)/Resource/Init:\(baseVer)/lib:\(baseVer)/fonts"
                
                var env = ProcessInfo.processInfo.environment
                env["GS_LIB"] = gsLibPath
                // Ensure TMPDIR is set to the sandboxed temporary directory
                env["TMPDIR"] = FileManager.default.temporaryDirectory.path
                task.environment = env
            }
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
                    // Scan XObjects recursively
                    scanXObjects(resources: resources, context: context)
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
        
        // Set GS_LIB environment variable for bundled Ghostscript
        if let resourcePath = Bundle.main.resourcePath {
            let gsBase = "\(resourcePath)/ghostscript/share/ghostscript"
            if let items = try? FileManager.default.contentsOfDirectory(atPath: gsBase),
               let versionDir = items.first(where: { $0.range(of: "^\\d+\\.\\d+(\\.\\d+)?$", options: .regularExpression) != nil }) {
                
                let baseVer = "\(gsBase)/\(versionDir)"
                let gsLibPath = "\(baseVer)/Resource/Init:\(baseVer)/lib:\(baseVer)/fonts"
                
                var env = ProcessInfo.processInfo.environment
                env["GS_LIB"] = gsLibPath
                env["TMPDIR"] = FileManager.default.temporaryDirectory.path
                task.environment = env
            }
        }
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        
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
        // Use PDFKit for rotation (Reliable, Lossless)
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
        
        let pageCount = doc.pageCount
        progressHandler(0.1)
        
        // Normalize angle to 0, 90, 180, 270
        // PDFKit expects absolute rotation in degrees (must be multiple of 90)
        let normalizedAngle = ((angle % 360) + 360) % 360
        
        for i in 0..<pageCount {
            // UI uses 1-based indexing for pages set
            let pageNum = i + 1
            
            let shouldRotate: Bool
            if let p = pages, !p.isEmpty {
                shouldRotate = p.contains(pageNum)
            } else {
                shouldRotate = true // Rotate all if no specific pages
            }
            
            if shouldRotate {
                if let page = doc.page(at: i) {
                    // PDFKit rotation is absolute.
                    // We set it to the requested angle to match UI "Orientation" selection logic (0, 90, 180, 270 absolute)
                    page.rotation = normalizedAngle
                }
            }
            
            if i % 10 == 0 {
                 progressHandler(0.1 + 0.8 * (Double(i) / Double(pageCount)))
            }
        }
        
        progressHandler(0.9)
        doc.write(to: output)
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

/// Extract references from PDF's bibliography section and convert to BibTeX using CrossRef API
func extractReferences(url: URL) async -> [String] {
    guard let doc = PDFDocument(url: url) else { return [] }
    
    var references: [String] = []
    var referenceText = ""
    var startCollecting = false
    var pagesCollected = 0
    
    // 1. Find References section and extract ALL text until end
    for pageIndex in 0..<doc.pageCount {
        guard let page = doc.page(at: pageIndex),
              let text = page.string else { continue }
        
        let lines = text.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Detect start of references section
            if !startCollecting {
                let refHeaders = ["References", "REFERENCES", "Bibliography", "BIBLIOGRAPHY", 
                                 "Works Cited", "WORKS CITED", "Literature Cited", "LITERATURE CITED"]
                if refHeaders.contains(where: { trimmed.hasPrefix($0) || trimmed == $0 }) {
                    startCollecting = true
                    print("DEBUG - Found references section on page \(pageIndex)")
                    continue
                }
            }
            
            if startCollecting {
                referenceText += line + "\n"
            }
        }
        
        // Keep collecting until end of document (references usually go to the end)
        if startCollecting {
            pagesCollected += 1
        }
    }
    
    print("DEBUG - Collected \(pagesCollected) pages of references, total chars: \(referenceText.count)")
    
    if referenceText.isEmpty {
        return ["// No references section found in PDF"]
    }
    
    // 2. Split into individual reference entries
    let refLines = referenceText.components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
    
    var currentRef = ""
    var individualRefs: [String] = []
    
    // First, check if references are numbered or name-based
    let hasNumberedRefs = refLines.contains { line in
        line.range(of: #"^\[\d+\]|^\d+\.\s|^\(\d+\)"#, options: .regularExpression) != nil
    }
    
    print("DEBUG - Reference format: \(hasNumberedRefs ? "numbered" : "name-based")")
    
    for line in refLines {
        var startsNewRef = false
        
        if hasNumberedRefs {
            // Numbered reference patterns
            let patterns = [
                #"^\[\d+\]"#,           // [1] format
                #"^\d+\.\s"#,           // 1. format
                #"^\(\d+\)"#            // (1) format
            ]
            for pattern in patterns {
                if line.range(of: pattern, options: .regularExpression) != nil {
                    startsNewRef = true
                    break
                }
            }
        } else {
            // Name-based references - simpler heuristic
            // If current ref is long enough and new line looks like it starts with author name:
            // - Starts with capital letter
            // - Has comma or period in first 20 characters (author initial)
            // - Doesn't start with common continuation words
            
            let startsWithCap = line.first?.isUppercase ?? false
            let first20 = String(line.prefix(20))
            let hasEarlyPunctuation = first20.contains(",") || first20.contains(".")
            let continuationWords = ["The", "A ", "An ", "In ", "On ", "And ", "For ", "With ", "From "]
            let isContinuation = continuationWords.contains { line.hasPrefix($0) }
            
            if startsWithCap && hasEarlyPunctuation && !isContinuation {
                if currentRef.count > 50 || currentRef.isEmpty {
                    startsNewRef = true
                }
            }
        }
        
        if startsNewRef {
            if !currentRef.isEmpty && currentRef.count > 30 {
                individualRefs.append(currentRef)
            }
            currentRef = line
        } else {
            currentRef += " " + line
        }
    }
    if !currentRef.isEmpty && currentRef.count > 30 {
        individualRefs.append(currentRef)
    }
    
    print("DEBUG - Found \(individualRefs.count) individual references")
    
    // 3. Send raw reference text directly to CrossRef (let their search engine parse it)
    var processedKeys: Set<String> = []
    var successCount = 0
    var failCount = 0
    
    for (index, refText) in individualRefs.enumerated() {
        // Clean up the reference text
        let cleanedRef = refText
            .replacingOccurrences(of: #"^\[\d+\]|\d+\."#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        
        // Skip very short references
        if cleanedRef.count < 20 {
            print("DEBUG - Skipping short ref: \(cleanedRef.prefix(30))...")
            continue
        }
        
        // Use more of the text for deduplication (100 chars)
        let key = String(cleanedRef.prefix(100)).lowercased()
        if processedKeys.contains(key) {
            print("DEBUG - Skipping duplicate: \(cleanedRef.prefix(30))...")
            continue
        }
        processedKeys.insert(key)
        
        // Send raw text to CrossRef bibliographic search
        if let bibtex = await queryBibTeXWithRawText(cleanedRef) {
            references.append(bibtex)
            successCount += 1
            print("DEBUG - [CrossRef] Found: \(cleanedRef.prefix(40))...")
        } else {
            print("DEBUG - CrossRef failed, trying Semantic Scholar...")
            if let bibtex = await querySemanticScholar(cleanedRef) {
                references.append(bibtex)
                successCount += 1
                print("DEBUG - [SemanticScholar] Found: \(cleanedRef.prefix(40))...")
            } else {
                failCount += 1
                print("DEBUG - No match found for: \(cleanedRef.prefix(40))...")
            }
        }
        
        // Rate limiting
        if index < individualRefs.count - 1 {
            try? await Task.sleep(nanoseconds: 250_000_000) // 250ms
        }
    }
    
    print("DEBUG - Final: \(successCount) found, \(failCount) failed")
    return references.isEmpty ? ["// No valid references found via CrossRef"] : references
}

/// Query CrossRef with raw reference text and build clean BibTeX from JSON
private func queryBibTeXWithRawText(_ refText: String) async -> String? {
    // Clean and prepare query text
    var cleanedText = String(refText.prefix(200))
    
    // Replace special characters that might break the query
    cleanedText = cleanedText
        .replacingOccurrences(of: "—", with: "-")  // em-dash
        .replacingOccurrences(of: "–", with: "-")  // en-dash
        .replacingOccurrences(of: "'", with: "'")  // smart quote
        .replacingOccurrences(of: "'", with: "'")
    
    // Detect and fix concatenated text (like "AmbatiM,KruseR" -> "Ambati M, Kruse R")
    // Check if text has very few spaces compared to its length
    let spaceCount = cleanedText.filter { $0 == " " }.count
    if spaceCount < cleanedText.count / 15 { // Very few spaces
        // Add space before each capital letter that follows lowercase
        var fixedText = ""
        var prevChar: Character = " "
        for char in cleanedText {
            if char.isUppercase && prevChar.isLowercase {
                fixedText += " "
            }
            fixedText += String(char)
            prevChar = char
        }
        cleanedText = fixedText
        print("DEBUG - Fixed concatenated text: \(cleanedText.prefix(50))...")
    }
    
    // Check for DOI in the reference text - if found, use it directly
    if let doiMatch = refText.range(of: #"10\.\d{4,}/[^\s]+"#, options: .regularExpression) {
        let doi = String(refText[doiMatch])
        print("DEBUG - Found DOI: \(doi)")
        
        // Try to get BibTeX directly using DOI
        let doiUrl = "https://api.crossref.org/works/\(doi)"
        if let url = URL(string: doiUrl) {
            var request = URLRequest(url: url)
            request.setValue("GhostPDF/1.0", forHTTPHeaderField: "User-Agent")
            
            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let message = json["message"] as? [String: Any] {
                    if let bibtex = buildBibTeXFromJSON(message) {
                        print("DEBUG - DOI lookup successful")
                        return bibtex
                    }
                }
            } catch {
                print("DEBUG - DOI lookup failed: \(error)")
            }
        }
    }
    
    let queryText = cleanedText
        .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
    
    guard !queryText.isEmpty else { return nil }
    
    // Request more results so we can validate
    let urlString = "https://api.crossref.org/works?query.bibliographic=\(queryText)&rows=5"
    guard let url = URL(string: urlString) else { 
        print("DEBUG - Invalid CrossRef URL")
        return nil 
    }
    
    var request = URLRequest(url: url)
    request.setValue("GhostPDF/1.0", forHTTPHeaderField: "User-Agent")
    
    do {
        let (data, _) = try await URLSession.shared.data(for: request)
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = json["message"] as? [String: Any],
           let items = message["items"] as? [[String: Any]] {
            
            // Extract year from reference text for validation
            var refYear: String? = nil
            if let yearMatch = refText.range(of: #"\b(19|20)\d{2}\b"#, options: .regularExpression) {
                refYear = String(refText[yearMatch])
            }
            
            // Extract first author surname from reference for validation
            var refAuthor: String? = nil
            if let firstWord = refText.components(separatedBy: CharacterSet.alphanumerics.inverted).first,
               firstWord.count >= 3,
               firstWord.first?.isUppercase == true {
                refAuthor = firstWord.lowercased()
            }
            
            // Find best matching result
            for item in items {
                let score = item["score"] as? Double ?? 0
                
                // Get result year
                var resultYear: String? = nil
                if let published = item["published"] as? [String: Any],
                   let dateParts = published["date-parts"] as? [[Int]],
                   let firstDate = dateParts.first,
                   let year = firstDate.first {
                    resultYear = String(year)
                } else if let issued = item["issued"] as? [String: Any],
                          let dateParts = issued["date-parts"] as? [[Int]],
                          let firstDate = dateParts.first,
                          let year = firstDate.first {
                    resultYear = String(year)
                }
                
                // Get result author
                var resultAuthor: String? = nil
                if let authors = item["author"] as? [[String: Any]],
                   let first = authors.first,
                   let family = first["family"] as? String {
                    resultAuthor = family.lowercased()
                }
                
                // Debug: show comparison values
                print("DEBUG - Comparing: refYear=\(refYear ?? "nil") vs resultYear=\(resultYear ?? "nil"), refAuthor=\(refAuthor ?? "nil") vs resultAuthor=\(resultAuthor ?? "nil")")
                
                // Validate: if we have year in reference, result year MUST match
                var yearMatches = false
                var authorMatches = false
                
                if let ry = refYear, let resY = resultYear {
                    yearMatches = (ry == resY)
                } else if refYear == nil {
                    yearMatches = true
                }
                
                if let ra = refAuthor, let resA = resultAuthor {
                    authorMatches = (ra == resA || resA.hasPrefix(ra) || ra.hasPrefix(resA))
                }
                
                // Only accept if year matches AND (author matches OR score is very high)
                let isValid = yearMatches && (authorMatches || score > 100)

                
                if isValid {
                    print("DEBUG - CrossRef match: year=\(resultYear ?? "nil"), author=\(resultAuthor ?? "nil"), score=\(score)")
                    return buildBibTeXFromJSON(item)
                }
            }
            
            print("DEBUG - No valid CrossRef match found for: \(refText.prefix(40))...")
        }
    } catch {
        print("DEBUG - CrossRef error: \(error)")
    }
    
    return nil
}

/// Query OpenAlex API as fallback
private func queryOpenAlex(_ refText: String) async -> String? {
    // Extract key terms for search
    let queryText = String(refText.prefix(150))
        .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
    
    guard !queryText.isEmpty else { return nil }
    
    let urlString = "https://api.openalex.org/works?search=\(queryText)&per_page=3"
    guard let url = URL(string: urlString) else { return nil }
    
    var request = URLRequest(url: url)
    request.setValue("GhostPDF/1.0", forHTTPHeaderField: "User-Agent")
    
    do {
        let (data, _) = try await URLSession.shared.data(for: request)
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let results = json["results"] as? [[String: Any]] {
            
            // Extract year from reference for validation
            var refYear: String? = nil
            if let yearMatch = refText.range(of: #"\b(19|20)\d{2}\b"#, options: .regularExpression) {
                refYear = String(refText[yearMatch])
            }
            
            for item in results {
                // Get result year
                let resultYear = item["publication_year"] as? Int
                
                // Validate year if present
                if let ry = refYear, let resY = resultYear {
                    if ry != String(resY) {
                        continue // Skip if year doesn't match
                    }
                }
                
                // Build BibTeX from OpenAlex result
                return buildBibTeXFromOpenAlex(item)
            }
        }
    } catch {
        print("DEBUG - OpenAlex error: \(error)")
    }
    
    return nil
}

/// Build BibTeX from OpenAlex JSON response
private func buildBibTeXFromOpenAlex(_ item: [String: Any]) -> String? {
    // Extract title
    let title = item["title"] as? String ?? ""
    guard !title.isEmpty else { return nil }
    
    // Extract year
    let year = item["publication_year"] as? Int ?? 0
    
    // Extract authors
    var authors: [String] = []
    if let authorships = item["authorships"] as? [[String: Any]] {
        for authorship in authorships {
            if let author = authorship["author"] as? [String: Any],
               let name = author["display_name"] as? String {
                authors.append(name)
            }
        }
    }
    
    // Extract journal/venue
    var journal = ""
    if let primaryLocation = item["primary_location"] as? [String: Any],
       let source = primaryLocation["source"] as? [String: Any],
       let displayName = source["display_name"] as? String {
        journal = displayName
    }
    
    // Extract DOI
    var doi = ""
    if let doiUrl = item["doi"] as? String {
        doi = doiUrl.replacingOccurrences(of: "https://doi.org/", with: "")
    }
    
    // Determine type
    let type = item["type"] as? String ?? "article"
    let bibType = type.contains("book") ? "book" : "article"
    
    // Build citation key
    let firstAuthor = authors.first?.components(separatedBy: " ").last ?? "Unknown"
    let key = "\(firstAuthor)\(year)"
    
    // Build BibTeX
    var bib = "@\(bibType){\(key),\n"
    bib += "    author = {\(authors.joined(separator: " and "))},\n"
    bib += "    title = {\(title)},\n"
    bib += "    year = {\(year)}"
    
    if !journal.isEmpty { bib += ",\n    journal = {\(journal)}" }
    if !doi.isEmpty { bib += ",\n    doi = {\(doi)}" }
    
    bib += "\n}"
    
    return bib
}

/// Query Semantic Scholar API as fallback
private func querySemanticScholar(_ refText: String) async -> String? {
    print("DEBUG - Trying Semantic Scholar...")
    
    var cleanedText = String(refText.prefix(150))
    cleanedText = cleanedText
        .replacingOccurrences(of: "—", with: "-")
        .replacingOccurrences(of: "–", with: "-")
    
    let queryText = cleanedText
        .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
    
    guard !queryText.isEmpty else { 
        print("DEBUG - SemanticScholar: empty query")
        return nil 
    }
    
    let urlString = "https://api.semanticscholar.org/graph/v1/paper/search?query=\(queryText)&limit=5&fields=title,authors,year,venue,externalIds"
    guard let url = URL(string: urlString) else { 
        print("DEBUG - SemanticScholar: invalid URL")
        return nil 
    }
    
    var request = URLRequest(url: url)
    request.setValue("GhostPDF/1.0", forHTTPHeaderField: "User-Agent")
    
    do {
        let (data, _) = try await URLSession.shared.data(for: request)
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let results = json["data"] as? [[String: Any]] {
            print("DEBUG - SemanticScholar: got \(results.count) results")

            
            var refYear: String? = nil
            if let yearMatch = refText.range(of: #"\b(19|20)\d{2}\b"#, options: .regularExpression) {
                refYear = String(refText[yearMatch])
            }
            
            var refAuthor: String? = nil
            if let firstWord = refText.components(separatedBy: CharacterSet.alphanumerics.inverted).first,
               firstWord.count >= 3, firstWord.first?.isUppercase == true {
                refAuthor = firstWord.lowercased()
            }
            
            for item in results {
                let resultYear = item["year"] as? Int
                var resultAuthor: String? = nil
                if let authors = item["authors"] as? [[String: Any]],
                   let first = authors.first,
                   let name = first["name"] as? String {
                    resultAuthor = name.components(separatedBy: " ").last?.lowercased()
                }
                
                var yearMatches = (refYear == nil)
                if let ry = refYear, let resY = resultYear {
                    yearMatches = (ry == String(resY))
                }
                
                var authorMatches = false
                if let ra = refAuthor, let resA = resultAuthor {
                    authorMatches = (ra == resA || resA.hasPrefix(ra) || ra.hasPrefix(resA))
                }
                
                if yearMatches && authorMatches {
                    return buildBibTeXFromSemanticScholar(item)
                }
            }
        }
    } catch {
        print("DEBUG - SemanticScholar error: \(error)")
    }
    return nil
}

/// Build BibTeX from Semantic Scholar JSON
private func buildBibTeXFromSemanticScholar(_ item: [String: Any]) -> String? {
    let title = item["title"] as? String ?? ""
    guard !title.isEmpty else { return nil }
    
    let year = item["year"] as? Int ?? 0
    let venue = item["venue"] as? String ?? ""
    
    var authors: [String] = []
    if let authorList = item["authors"] as? [[String: Any]] {
        for author in authorList {
            if let name = author["name"] as? String { authors.append(name) }
        }
    }
    
    var doi = ""
    if let externalIds = item["externalIds"] as? [String: Any],
       let doiValue = externalIds["DOI"] as? String { doi = doiValue }
    
    let firstAuthor = authors.first?.components(separatedBy: " ").last ?? "Unknown"
    let key = "\(firstAuthor)\(year)"
    
    var bib = "@article{\(key),\n"
    bib += "    author = {\(authors.joined(separator: " and "))},\n"
    bib += "    title = {\(title)},\n"
    bib += "    year = {\(year)}"
    if !venue.isEmpty { bib += ",\n    journal = {\(venue)}" }
    if !doi.isEmpty { bib += ",\n    doi = {\(doi)}" }
    bib += "\n}"
    return bib
}

/// Build clean BibTeX from CrossRef JSON response

private func buildBibTeXFromJSON(_ item: [String: Any]) -> String? {
    // Extract title (clean, no MathML)
    var title = ""
    if let titles = item["title"] as? [String], let firstTitle = titles.first {
        // Strip any HTML/XML tags
        title = firstTitle.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
    }
    
    // Extract authors
    var authors: [String] = []
    if let authorList = item["author"] as? [[String: Any]] {
        for author in authorList {
            let family = author["family"] as? String ?? ""
            let given = author["given"] as? String ?? ""
            if !family.isEmpty {
                authors.append("\(given) \(family)".trimmingCharacters(in: .whitespaces))
            }
        }
    }
    
    // Extract year
    var year = ""
    if let published = item["published"] as? [String: Any],
       let dateParts = published["date-parts"] as? [[Int]],
       let firstDate = dateParts.first,
       let firstYear = firstDate.first {
        year = String(firstYear)
    } else if let issued = item["issued"] as? [String: Any],
              let dateParts = issued["date-parts"] as? [[Int]],
              let firstDate = dateParts.first,
              let firstYear = firstDate.first {
        year = String(firstYear)
    }
    
    // Extract journal
    var journal = ""
    if let containerTitle = item["container-title"] as? [String], let first = containerTitle.first {
        journal = first
    }
    
    // Extract other fields
    let doi = item["DOI"] as? String ?? ""
    let volume = item["volume"] as? String ?? ""
    let issue = item["issue"] as? String ?? ""
    let page = item["page"] as? String ?? ""
    
    // Determine entry type
    let type = item["type"] as? String ?? "article"
    let bibType = type.contains("book") ? "book" : "article"
    
    // Build citation key
    let firstAuthor = authors.first?.components(separatedBy: " ").last ?? "Unknown"
    let key = "\(firstAuthor)\(year)"
    
    // Build BibTeX
    var bib = "@\(bibType){\(key),\n"
    bib += "    author = {\(authors.joined(separator: " and "))},\n"
    bib += "    title = {\(title)},\n"
    bib += "    year = {\(year)}"
    
    if !journal.isEmpty { bib += ",\n    journal = {\(journal)}" }
    if !volume.isEmpty { bib += ",\n    volume = {\(volume)}" }
    if !issue.isEmpty { bib += ",\n    number = {\(issue)}" }
    if !page.isEmpty { bib += ",\n    pages = {\(page)}" }
    if !doi.isEmpty { bib += ",\n    doi = {\(doi)}" }
    
    bib += "\n}"
    
    return bib
}

/// Parse reference text to extract metadata
private func parseReferenceText(_ text: String) -> (authors: String, title: String, journal: String?, year: String?)? {
    // Remove numbering
    var cleaned = text.replacingOccurrences(of: #"^\[\d+\]|\d+\."#, with: "", options: .regularExpression)
        .trimmingCharacters(in: .whitespaces)
    
    // Extract year using regex
    var year: String? = nil
    if let yearMatch = cleaned.range(of: #"\((\d{4})\)|\b(19|20)\d{2}\b"#, options: .regularExpression) {
        year = String(cleaned[yearMatch]).filter { $0.isNumber }
    }
    
    // Use Apple NaturalLanguage framework for entity recognition
    let tagger = NLTagger(tagSchemes: [.nameType])
    tagger.string = cleaned
    
    var personNames: [String] = []
    var organizations: [String] = []
    
    // Extract named entities
    tagger.enumerateTags(in: cleaned.startIndex..<cleaned.endIndex, unit: .word, scheme: .nameType) { tag, range in
        if let tag = tag {
            let entity = String(cleaned[range])
            switch tag {
            case .personalName:
                personNames.append(entity)
            case .organizationName:
                organizations.append(entity)
            default:
                break
            }
        }
        return true
    }
    
    // Build authors from detected person names
    var authors = personNames.prefix(6).joined(separator: " ")
    
    // Fallback to traditional parsing if NL didn't find names
    if authors.isEmpty {
        let parts = cleaned.components(separatedBy: ".").map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count >= 1 {
            authors = parts[0]
        }
    }
    
    // Extract title - usually in quotes or after author section
    var title = ""
    if let quoteMatch = cleaned.range(of: #""[^"]+""#, options: .regularExpression) {
        title = String(cleaned[quoteMatch]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    } else {
        // Fall back to period-based splitting
        let parts = cleaned.components(separatedBy: ".").map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count > 1 {
            title = parts[1]
        }
    }
    
    // Journal might be in organizations or third part
    var journal: String? = organizations.first
    if journal == nil {
        let parts = cleaned.components(separatedBy: ".").map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count > 2 {
            journal = parts[2]
        }
    }
    
    guard !authors.isEmpty || !title.isEmpty else { return nil }
    
    return (authors: authors, title: title, journal: journal, year: year)
}

/// Query CrossRef API using metadata
private func queryWithBibTeXFromMetadata(_ metadata: (authors: String, title: String, journal: String?, year: String?)) async -> String? {
    // Build query using bibliographic query for best results
    var queryParts: [String] = []
    
    // Add author (first author surname is most useful)
    if !metadata.authors.isEmpty {
        let firstAuthor = metadata.authors.components(separatedBy: " ").first ?? metadata.authors
        queryParts.append(firstAuthor)
    }
    
    // Add title keywords (first 5 significant words)
    if !metadata.title.isEmpty {
        let titleWords = metadata.title.components(separatedBy: " ")
            .filter { $0.count > 3 }
            .prefix(5)
            .joined(separator: " ")
        queryParts.append(titleWords)
    }
    
    // Add year
    if let year = metadata.year {
        queryParts.append(year)
    }
    
    // Add journal if available
    if let journal = metadata.journal, !journal.isEmpty {
        queryParts.append(journal.prefix(20).description)
    }
    
    let query = queryParts.joined(separator: " ")
        .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
    
    guard !query.isEmpty else { return nil }
    
    let urlString = "https://api.crossref.org/works?query.bibliographic=\(query)&rows=1"
    guard let url = URL(string: urlString) else { return nil }
    
    var request = URLRequest(url: url)
    request.setValue("GhostPDF/1.0", forHTTPHeaderField: "User-Agent")
    
    do {
        let (data, _) = try await URLSession.shared.data(for: request)
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = json["message"] as? [String: Any],
           let items = message["items"] as? [[String: Any]],
           let first = items.first,
           let doi = first["DOI"] as? String {
            return await fetchBibTeXFromCrossRef(doi: doi)
        }
    } catch {
        print("DEBUG - CrossRef query error: \(error)")
    }
    
    return nil
}

/// Construct basic BibTeX from parsed data
private func constructBibTeXFromParsed(_ metadata: (authors: String, title: String, journal: String?, year: String?)) -> String {
    let key = (metadata.authors.components(separatedBy: " ").first ?? "ref") + (metadata.year ?? "")
    var bib = "@article{\(key),\n"
    bib += "    author = {\(metadata.authors)},\n"
    bib += "    title = {\(metadata.title)}"
    if let year = metadata.year {
        bib += ",\n    year = {\(year)}"
    }
    if let journal = metadata.journal {
        bib += ",\n    journal = {\(journal)}"
    }
    bib += ",\n    note = {Extracted from references, verification failed}\n"
    bib += "}"
    return bib
}

/// Fetch BibTeX from CrossRef API for a given DOI
private func fetchBibTeXFromCrossRef(doi: String) async -> String? {
    let urlString = "https://api.crossref.org/works/\(doi)/transform/application/x-bibtex"
    guard let url = URL(string: urlString) else { return nil }
    
    var request = URLRequest(url: url)
    request.setValue("application/x-bibtex", forHTTPHeaderField: "Accept")
    request.setValue("GhostPDF/1.0 (mailto:user@example.com)", forHTTPHeaderField: "User-Agent")
    
    do {
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            print("DEBUG - CrossRef API returned error for DOI: \(doi)")
            return nil
        }
        
        if let bibtex = String(data: data, encoding: .utf8) {
            return bibtex.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    } catch {
        print("DEBUG - Network error fetching DOI \(doi): \(error)")
    }
    
    return nil
}

