import Foundation

/// Citation style options
enum CitationStyle: String, CaseIterable, Identifiable {
    case apa = "APA"
    case mla = "MLA"
    case chicago = "Chicago"

    var id: String { rawValue }
}

/// Parse and format BibTeX entries into readable citations
struct CitationFormatter {

    /// Format a BibTeX entry according to the specified citation style
    static func format(_ bibtexEntry: String, style: CitationStyle) -> String {
        let parsed = parseBibTeX(bibtexEntry)

        switch style {
        case .apa:
            return formatAPA(parsed)
        case .mla:
            return formatMLA(parsed)
        case .chicago:
            return formatChicago(parsed)
        }
    }

    /// Format multiple BibTeX entries
    static func formatMultiple(_ bibtexText: String, style: CitationStyle) -> String {
        let entries = bibtexText.components(separatedBy: "\n\n")
            .filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).starts(with: "@") }

        return entries.map { format($0, style: style) }.joined(separator: "\n\n")
    }

    // MARK: - Parsing

    private static func parseBibTeX(_ entry: String) -> [String: String] {
        var fields: [String: String] = [:]

        let lines = entry.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Match field = {value} pattern
            if let range = trimmed.range(of: #"(\w+)\s*=\s*\{([^}]+)\}"#, options: .regularExpression) {
                let match = String(trimmed[range])
                let parts = match.components(separatedBy: "=")
                if parts.count == 2 {
                    let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
                    let value = parts[1]
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
                    fields[key] = value
                }
            }
        }

        return fields
    }

    // MARK: - APA Style

    private static func formatAPA(_ fields: [String: String]) -> String {
        var result = ""

        // Authors
        if let authors = fields["author"] {
            result += formatAPAAuthors(authors) + " "
        }

        // Year
        if let year = fields["year"] {
            result += "(\(year)). "
        }

        // Title
        if let title = fields["title"] {
            result += "\(title). "
        }

        // Journal
        if let journal = fields["journal"] {
            result += "\(journal)"

            // Volume
            if let volume = fields["volume"] {
                result += ", \(volume)"
            }

            // Issue
            if let issue = fields["number"] ?? fields["issue"] {
                result += "(\(issue))"
            }

            // Pages
            if let pages = fields["pages"] {
                result += ", \(pages)"
            }

            result += ". "
        }

        // DOI
        if let doi = fields["doi"] {
            result += "https://doi.org/\(doi)"
        }

        return result.trimmingCharacters(in: .whitespaces)
    }

    private static func formatAPAAuthors(_ authors: String) -> String {
        let authorList = authors.components(separatedBy: " and ").map { $0.trimmingCharacters(in: .whitespaces) }

        if authorList.count == 1 {
            return formatAPASingleAuthor(authorList[0])
        } else if authorList.count == 2 {
            return "\(formatAPASingleAuthor(authorList[0])), & \(formatAPASingleAuthor(authorList[1]))"
        } else {
            let formatted = authorList.prefix(authorList.count - 1).map { formatAPASingleAuthor($0) }
            return formatted.joined(separator: ", ") + ", & " + formatAPASingleAuthor(authorList.last!)
        }
    }

    private static func formatAPASingleAuthor(_ author: String) -> String {
        // Handle "Last, First" format
        if author.contains(",") {
            let parts = author.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 {
                let last = parts[0]
                let first = parts[1].components(separatedBy: " ").map { String($0.prefix(1)) + "." }.joined(separator: " ")
                return "\(last), \(first)"
            }
        }

        // Handle "First Last" format
        let parts = author.components(separatedBy: " ").filter { !$0.isEmpty }
        if parts.count >= 2 {
            let last = parts.last!
            let first = parts.dropLast().map { String($0.prefix(1)) + "." }.joined(separator: " ")
            return "\(last), \(first)"
        }

        return author
    }

    // MARK: - MLA Style

    private static func formatMLA(_ fields: [String: String]) -> String {
        var result = ""

        // Authors
        if let authors = fields["author"] {
            result += formatMLAAuthors(authors) + ". "
        }

        // Title
        if let title = fields["title"] {
            result += "\"\(title).\" "
        }

        // Journal
        if let journal = fields["journal"] {
            result += "\(journal), "

            // Volume
            if let volume = fields["volume"] {
                result += "vol. \(volume), "
            }

            // Issue
            if let issue = fields["number"] ?? fields["issue"] {
                result += "no. \(issue), "
            }
        }

        // Year
        if let year = fields["year"] {
            result += "\(year), "
        }

        // Pages
        if let pages = fields["pages"] {
            result += "pp. \(pages)."
        }

        return result.trimmingCharacters(in: CharacterSet(charactersIn: ", "))
    }

    private static func formatMLAAuthors(_ authors: String) -> String {
        let authorList = authors.components(separatedBy: " and ").map { $0.trimmingCharacters(in: .whitespaces) }

        if authorList.isEmpty { return "" }
        if authorList.count == 1 { return formatMLASingleAuthor(authorList[0]) }

        // First author: Last, First
        var result = formatMLASingleAuthor(authorList[0])

        // Remaining authors: First Last
        if authorList.count == 2 {
            result += ", and " + formatMLAOtherAuthor(authorList[1])
        } else {
            let others = authorList.dropFirst().map { formatMLAOtherAuthor($0) }
            result += ", " + others.joined(separator: ", and ")
        }

        return result
    }

    private static func formatMLASingleAuthor(_ author: String) -> String {
        // Handle "Last, First" format
        if author.contains(",") {
            return author
        }

        // Handle "First Last" format - convert to "Last, First"
        let parts = author.components(separatedBy: " ").filter { !$0.isEmpty }
        if parts.count >= 2 {
            let last = parts.last!
            let first = parts.dropLast().joined(separator: " ")
            return "\(last), \(first)"
        }

        return author
    }

    private static func formatMLAOtherAuthor(_ author: String) -> String {
        // Handle "Last, First" format - convert to "First Last"
        if author.contains(",") {
            let parts = author.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 {
                return "\(parts[1]) \(parts[0])"
            }
        }

        return author
    }

    // MARK: - Chicago Style

    private static func formatChicago(_ fields: [String: String]) -> String {
        var result = ""

        // Authors
        if let authors = fields["author"] {
            result += formatChicagoAuthors(authors) + ". "
        }

        // Title
        if let title = fields["title"] {
            result += "\"\(title).\" "
        }

        // Journal
        if let journal = fields["journal"] {
            result += "\(journal) "

            // Volume
            if let volume = fields["volume"] {
                result += "\(volume), "
            }

            // Issue
            if let issue = fields["number"] ?? fields["issue"] {
                result += "no. \(issue) "
            }
        }

        // Year
        if let year = fields["year"] {
            result += "(\(year)): "
        }

        // Pages
        if let pages = fields["pages"] {
            result += "\(pages)."
        }

        return result.trimmingCharacters(in: .whitespaces)
    }

    private static func formatChicagoAuthors(_ authors: String) -> String {
        let authorList = authors.components(separatedBy: " and ").map { $0.trimmingCharacters(in: .whitespaces) }

        if authorList.isEmpty { return "" }
        if authorList.count == 1 { return formatMLASingleAuthor(authorList[0]) }

        // First author: Last, First
        var result = formatMLASingleAuthor(authorList[0])

        // Remaining authors: First Last
        let others = authorList.dropFirst().map { formatMLAOtherAuthor($0) }
        result += ", and " + others.joined(separator: ", ")

        return result
    }
}
