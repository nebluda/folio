import Foundation
import Markdown

/// Semantic source ranges in AppKit's UTF-16 coordinates. No document text is rewritten.
public enum MarkdownSyntax {
    public enum Kind: Equatable { case heading, strong, emphasis, link, code, quote, marker, strikethrough }
    public struct Span: Equatable {
        public let range: NSRange
        public let kind: Kind
    }

    private static let listMarker = try! NSRegularExpression(pattern: #"^[ \t]*(?:[-+*]|[0-9]+[.)])[ \t]+(?:\[[ xX]\][ \t]+)?"#)
    private static let tableMarker = try! NSRegularExpression(pattern: #"\||(?m:^[ \t|]*:?-{3,}[-:| \t]*$)"#)

    public static func spans(in source: String) -> [Span] {
        // cmark reports UTF-8 columns; NSTextView uses UTF-16. Build the conversion
        // once to keep many spans linear, including emoji and combining marks.
        var offsets: [Int32] = []
        offsets.reserveCapacity(source.utf8.count + 1)
        var lines = [0], utf16 = 0, previousCR = false
        for scalar in source.unicodeScalars {
            for _ in 0..<scalar.utf8.count { offsets.append(Int32(utf16)) }
            utf16 += scalar.utf16.count
            if scalar.value == 10 && previousCR { lines[lines.count - 1] = offsets.count }
            else if scalar.value == 10 || scalar.value == 13 { lines.append(offsets.count) }
            previousCR = scalar.value == 13
        }
        offsets.append(Int32(utf16))
        func position(_ location: SourceLocation) -> Int? {
            guard location.line > 0, location.line <= lines.count, location.column > 0 else { return nil }
            let byte = lines[location.line - 1] + location.column - 1
            let end = location.line < lines.count ? lines[location.line] : offsets.count - 1
            guard byte <= end, byte < offsets.count else { return nil }
            return Int(offsets[byte])
        }
        func range(_ node: Markup) -> NSRange? {
            guard let sourceRange = node.range, let start = position(sourceRange.lowerBound),
                  let end = position(sourceRange.upperBound), end > start else { return nil }
            return NSRange(location: start, length: end - start)
        }
        var result: [Span] = []
        var pending: [Markup] = [Document(parsing: source)]
        while let node = pending.popLast() {
            if let range = range(node) {
                let kind: Kind?
                switch node {
                case is Heading: kind = .heading
                case is Strong: kind = .strong
                case is Emphasis: kind = .emphasis
                case is Link, is Image: kind = .link
                case is InlineCode, is CodeBlock: kind = .code
                case is BlockQuote: kind = .quote
                case is Strikethrough: kind = .strikethrough
                case is ThematicBreak, is HTMLBlock, is InlineHTML: kind = .marker
                default: kind = nil
                }
                if let kind { result.append(Span(range: range, kind: kind)) }
                if node is ListItem,
                   let match = listMarker.firstMatch(in: source, range: range) {
                    result.append(Span(range: match.range, kind: .marker))
                }
                if node is Table {
                    for match in tableMarker.matches(in: source, range: range) {
                        result.append(Span(range: match.range, kind: .marker))
                    }
                }
            }
            // Parent styles first; inline syntax can override the surrounding quote/heading.
            pending.append(contentsOf: node.children.reversed())
        }
        return result
    }
}
