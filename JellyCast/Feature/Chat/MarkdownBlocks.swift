import Foundation

/// The block structure of a chat answer: what `AttributedString(markdown:)` leaves out, since
/// it only styles inline text and drops tables, lists and headings into one run.
nonisolated enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case listItem(marker: String, depth: Int, text: String)
    case quote(String)
    case code(String)
    case table(header: [String], rows: [[String]])
    case rule

    static func parse(_ markdown: String) -> [MarkdownBlock] {
        var parser = Parser(lines: markdown.components(separatedBy: .newlines))
        return parser.blocks()
    }

    /// Inline Markdown (bold, italic, code, links) as styled text; plain text when it doesn't parse.
    static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

private nonisolated struct Parser {
    let lines: [String]
    var position = 0
    var paragraph: [String] = []
    var result: [MarkdownBlock] = []

    private static let spacesPerDepth = 2
    private static let maxHeadingLevel = 6

    init(lines: [String]) {
        self.lines = lines
    }

    mutating func blocks() -> [MarkdownBlock] {
        while position < lines.count {
            let line = lines[position]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flushParagraph()
                position += 1
            } else if trimmed.hasPrefix("```") {
                flushParagraph()
                readCode()
            } else if isTableStart {
                flushParagraph()
                readTable()
            } else if let block = Self.singleLineBlock(line, trimmed: trimmed) {
                flushParagraph()
                result.append(block)
                position += 1
            } else {
                paragraph.append(trimmed)
                position += 1
            }
        }
        flushParagraph()
        return result
    }

    private mutating func flushParagraph() {
        guard !paragraph.isEmpty else { return }
        result.append(.paragraph(paragraph.joined(separator: "\n")))
        paragraph = []
    }

    private static func singleLineBlock(_ line: String, trimmed: String) -> MarkdownBlock? {
        if isRule(trimmed) { return .rule }
        if let heading = heading(trimmed) { return heading }
        if trimmed.hasPrefix(">") {
            return .quote(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
        }
        return listItem(line)
    }

    private static func isRule(_ trimmed: String) -> Bool {
        let compact = trimmed.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3, let first = compact.first, "-*_".contains(first) else { return false }
        return compact.allSatisfy { $0 == first }
    }

    private static func heading(_ trimmed: String) -> MarkdownBlock? {
        let hashes = trimmed.prefix { $0 == "#" }.count
        guard (1...maxHeadingLevel).contains(hashes) else { return nil }
        let rest = trimmed.dropFirst(hashes)
        guard rest.first == " " else { return nil }
        return .heading(level: hashes, text: rest.trimmingCharacters(in: .whitespaces))
    }

    private static func listItem(_ line: String) -> MarkdownBlock? {
        let indent = line.prefix { $0 == " " || $0 == "\t" }
            .reduce(0) { $0 + ($1 == "\t" ? spacesPerDepth : 1) }
        let body = line.drop { $0 == " " || $0 == "\t" }
        let depth = indent / spacesPerDepth
        if let first = body.first, "-*+".contains(first), body.dropFirst().first == " " {
            return .listItem(marker: "•", depth: depth, text: String(body.dropFirst(2)))
        }
        let digits = body.prefix { $0.isNumber }
        let afterDigits = body.dropFirst(digits.count)
        guard !digits.isEmpty, digits.count <= 3, let dot = afterDigits.first, ".)".contains(dot),
              afterDigits.dropFirst().first == " "
        else { return nil }
        return .listItem(marker: "\(digits).", depth: depth, text: String(afterDigits.dropFirst(2)))
    }

    private mutating func readCode() {
        position += 1
        var code: [String] = []
        while position < lines.count, !lines[position].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
            code.append(lines[position])
            position += 1
        }
        position += 1
        result.append(.code(code.joined(separator: "\n")))
    }

    private var isTableStart: Bool {
        guard position + 1 < lines.count,
              lines[position].trimmingCharacters(in: .whitespaces).hasPrefix("|")
        else { return false }
        return Self.isSeparator(lines[position + 1])
    }

    private static func isSeparator(_ line: String) -> Bool {
        let cells = cells(line)
        return !cells.isEmpty && cells.allSatisfy { cell in
            !cell.isEmpty && cell.allSatisfy { "-:".contains($0) } && cell.contains("-")
        }
    }

    private mutating func readTable() {
        let header = Self.cells(lines[position])
        position += 2
        var rows: [[String]] = []
        while position < lines.count, lines[position].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
            let row = Self.cells(lines[position])
            rows.append(Array((row + Array(repeating: "", count: header.count)).prefix(header.count)))
            position += 1
        }
        result.append(.table(header: header, rows: rows))
    }

    private static func cells(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }
        return trimmed.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
