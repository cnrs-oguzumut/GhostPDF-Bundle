import Foundation

struct BibTeXFormatOptions {
    var shortenAuthors: Bool = false
    var abbreviateJournals: Bool = false
    var useLaTeXEscaping: Bool = false
    var addDotsToInitials: Bool = false // Minimalist Mode
}

func reformatBibTeX(_ bibtexText: String, options: BibTeXFormatOptions = BibTeXFormatOptions()) -> String {
    var modifiedEntry = bibtexText
    let authorPattern = #"author\s*=\s*\{([^}]+)\}"#
    
    guard let regex = try? NSRegularExpression(pattern: authorPattern, options: .caseInsensitive),
          let match = regex.firstMatch(in: modifiedEntry, range: NSRange(modifiedEntry.startIndex..., in: modifiedEntry)),
          let range = Range(match.range(at: 1), in: modifiedEntry) else { return bibtexText }
    
    let authors = String(modifiedEntry[range])
    var normalized = authors
    
    // Legacy ALL CAPS check (omitted for brevity as we know user just wants the processing logic)
    // Applying the unconditional logic from PDFCompressor.swift
    
    if options.addDotsToInitials {
         // ... (add dots logic)
    } else {
        // Current Logic: Match ANY Uppercase Letter followed by a dot
        let dotPattern = #"([A-Z])\."#
        if let dotRegex = try? NSRegularExpression(pattern: dotPattern, options: []) {
             let nsRange = NSRange(location: 0, length: normalized.count)
             normalized = dotRegex.stringByReplacingMatches(
                 in: normalized,
                 options: [],
                 range: nsRange,
                 withTemplate: "$1"
             )
        }
    }
    
    if normalized != authors {
        modifiedEntry = modifiedEntry.replacingOccurrences(of: authors, with: normalized)
    }
    
    return modifiedEntry
}

// TEST CASES
// User Case: N.P. van Dijk -> N P van Dijk
let case1 = "author = {N.P. van Dijk}"
// Variant: J.J. Espadas -> J J Espadas
let case2 = "author = {J.J. Espadas}"
// Variant: Already Spaced: J. J. Espadas -> J J Espadas
let case3 = "author = {J. J. Espadas}"

print("--- Testing Minimalist Reformat (NO DOTS) ---")
print("Case 1 (N.P.): \(reformatBibTeX(case1))") // Expect: N P van Dijk
print("Case 2 (J.J.): \(reformatBibTeX(case2))") // Expect: J J Espadas
print("Case 3 (J. J.): \(reformatBibTeX(case3))") // Expect: J J Espadas
