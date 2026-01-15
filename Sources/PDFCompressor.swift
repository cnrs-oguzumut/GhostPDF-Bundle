import Foundation
import PDFKit
import Quartz
import UniformTypeIdentifiers
import CoreGraphics
import ImageIO
import NaturalLanguage
import FoundationModels
import Vision

// MARK: - AI-Powered Metadata Extraction Models

@available(macOS 26.0, *)
@Generable
struct AIExtractedMetadata {
    @Guide(description: "The full title of the academic paper, exactly as it appears in the document.")
    let title: String

    @Guide(description: "List of all authors in order, with full names. Format: 'FirstName LastName' or 'F. LastName'")
    let authors: [String]

    @Guide(description: "The journal, conference, or publisher name where this was published. If unknown, return 'Unknown'.")
    let journal: String

    @Guide(description: "The publication year as a 4-digit number. If unknown, return current year.")
    let year: Int

    @Guide(description: "The volume number if available, empty string if unknown.")
    let volume: String

    @Guide(description: "The issue or number if available, empty string if unknown.")
    let number: String

    @Guide(description: "The page range (e.g., '123-145') if available, empty string if unknown.")
    let pages: String

    @Guide(description: "The DOI if found in the document (e.g., '10.1103/PhysRevB.99.014406'), empty string if not found.")
    let doi: String

    @Guide(description: "The document type: 'article' for journal papers, 'inproceedings' for conferences, 'book', 'phdthesis', 'misc'. Default to 'article'.")
    let documentType: String
}

// MARK: - AI-Powered Grammar Checking Models

@available(macOS 26.0, *)
@Generable
struct GrammarCorrection {
    @Guide(description: "The original text snippet containing the error. Must be exact text from the document.")
    let original: String

    @Guide(description: "The corrected version of the text. Must be different from original.")
    let suggested: String

    @Guide(description: "Brief explanation of what type of error this is (e.g., 'spelling', 'grammar', 'merged words', 'punctuation').")
    let errorType: String
}

@available(macOS 26.0, *)
@Generable
struct GrammarCheckResult {
    @Guide(description: "List of all grammar corrections found in the text. If no errors found, return an empty array.")
    let corrections: [GrammarCorrection]
}

// MARK: - Multi-Document Intelligence Models

@available(macOS 26.0, *)
@Generable
struct DocumentContribution {
    @Guide(description: "The filename of the PDF (e.g., 'paper_a.pdf')")
    let fileName: String

    @Guide(description: "What this specific document says about the question, or 'Not applicable' if it doesn't address the question")
    let insight: String
}

@available(macOS 26.0, *)
@Generable
struct MultiDocAnswer {
    @Guide(description: "The main answer synthesizing information from all documents. Be comprehensive and cite which papers support each point.")
    let answer: String

    @Guide(description: "List of document filenames that contributed to this answer")
    let sources: [String]

    @Guide(description: "Per-document insights showing what each paper specifically says")
    let documentContributions: [DocumentContribution]
}

/// Extract metadata from PDF text using Apple Foundation Models (macOS 26+)
@available(macOS 26.0, *)
func extractMetadataWithAI(from text: String) async -> AIExtractedMetadata? {
    do {
        // Limit text to first ~6000 chars (first 2-3 pages typically have all metadata)
        let limitedText = String(text.prefix(6000))
        
        let prompt = """
        Extract bibliographic metadata from this academic paper text.
        Focus on the first page header, title, author list, and journal citation line.
        Look for DOI patterns like "10.xxxx/..." and publication details.
        
        Document text:
        \(limitedText)
        """
        
        print("DEBUG - extractMetadataWithAI: Creating session...")
        let session = LanguageModelSession()
        print("DEBUG - extractMetadataWithAI: Calling respond with structured output...")
        let response = try await session.respond(to: prompt, generating: AIExtractedMetadata.self)
        print("DEBUG - extractMetadataWithAI: Success! Got structured metadata.")
        
        return response.content
    } catch {
        print("AI metadata extraction failed: \(error)")
        return nil
    }
}

/// Build BibTeX entry from AI-extracted metadata
@available(macOS 26.0, *)
func buildBibTeXFromAIMetadata(_ meta: AIExtractedMetadata, fallbackDOI: String, options: BibTeXFormatOptions, sourceURL: URL) -> String {
    // Format authors for BibTeX
    var authorsForBib: String
    if meta.authors.isEmpty {
        authorsForBib = "Unknown Author"
    } else if options.shortenAuthors {
        // Use formatAuthorName on each author and join with "and"
        authorsForBib = meta.authors.map { formatAuthorName($0) }.joined(separator: " and ")
    } else {
        authorsForBib = meta.authors.joined(separator: " and ")
    }
    
    // Use AI-extracted DOI or fallback
    let doi = meta.doi.isEmpty ? fallbackDOI : meta.doi
    
    // Format journal if needed
    var journalForBib = meta.journal
    if options.abbreviateJournals {
        journalForBib = formatJournalName(journalForBib)
    }
    
    // Generate citation key
    let authorLast = meta.authors.first?.components(separatedBy: " ").last?.filter { $0.isLetter } ?? "Author"
    let titleFirst = meta.title.components(separatedBy: " ").filter { $0.count > 3 }.first?.filter { $0.isLetter } ?? "Title"
    let cleanAuthorKey = authorLast.folding(options: .diacriticInsensitive, locale: .current)
    let cleanTitleKey = titleFirst.folding(options: .diacriticInsensitive, locale: .current)
    let citeKey = "\(cleanAuthorKey)\(meta.year)\(cleanTitleKey)".lowercased()
    
    // Build BibTeX entry
    let docType = meta.documentType.isEmpty ? "article" : meta.documentType
    var bib = "@\(docType){\(citeKey),\n"
    bib += "    author = {\(options.useLaTeXEscaping ? latexEscaped(authorsForBib) : authorsForBib)},\n"
    bib += "    title = {\(options.useLaTeXEscaping ? latexEscaped(meta.title) : meta.title)},\n"
    bib += "    year = {\(meta.year)},\n"
    bib += "    journal = {\(options.useLaTeXEscaping ? latexEscaped(journalForBib) : journalForBib)}"
    
    if !meta.volume.isEmpty { bib += ",\n    volume = {\(meta.volume)}" }
    if !meta.number.isEmpty { bib += ",\n    number = {\(meta.number)}" }
    if !meta.pages.isEmpty { bib += ",\n    pages = {\(meta.pages)}" }
    if !doi.isEmpty { bib += ",\n    doi = {\(doi)}" }
    
    bib += ",\n    note = {Extracted from \(sourceURL.lastPathComponent) by GhostPDF (AI)}\n"
    bib += "}"
    
    return bib
}

// MARK: - AI-Powered Reference Extraction

/// Struct for a single extracted reference
@available(macOS 26.0, *)
@Generable
struct AIExtractedReference {
    @Guide(description: "List of author names for this reference. Format: 'FirstName LastName' or 'F. LastName'")
    let authors: [String]
    
    @Guide(description: "The title of the referenced work.")
    let title: String
    
    @Guide(description: "The journal, conference, or book name.")
    let journal: String
    
    @Guide(description: "The publication year as a 4-digit number.")
    let year: Int
    
    @Guide(description: "The volume number if available, empty string otherwise.")
    let volume: String
    
    @Guide(description: "The page range (e.g., '123-145') if available, empty string otherwise.")
    let pages: String
    
    @Guide(description: "The DOI if present in the reference, empty string otherwise.")
    let doi: String
}

/// Container for multiple references extracted by AI
@available(macOS 26.0, *)
@Generable
struct AIExtractedReferences {
    @Guide(description: "List of all bibliographic references extracted from the text. Each reference should be parsed into its components.")
    let references: [AIExtractedReference]
}

/// Extract references from PDF text using Apple Foundation Models (macOS 26+)
@available(macOS 26.0, *)
func extractReferencesWithAI(from text: String, options: BibTeXFormatOptions) async -> [String]? {
    do {
        // Limit text - references section is usually at the end
        // Take last 15000 chars to capture references section
        let limitedText: String
        if text.count > 15000 {
            limitedText = String(text.suffix(15000))
        } else {
            limitedText = text
        }
        
        let prompt = """
        Extract all bibliographic references from this academic paper text.
        The references section is usually at the end of the paper.
        Parse each reference into its components: authors, title, journal, year, volume, pages, and DOI.
        
        Document text:
        \(limitedText)
        """
        
        print("DEBUG - extractReferencesWithAI: Creating session...")
        let session = LanguageModelSession()
        print("DEBUG - extractReferencesWithAI: Calling respond with structured output...")
        let response = try await session.respond(to: prompt, generating: AIExtractedReferences.self)
        print("DEBUG - extractReferencesWithAI: Success! Got \(response.content.references.count) references.")
        
        // Convert to BibTeX format
        var bibTexEntries: [String] = []
        for (index, ref) in response.content.references.enumerated() {
            let bib = formatReferenceToBibTeX(ref, index: index + 1, options: options)
            bibTexEntries.append(bib)
        }
        
        return bibTexEntries
    } catch {
        print("AI reference extraction failed: \(error)")
        return nil
    }
}

/// Format a single AI-extracted reference to BibTeX
@available(macOS 26.0, *)
private func formatReferenceToBibTeX(_ ref: AIExtractedReference, index: Int, options: BibTeXFormatOptions) -> String {
    // Format authors
    var authorsForBib: String
    if ref.authors.isEmpty {
        authorsForBib = "Unknown Author"
    } else if options.shortenAuthors {
        authorsForBib = ref.authors.map { formatAuthorName($0) }.joined(separator: " and ")
    } else {
        authorsForBib = ref.authors.joined(separator: " and ")
    }
    
    // Format journal if needed
    var journalForBib = ref.journal
    if options.abbreviateJournals {
        journalForBib = formatJournalName(journalForBib)
    }
    
    // Generate citation key
    let authorLast = ref.authors.first?.components(separatedBy: " ").last?.filter { $0.isLetter } ?? "ref"
    let cleanAuthorKey = authorLast.folding(options: .diacriticInsensitive, locale: .current).lowercased()
    let citeKey = "\(cleanAuthorKey)\(ref.year)ref\(index)"
    
    // Build BibTeX entry
    var bib = "@article{\(citeKey),\n"
    bib += "    author = {\(options.useLaTeXEscaping ? latexEscaped(authorsForBib) : authorsForBib)},\n"
    bib += "    title = {\(options.useLaTeXEscaping ? latexEscaped(ref.title) : ref.title)},\n"
    bib += "    year = {\(ref.year)},\n"
    bib += "    journal = {\(options.useLaTeXEscaping ? latexEscaped(journalForBib) : journalForBib)}"
    
    if !ref.volume.isEmpty { bib += ",\n    volume = {\(ref.volume)}" }
    if !ref.pages.isEmpty { bib += ",\n    pages = {\(ref.pages)}" }
    if !ref.doi.isEmpty { bib += ",\n    doi = {\(ref.doi)}" }
    
    bib += "\n}"
    
    return bib
}

// MARK: - AI-Powered Caption Extraction

/// Struct for a single extracted figure/table caption
@available(macOS 26.0, *)
@Generable
struct AIExtractedCaption {
    @Guide(description: "The type of the item: 'Figure', 'Table', 'Scheme', or 'Chart'.")
    let type: String
    
    @Guide(description: "The number or identifier (e.g., '1', '2a', 'IV').")
    let number: String
    
    @Guide(description: "The full text of the caption/description.")
    let text: String
    
    @Guide(description: "The page number where this caption appears (if inferable from text context), otherwise 0.")
    let page: Int
}

/// Container for multiple captions extracted by AI
@available(macOS 26.0, *)
@Generable
struct AIExtractedCaptions {
    @Guide(description: "List of all figure and table captions found in the text.")
    let captions: [AIExtractedCaption]
}

/// Extract figure/table captions from PDF text using Apple Foundation Models (macOS 26+)
@available(macOS 26.0, *)
@available(macOS 26.0, *)
func extractCaptionsWithAI(from text: String) async -> [AIExtractedCaption]? {
    do {
        // Captions can be anywhere, but context window is limited.
        // We'll take a large chunk from the beginning and maybe some from end?
        // Actually, for captions, simpler is better: take as much as fits.
        let limitedText: String
        if text.count > 25000 {
            limitedText = String(text.prefix(25000))
        } else {
            limitedText = text
        }
        
        let prompt = """
        Extract all Figure and Table captions from this academic paper text.
        Look for patterns like "Figure 1: ...", "Fig. 2.", "Table 1 ...".
        Extract the full caption text for each.
        
        Document text:
        \(limitedText)
        """
        
        print("DEBUG - extractCaptionsWithAI: Creating session...")
        let session = LanguageModelSession()
        print("DEBUG - extractCaptionsWithAI: Calling respond with structured output...")
        let response = try await session.respond(to: prompt, generating: AIExtractedCaptions.self)
        print("DEBUG - extractCaptionsWithAI: Success! Got \(response.content.captions.count) captions.")
        
        return response.content.captions
    } catch {
        print("AI caption extraction failed: \(error)")
        return nil
    }
}

// MARK: - AI Question Answering

/// Answer a user question based on the provided PDF context using Apple Foundation Models
@available(macOS 26.0, *)
func answerQuestionWithAI(question: String, context: String) async throws -> String {
    // Limit context to avoid token limits (conservatively ~20k chars)
    let limitedContext: String
    if context.count > 25000 {
        // Prioritize the beginning and potentially search for keywords? 
        // For now, just truncating to safe limit.
        limitedContext = String(context.prefix(25000)) + "\n...(truncated)..."
    } else {
        limitedContext = context
    }
    
    let prompt = """
    You are a helpful academic assistant analyzing a PDF document.
    Answer the user's question based ONLY on the provided document context below.
    If the answer is not in the context, say "I cannot find the answer in the document."
    Keep your answer concise and relevant.

    Document Context:
    \(limitedContext)

    User Question:
    \(question)
    """
    
    let session = LanguageModelSession()
    let response = try await session.respond(to: prompt)
    return response.content
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
/// Extract text from PDF using Ghostscript (more robust spacing)
func extractTextWithGS(url: URL, pageIndex: Int? = nil) async -> String? {
    guard let gsPath = PDFCompressor.findGhostscript() else { return nil }
    
    let fileManager = FileManager.default
    let tempOutputPath = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
    
    var arguments = [
        "-q",
        "-dNOPAUSE",
        "-dBATCH",
        "-sDEVICE=txtwrite",
        "-sOutputFile=\(tempOutputPath.path)"
    ]
    
    if let page = pageIndex {
        arguments.append("-dFirstPage=\(page + 1)")
        arguments.append("-dLastPage=\(page + 1)")
    }
    
    arguments.append(url.path)
    
    let task = Process()
    task.executableURL = URL(fileURLWithPath: gsPath)
    task.arguments = arguments

    // Capture stderr for debugging
    let errorPipe = Pipe()
    task.standardError = errorPipe

    do {
        try task.run()
        task.waitUntilExit()

        if task.terminationStatus == 0 && fileManager.fileExists(atPath: tempOutputPath.path) {
            // Check if file is empty
            let attributes = try? fileManager.attributesOfItem(atPath: tempOutputPath.path)
            let fileSize = attributes?[.size] as? Int ?? 0

            if fileSize == 0 {
                try? fileManager.removeItem(at: tempOutputPath)
                return nil
            }

            // Read file and try multiple encodings
            if let data = try? Data(contentsOf: tempOutputPath) {
                // Try multiple encodings - Ghostscript often outputs ISO-8859-1
                let encodings: [String.Encoding] = [
                    .utf8,
                    .isoLatin1,        // ISO-8859-1 (most common for GS)
                    .windowsCP1252,
                    .ascii,
                    .macOSRoman,
                    .utf16
                ]

                for encoding in encodings {
                    if let extractedText = String(data: data, encoding: encoding) {
                        try? fileManager.removeItem(at: tempOutputPath)
                        return extractedText
                    }
                }
            }
        }
    } catch {
        print("Ghostscript text extraction failed: \(error)")
    }

    try? fileManager.removeItem(at: tempOutputPath)
    return nil
}

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

/// Options for BibTeX formatting
struct BibTeXFormatOptions {
    var shortenAuthors: Bool = false
    var abbreviateJournals: Bool = false
    var useLaTeXEscaping: Bool = false
    var addDotsToInitials: Bool = true // Default to true (Gong, L.)
    var addDotsToJournals: Bool = true // Default to true (Phys. Rev. Lett.)
    var processAuthors: Bool = true // Guard to skip author processing entirely
}

/// Extract BibTeX metadata from PDF with optional online lookup
func extractBibTeX(url: URL, allowOnline: Bool = false, options: BibTeXFormatOptions = BibTeXFormatOptions()) async -> String? {
    guard let doc = PDFDocument(url: url) else { return nil }

    // First, try to extract DOI using unified logic
    var doi = await findDOI(in: doc, allowOnline: allowOnline) ?? ""
    var arxivID = ""
    
    // Extract arXiv ID locally
    if let firstPage = doc.page(at: 0), let text = firstPage.string {
        // Extract arXiv ID (formats: arXiv:YYMM.NNNNN or just YYMM.NNNNN)
        let arxivPattern = #"(?:arXiv:)?(\d{4}\.\d{4,5}(?:v\d+)?)"#
        if let range = text.range(of: arxivPattern, options: [.regularExpression, .caseInsensitive]) {
            var match = String(text[range])
            // Clean up to get just the ID
            match = match.replacingOccurrences(of: "arXiv:", with: "", options: .caseInsensitive)
            arxivID = match.trimmingCharacters(in: .whitespaces)
            print("DEBUG - Found arXiv ID: \(arxivID)")
        }
    }

    // If online lookup is allowed and we have an arXiv ID, try arXiv first
    if !arxivID.isEmpty && allowOnline {
        print("DEBUG - Attempting to fetch BibTeX from arXiv for ID: \(arxivID)")
        if let arxivBib = await fetchBibTeXFromArXiv(arxivID) {
            print("DEBUG - Successfully fetched BibTeX from arXiv!")
            print("DEBUG - Original arXiv BibTeX:\n\(arxivBib)")
            
            // For arXiv entries, apply formatting but ensure arXiv fields are preserved
            // reformatBibTeX might strip arXiv-specific fields, so we apply formatting carefully
            var formattedBib = reformatBibTeX(arxivBib, options: options)
            print("DEBUG - After reformatBibTeX:\n\(formattedBib)")
            
            // Ensure arXiv fields are still present (they might have been stripped)
            if !formattedBib.contains("eprint") && arxivBib.contains("eprint") {
                print("DEBUG - eprint field was stripped! Attempting to restore...")
                // Extract and re-add arXiv fields
                if let eprintRange = arxivBib.range(of: #"eprint\s*=\s*\{[^}]+\}"#, options: .regularExpression),
                   let archiveRange = arxivBib.range(of: #"archivePrefix\s*=\s*\{[^}]+\}"#, options: .regularExpression),
                   let primaryRange = arxivBib.range(of: #"primaryClass\s*=\s*\{[^}]+\}"#, options: .regularExpression) {
                    
                    let eprint = String(arxivBib[eprintRange])
                    let archive = String(arxivBib[archiveRange])
                    let primary = String(arxivBib[primaryRange])
                    
                    print("DEBUG - Extracted fields: \(eprint), \(archive), \(primary)")
                    
                    // Insert before the closing brace
                    if let closingBrace = formattedBib.range(of: "}", options: .backwards) {
                        let insertFields = ",\n  \(eprint),\n  \(archive),\n  \(primary)\n"
                        formattedBib.insert(contentsOf: insertFields, at: closingBrace.lowerBound)
                        print("DEBUG - Restored arXiv fields!")
                    }
                } else {
                    print("DEBUG - Failed to extract arXiv fields from original BibTeX")
                }
            } else {
                print("DEBUG - eprint field preserved through reformatting")
            }
            
            print("DEBUG - Final BibTeX:\n\(formattedBib)")
            return formattedBib
        } else {
            print("DEBUG - Failed to fetch BibTeX from arXiv, will try other methods")
        }
    }

    // If online lookup is allowed and we have a DOI, try fetching authoritative BibTeX from CrossRef
    if !doi.isEmpty && allowOnline {
        print("DEBUG - Found DOI: \(doi). Attempting direct CrossRef fetch...")
        
        if let onlineBib = await fetchBibTeXFromCrossRef(doi: doi) {
            print("DEBUG - Successfully fetched BibTeX from CrossRef via DOI.")
            // Apply formatting options (clean up, shorten authors, etc.)
            // We use reformatBibTeX to ensure the output matches user preferences
            let formattedBib = reformatBibTeX(onlineBib, options: options)
            return formattedBib
        } else {
            print("DEBUG - Failed to fetch BibTeX from CrossRef. Falling back to offline extraction.")
        }
    }

    // Fallback: Offline extraction with AI-first approach
    // If we are here, either offline mode is on, no DOI found, or CrossRef failed.
    
    // Try AI-powered extraction first (macOS 26+)
    if #available(macOS 26.0, *) {
        // Extract text from first few pages for AI analysis
        var headerText = ""
        for i in 0..<min(3, doc.pageCount) {
            if let page = doc.page(at: i), let pageText = page.string {
                headerText += pageText + "\n\n"
            }
        }
        
        if !headerText.isEmpty {
            print("DEBUG - Attempting AI-powered metadata extraction for BibTeX...")
            if let aiMetadata = await extractMetadataWithAI(from: headerText) {
                print("DEBUG - AI extraction successful! Building BibTeX from AI metadata.")
                let aiBib = buildBibTeXFromAIMetadata(aiMetadata, fallbackDOI: doi, options: options, sourceURL: url)
                return reformatBibTeX(aiBib, options: options)
            } else {
                print("DEBUG - AI extraction failed, falling back to heuristic extraction.")
            }
        }
    } else {
        print("DEBUG - macOS < 26, using heuristic extraction for BibTeX")
    }
    
    // Fallback: Heuristic-based offline extraction
    let offlineBib = extractBibTeXOffline(url: url, doc: doc, extractedDOI: doi, options: options)
    
    // Proceed to fallback chain

    // Fallback chain when no DOI or CrossRef failed - try title-based searches
    if allowOnline {
        // Get title from PDF metadata
        var searchTitle: String? = nil
        if let attrs = doc.documentAttributes, let title = attrs[PDFDocumentAttribute.titleAttribute] as? String, !title.isEmpty {
            searchTitle = title
        }
        
        if let title = searchTitle {
            // Try Semantic Scholar
            print("DEBUG - extractBibTeX: Trying Semantic Scholar for title: '\(title)'")
            if let ssBib = await querySemanticScholar(title, originalContext: nil, options: options) {
                return reformatBibTeX(ssBib, options: options)
            }
            
            // Try OpenLibrary (for books)
            print("DEBUG - extractBibTeX: Trying OpenLibrary for title: '\(title)'")
            if let olBib = await queryOpenLibrary(title, options: options) {
                return reformatBibTeX(olBib, options: options)
            }
        }
    }

    if let off = offlineBib {
        return reformatBibTeX(off, options: options)
    }
    return nil
}

/// Extract BibTeX metadata from PDF (offline version)
private func extractBibTeXOffline(url: URL, doc: PDFDocument, extractedDOI: String, options: BibTeXFormatOptions = BibTeXFormatOptions()) -> String? {
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
    let finalJournal = journal
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
    
    // Clean key for BibTeX (ASCII only)
    let cleanAuthorKey = authorLast.folding(options: .diacriticInsensitive, locale: .current)
    let cleanTitleKey = titleFirst.folding(options: .diacriticInsensitive, locale: .current)
    let citeKey = "\(cleanAuthorKey)\(year)\(cleanTitleKey)".lowercased()
    
    var bib = "@article{\(citeKey),\n"
    bib += "    author = {\(options.useLaTeXEscaping ? latexEscaped(finalAuthor) : finalAuthor)},\n"
    bib += "    title = {\(options.useLaTeXEscaping ? latexEscaped(finalTitle) : finalTitle)},\n"
    bib += "    year = {\(year)},\n"
    bib += "    journal = {\(options.useLaTeXEscaping ? latexEscaped(finalJournal) : finalJournal)}"
    
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
    
    /// Write new metadata to a PDF file using Ghostscript's pdfmark
    static func writeMetadata(
        url: URL,
        title: String,
        author: String,
        subject: String,
        keywords: String,
        creator: String
    ) async -> Bool {
        guard let gsPath = findGhostscript() else { return false }
        
        let fileManager = FileManager.default
        let tempParamsPath = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ps")
        let tempOutputPath = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        
        // Sanitize string for PostScript (escape parentheses)
        func escape(_ s: String) -> String {
            return s.replacingOccurrences(of: "(", with: "\\(").replacingOccurrences(of: ")", with: "\\)")
        }
        
        // Create pdfmark content
        let pdfmark = """
        [ /Title (\(escape(title)))
          /Author (\(escape(author)))
          /Subject (\(escape(subject)))
          /Keywords (\(escape(keywords)))
          /Creator (\(escape(creator)))
          /DOCINFO pdfmark
        """
        
        do {
            try pdfmark.write(to: tempParamsPath, atomically: true, encoding: .utf8)
            
            let args = [
                gsPath,
                "-dSAFER",
                "-dBATCH",
                "-dNOPAUSE",
                "-sDEVICE=pdfwrite",
                "-sOutputFile=\(tempOutputPath.path)",
                tempParamsPath.path,
                "-f",
                url.path
            ]
            
            // Execute
            try await executeGhostscript(args: args)
            
            // If successful, replace original file
            if fileManager.fileExists(atPath: tempOutputPath.path) {
                // Check if file is valid/non-empty
                let attr = try fileManager.attributesOfItem(atPath: tempOutputPath.path)
                if let size = attr[.size] as? Int64, size > 100 {
                    _ = try? fileManager.removeItem(at: url)
                    try fileManager.moveItem(at: tempOutputPath, to: url)
                    
                    // Cleanup params
                    try? fileManager.removeItem(at: tempParamsPath)
                    return true
                }
            }
        } catch {
            print("Metadata write error: \(error)")
        }
        
        // Cleanup on failure
        try? fileManager.removeItem(at: tempParamsPath)
        try? fileManager.removeItem(at: tempOutputPath)
        return false
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
/// - Parameters:
///   - url: The PDF file URL
///   - options: BibTeX formatting options
///   - isCancelledCheck: Optional closure to check if the task should be cancelled
///   - progressCallback: Called with (current, total) for progress updates
func extractReferences(url: URL, options: BibTeXFormatOptions = BibTeXFormatOptions(), mode: ReferenceLookupMode = .hybrid, isCancelledCheck: (() -> Bool)? = nil, progressCallback: ((Int, Int) -> Void)? = nil) async -> [String] {
    guard let doc = PDFDocument(url: url) else { return [] }
    
    var references: [String] = []
    var referenceText = ""
    var startCollecting = false
    var pagesCollected = 0
    
    // Determine if we should allow online
    let allowOnline = mode == .online || mode == .hybrid
    
    // 0. Try to find DOI using sophisticated logic
    var docDOI: String? = await findDOI(in: doc, allowOnline: allowOnline)
    var docArXivID: String? = nil
    
    // 1. Try to find arXiv ID (scanning text)
    if docArXivID == nil {
        for pageIndex in 0..<min(3, doc.pageCount) {
             if let page = doc.page(at: pageIndex), let text = page.string {
                 let arxivPattern = #"(?:arXiv:)?(\d{4}\.\d{4,5}(?:v\d+)?)"#
                 if let arxivMatch = text.range(of: arxivPattern, options: [.regularExpression, .caseInsensitive]) {
                     var arxivID = String(text[arxivMatch])
                     arxivID = arxivID.replacingOccurrences(of: "arXiv:", with: "", options: .caseInsensitive)
                         .trimmingCharacters(in: .whitespaces)
                     docArXivID = arxivID
                     break
                 }
             }
        }
    }

    // New Strategy: Try online reference list fetching
    if allowOnline {
        var onlineRefs: [String]? = nil
        
        // Priority 1: Try arXiv if we have an arXiv ID
        if let arxivID = docArXivID {
            print("DEBUG - Found arXiv ID: \(arxivID).")
            // arXiv API usually doesn't provide references list, so we might skip or try
        }
        
        // Priority 2: Try CrossRef if we have a DOI
        if let doi = docDOI {
             print("DEBUG - Found Document DOI: \(doi). Attempting to fetch reference list from CrossRef...")
             onlineRefs = await fetchReferenceListFromDOI(doi, options: options)
             
             if let refs = onlineRefs {
                 print("DEBUG - Successfully fetched \(refs.count) references from CrossRef directly.")
                 return refs
             }
             print("DEBUG - Failed to fetch references from CrossRef (or list empty).")
        }
        
        // If Online Only mode and we failed to get online refs, return empty or handle error
        if mode == .online {
            print("DEBUG - Online Only mode: Failed to fetch references online. Returning empty.")
            return []
        }
    }

    
    // Try AI-powered extraction (macOS 26+) before heuristic parsing
    if #available(macOS 99.0, *) {
        // Extract full text from PDF
        var fullText = ""
        for i in 0..<doc.pageCount {
            if let page = doc.page(at: i), let pageText = page.string {
                fullText += pageText + "\n\n"
            }
        }
        
        if !fullText.isEmpty {
            print("DEBUG - Attempting AI-powered reference extraction...")
            if let aiRefs = await extractReferencesWithAI(from: fullText, options: options) {
                print("DEBUG - AI extraction successful! Got \(aiRefs.count) references.")
                return aiRefs
            } else {
                print("DEBUG - AI reference extraction failed, falling back to heuristic parsing.")
            }
        }
    } else {
        print("DEBUG - macOS < 26, using heuristic reference extraction")
    }


    // 1. Find References section and extract ALL text until end
    for pageIndex in 0..<doc.pageCount {
        // Check for cancellation
        if isCancelledCheck?() == true { return ["// Extraction cancelled by user"] }
        
        guard let page = doc.page(at: pageIndex),
              let text = page.string else { continue }
        
        let lines = text.components(separatedBy: .newlines)
        
        // Track if we found a potential reference pattern on this page to help implicit detection
        var pageRefPatternCount = 0
        
        for (lineIdx, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            // Detect start of references section
            if !startCollecting {
                let refHeaders = ["References", "REFERENCES", "Bibliography", "BIBLIOGRAPHY", 
                                 "Works Cited", "WORKS CITED", "Literature Cited", "LITERATURE CITED"]
                
                // If it's an exact match on a line, it's very likely a header
                if refHeaders.contains(trimmed) {
                    startCollecting = true
                    print("DEBUG - Found references section (exact match) on page \(pageIndex)")
                    continue
                }
                
                // Regex for "6. References" or "VII. Bibliography"
                if trimmed.range(of: #"^(\d+\.|[IVX]+\.)\s*(References|Bibliography|Literature Cited)$"#, options: [.regularExpression, .caseInsensitive]) != nil {
                     startCollecting = true
                     print("DEBUG - Found references section (numbered header) on page \(pageIndex)")
                     continue
                }
                
                // If it's a prefix (e.g. "References:"), validate it's followed by something that looks like a ref
                if refHeaders.contains(where: { trimmed.hasPrefix($0) }) {
                    // Check if the REST of the line is empty or just punctuation
                    let pattern = "^(" + refHeaders.joined(separator: "|") + ")[:.]?$"
                    if trimmed.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                        startCollecting = true
                        print("DEBUG - Found references section (regex prefix match) on page \(pageIndex)")
                        continue
                    }
                }
                
                // IMPLICIT DETECTION:
                // For arXiv papers, references might be anywhere (before appendix).
                // For generic papers, usually at the end.
                let isLatePage = pageIndex >= Int(Double(doc.pageCount) * 0.8) || pageIndex >= doc.pageCount - 2
                let shouldCheckImplicit = (docArXivID != nil) || isLatePage // Always check for arXiv papers
                
                if shouldCheckImplicit {
                    // Diagnostic
                    if isLatePage && lineIdx < 3 {
                         print("DEBUG - Page \(pageIndex) Line \(lineIdx): '\(trimmed)'")
                    }

                    // Strong signal: Line starts with [1]
                    if trimmed.range(of: #"^\[1\]"#, options: .regularExpression) != nil {
                        // Found explicit start of numbered references!
                        startCollecting = true
                        print("DEBUG - Implicitly detected reference section (start with [1]) on page \(pageIndex)")
                        // Process this line
                    }
                    // Strong signal: Line starts with 1. followed by text (and year/author-like content)
                    else if trimmed.range(of: #"^1\.\s+[A-Z]"#, options: .regularExpression) != nil {
                         // Verify it looks like a citation (has year or author names) to avoid false positives (e.g. "1. Introduction")
                         let hasYear = trimmed.range(of: #"(19|20)\d{2}"#, options: .regularExpression) != nil
                         let hasPages = trimmed.contains("pp.") || trimmed.contains("pages")
                         
                         if hasYear || hasPages {
                            startCollecting = true
                            print("DEBUG - Implicitly detected reference section (start with 1. + year/pages) on page \(pageIndex)")
                            // Process this line
                         }
                    }
                    else {
                        // General pattern accumulation for other numbers [2], [3] etc.
                        if trimmed.range(of: #"^\[\d+\]"#, options: .regularExpression) != nil {
                            pageRefPatternCount += 1
                        } else if trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil {
                            // Only count x. pattern if it looks reference-y (has year)
                             if trimmed.range(of: #"(19|20)\d{2}"#, options: .regularExpression) != nil {
                                 pageRefPatternCount += 1
                             }
                        }
                        
                        // If we see multiple ref-like lines on this page, assume we are in references
                        // Lower threshold if we have arXiv ID
                        let threshold = (docArXivID != nil) ? 2 : 3
                        if pageRefPatternCount >= threshold {
                             startCollecting = true
                             print("DEBUG - Implicitly detected reference section (pattern count \(pageRefPatternCount)) on page \(pageIndex)")
                        }
                    }
                }
            }

            if startCollecting {
                // heuristic to stop if we hit "Appendix" or "Supplementary Material" headers
                let stopHeaders = ["Appendix", "APPENDIX", "Supplementary Material", "SUPPLEMENTARY MATERIAL"]
                if stopHeaders.contains(where: { trimmed.hasPrefix($0) }) && trimmed.count < 30 {
                     // Only stop if it looks like a header (short line)
                     print("DEBUG - Stopping collection at Appendix/Supplementary header")
                     break
                }
            
                // Skip lines that look like obvious equations only if they are very short
                // Physics papers have long equations that we shouldn't confuse with refs
                // But we should keep lines that *contain* math if they look like part of a title
                let isEquation = trimmed.contains("=") && !trimmed.contains(",") && trimmed.count < 30
                
                if !isEquation {
                    referenceText += line + "\n"
                }
            }
        }
        
        // Keep collecting until end of document (references usually go to the end)
        if startCollecting {
            pagesCollected += 1
        }
    }
    
    // Fallback: If no references collected but we saw implicit patterns, maybe we missed the "start"
    // (This is hard to recover, but the implicit detection above should cover it)
    
    print("DEBUG - Collected \(pagesCollected) pages of references, total chars: \(referenceText.count)")
    
    // 2. Split into individual reference entries
    let refLines = referenceText.components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
    
    var currentRef = ""
    var individualRefs: [String] = []
    
    // First, check if references are numbered or name-based using a majority vote
    var numberedVotes = 0
    var nameBasedVotes = 0
    
    for line in refLines {
        // [1] or 1. or 1 format
        if line.range(of: #"^\[\d+\]|^\d+\.\s"#, options: .regularExpression) != nil {
            numberedVotes += 1
        }
        
        // Name-based patterns: Author, A., or Author, A.B.,
        // Improved to handle accents, hyphens, and lowercase prefixes (de, van, etc.)
        let authorPattern = #"^(\p{Lu}|de\s|von\s|van\s|di\s|le\s|la\s)[\p{L}-]+,\s+\p{Lu}\."#
        if line.range(of: authorPattern, options: [.regularExpression, .caseInsensitive]) != nil && line.count > 15 {
            nameBasedVotes += 1
        }
    }
    
    // Predominantly numbered if numberedVotes is high or at least > nameBasedVotes
    let hasNumberedRefs = numberedVotes > nameBasedVotes
    
    print("DEBUG - Reference format: \(hasNumberedRefs ? "numbered (\(numberedVotes) votes)" : "name-based (\(nameBasedVotes) votes)")")
    
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
            // Name-based references - improved heuristic
            // A new reference typically starts with: Author, Initial. or Author, A.B.
            // Look for patterns like: "Surname, I." or "Surname, I.J." at start of line
            
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            // Common continuation patterns (unlikely to start a reference)
            let continuationWords = ["The", "A ", "An ", "In ", "On ", "And ", "For ", "With ", "From ", "To ", "Of ", "At ", "By "]
            let isContinuation = continuationWords.contains { trimmedLine.hasPrefix($0) }

            // Check if line looks like author name format: "Lastname, F." or "Lastname, F.G."
            // Supports accents, hyphens, and common lowercase prefixes
            let authorPattern = #"^(\p{Lu}|de\s|von\s|van\s|di\s|le\s|la\s)[\p{L}-]+,\s+\p{Lu}\."#
            let looksLikeAuthor = trimmedLine.range(of: authorPattern, options: [.regularExpression, .caseInsensitive]) != nil

            // Additional check: line starts with multiple capital letters (like "Bourdin B, ")
            let multiCapsPattern = #"^(\p{Lu}|de\s|von\s|van\s|di\s|le\s|la\s)[\p{L}-]+\s+\p{Lu}"#
            let hasMultipleCaps = trimmedLine.range(of: multiCapsPattern, options: [.regularExpression, .caseInsensitive]) != nil

            // Start new reference if it looks like author name and current ref is substantial
            if !isContinuation && (looksLikeAuthor || hasMultipleCaps) {
                if currentRef.count > 60 || currentRef.isEmpty {
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

    // Debug: Print first 50 chars of each reference for diagnostics
    if individualRefs.count < 10 {
        for (i, ref) in individualRefs.enumerated() {
            print("DEBUG - Ref \(i+1): \(ref.prefix(60))...")
        }
    }
    
    // 3. Process references concurrently in batches of 4 for API rate limiting
    var processedKeys: Set<String> = []
    var successCount = 0
    var failCount = 0
    let batchSize = 4
    
    // Prepare unique references (filter duplicates first)
    var uniqueRefs: [(index: Int, cleanedRef: String, originalRef: String)] = []
    for (index, refText) in individualRefs.enumerated() {
        // 1. Clean up hyphens and newlines (e.g., "sol-\nids" -> "solids")
        let dehyphenated = refText.replacingOccurrences(of: #"-\s*\n\s*"#, with: "", options: .regularExpression)
                                  .replacingOccurrences(of: #"\s*\n\s*"#, with: " ", options: .regularExpression)
        
        // 2. Remove numbering
        let cleanedRef = dehyphenated
            .replacingOccurrences(of: #"^\[\d+\]|\d+\."#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        
        if cleanedRef.count < 20 {
            print("DEBUG - Skipping short ref: \(cleanedRef.prefix(30))...")
            continue
        }
        
        let key = String(cleanedRef.prefix(100)).lowercased()
        if processedKeys.contains(key) {
            print("DEBUG - Skipping duplicate: \(cleanedRef.prefix(30))...")
            continue
        }
        processedKeys.insert(key)
        uniqueRefs.append((index: index, cleanedRef: cleanedRef, originalRef: refText))
    }
    
    // Process in batches for better performance while respecting rate limits
    for batchStart in stride(from: 0, to: uniqueRefs.count, by: batchSize) {
        // Check for cancellation before each batch
        if isCancelledCheck?() == true {
            print("DEBUG - Extraction cancelled by user")
            return references.isEmpty ? ["// Extraction cancelled by user"] : references
        }
        
        let batchEnd = min(batchStart + batchSize, uniqueRefs.count)
        let batch = Array(uniqueRefs[batchStart..<batchEnd])
        
        // Report progress
        progressCallback?(batchEnd, uniqueRefs.count)
        
        // Process batch concurrently
        let batchResults = await withTaskGroup(of: (Int, String?).self) { group in
            for item in batch {
                group.addTask {
                    // Check cancellation inside task
                    if isCancelledCheck?() == true { return (item.index, nil) }

                    // Parse text first
                    guard let parsed = parseReferenceText(item.cleanedRef) else {
                        // If we can't even parse parsing offline, we can't do much
                        return (item.index, nil)
                    }

                    // Try CrossRef first
                    if let bibtex = await queryBibTeXWithRawText(item.cleanedRef, options: options) {
                        print("DEBUG - [CrossRef] Found: \(item.cleanedRef.prefix(40))...")
                        return (item.index, bibtex)
                    }
                    
                    // Fallback to Semantic Scholar
                    if let bibtex = await querySemanticScholar(item.cleanedRef, originalContext: item.originalRef, options: options) {
                        print("DEBUG - [SemanticScholar] Found: \(item.cleanedRef.prefix(40))...")
                        return (item.index, bibtex)
                    }
                    
                    // Final Fallback: Use Offline Parsing
                    // This is crucial for Books where online databases might return Reviews instead
                    // or for references not indexed online.
                    let offlineBib = constructBibTeXFromParsed(parsed)
                    print("DEBUG - [Offline] Generated fallback for: \(item.cleanedRef.prefix(40))...")
                    return (item.index, offlineBib)
                }
            }
            
            var results: [(Int, String?)] = []
            for await result in group {
                results.append(result)
            }
            return results.sorted { $0.0 < $1.0 }
        }
        
        // Collect results
        for (_, bibtex) in batchResults {
            if let bib = bibtex {
                references.append(bib)
                successCount += 1
            } else {
                failCount += 1
            }
        }
        
        // Rate limiting between batches (100ms per batch instead of 250ms per item)
        if batchEnd < uniqueRefs.count {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms between batches
        }
    }
    
    print("DEBUG - Final: \(successCount) found, \(failCount) failed")
    return references.isEmpty ? ["// No valid references found via CrossRef"] : references
}

/// Query CrossRef with raw reference text and build clean BibTeX from JSON
private func queryBibTeXWithRawText(_ refText: String, originalContext: String? = nil, options: BibTeXFormatOptions = BibTeXFormatOptions()) async -> String? {
    // Clean and prepare query text
    var cleanedText = String(refText.prefix(200))
    
    // Replace special characters that might break the query
    cleanedText = cleanedText
        .replacingOccurrences(of: "—", with: "-")  // em-dash
        .replacingOccurrences(of: "–", with: "-")  // en-dash
        .replacingOccurrences(of: "'", with: "'")  // smart quote
        .replacingOccurrences(of: "'", with: "'")
    
    // Detect and fix concatenated text (like "AmbatiM,KruseR" -> "Ambati M, Kruse R")
    // Also handles "SuquetPM.Surleséquations..." -> "Suquet P M. Sur les équations..."
    let spaceCount = cleanedText.filter { $0 == " " }.count
    if spaceCount < cleanedText.count / 10 { // Increased sensitivity (was /15)
        var fixedText = ""
        var prevChar: Character = " "
        
        for char in cleanedText {
            // Insert space if:
            // 1. Current is Uppercase AND Previous is Lowercase (CamelCase boundary)
            // 2. Current is Uppercase AND Previous is '.' (Period boundary like "P.M.")
            if (char.isUppercase && prevChar.isLowercase) ||
               (char.isUppercase && prevChar == ".") ||
               (char.isUppercase && prevChar.isUppercase) { // Force split between consecutive uppercase if spaces are missing? No, that breaks initials.
                // Wait, checking specifically for "PM.Sur" -> "P M. Sur"
                 if char.isUppercase && prevChar == "." {
                     fixedText += " "
                 } else if char.isUppercase && prevChar.isLowercase {
                      fixedText += " "
                 }
            }
            fixedText += String(char)
            prevChar = char
        }
        cleanedText = fixedText
        print("DEBUG - Fixed concatenated text: \(cleanedText.prefix(50))...")
    }
    
    var extractedDOI: String? = nil
    // Check for DOI in the reference text - if found, use it directly
    // First, try to clean up potential split DOIs (e.g. "10.\n1016")
    let textForDoi = refText
        .replacingOccurrences(of: "\n", with: "")
        .replacingOccurrences(of: "10. ", with: "10.")
    
    if let doiMatch = textForDoi.range(of: #"10\.\d{4,}/[^\s]+"#, options: .regularExpression) {
        var doi = String(textForDoi[doiMatch])
        // Clean up any trailing punctuation that might have been matched
        doi = doi.trimmingCharacters(in: CharacterSet(charactersIn: ".,;"))
        extractedDOI = doi
        print("DEBUG - Found DOI: \(doi)")
        
        // Try to get BibTeX directly using DOI
        let doiUrl = "https://api.crossref.org/works/\(doi)"
        if let url = URL(string: doiUrl) {
            var request = URLRequest(url: url)
            request.setValue("GhostPDF/1.0", forHTTPHeaderField: "User-Agent")
            
            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let bibtex = buildBibTeXFromJSON(json, options: options) {
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
            // Updated: Removed word boundaries \b to capture "JMéc1981"
            var refYear: String? = nil
            // Use cleanedText so we benefit from space insertion (e.g. splitting years from text)
            if let yearMatch = cleanedText.range(of: #"(?<!\d)(19|20)\d{2}(?!\d)"#, options: .regularExpression) {
                refYear = String(cleanedText[yearMatch])
            }
            
            // Extract first author surname from reference for validation
            var refAuthor: String? = nil
            // Split on non‑alphanumeric characters and take the first non‑empty token
            // Use cleanedText here too! This splits "SuquetPM" -> "Suquet P M" -> ["Suquet", "P", "M"]
            let authorTokens = cleanedText.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
            
            // Heuristic using cleaning results:
            if let firstToken = authorTokens.first,
               firstToken.count >= 2,
               (firstToken.first?.isUppercase == true || cleanedText.count < 30) { // Allow lowercase if text is very short (minimal retry)
                refAuthor = firstToken.lowercased()
            }
            // Fallback: use regex to find first capitalized word if token method failed
            if refAuthor == nil {
                if let match = cleanedText.range(of: #"\\b[A-Z][a-zA-Z]+\\b"#, options: .regularExpression) {
                    let word = String(cleanedText[match])
                    refAuthor = word.lowercased()
                }
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
                } else {
                    // If reference author is missing, consider it a match
                    authorMatches = true
                }
                
                // Only accept if year matches AND (author matches OR score is very high)
                // If we found a DOI in the reference, be more lenient but still validate
                var isValid: Bool
                if extractedDOI != nil {
                    // DOI was found - require either year match OR high score, but don't bypass all validation
                    isValid = yearMatches || score > 30
                } else {
                    // No DOI - require strict validation
                    isValid = yearMatches && (authorMatches || score > 50)
                }
                
                // Extra validation: Title Context
                // If we are running a minimal query (originalContext is present), we MUST validate the title.
                // Otherwise we risk returning a popular but wrong paper by the same author/year.
                if isValid, let context = originalContext, let title = item["title"] as? [String], let resultTitle = title.first {
                    // Normalize: lowercase, remove non-alphanumeric
                    let cleanContext = context.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
                    let _ = resultTitle.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
                    
                    // HEURISTIC: Check if significant chunks of the result title exist in the context blob.
                    // Just checking "cleanTitle" in "cleanContext" fails if context is partial or OCR is bad.
                    // Instead, break title into big words (length > 4) and check overlap.
                    let titleWords = resultTitle.lowercased().split(separator: " ").map { String($0) }.filter { $0.count > 4 }
                    if !titleWords.isEmpty {
                        let matchedWords = titleWords.filter { cleanContext.contains($0) }
                        if matchedWords.isEmpty {
                            // No significant title words found in the original text blob. REJECT.
                            print("DEBUG - Rejecting match due to title mismatch. Title: '\(resultTitle)' not in context.")
                            isValid = false
                        }
                    }
                }
                
                if isValid {
                    print("DEBUG - CrossRef match: year=\(resultYear ?? "nil"), author=\(resultAuthor ?? "nil"), score=\(score)")
                    return buildBibTeXFromJSON(["message": item], options: options) // Pass item wrapped in "message" as buildBibTeXFromJSON expects it
                }
            }
            
            print("DEBUG - No valid CrossRef match found for: \(refText.prefix(40))...")
            
            // Retry with minimal query if full query failed
            if let _ = refYear, let _ = refAuthor, refText.count > 50 {
                // Use capitalized author for minimal query to ensure it's treated as a name in the recursive call
                if let minimalQuery = "\(refAuthor ?? "") \(refYear ?? "")".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                    print("DEBUG - Retrying with minimal query: \(minimalQuery)")
                    return await queryBibTeXWithRawText(minimalQuery, originalContext: refText, options: options)
                }
            }
        }
    } catch {
        print("DEBUG - CrossRef error: \(error)")
    }
    

    
    // Call Semantic Scholar as final fallback
    // Use CLEANED text so "SuquetPM" -> "Suquet P M"
    if let semantic = await querySemanticScholar(cleanedText, originalContext: refText, options: options) {
        return semantic
    }
    
    return nil
}

/// Query Semantic Scholar API as fallback (Free alternative to Scopus)
private func querySemanticScholar(_ refText: String, originalContext: String? = nil, options: BibTeXFormatOptions = BibTeXFormatOptions()) async -> String? {
    let queryText = String(refText.prefix(200))
        .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
    
    let urlString = "https://api.semanticscholar.org/graph/v1/paper/search?query=\(queryText)&limit=1&fields=title,authors,year,venue,externalIds"
    guard let url = URL(string: urlString) else { return nil }
    
    var request = URLRequest(url: url)
    request.setValue("GhostPDF/1.0", forHTTPHeaderField: "User-Agent")
    
    do {
        let (data, _) = try await URLSession.shared.data(for: request)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let dataArray = json["data"] as? [[String: Any]],
           let firstItem = dataArray.first {
            
            // Validate Title Context if available
            let title = firstItem["title"] as? String ?? "Unknown Title"
            
            if let context = originalContext {
                // Normalize: lowercase, remove non-alphanumeric
                let cleanContext = context.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
                
                // HEURISTIC: Check if significant chunks of the result title exist in the context blob.
                let titleWords = title.lowercased().split(separator: " ").map { String($0) }.filter { $0.count > 4 }
                if !titleWords.isEmpty {
                    let matchedWords = titleWords.filter { cleanContext.contains($0) }
                    if matchedWords.isEmpty {
                        print("DEBUG - Semantic Scholar: Rejecting match due to title mismatch. Title: '\(title)' not in context.")
                        return nil
                    }
                }
            }
            
            // Build BibTeX
            let year = firstItem["year"] as? Int ?? 0
            let venue = firstItem["venue"] as? String ?? ""
            
            var authors: [String] = []
            if let authorList = firstItem["authors"] as? [[String: Any]] {
                for author in authorList {
                    if let name = author["name"] as? String { authors.append(name) }
                }
            }
            
            var doi = ""
            if let externalIds = firstItem["externalIds"] as? [String: Any],
               let doiValue = externalIds["DOI"] as? String { doi = doiValue }
            
            let firstAuthor = authors.first?.components(separatedBy: " ").last ?? "Unknown"
            let key = "\(firstAuthor)\(year)"
            
            
            // Apply formatting options
            var processedAuthors = authors
            if options.shortenAuthors {
                processedAuthors = authors.map { formatAuthorName($0) }
            }
            
            var processedVenue = venue
            if options.abbreviateJournals {
                processedVenue = formatJournalName(venue)
            }
            
            var bib = "@article{\(key),\n"
            bib += "    author = {\(processedAuthors.joined(separator: " and "))},\n"
            bib += "    title = {\(title)},\n"
            bib += "    year = {\(year)}"
            if !venue.isEmpty { bib += ",\n    journal = {\(processedVenue)}" }
            if !doi.isEmpty { bib += ",\n    doi = {\(doi)}" }
            bib += "\n}"
            return bib
        }
    } catch {
        print("DEBUG - Semantic Scholar query failed: \(error)")
    }
    return nil
}
/// Comprehensive journal abbreviation dictionary (Enriched with 100+ journals)
private let JOURNAL_ABBREV: [String: String] = [
    // Materials Science & Engineering (Original + Expanded)
    "Computational Materials Science": "Comput. Mater. Sci.",
    "Acta Materialia": "Acta Mater.",
    "International Journal of Plasticity": "Int. J. Plast.",
    "Materials transactions": "Mater. Trans.",
    "Journal of the Mechanics and Physics of Solids": "J. Mech. Phys. Solids",
    "Journal of Applied Mechanics": "J. Appl. Mech.",
    "Philosophical Magazine": "Philos. Mag.",
    "Progress in Materials Science": "Prog. Mater. Sci.",
    "Computer methods in applied mechanics and engineering": "Comput. Methods Appl. Mech. Eng.",
    "Acta metallurgica": "Acta Metall.",
    "Physical Review Materials": "Phys. Rev. Mater.",
    "Scripta Materialia": "Scr. Mater.",
    "Materials Science and Engineering: A": "Mater. Sci. Eng. A",
    "Materials Science and Engineering: R: Reports": "Mater. Sci. Eng. R",
    "Journal of Materials Science": "J. Mater. Sci.",
    "Metallurgical and Materials Transactions A": "Metall. Mater. Trans. A",
    "Metallurgical and Materials Transactions B": "Metall. Mater. Trans. B",
    "Materials Characterization": "Mater. Charact.",
    "Materials Letters": "Mater. Lett.",
    "Materials & Design": "Mater. Des.",
    "Intermetallics": "Intermetallics",

    // Physics Journals (Original + Expanded)
    "Physical Review Letters": "Phys. Rev. Lett.",
    "Physical Review B": "Phys. Rev. B",
    "Physical Review A": "Phys. Rev. A",
    "Physical Review C": "Phys. Rev. C",
    "Physical Review D": "Phys. Rev. D",
    "Physical Review E": "Phys. Rev. E",
    "Physical Review X": "Phys. Rev. X",
    "Physical Review Applied": "Phys. Rev. Appl.",
    "Reviews of Modern Physics": "Rev. Mod. Phys.",
    "Journal of Physics D: Applied Physics": "J. Phys. D Appl. Phys.",
    "Journal of Physics: Condensed Matter": "J. Phys. Condens. Matter",
    "Journal of Applied Physics": "J. Appl. Phys.",
    "Applied Physics Letters": "Appl. Phys. Lett.",
    "Advances in physics": "Adv. Phys.",
    "Comptes rendus. Physique": "C. R. Phys.",
    "Reports on Progress in Physics": "Rep. Prog. Phys.",
    "New Journal of Physics": "New J. Phys.",
    "Journal of Statistical Mechanics: Theory and Experiment": "J. Stat. Mech.",
    "Frontiers in Physics": "Front. Phys.",

    // Nature/Science Family
    "Nature": "Nature",
    "Science": "Science",
    "Nature Materials": "Nat. Mater.",
    "Nature Communications": "Nat. Commun.",
    "Nature Physics": "Nat. Phys.",
    "Nature Nanotechnology": "Nat. Nanotechnol.",
    "Nature Chemistry": "Nat. Chem.",
    "Nature Methods": "Nat. Methods",
    "Science Advances": "Sci. Adv.",
    "Scientific Reports": "Sci. Rep.",

    // Mechanics & Structural Engineering
    "Mechanics of Materials": "Mech. Mater.",
    "International Journal of Solids and Structures": "Int. J. Solids Struct.",
    "Engineering Fracture Mechanics": "Eng. Fract. Mech.",
    "Extreme Mechanics Letters": "Extreme Mech. Lett.",
    "International Journal of Mechanical Sciences": "Int. J. Mech. Sci.",
    "Journal of Engineering Mechanics": "J. Eng. Mech.",
    "Mechanics Research Communications": "Mech. Res. Commun.",
    "European Journal of Mechanics - A/Solids": "Eur. J. Mech. A. Solids",
    "Acta Mechanica": "Acta Mech.",
    "Archive of Applied Mechanics": "Arch. Appl. Mech.",

    // Computational & Numerical Methods
    "Journal of Computational Physics": "J. Comput. Phys.",
    "Computer Methods in Applied Mechanics and Engineering": "Comput. Methods Appl. Mech. Eng.",
    "Computational Mechanics": "Comput. Mech.",
    "Computers & Structures": "Comput. Struct.",
    "Finite Elements in Analysis and Design": "Finite Elem. Anal. Des.",
    "Applied Numerical Mathematics": "Appl. Numer. Math.",
    "Journal of Scientific Computing": "J. Sci. Comput.",

    // Composites
    "Composites Science and Technology": "Compos. Sci. Technol.",
    "Composite Structures": "Compos. Struct.",
    "Composites Part A: Applied Science and Manufacturing": "Compos. Part A Appl. Sci. Manuf.",
    "Composites Part B: Engineering": "Compos. Part B Eng.",
    "Journal of Composite Materials": "J. Compos. Mater.",

    // Nanotechnology & Advanced Materials
    "Nano Letters": "Nano Lett.",
    "ACS Nano": "ACS Nano",
    "Advanced Materials": "Adv. Mater.",
    "Advanced Functional Materials": "Adv. Funct. Mater.",
    "Advanced Energy Materials": "Adv. Energy Mater.",
    "Small": "Small",
    "Nanoscale": "Nanoscale",
    "Journal of Materials Research": "J. Mater. Res.",
    "npj Computational Materials": "npj Comput. Mater.",
    "Materials Theory": "Mater. Theor.",
    "Mechanics of Nano-objects": "Mech. Nano-obj.",

    // Modeling & Simulation
    "Modelling and Simulation in Materials Science and Engineering": "Model. Simul. Mater. Sci. Eng.",
    "Molecular Simulation": "Mol. Simul.",
    "Journal of Chemical Physics": "J. Chem. Phys.",

    // Chemistry & Electrochemistry
    "Journal of the American Chemical Society": "J. Am. Chem. Soc.",
    "Angewandte Chemie International Edition": "Angew. Chem. Int. Ed.",
    "Chemical Reviews": "Chem. Rev.",
    "Accounts of Chemical Research": "Acc. Chem. Res.",
    "Journal of Physical Chemistry C": "J. Phys. Chem. C",
    "Electrochimica Acta": "Electrochim. Acta",
    "Journal of Power Sources": "J. Power Sources",
    "Energy & Environmental Science": "Energy Environ. Sci.",

    // Mathematics
    "SIAM Journal on Scientific Computing": "SIAM J. Sci. Comput.",
    "SIAM Journal on Numerical Analysis": "SIAM J. Numer. Anal.",
    "SIAM Journal on Applied Mathematics": "SIAM J. Appl. Math.",
    "Numerische Mathematik": "Numer. Math.",
    "Mathematics of Computation": "Math. Comput.",

    // Tribology & Surface Science
    "Wear": "Wear",
    "Tribology International": "Tribol. Int.",
    "Surface and Coatings Technology": "Surf. Coat. Technol.",
    "Applied Surface Science": "Appl. Surf. Sci.",

    // General Engineering
    "Proceedings of the National Academy of Sciences": "Proc. Natl. Acad. Sci. U.S.A.",
    "Annual Review of Materials Research": "Annu. Rev. Mater. Res.",
    "Proceedings of the Royal Society A": "Proc. R. Soc. A",
    "Proceedings of the Royal Society of London. Series A: Mathematical, Physical and Engineering Sciences": "Proc. R. Soc. Lond. Ser. A",
    "Journal of Nonlinear Science": "J. Nonlinear Sci.",
    "Journal of Engineering Materials and Technology": "J. Eng. Mater. Technol.",
    "International Journal of Engineering Science": "Int. J. Eng. Sci."
]

/// Helper to abbreviate journal names using comprehensive dictionary
private func formatJournalName(_ name: String) -> String {
    let clean = name.replacingOccurrences(of: "[{}]", with: "", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)

    // 1. Try exact match with Full Name (case-insensitive)
    for (fullName, abbrev) in JOURNAL_ABBREV {
        if fullName.lowercased() == clean.lowercased() {
            return abbrev
        }
    }
    
    // 2. Try matching against existing Abbreviations (support reversibility: No Dots -> Dots)
    // If input is "Phys Rev Mater", check if we have a known abbreviation "Phys. Rev. Mater."
    let cleanNoDots = clean.replacingOccurrences(of: ".", with: "")
    for (_, abbrev) in JOURNAL_ABBREV {
        let abbrevNoDots = abbrev.replacingOccurrences(of: ".", with: "")
        if abbrevNoDots.lowercased() == cleanNoDots.lowercased() {
             return abbrev
        }
    }

    // Return original if no match found
    // TODO: Future enhancement - implement online lookup via CrossRef API
    // or ISO 4 automatic abbreviation rules for unknown journals
    return clean
}

/// Get initials from a name (handles hyphenated names like "Pierre-Marie")
private func getInitials(_ name: String) -> String {
    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }

    return name.trimmingCharacters(in: .whitespacesAndNewlines)
        .components(separatedBy: " ")
        .map { part in
            if part.contains("-") {
                return part.components(separatedBy: "-")
                    .map { $0.isEmpty ? "" : String($0.prefix(1).uppercased()) + "." }
                    .joined(separator: "-")
            }
            return part.isEmpty ? "" : String(part.prefix(1).uppercased()) + "."
        }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
}

/// Format author name to initials (comprehensive algorithm from LaTeX BibTeX Tools)
private func formatAuthorName(_ name: String) -> String {
    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }

    var author = name.trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "~", with: " ")
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

    // Remove surrounding braces
    if author.hasPrefix("{") && author.hasSuffix("}") {
        author = String(author.dropFirst().dropLast())
    }

    // If already has 2+ periods, assume it's already formatted
    let periodCount = author.filter { $0 == "." }.count
    if periodCount >= 2 {
        return author.replacingOccurrences(of: "\\.\\s*\\.", with: ". ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Handle "Family, Given" format
    if author.contains(",") {
        let parts = author.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if parts.count >= 2 {
            let firstPart = parts[0]
            let secondPart = parts[1]

            // Check if second part looks like journal metadata (not a name)
            let journalIndicators = ["[", "]", "(", ")", "arXiv", "doi", "vol", "pp", "pages", "et al.", "manuscript", "preprint", "submitted"]
            let hasJournalIndicator = journalIndicators.contains { secondPart.localizedCaseInsensitiveContains($0) }

            if secondPart.count < 50 && !hasJournalIndicator {
                // It's a name - format it
                let firstNames = parts.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                return firstNames.isEmpty ? firstPart : "\(getInitials(firstNames)) \(firstPart)"
            }

            // Otherwise, just use first part
            author = firstPart
        }
    }

    // Handle "First Middle Last" format (space separated)
    let parts = author.components(separatedBy: " ").filter { !$0.isEmpty }
    if parts.isEmpty { return "" }
    if parts.count == 1 { return parts[0] }

    // Ambiguity Heuristic: Check for "Surname Initial" format (missing comma)
    // Entry: "Author E." -> parts=["Author", "E."]
    // If Part 0 looks like a Surname (>2 chars) and Part Last looks like an Initial (1 char or "X."),
    // Then assume Surname-First order.
    if parts.count == 2 {
        let first = parts[0]
        let last = parts[1]
        let lastIsInitial = (last.count == 1) || (last.count == 2 && last.hasSuffix("."))
        let firstIsName = first.replacingOccurrences(of: ".", with: "").count > 2 // Ensure it's not just "A. B."
        
        if lastIsInitial && firstIsName {
            // Treat as "Surname Initial" -> "Initial. Surname"
            return "\(getInitials(last)) \(first)"
        }
    }

    // Convert all but last name to initials (Standard Assumed Order: First... Last)
    let lastName = parts.last!
    let firstNames = parts.dropLast().joined(separator: " ")
    return "\(getInitials(firstNames)) \(lastName)"
}

/// Build BibTeX string from CrossRef JSON response
/// Helper to escape special characters for LaTeX/BibTeX compatibility
private func latexEscaped(_ text: String) -> String {
    let mapping: [Character: String] = [
        "à": "\\`a", "á": "\\'a", "â": "\\^a", "ã": "\\~a", "ä": "\\\"a", "å": "\\r{a}", "æ": "\\ae",
        "ç": "\\c{c}",
        "è": "\\`e", "é": "\\'e", "ê": "\\^e", "ë": "\\\"e",
        "ì": "\\`i", "í": "\\'i", "î": "\\^i", "ï": "\\\"i",
        "ñ": "\\~n",
        "ò": "\\`o", "ó": "\\'o", "ô": "\\^o", "õ": "\\~o", "ö": "\\\"o", "ø": "\\o",
        "ù": "\\`u", "ú": "\\'u", "û": "\\^u", "ü": "\\\"u",
        "ý": "\\'y", "ÿ": "\\\"y",
        "À": "\\`A", "Á": "\\'A", "Â": "\\^A", "Ã": "\\~A", "Ä": "\\\"A", "Å": "\\r{A}", "Æ": "\\AE",
        "Ç": "\\c{C}",
        "È": "\\`E", "É": "\\'E", "Ê": "\\^E", "Ë": "\\\"E",
        "Ì": "\\`I", "Í": "\\'I", "Î": "\\^I", "Ï": "\\\"I",
        "Ñ": "\\~N",
        "Ò": "\\`O", "Ó": "\\'O", "Ô": "\\^O", "Õ": "\\~O", "Ö": "\\\"O", "Ø": "\\O",
        "Ù": "\\`U", "Ú": "\\'U", "Û": "\\^U", "Ü": "\\\"U",
        "Ý": "\\'Y"
    ]
    
    var result = ""
    for char in text {
        if let escaped = mapping[char] {
            result += "{\(escaped)}"
        } else {
            result.append(char)
        }
    }
    return result
}

/// Helper to unescape LaTeX character sequences back to UTF-8
private func latexUnescaped(_ text: String) -> String {
    let mapping: [String: String] = [
        "{\\`a}": "à", "{\\'a}": "á", "{\\^a}": "â", "{\\~a}": "ã", "{\\\"a}": "ä", "{\\r{a}}": "å", "{\\ae}": "æ",
        "{\\c{c}}": "ç",
        "{\\`e}": "è", "{\\'e}": "é", "{\\^e}": "ê", "{\\\"e}": "ë",
        "{\\`i}": "ì", "{\\'i}": "í", "{\\^i}": "î", "{\\\"i}": "ï",
        "{\\~n}": "ñ",
        "{\\`o}": "ò", "{\\'o}": "ó", "{\\^o}": "ô", "{\\~o}": "õ", "{\\\"o}": "ö", "{\\o}": "ø",
        "{\\`u}": "ù", "{\\'u}": "ú", "{\\^u}": "û", "{\\\"u}": "ü",
        "{\\'y}": "ý", "{\\\"y}": "ÿ",
        "{\\`A}": "À", "{\\'A}": "Á", "{\\^A}": "Â", "{\\~A}": "Ã", "{\\\"A}": "Ä", "{\\r{A}}": "Å", "{\\AE}": "Æ",
        "{\\c{C}}": "Ç",
        "{\\`E}": "È", "{\\'E}": "É", "{\\^E}": "Ê", "{\\\"E}": "Ë",
        "{\\`I}": "Ì", "{\\'I}": "Í", "{\\^I}": "Î", "{\\\"I}": "Ï",
        "{\\~N}": "Ñ",
        "{\\`O}": "Ò", "{\\'O}": "Ó", "{\\^O}": "Ô", "{\\~O}": "Õ", "{\\\"O}": "Ö", "{\\O}": "Ø",
        "{\\`U}": "Ù", "{\\'U}": "Ú", "{\\^U}": "Û", "{\\\"U}": "Ü",
        "{\\'Y}": "Ý"
    ]
    
    var result = text
    for (escaped, unescaped) in mapping {
        result = result.replacingOccurrences(of: escaped, with: unescaped)
    }
    return result
}

private func buildBibTeXFromJSON(_ json: [String: Any], options: BibTeXFormatOptions = BibTeXFormatOptions()) -> String? {
    guard let message = json["message"] as? [String: Any] else { return nil }
    
    // Extract fields
    let title = (message["title"] as? [String])?.first ?? "Unknown Title"
    
    // Author formatting
    var authors = "Unknown"
    if let authorList = message["author"] as? [[String: Any]] {
        let names = authorList.compactMap { author -> String? in
            if let given = author["given"] as? String, let family = author["family"] as? String {
                let fullName = "\(family), \(given)"
                if options.shortenAuthors {
                    // Use comprehensive formatAuthorName function
                    return formatAuthorName(fullName)
                } else {
                    return fullName
                }
            } else if let family = author["family"] as? String {
                return family
            }
            return nil
        }
        if !names.isEmpty {
            authors = names.joined(separator: " and ")
        }
    }
    
    let year = (message["issued"] as? [String: Any])
        .flatMap { $0["date-parts"] as? [[Int]] }?
        .first?.first ?? 0
    
    var journal = (message["container-title"] as? [String])?.first
    
    // Apply journal abbreviation if requested
    if options.abbreviateJournals, let jName = journal {
       journal = formatJournalName(jName)
    }
    
    let doi = message["DOI"] as? String ?? ""
    
    // Generate citation key: FirstAuthor + Year (e.g., Smith2020)
    // Normalize key to ASCII for BibTeX compatibility
    let firstAuthorFamily = (message["author"] as? [[String: Any]])?
        .first?["family"] as? String ?? "Unknown"
    let cleanKey = firstAuthorFamily.folding(options: .diacriticInsensitive, locale: .current)
        .components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
    let key = "\(cleanKey)\(year)"
    
    var bib = "@article{\(key),\n"
    bib += "    author = {\(options.useLaTeXEscaping ? latexEscaped(authors) : authors)},\n"
    bib += "    title = {\(options.useLaTeXEscaping ? latexEscaped(title) : title)},\n"
    bib += "    year = {\(year)}"
    
    if let j = journal, !j.isEmpty {
        bib += ",\n    journal = {\(j)}"
    }
    
    // Add volume if available
    if let volume = message["volume"] as? String, !volume.isEmpty {
        bib += ",\n    volume = {\(volume)}"
    }
    
    // Add issue/number if available
    if let issue = message["issue"] as? String, !issue.isEmpty {
        bib += ",\n    number = {\(issue)}"
    }
    
    // Add pages if available
    if let page = message["page"] as? String, !page.isEmpty {
        bib += ",\n    pages = {\(page)}"
    }
    
    if !doi.isEmpty {
        bib += ",\n    doi = {\(doi)}"
    }
    bib += "\n}"
    return bib
}


private func parseReferenceText(_ text: String) -> (authors: String, title: String, journal: String?, year: String?, publisher: String?, address: String?, type: String?)? {
    // Remove numbering
    let cleaned = text.replacingOccurrences(of: #"^\[\d+\]|\d+\."#, with: "", options: .regularExpression)
        .trimmingCharacters(in: .whitespaces)
    
    // Extract year using regex
    var extractedYear: String? = nil
    
    // Improved Year Extraction: check year at end of string first (common in numbered styles)
    if let yearMatch = cleaned.range(of: #"\b(19|20)\d{2}\b[^\w]*$"#, options: .regularExpression) {
         let y = String(cleaned[yearMatch]).trimmingCharacters(in: CharacterSet.decimalDigits.inverted)
         extractedYear = y
    } else if let yearMatch = cleaned.range(of: #"\b(19|20)\d{2}\b"#, options: .regularExpression) {
        extractedYear = String(cleaned[yearMatch])
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
    
    // Check for Book characteristics
    var type: String? = "article"
    var publisher: String? = nil
    var address: String? = nil
    
    let isBook = cleaned.range(of: #"(University Press|Wiley|Sons|Springer|Academic Press|New York|Cambridge|London|Oxford)"#, options: [.regularExpression, .caseInsensitive]) != nil
    if isBook { type = "book" }

    // Fallback to traditional parsing if NL didn't find names
    if authors.isEmpty {
        let parts = cleaned.components(separatedBy: ".").map { $0.trimmingCharacters(in: .whitespaces) }
        // Author Cleaning: Remove "editors", "(Eds)"
        if parts.count >= 1 {
            var rawAuthors = parts[0]
            rawAuthors = rawAuthors.replacingOccurrences(of: #",?\s*editors"#, with: "", options: [.regularExpression, .caseInsensitive])
            rawAuthors = rawAuthors.replacingOccurrences(of: #",?\s*\(Eds\)"#, with: "", options: [.regularExpression, .caseInsensitive])
            authors = rawAuthors
        }
    }
    
    // Extract title - usually in quotes or after author section
    var title = ""
    var journal: String? = organizations.first
    
    if let quoteMatch = cleaned.range(of: #""[^"]+""#, options: .regularExpression) {
        title = String(cleaned[quoteMatch]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    } else {
        // Fall back to period-based splitting with Edition awareness
        let parts = cleaned.components(separatedBy: CharacterSet(charactersIn: ".?!")).filter { $0.count > 3 } // split by punctuation
        if parts.count >= 2 {
             // Title is second part
             title = parts[1].trimmingCharacters(in: .whitespaces)
             
             if parts.count >= 3 {
                 // Remaining parts could be Edition, Publisher, Journal
                 for i in 2..<parts.count {
                     let part = parts[i].trimmingCharacters(in: .whitespaces)
                     
                     // Skip Edition info
                     let editionPattern = #"\b(\d+(st|nd|rd|th)?\s+(edn|ed|edition))\b"#
                     if part.range(of: editionPattern, options: [.regularExpression, .caseInsensitive]) != nil {
                         continue
                     }
                     
                     // Check for Publisher Info
                     if part.contains(":") && isBook {
                         let pubParts = part.components(separatedBy: ":")
                         if pubParts.count > 1 {
                             address = pubParts[0].trimmingCharacters(in: .whitespaces)
                             publisher = pubParts[1].trimmingCharacters(in: .whitespaces)
                             break
                         }
                     } else if isBook && publisher == nil {
                         if part.range(of: #"(Press|Wiley|Sons|Springer)"#, options: .caseInsensitive) != nil {
                             publisher = part
                             break
                         }
                     } else {
                         if journal == nil { journal = part }
                     }
                 }
             }
        }
    }
    
    guard !authors.isEmpty || !title.isEmpty else { return nil }
    
    return (authors: authors, title: title, journal: journal, year: extractedYear, publisher: publisher, address: address, type: type)
}

/// Query CrossRef API using metadata
private func queryWithBibTeXFromMetadata(_ metadata: (authors: String, title: String, journal: String?, year: String?, publisher: String?, address: String?, type: String?)) async -> String? {
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
    
    // Add journal or publisher if available
    if let journal = metadata.journal, !journal.isEmpty {
        queryParts.append(journal.prefix(20).description)
    }
    if let publisher = metadata.publisher, !publisher.isEmpty {
        queryParts.append(publisher.prefix(20).description)
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
             
             // Validation: Check if the returned item's author matches our offline author
             // This prevents "Salje" (Book) -> "Price" (Book Review) mismatches
             if let type = metadata.type, type == "book" {
                 if let authorsList = first["author"] as? [[String: Any]],
                    let firstOnlineAuthor = authorsList.first,
                    let onlineFamily = firstOnlineAuthor["family"] as? String {
                     
                     let offlineFamily = metadata.authors.components(separatedBy: CharacterSet(charactersIn: " ,.")).first ?? metadata.authors
                     
                     // Simple containment check (case insensitive)
                     if !onlineFamily.localizedCaseInsensitiveContains(offlineFamily) && !offlineFamily.localizedCaseInsensitiveContains(onlineFamily) {
                         print("DEBUG - Author mismatch for book (Offline: \(offlineFamily) vs Online: \(onlineFamily)). Ignoring online result to avoid Reviews.")
                         return nil
                     }
                 }
             }

            // Try CrossRef first
            if let bib = await fetchBibTeXFromCrossRef(doi: doi) {
                return bib
            } else {
                print("DEBUG - CrossRef failed or returned corrupted data. Falling back to Semantic Scholar.")
                // Fallback to Semantic Scholar using metadata
                // Construct a query string from title
                return await querySemanticScholar(metadata.title, originalContext: metadata.authors + " " + metadata.year.map { String($0) }.debugDescription)
            }
        }
    } catch {
        print("DEBUG - CrossRef query error: \(error)")
    }
    
    return nil
}

/// Construct basic BibTeX from parsed data
private func constructBibTeXFromParsed(_ metadata: (authors: String, title: String, journal: String?, year: String?, publisher: String?, address: String?, type: String?)) -> String {
    let key = (metadata.authors.components(separatedBy: " ").first ?? "ref") + (metadata.year ?? "")
    
    let entryType = metadata.type ?? "article"
    
    var bib = "@\(entryType){\(key),\n"
    bib += "    author = {\(metadata.authors)},\n"
    bib += "    title = {\(metadata.title)}"
    if let year = metadata.year {
        bib += ",\n    year = {\(year)}"
    }
    
    if entryType == "book" {
        if let publisher = metadata.publisher {
             bib += ",\n    publisher = {\(publisher)}"
        }
        if let address = metadata.address {
             bib += ",\n    address = {\(address)}"
        }
    } else {
        if let journal = metadata.journal {
            bib += ",\n    journal = {\(journal)}"
        }
    }

    bib += ",\n    note = {Extracted from references, verification failed}\n"
    bib += "}"
    return bib
}

/// Fetch BibTeX from CrossRef API for a given DOI
func fetchBibTeXFromCrossRef(doi: String) async -> String? {
    // URL-encode the DOI - must encode parentheses which urlPathAllowed does NOT encode
    var allowedChars = CharacterSet.urlPathAllowed
    allowedChars.remove(charactersIn: "()")
    guard let encodedDOI = doi.addingPercentEncoding(withAllowedCharacters: allowedChars) else { return nil }
    let urlString = "https://api.crossref.org/works/\(encodedDOI)/transform/application/x-bibtex"
    guard let url = URL(string: urlString) else { return nil }
    
    var request = URLRequest(url: url)
    request.setValue("application/x-bibtex", forHTTPHeaderField: "Accept")
    request.setValue("GhostPDF/1.0 (mailto:user@example.com)", forHTTPHeaderField: "User-Agent")
    
    do {
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("DEBUG - CrossRef: No HTTP response for DOI: \(doi)")
            return nil
        }
        
        if httpResponse.statusCode != 200 {
            print("DEBUG - CrossRef API error for DOI: \(doi) | Status: \(httpResponse.statusCode) | URL: \(urlString)")
            return nil
        }
        
        if var bibtex = String(data: data, encoding: .utf8) {
            // Strip replacement characters instead of rejecting (common with CrossRef German umlauts)
            if bibtex.contains("\u{FFFD}") {
                print("DEBUG - CrossRef has corrupted characters. Stripping and keeping data.")
                bibtex = bibtex.replacingOccurrences(of: "\u{FFFD}", with: "")
            }
            return bibtex.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    } catch {
        print("DEBUG - Network error fetching DOI \(doi): \(error)")
    }

    return nil
}

/// Reformat existing BibTeX entries with new formatting options
func reformatBibTeX(_ bibtexText: String, options: BibTeXFormatOptions) -> String {
    // 1. Global Cleanup (Normalization & Tag Stripping)
    var cleanedText = bibtexText
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
    
    // Clean MathML and XML tags GLOBALLY
    // Example: <mml:math ...><mml:mi>A</mml:mi>...</mml:math> -> A
    cleanedText = cleanedText.replacingOccurrences(of: "</?mml:[^>]+>", with: "", options: [.regularExpression, .caseInsensitive])
    cleanedText = cleanedText.replacingOccurrences(of: "</?math[^>]*>", with: "", options: [.regularExpression, .caseInsensitive])
    cleanedText = cleanedText.replacingOccurrences(of: "−", with: "-") // U+2212 -> Hyphen
    cleanedText = cleanedText.replacingOccurrences(of: "&amp;", with: "&")

    // Split into individual entries
    let entries = cleanedText.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var reformattedEntries: [String] = []

    for entry in entries {
        var modifiedEntry = entry

        // Skip comments and non-BibTeX lines
        if entry.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
            reformattedEntries.append(entry)
            continue
        }

        // Only process if it looks like a BibTeX entry
        guard entry.contains("@article") || entry.contains("@inproceedings") || entry.contains("@book") || entry.contains("@misc") else {
            reformattedEntries.append(entry)
            continue
        }

        // 1. Apply author shortening first (Canonicalize to 'Initials. Lastname')
        // GUARD: Only process if both processAuthors AND shortenAuthors are true
        if options.processAuthors && options.shortenAuthors {
            // Match author field: author = {Name1, Given1 and Name2, Given2}
            let authorPattern = #"author\s*=\s*\{([^}]+)\}"#
            if let regex = try? NSRegularExpression(pattern: authorPattern, options: []),
               let match = regex.firstMatch(in: modifiedEntry, options: [], range: NSRange(modifiedEntry.startIndex..., in: modifiedEntry)) {

                if let authorRange = Range(match.range(at: 1), in: modifiedEntry) {
                    let authorValue = String(modifiedEntry[authorRange])
                    let authors = authorValue.components(separatedBy: " and ")

                    let shortenedAuthors = authors.map { author -> String in
                        return formatAuthorName(author.trimmingCharacters(in: .whitespaces))
                    }

                    modifiedEntry = modifiedEntry.replacingOccurrences(
                        of: authorValue,
                        with: shortenedAuthors.joined(separator: " and ")
                    )
                }
            }
        }

        // 2. Apply ALL CAPS normalization and Dot Management (Add/Remove)
        // This must happen AFTER shortening to ensure we enforce the user's dot preference
        // (Shortening resets to dotted format, so we must potentially remove dots afterwards)
        // GUARD: Only process authors if requested
        if options.processAuthors {
            let capsPattern = #"author\s*=\s*\{([^}]+)\}"#
            if let regex = try? NSRegularExpression(pattern: capsPattern, options: .caseInsensitive) {
                let nsString = modifiedEntry as NSString
                if let match = regex.firstMatch(in: modifiedEntry, options: [], range: NSRange(location: 0, length: nsString.length)) {
                    let authors = nsString.substring(with: match.range(at: 1))
                    
                    // Only normalize if it looks like ALL CAPS (ignore "and", "AND", spaces, punctuation)
                    // We remove "and" (case insensitive) before checking if everything else is uppercase
                    let textForCheck = authors.replacingOccurrences(of: " and ", with: "", options: .caseInsensitive)
                    let lettersOnly = textForCheck.components(separatedBy: CharacterSet.letters.inverted).joined()
                    let isAllCaps = !lettersOnly.isEmpty && lettersOnly == lettersOnly.uppercased()
                    
                    var normalized = authors
                    
                    if isAllCaps {
                        normalized = authors.capitalized // "GONG, L" -> "Gong, L"
                            .replacingOccurrences(of: " And ", with: " and ") // Fix " and "
                    }
                    
                    if options.addDotsToInitials {
                        // Add dots to single initials (e.g., "Gong, L" -> "Gong, L.")
                        let initialPattern = #"(^|[\s,])([A-Z])(?=$|[\s,])"#
                        if let initialRegex = try? NSRegularExpression(pattern: initialPattern, options: []) {
                            let range = NSRange(location: 0, length: normalized.count)
                            normalized = initialRegex.stringByReplacingMatches(
                                in: normalized,
                                options: [],
                                range: range,
                                withTemplate: "$1$2."
                            )
                        }
                    } else {
                        // REMOVE dots from single initials (e.g. "Gong, L." -> "Gong, L")
                        // 1. Separate condensed initials first: "N.P." -> "N. P." to ensure "N P" later
                        //    Match a letter-dot followed immediately by another letter
                        let splitPattern = #"([A-Z])\.([A-Z])"#
                        if let splitRegex = try? NSRegularExpression(pattern: splitPattern, options: []) {
                             let range = NSRange(location: 0, length: normalized.count)
                             normalized = splitRegex.stringByReplacingMatches(
                                 in: normalized,
                                 options: [],
                                 range: range,
                                 withTemplate: "$1. $2"
                             )
                             // Run twice to handle N.P.Q. -> N. P.Q. -> N. P. Q.
                             let range2 = NSRange(location: 0, length: normalized.count)
                             normalized = splitRegex.stringByReplacingMatches(
                                 in: normalized,
                                 options: [],
                                 range: range2,
                                 withTemplate: "$1. $2"
                             )
                        }

                        // 2. Remove dots: Match ANY Uppercase Letter followed by a dot (e.g. "K. Salman" -> "K Salman")
                        let dotPattern = #"([A-Z])\."#
                        if let dotRegex = try? NSRegularExpression(pattern: dotPattern, options: []) {
                             let range = NSRange(location: 0, length: normalized.count)
                             normalized = dotRegex.stringByReplacingMatches(
                                 in: normalized,
                                 options: [],
                                 range: range,
                                 withTemplate: "$1"
                             )
                        }
                    }
                    
                    if normalized != authors {
                        modifiedEntry = modifiedEntry.replacingOccurrences(of: authors, with: normalized)
                    }
                }
            }
        }

        // Apply journal abbreviation using depth-tracking algorithm (from latex-bibtex-tools_v2)
        if options.abbreviateJournals {
            let journalPattern = #"journal\s*=\s*\{"#
            if let regex = try? NSRegularExpression(pattern: journalPattern, options: .caseInsensitive) {
                let nsString = modifiedEntry as NSString
                let matches = regex.matches(in: modifiedEntry, options: [], range: NSRange(location: 0, length: nsString.length))

                // Build replacement list with integer indices
                var replacements: [(start: Int, end: Int, text: String)] = []

                for match in matches {
                    let start = match.range.location
                    let contentStart = start + match.range.length

                    // Track brace depth to handle nested braces correctly
                    var depth = 1
                    var pos = contentStart
                    while pos < nsString.length && depth > 0 {
                        let char = nsString.character(at: pos)
                        if char == 123 { // '{'
                            depth += 1
                        } else if char == 125 { // '}'
                            depth -= 1
                            if depth == 0 {
                                break
                            }
                        }
                        pos += 1
                    }

                    if depth == 0 && pos < nsString.length {
                        let content = nsString.substring(with: NSRange(location: contentStart, length: pos - contentStart))
                        var abbreviated = formatJournalName(content)
                        
                        // Remove dots if requested (e.g. "Phys. Rev. Lett." -> "Phys Rev Lett")
                        if !options.addDotsToJournals {
                            abbreviated = abbreviated.replacingOccurrences(of: ".", with: "")
                        }
                        
                        let endIndex = pos + 1
                        replacements.append((start: start, end: endIndex, text: "journal = {\(abbreviated)}"))
                    }
                }

                // Apply replacements in reverse order to maintain indices
                var result = modifiedEntry
                for replacement in replacements.reversed() {
                    let nsResult = result as NSString
                    let before = nsResult.substring(to: replacement.start)
                    let after = nsResult.substring(from: replacement.end)
                    result = before + replacement.text + after
                }

                modifiedEntry = result
            }
        }
        
        // Handle LaTeX escaping/unescaping for author and title
        let fieldsToProcess = ["author", "title", "journal", "booktitle"]
        for field in fieldsToProcess {
            let fieldPattern = #"(?i)"# + field + #"\s*=\s*\{"#
            if let regex = try? NSRegularExpression(pattern: fieldPattern, options: []) {
                let nsString = modifiedEntry as NSString
                let matches = regex.matches(in: modifiedEntry, options: [], range: NSRange(location: 0, length: nsString.length))
                
                var replacements: [(range: NSRange, text: String)] = []
                
                for match in matches {
                    let contentStart = match.range.location + match.range.length
                    var depth = 1
                    var pos = contentStart
                    while pos < nsString.length && depth > 0 {
                        let char = nsString.character(at: pos)
                        if char == 123 { depth += 1 }
                        else if char == 125 { depth -= 1 }
                        if depth == 0 { break }
                        pos += 1
                    }
                    
                    if depth == 0 {
                        let content = nsString.substring(with: NSRange(location: contentStart, length: pos - contentStart))
                        let newValue = options.useLaTeXEscaping ? latexEscaped(latexUnescaped(content)) : latexUnescaped(content)
                        if content != newValue {
                            replacements.append((range: NSRange(location: contentStart, length: pos - contentStart), text: newValue))
                        }
                    }
                }
                
                // Apply replacements in reverse
                for r in replacements.reversed() {
                    let nsResult = modifiedEntry as NSString
                    modifiedEntry = nsResult.replacingCharacters(in: r.range, with: r.text)
                }
            }
        }

        reformattedEntries.append(modifiedEntry)
    }

    return reformattedEntries.joined(separator: "\n\n")
}

/// Clean BibTeX entries by removing unnecessary fields, cleaning special characters, and removing duplicates
/// - Parameters:
///   - bibtexText: The raw BibTeX text to clean
///   - fieldsToRemove: Set of field names to remove (default includes abstract, language, etc.)
/// - Returns: Cleaned BibTeX string
func cleanBibTeX(_ bibtexText: String, fieldsToRemove: Set<String>? = nil, options: BibTeXFormatOptions = BibTeXFormatOptions()) -> String {
    // 1. Global Cleanup (Normalization & Tag Stripping)
    var cleanedGlobal = bibtexText
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
    
    // Clean MathML and XML tags GLOBALLY
    cleanedGlobal = cleanedGlobal.replacingOccurrences(of: "</?mml:[^>]+>", with: "", options: [.regularExpression, .caseInsensitive])
    cleanedGlobal = cleanedGlobal.replacingOccurrences(of: "</?math[^>]*>", with: "", options: [.regularExpression, .caseInsensitive])
    cleanedGlobal = cleanedGlobal.replacingOccurrences(of: "−", with: "-") // U+2212 -> Hyphen
    cleanedGlobal = cleanedGlobal.replacingOccurrences(of: "&amp;", with: "&")
    // Default fields to remove (commonly unnecessary for citations)
    let defaultFieldsToRemove: Set<String> = [
        "abstract", "keywords", "url", "urldate", "note", "annotation",
        "file", "issn", "isbn", "doi", "annote", "copyright", "language",
        "month", "address", "series", "edition", "howpublished",
        "mendeley-groups", "review", "date-modified", "date-added", "bdsk-url-1", "bdsk-url-2", "bdsk-file-1"
        // Removed from this list: "eprint", "archiveprefix", "primaryclass" - these are important for arXiv papers
    ]
    
    let fieldsToClean = fieldsToRemove ?? defaultFieldsToRemove
    
    
    // Split into entries, tracking which are BibTeX vs comments
    let rawEntries = cleanedGlobal.components(separatedBy: "\n\n")
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    
    var cleanedEntries: [String] = []
    var seenKeys: Set<String> = []  // For duplicate detection
    
    for var rawEntry in rawEntries {
        // Normalize ALL CAPS authors (e.g. "GONG, L" -> "Gong, L")
        let capsPattern = #"author\s*=\s*\{([^}]+)\}"#
        if let regex = try? NSRegularExpression(pattern: capsPattern, options: .caseInsensitive) {
            let nsString = rawEntry as NSString
            if let match = regex.firstMatch(in: rawEntry, options: [], range: NSRange(location: 0, length: nsString.length)) {
                let authors = nsString.substring(with: match.range(at: 1))
                
                print("DEBUG - Checking authors for ALL CAPS: '\(authors)'")
                
                // Only normalize if it looks like ALL CAPS (ignore "and", "AND", spaces, punctuation)
                // We remove "and" (case insensitive) before checking if everything else is uppercase
                let textForCheck = authors.replacingOccurrences(of: " and ", with: "", options: .caseInsensitive)
                let lettersOnly = textForCheck.components(separatedBy: CharacterSet.letters.inverted).joined()
                let isAllCaps = !lettersOnly.isEmpty && lettersOnly == lettersOnly.uppercased()
                
                print("DEBUG - Is All Caps: \(isAllCaps) (letters: '\(lettersOnly)')")
                
                var normalized = authors
                
                if isAllCaps {
                    normalized = authors.capitalized // "GONG, L" -> "Gong, L"
                        .replacingOccurrences(of: " And ", with: " and ") // Fix " and "
                }
                
                if options.addDotsToInitials {
                    // Add dots to single initials (e.g., "Gong, L" -> "Gong, L.")
                    let initialPattern = #"(^|[\s,])([A-Z])(?=$|[\s,])"#
                    if let initialRegex = try? NSRegularExpression(pattern: initialPattern, options: []) {
                        let range = NSRange(location: 0, length: normalized.count)
                        normalized = initialRegex.stringByReplacingMatches(
                            in: normalized,
                            options: [],
                            range: range,
                            withTemplate: "$1$2."
                        )
                    }
                } else {
                    // REMOVE dots from single initials (e.g. "Gong, L." -> "Gong, L")
                    // 1. Separate condensed initials first: "N.P." -> "N. P." to ensure "N P" later
                    //    Match a letter-dot followed immediately by another letter
                    let splitPattern = #"([A-Z])\.([A-Z])"#
                    if let splitRegex = try? NSRegularExpression(pattern: splitPattern, options: []) {
                         let range = NSRange(location: 0, length: normalized.count)
                         normalized = splitRegex.stringByReplacingMatches(
                             in: normalized,
                             options: [],
                             range: range,
                             withTemplate: "$1. $2"
                         )
                         // Run twice to handle N.P.Q. -> N. P.Q. -> N. P. Q.
                         let range2 = NSRange(location: 0, length: normalized.count)
                         normalized = splitRegex.stringByReplacingMatches(
                             in: normalized,
                             options: [],
                             range: range2,
                             withTemplate: "$1. $2"
                         )
                    }

                    // 2. Remove dots: Match ANY Uppercase Letter followed by a dot (e.g. "K. Salman" -> "K Salman")
                    let dotPattern = #"([A-Z])\."#
                    if let dotRegex = try? NSRegularExpression(pattern: dotPattern, options: []) {
                         let range = NSRange(location: 0, length: normalized.count)
                         normalized = dotRegex.stringByReplacingMatches(
                             in: normalized,
                             options: [],
                             range: range,
                             withTemplate: "$1"
                         )
                    }
                }
                
                if normalized != authors {
                    print("DEBUG - Normalizing authors: '\(authors)' -> '\(normalized)'")
                    rawEntry = rawEntry.replacingOccurrences(of: authors, with: normalized)
                }
            }
        }
        let entry = rawEntry.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Skip comments
        if entry.hasPrefix("//") || entry.hasPrefix("%") {
            cleanedEntries.append(entry)
            continue
        }
        
        // Check if it's a BibTeX entry
        guard entry.hasPrefix("@") else {
            cleanedEntries.append(entry)
            continue
        }
        
        // Extract citation key for duplicate detection
        if let keyMatch = entry.range(of: #"@\w+\{([^,]+),"#, options: .regularExpression) {
            let keyPart = String(entry[keyMatch])
            let key = keyPart.replacingOccurrences(of: #"@\w+\{"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: ",", with: "")
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            
            // Skip duplicates
            if seenKeys.contains(key) {
                continue
            }
            seenKeys.insert(key)
        }
        
        var cleanedEntry = entry
        
        // Remove unwanted fields using regex
        for field in fieldsToClean {
            // Pattern matches: field = {value} or field = "value" with optional trailing comma
            let pattern = #"(?m)^\s*"# + field + #"\s*=\s*(\{[^}]*\}|\"[^\"]*\"|\S+)\s*,?\s*\n?"#
            cleanedEntry = cleanedEntry.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        
        // Clean braces from author/editor names: {Name} -> Name
        // But preserve braces in title (they're meaningful for capitalization)
        let authorPattern = #"(author|editor)\s*=\s*\{([^}]*)\}"#
        if let regex = try? NSRegularExpression(pattern: authorPattern, options: .caseInsensitive) {
            let nsEntry = cleanedEntry as NSString
            let matches = regex.matches(in: cleanedEntry, options: [], range: NSRange(location: 0, length: nsEntry.length))
            
            // Process in reverse to maintain indices
            for match in matches.reversed() {
                if let valueRange = Range(match.range(at: 2), in: cleanedEntry) {
                    var authorValue = String(cleanedEntry[valueRange])
                    
                    // Remove inner braces around individual names: {John} Doe -> John Doe
                    authorValue = authorValue.replacingOccurrences(of: #"\{([^}]+)\}"#, with: "$1", options: .regularExpression)
                    
                    // Clean up multiple spaces
                    authorValue = authorValue.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    
                    cleanedEntry = cleanedEntry.replacingCharacters(in: valueRange, with: authorValue)
                }
            }
        }
        
        // Clean up empty lines and trailing whitespace
        let lines = cleanedEntry.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        // Ensure proper formatting with the closing brace
        var formatted = lines.joined(separator: "\n")
        
        // Fix any double commas or comma before closing brace
        formatted = formatted.replacingOccurrences(of: #",\s*,"#, with: ",", options: .regularExpression)
        formatted = formatted.replacingOccurrences(of: #",\s*\}"#, with: "\n}", options: .regularExpression)
        
        cleanedEntries.append(formatted)
    }
    
    return cleanedEntries.joined(separator: "\n\n")
}

/// Fetch the reference list for a given DOI from CrossRef and convert to BibTeX
private func fetchReferenceListFromDOI(_ doi: String, options: BibTeXFormatOptions) async -> [String]? {
    let urlString = "https://api.crossref.org/works/\(doi)"
    guard let url = URL(string: urlString) else { return nil }
    
    var request = URLRequest(url: url)
    request.setValue("GhostPDF/1.0", forHTTPHeaderField: "User-Agent")
    
    do {
        let (data, _) = try await URLSession.shared.data(for: request)
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = json["message"] as? [String: Any],
           let references = message["reference"] as? [[String: Any]],
           !references.isEmpty {
            
            print("DEBUG - CrossRef Metadata has \(references.count) references.")
            
            // Process in batches to avoid rate limiting (429)
            let batchSize = 5
            var results: [String] = []
            
            for batchStart in stride(from: 0, to: references.count, by: batchSize) {
                let batchEnd = min(batchStart + batchSize, references.count)
                let batch = Array(references[batchStart..<batchEnd])
                
                // Process batch concurrently
                let batchResults = await withTaskGroup(of: String?.self) { group in
                    for ref in batch {
                        group.addTask {
                            // 1. Try to fetch full BibTeX from CrossRef if DOI is present
                            if let refDOI = ref["DOI"] as? String {
                                if let deepBib = await fetchBibTeXFromCrossRef(doi: refDOI) {
                                    return deepBib
                                }
                                
                                // 1b. Fallback: Try Semantic Scholar if CrossRef failed
                                let ssQuery = ref["article-title"] as? String ?? ref["unstructured"] as? String ?? ""
                                if !ssQuery.isEmpty {
                                    if let ssBib = await querySemanticScholar(ssQuery, originalContext: nil, options: options) {
                                        return ssBib
                                    }
                                }
                            } else {
                                // 1c. No DOI - try Semantic Scholar with title
                                let title = ref["article-title"] as? String ?? ref["series-title"] as? String ?? ref["volume-title"] as? String ?? ""
                                if !title.isEmpty {
                                    print("DEBUG - No DOI for ref. Searching Semantic Scholar for: '\(title)'")
                                    if let ssBib = await querySemanticScholar(title, originalContext: nil, options: options) {
                                        print("DEBUG - Semantic Scholar found match for: '\(title)'")
                                        return ssBib
                                    } else {
                                        print("DEBUG - Semantic Scholar found nothing. Trying OpenLibrary for: '\(title)'")
                                        // 1d. Try OpenLibrary for books
                                        if let olBib = await queryOpenLibrary(title, options: options) {
                                            return olBib
                                        }
                                    }
                                } else {
                                    print("DEBUG - No DOI and no title found for ref: \(ref["key"] ?? "unknown")")
                                }
                            }
                            
                            // 2. Final Fallback: Parse sparse data
                            return buildSparseBibTeX(ref, options: options)
                        }
                    }
                    
                    var batchItems: [String] = []
                    for await result in group {
                        if let bib = result { batchItems.append(bib) }
                    }
                    return batchItems
                }
                
                results.append(contentsOf: batchResults)
                
                // Rate limit delay between batches (200ms)
                if batchEnd < references.count {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            }
            
            return results
        }
    } catch {
        print("DEBUG - Failed to fetch reference list for DOI \(doi): \(error)")
    }
    
    return nil
}

/// Helper to build BibTeX from the sparse "reference" object in CrossRef metadata
private func buildSparseBibTeX(_ ref: [String: Any], options: BibTeXFormatOptions) -> String {
    let key = ref["key"] as? String ?? "ref\(UUID().uuidString.prefix(8))"
    let doi = ref["DOI"] as? String
    var type = "article"
    
    // Attempt guess type
    if doi == nil && (ref["series-title"] != nil || ref["journal-title"] == nil) {
        type = "misc" 
    }
    
    var bib = "@\(type){\(key),\n"
    
    if let author = ref["author"] as? String {
         bib += "    author = {\(options.useLaTeXEscaping ? latexEscaped(author) : author)},\n"
    }
    
    if let artTitle = ref["article-title"] as? String {
        bib += "    title = {\(options.useLaTeXEscaping ? latexEscaped(artTitle) : artTitle)},\n"
    } else if let seriesTitle = ref["series-title"] as? String {
         bib += "    title = {\(options.useLaTeXEscaping ? latexEscaped(seriesTitle) : seriesTitle)},\n"
    } else if let unstruct = ref["unstructured"] as? String {
         // If we have absolutely nothing else, put unstructured in title or note
         // often unstructured is "H. J. Herrmann, Book Title (1990)"
         if bib.contains("author =") == false {
              bib += "    title = {\(options.useLaTeXEscaping ? latexEscaped(unstruct) : unstruct)},\n"
         } else {
              bib += "    note = {\(options.useLaTeXEscaping ? latexEscaped(unstruct) : unstruct)},\n"
         }
    }
    
    if let journal = ref["journal-title"] as? String {
        bib += "    journal = {\(options.useLaTeXEscaping ? latexEscaped(journal) : journal)},\n"
    }
    
    if let year = ref["year"] as? String {
        bib += "    year = {\(year)},\n"
    }
    
    if let vol = ref["volume"] as? String {
        bib += "    volume = {\(vol)},\n"
    }
    if let page = ref["first-page"] as? String {
        bib += "    pages = {\(page)},\n"
    }
    
    if let d = doi {
        bib += "    doi = {\(d)},\n"
    }
    
    bib += "    note = {Metadata limited (CrossRef sparse reference)}\n"
    bib += "}"
    
    return bib
}

/// Fetch BibTeX directly from arXiv for a given arXiv ID
private func fetchBibTeXFromArXiv(_ arxivID: String) async -> String? {
    // Clean the arXiv ID (remove "arX iv:" prefix if present)
    let cleanID = arxivID.replacingOccurrences(of: "arXiv:", with: "", options: .caseInsensitive)
        .trimmingCharacters(in: .whitespaces)
    
    let urlString = "https://arxiv.org/bibtex/\(cleanID)"
    guard let url = URL(string: urlString) else { return nil }
    
    var request = URLRequest(url: url)
    request.setValue("GhostPDF/1.0", forHTTPHeaderField: "User-Agent")
    request.timeoutInterval = 10
    
    do {
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil
        }
        
        guard var bibtex = String(data: data, encoding: .utf8) else { return nil }
        
        // Check if response contains BibTeX (should start with @)
        bibtex = bibtex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard bibtex.hasPrefix("@") else { return nil }
        
        // Add arXiv ID fields if not already present
        if !bibtex.contains("eprint") {
            // Find the closing brace
            if let closingBraceRange = bibtex.range(of: "}", options: .backwards) {
                let insertPosition = closingBraceRange.lowerBound
                
                // Extract primary category if exists in the BibTeX
                var eprintclass = "arXiv"
                if let primaryClassRange = bibtex.range(of: "primaryClass\\s*=\\s*\\{([^}]+)\\}", options: .regularExpression) {
                    let match = String(bibtex[primaryClassRange])
                    if let valueRange = match.range(of: "\\{([^}]+)\\}", options: .regularExpression) {
                        eprintclass = String(match[valueRange])
                            .replacingOccurrences(of: "{", with: "")
                            .replacingOccurrences(of: "}", with: "")
                    }
                }
                
                let arxivFields = ",\n  eprint = {\(cleanID)},\n  eprinttype = {arXiv},\n  eprintclass = {\(eprintclass)}\n"
                bibtex.insert(contentsOf: arxivFields, at: insertPosition)
            }
        }
        
        return bibtex
    } catch {
        print("DEBUG - Failed to fetch arXiv BibTeX for \(cleanID): \(error)")
        return nil
    }
}

/// Fallback Search: Find DOI by Title using CrossRef API
private func fetchDOIFromTitle(_ title: String) async -> String? {
    let query = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
    let urlString = "https://api.crossref.org/works?query.title=\(query)&rows=1&select=DOI,score"
    
    guard let url = URL(string: urlString) else { return nil }
    
    var request = URLRequest(url: url)
    request.setValue("GhostPDF/1.0 (mailto:user@example.com)", forHTTPHeaderField: "User-Agent")
    
    do {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return nil }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = json["message"] as? [String: Any],
           let items = message["items"] as? [[String: Any]],
           let firstItem = items.first,
           let doi = firstItem["DOI"] as? String {
            
            // Optional: Check score or title match similarity to avoid bad matches?
            // For now, trust the first result if it exists.
            return doi
        }
    } catch {
        print("DEBUG - DOI Title Search failed: \(error)")
    }
    
    return nil
}

/// Helper: Find DOI using sophisticated logic (Metadata -> Text -> PII -> Title Search)
private func findDOI(in doc: PDFDocument, allowOnline: Bool) async -> String? {
    var docDOI: String? = nil
    
    // 1. Check Metadata Attributes first (Subject, Keywords)
    if let attrs = doc.documentAttributes {
        let candidates = [attrs[PDFDocumentAttribute.subjectAttribute] as? String, 
                          attrs[PDFDocumentAttribute.keywordsAttribute] as? String]
        
        for candidate in candidates {
            if let text = candidate, let doiMatch = text.range(of: #"10\.\d{4,}/[^\s]+"#, options: .regularExpression) {
                 var doi = String(text[doiMatch])
                 if let last = doi.last, ",;.".contains(last) { doi.removeLast() }
                 docDOI = doi
                 break
            }
        }
    }
    
    // 2. If not found in metadata, scan first 3 pages for DOI
    if docDOI == nil {
        for pageIndex in 0..<min(3, doc.pageCount) {
             if let page = doc.page(at: pageIndex), let text = page.string {
                 if let doiMatch = text.range(of: #"10\.\d{4,}/[^\s]+"#, options: .regularExpression) {
                     var doi = String(text[doiMatch])
                     if let last = doi.last, ",;.".contains(last) { doi.removeLast() }
                     docDOI = doi
                     break
                 }
             }
        }
    }
    
    // 3. Fallback: Check for PII in Metadata or Text
    if docDOI == nil {
        var piiCandidates: [String] = []
        
        // Scan Metadata
        if let attrs = doc.documentAttributes {
            for (_, value) in attrs {
                if let text = value as? String { piiCandidates.append(text) }
            }
        }
        
        // Scan first 3 pages
        for pageIndex in 0..<min(3, doc.pageCount) {
             if let page = doc.page(at: pageIndex), let text = page.string {
                 piiCandidates.append(text)
             }
        }
        
        // Regex for PII with optional S/0 prefix
        let piiPattern = #"(?:PII:?\s*)?((?:S|0|)\d{4}-?\d{3,4}\(?\d{2}\)?\d{5,6}-?[\dX])"#
        
        for text in piiCandidates {
            if let piiMatch = text.range(of: piiPattern, options: .regularExpression) {
                var pii = String(text[piiMatch])
                if pii.lowercased().hasPrefix("pii") {
                    pii = pii.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? pii
                }
                
                let cleanPII = pii.trimmingCharacters(in: CharacterSet(charactersIn: ".:,; "))
                let potentialDOI = "10.1016/\(cleanPII)"
                
                print("DEBUG - Detected PII: \(cleanPII). Constructed DOI: \(potentialDOI)")
                docDOI = potentialDOI
                break
            }
        }
    }
    
    // 4. Fallback: Search online by Title (Robust)
    if docDOI == nil, allowOnline {
        var searchTitle: String? = nil
        if let attrs = doc.documentAttributes, let title = attrs[PDFDocumentAttribute.titleAttribute] as? String, !title.isEmpty, !title.lowercased().contains("untitled") {
            searchTitle = title
        }
        
        // If metadata title is missing or bad, try heuristic extraction
        if searchTitle == nil || (searchTitle?.count ?? 0) < 5 {
             print("DEBUG - Metadata title is poor. Attempting heuristic title extraction...")
             searchTitle = extractTitleFromPDF(doc: doc)
        }
        
        if let title = searchTitle {
            print("DEBUG - No DOI found locally. Searching CrossRef by Title: '\(title)'")
            if let foundDOI = await fetchDOIFromTitle(title) {
                print("DEBUG - Found DOI via Title Search: \(foundDOI)")
                docDOI = foundDOI
            }
        }
    }
    
    return docDOI
}

/// Query OpenLibrary for book metadata by title
private func queryOpenLibrary(_ title: String, options: BibTeXFormatOptions) async -> String? {
    guard let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
    let urlString = "https://openlibrary.org/search.json?title=\(encodedTitle)&limit=1"
    guard let url = URL(string: urlString) else { return nil }
    
    var request = URLRequest(url: url)
    request.setValue("GhostPDF/1.0", forHTTPHeaderField: "User-Agent")
    request.timeoutInterval = 10
    
    do {
        let (data, _) = try await URLSession.shared.data(for: request)
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let docs = json["docs"] as? [[String: Any]],
           let firstDoc = docs.first {
            
            let foundTitle = firstDoc["title"] as? String ?? title
            let authorNames = firstDoc["author_name"] as? [String] ?? []
            let firstYear = firstDoc["first_publish_year"] as? Int
            let publisher = (firstDoc["publisher"] as? [String])?.first
            let publishPlace = (firstDoc["publish_place"] as? [String])?.first
            
            print("DEBUG - OpenLibrary raw data: title='\(foundTitle)', authors=\(authorNames), year=\(firstYear ?? 0), publisher='\(publisher ?? "nil")', place='\(publishPlace ?? "nil")'")
            
            // Validate match - title should be reasonably similar
            let cleanInput = title.lowercased().filter { $0.isLetter || $0.isNumber }
            let cleanFound = foundTitle.lowercased().filter { $0.isLetter || $0.isNumber }
            guard cleanFound.contains(cleanInput.prefix(20)) || cleanInput.contains(cleanFound.prefix(20)) else {
                print("DEBUG - OpenLibrary title mismatch: '\(foundTitle)' vs '\(title)'")
                return nil
            }
            
            // Format author names
            var formattedAuthors = authorNames.joined(separator: " and ")
            if options.shortenAuthors && !authorNames.isEmpty {
                formattedAuthors = authorNames.map { formatAuthorName($0) }.joined(separator: " and ")
            }
            
            // Generate BibTeX key
            let firstAuthorLast = authorNames.first?.components(separatedBy: " ").last ?? "Unknown"
            let yearStr = firstYear.map { String($0) } ?? ""
            let key = "\(firstAuthorLast)\(yearStr)"
            
            var bib = "@book{\(key),\n"
            if !formattedAuthors.isEmpty {
                bib += "    author = {\(options.useLaTeXEscaping ? latexEscaped(formattedAuthors) : formattedAuthors)},\n"
            }
            bib += "    title = {\(options.useLaTeXEscaping ? latexEscaped(foundTitle) : foundTitle)},\n"
            if let year = firstYear {
                bib += "    year = {\(year)},\n"
            }
            if let pub = publisher {
                bib += "    publisher = {\(options.useLaTeXEscaping ? latexEscaped(pub) : pub)},\n"
            }
            if let place = publishPlace {
                bib += "    address = {\(options.useLaTeXEscaping ? latexEscaped(place) : place)},\n"
            }
            bib += "}"
            
            print("DEBUG - OpenLibrary found book: '\(foundTitle)' by \(authorNames.joined(separator: ", "))")
            return bib
        }
    } catch {
        print("DEBUG - OpenLibrary query failed: \(error)")
    }
    
    return nil
}
