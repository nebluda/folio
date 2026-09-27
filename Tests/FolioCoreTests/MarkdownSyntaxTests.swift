import XCTest
@testable import FolioCore

final class MarkdownSyntaxTests: XCTestCase {
    func testSemanticRangesAndUnicode() {
        let source = "# Café 👋\n\n日本語 **bold** and *italic* [site](https://example.com) `code` ~~gone~~\n"
        let spans = MarkdownSyntax.spans(in: source)
        let text = source as NSString
        func contains(_ value: String, _ kind: MarkdownSyntax.Kind) -> Bool {
            spans.contains { $0.kind == kind && text.substring(with: $0.range) == value }
        }
        XCTAssertTrue(contains("# Café 👋", .heading))
        XCTAssertTrue(contains("**bold**", .strong))
        XCTAssertTrue(contains("*italic*", .emphasis))
        XCTAssertTrue(contains("[site](https://example.com)", .link))
        XCTAssertTrue(contains("`code`", .code))
        XCTAssertTrue(contains("~~gone~~", .strikethrough))
    }

    func testCodeDoesNotParseMarkdownAndMalformedInputIsSafe() {
        let source = "```md\n# not a heading\n**not bold**\n```\n\n\\*escaped\\* and **unfinished 👩🏽‍💻"
        let spans = MarkdownSyntax.spans(in: source)
        XCTAssertEqual(spans.filter { $0.kind == .code }.count, 1)
        XCTAssertFalse(spans.contains { $0.kind == .heading || $0.kind == .strong || $0.kind == .emphasis })
        for span in spans { XCTAssertLessThanOrEqual(NSMaxRange(span.range), (source as NSString).length) }
    }

    func testListsQuotesTablesAndNestedEmphasis() {
        let source = "- [x] Done\n\n> A **bold** quote\n\n| A | B |\n| --- | --- |\n| x | y |\n"
        let spans = MarkdownSyntax.spans(in: source)
        let text = source as NSString
        XCTAssertTrue(spans.contains { $0.kind == .marker && text.substring(with: $0.range).contains("[x]") })
        XCTAssertTrue(spans.contains { $0.kind == .quote })
        XCTAssertTrue(spans.contains { $0.kind == .strong })
        XCTAssertTrue(spans.contains { $0.kind == .marker && text.substring(with: $0.range) == "|" })
    }

    func testEmptyAndWindowsLineEndings() {
        XCTAssertTrue(MarkdownSyntax.spans(in: "").isEmpty)
        let source = "👋\r\n\r\n## Title\r\n\r\n**Café**"
        let spans = MarkdownSyntax.spans(in: source)
        XCTAssertTrue(spans.contains { $0.kind == .strong && (source as NSString).substring(with: $0.range) == "**Café**" })
    }
}
