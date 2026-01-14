import Foundation
import PDFKit
import Quartz

/// robustly extract title from PDF text using scoring heuristics
func extractTitleFromPDF(doc: PDFDocument, knownJournal: String? = nil) -> String? {
    guard let firstPage = doc.page(at: 0), let text = firstPage.string else { return nil }
    
    let allLines = text.components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespaces) }
    let lines = allLines.filter { $0.count > 2 }
    
    let attrs = doc.documentAttributes
    
    // 2. Score lines to find the Title
    var titleCandidates: [(line: String, score: Int, index: Int)] = []
    let noise = ["Contents lists", "homepage", "www.", "Research Article", "Full Length", "ScienceDirect",
                 "article info", "a r t i c l e", "abstract", "keywords", "Polish Academy", "available online",
                 "journal of", "transactions on", "proceedings of"]
    
    // Boost potential journal name exclusion
    var journal = knownJournal ?? ""
    if journal.isEmpty {
        // Quick attempt to find journal if not known, to avoid selecting it as title
        let jPatterns = [#"Journal of [\w\s&]+"#, #"Int\.? J\.? of [\w\s&]+"#, #"Nature [\w\s]*"#, #"Science"#]
        for p in jPatterns {
            if let r = text.range(of: p, options: [.regularExpression, .caseInsensitive]) {
                journal = String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
    }

    for (i, line) in lines.prefix(25).enumerated() { // Scan slightly more lines
        var score = 0
        if line.count > 30 && line.count < 250 { score += 10 }
        if line == line.uppercased() { score += 5 }
        if !journal.isEmpty && line.contains(journal) { score -= 25 }
        if noise.contains(where: { line.localizedCaseInsensitiveContains($0) }) { score -= 30 }
        
        // De-prioritize lines that look like a list of authors (comma separated, initials)
        if line.components(separatedBy: ",").count > 2 || line.range(of: #"\b[A-Z]\.\s*[A-Z]"#, options: .regularExpression) != nil {
             score -= 15
        }

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
        
        // Multi-line Title Merging (simplified logic)
        let prepositions = ["of", "in", "and", "on", "at", "for", "with", "by"]
        let stopWords = ["article", "info", "abstract", "keywords", "polish academy", "institute",
                         "university", "department", "ippt", "received", "revised", "accepted", "published"]

        while lastIdx + 1 < lines.count {
            // Find the index of the next line in the FILTERED list (lines)
            // But we iterate lines array directly so it's fine
            if lastIdx + 1 >= lines.count { break }
            
            let current = lines[lastIdx].lowercased()
            let next = lines[lastIdx + 1]
            let nextLower = next.lowercased()

            if stopWords.contains(where: { nextLower.contains($0) }) { break }
            if next.range(of: #"\b[A-Z]\.\s*[A-Z]\."#, options: .regularExpression) != nil { break } // Authors?

            let endsWithPreposition = prepositions.contains { current.hasSuffix(" " + $0) || current.hasSuffix($0) }
            let endsWithHyphen = current.hasSuffix("-")
            let nextStartsLower = next.first?.isLowercase ?? false
            // Also merge if previous line was short and title-like and next line is title-like
            let clearlyContinuation = endsWithPreposition || endsWithHyphen || nextStartsLower || (bt.score > 20 && next.count > 10)

            if clearlyContinuation {
                mergedTitle += (endsWithHyphen ? "" : " ") + next
                lastIdx += 1
                if lastIdx > bt.index + 2 { break }
            } else {
                break
            }
        }

        // Clean up
        if let authorPattern = mergedTitle.range(of: #"\s+[A-Z]\.\s+[A-Z][a-z]+"#, options: .regularExpression) {
            mergedTitle = String(mergedTitle[..<authorPattern.lowerBound])
        }
        
        let metadataPatterns = ["Institute of", "IPPT", "Polish Academy", "article info", "a r t i c l e"]
        for pattern in metadataPatterns {
            if let range = mergedTitle.range(of: pattern, options: .caseInsensitive) {
                mergedTitle = String(mergedTitle[..<range.lowerBound])
            }
        }
        
        return mergedTitle.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".-:;,/")))
    }
    
    return nil
}
