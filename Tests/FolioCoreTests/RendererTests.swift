import XCTest
@testable import FolioCore

final class RendererTests: XCTestCase {
    private var renderer: MarkdownRenderer!
    override func setUp() { renderer = MarkdownRenderer() }

    func testGitHubMarkdown() {
        let source = """
        # A heading
        ## A heading

        **bold** *italic* ~~gone~~ `inline`

        > A quote

        - [x] done
        - [ ] pending

        3. three
        4. four

        | Left | Right |
        | :--- | ---: |
        | one | two |

        ---

        ```swift
        let value = "hello"
        ```
        """
        let html = renderer.render(source)
        for expected in ["<h1 id=\"a-heading\">", "id=\"a-heading-1\"", "<strong>bold</strong>", "<em>italic</em>", "<del>gone</del>", "<code>inline</code>", "<blockquote>", "aria-label=\"Complete\"", "aria-label=\"Incomplete\"", "<ol start=\"3\">", "<table>", "align-right", "<hr>", "hljs-keyword"] {
            XCTAssertTrue(html.contains(expected), "Missing \(expected)")
        }
    }

    func testUntrustedHTMLAndURLsAreInert() {
        let html = renderer.render("""
        <script>alert('x')</script>

        <img src=x onerror=alert(1)>

        [bad](javascript:alert%281%29) [data](data:text/html,x) [app](x-apple.systempreferences:foo)
        """)
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertFalse(html.contains("<img src=x"))
        XCTAssertFalse(html.contains("href=\"javascript:"))
        XCTAssertFalse(html.contains("href=\"data:"))
        XCTAssertFalse(html.contains("href=\"x-apple"))
        XCTAssertTrue(html.contains("script-src 'none'"))
        XCTAssertTrue(html.contains("&lt;script&gt;"))
    }

    func testLinksAndAnchors() {
        let html = renderer.render("[site](https://example.com) [section](#hello) [next](next.md)", fileURL: URL(fileURLWithPath: "/tmp/docs/readme.md"))
        XCTAssertTrue(html.contains("href=\"https://example.com\""))
        XCTAssertTrue(html.contains("href=\"#hello\""))
        XCTAssertTrue(html.contains("href=\"file:///tmp/docs/next.md\""))
        XCTAssertNil(MarkdownRenderer.safeLink("file:///Applications/Calculator.app", relativeTo: nil))
        XCTAssertNil(MarkdownRenderer.safeLink("java\nscript:alert(1)", relativeTo: nil))
    }

    func testMissingRemoteAndEscapingImages() throws {
        let html = renderer.render("![local](missing.png) ![remote](https://example.com/track.png) ![escape](../secret.png)", fileURL: URL(fileURLWithPath: "/tmp/docs/readme.md"))
        XCTAssertFalse(html.contains("<img"))
        XCTAssertTrue(html.contains("image unavailable"))
        XCTAssertTrue(html.contains("image not loaded"))
        XCTAssertTrue(html.contains("outside document folder"))
    }

    func testLocalImageAndSymlinkBoundary() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data([1, 2, 3]).write(to: directory.appendingPathComponent("image.png"))
        let html = renderer.render("![sample](image.png)", fileURL: directory.appendingPathComponent("readme.md"))
        XCTAssertTrue(html.contains("src=\"data:image/png;base64,AQID\""))
        try FileManager.default.createSymbolicLink(atPath: directory.appendingPathComponent("escape.png").path, withDestinationPath: "/etc/hosts")
        XCTAssertFalse(renderer.render("![](escape.png)", fileURL: directory.appendingPathComponent("readme.md")).contains("<img"))
    }

    func testMalformedAndUnicode() {
        let html = renderer.render("# Café 日本語\n\n**unfinished [broken](\n\n```unknown\n<script> & text")
        XCTAssertTrue(html.contains("Café 日本語"))
        XCTAssertTrue(html.contains("&lt;script&gt; &amp; text"))
    }

    func testLargeCodeFenceSkipsExpensiveHighlighting() {
        let html = renderer.render("```swift\n" + String(repeating: "let a = 1\n", count: 15_000) + "```")
        XCTAssertTrue(html.contains("<pre><code>let a = 1"))
    }
}
