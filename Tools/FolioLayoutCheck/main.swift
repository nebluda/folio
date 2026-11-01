import AppKit
import FolioCore
import WebKit

// Exercise real WebKit layout, including the HTML/CSP used by both the app and Quick Look.
// Runs with Command Line Tools as well as full Xcode; no XCTest runtime required.
final class LayoutCheck: NSObject, WKNavigationDelegate {
    let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 1100))
    var loaded = false
    var navigationError: Error?

    override init() {
        super.init()
        webView.navigationDelegate = self
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded = true }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navigationError = error
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        navigationError = error
    }

    func wait(until done: () -> Bool) throws {
        let deadline = Date(timeIntervalSinceNow: 20)
        while !done() && Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        }
        guard done() else { throw CheckError.failure("WebKit timed out") }
        if let navigationError { throw navigationError }
    }

    func evaluate(_ script: String) throws -> Any {
        var result: Result<Any, Error>?
        webView.evaluateJavaScript(script) { value, error in
            result = error.map { .failure($0) } ?? .success(value ?? NSNull())
        }
        try wait { result != nil }
        return try result!.get()
    }

    func snapshot(to url: URL) throws {
        var result: Result<NSImage, Error>?
        webView.takeSnapshot(with: nil) { image, error in
            if let image { result = .success(image) }
            else { result = .failure(error ?? CheckError.failure("No WebKit snapshot")) }
        }
        try wait { result != nil }
        let image = try result!.get()
        guard let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            throw CheckError.failure("Cannot encode WebKit snapshot")
        }
        try png.write(to: url)
    }
}

enum CheckError: Error { case failure(String) }

let probe = #"""
(() => {
    const tables = [...document.querySelectorAll('table')];
    const width = e => e.getBoundingClientRect().width;
    const cells = [...tables[0].rows[0].cells];
    // Check actual text fragments, not the presence of a particular CSS declaration.
    function lines(e) {
        const range = document.createRange(); range.selectNodeContents(e);
        return new Set([...range.getClientRects()].filter(r => r.width > 0).map(r => Math.round(r.top))).size;
    }
    const failures = [];
    function check(ok, message) { if (!ok) failures.push(message); }
    check(lines(cells[0]) === 1, 'Consumer header breaks across lines');
    check(lines(tables[0].rows[2].cells[0]) === 1, 'device_firmware label breaks across lines');
    check(cells.every(c => c.clientWidth >= c.scrollWidth - 1), 'Header content overflows its cell');
    check(width(tables[1].rows[0].cells[0]) < width(tables[1].rows[0].cells[2]), 'Compact ID column wastes description space');
    check(document.documentElement.scrollWidth <= innerWidth + 1, 'Table causes page-wide horizontal overflow');
    for (const table of tables) {
        const wrap = table.parentElement;
        const rect = wrap.getBoundingClientRect();
        check(rect.left >= -1 && rect.right <= innerWidth + 1, 'Table scroll container escapes viewport');
        if (wrap.scrollWidth > wrap.clientWidth + 1) {
            wrap.scrollLeft = wrap.scrollWidth;
            check(wrap.scrollLeft > 0, 'Overflowing table cannot scroll');
            wrap.scrollLeft = 0;
        }
    }
    if (innerWidth >= 700) {
        check(tables[0].parentElement.scrollWidth <= tables[0].parentElement.clientWidth + 1,
              'Ordinary mixed-content table scrolls despite sufficient room');
        check(width(cells[2]) > width(cells[0]), 'Description does not receive remaining space');
    }
    if (innerWidth > 1000) {
        const main = document.querySelector('main');
        const style = getComputedStyle(main);
        check(width(tables[0]) > width(main) - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight),
              'Wide table remains constrained to prose width');
    }
    return {viewport: innerWidth, columns: cells.map(c => Math.round(width(c))), failures};
})()
"""#

do {
    _ = NSApplication.shared
    let source = try String(contentsOfFile: "Fixtures/TableLayout.md", encoding: .utf8)
    let html = MarkdownRenderer().render(source)
    let check = LayoutCheck()
    let window = NSWindow(contentRect: check.webView.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = check.webView
    let output = CommandLine.arguments.dropFirst().first.map { URL(fileURLWithPath: $0, isDirectory: true) }
    if let output { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
    var failures: [String] = []
    let scenarios: [(Double, Double, Bool)] = [
        (360, 1, false), (540, 1, false), (800, 1, false), (1280, 1, false),
        (800, 1.5, false), (800, 2, false), (1280, 1, true), (800, 2, true),
    ]
    for (width, zoom, dark) in scenarios {
        window.setContentSize(NSSize(width: width, height: 1100))
        check.webView.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        check.webView.pageZoom = zoom
        check.loaded = false
        check.webView.loadHTMLString(html, baseURL: nil)
        try check.wait { check.loaded || check.navigationError != nil }
        let result = try check.evaluate(probe) as! [String: Any]
        let errors = result["failures"] as! [String]
        let name = "width-\(Int(width))-zoom-\(zoom)-\(dark ? "dark" : "light")"
        failures += errors.map { "\(name): \($0)" }
        let json = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print("\(name): \(String(decoding: json, as: UTF8.self))")
        if let output { try check.snapshot(to: output.appendingPathComponent("\(name).png")) }
    }
    guard failures.isEmpty else { throw CheckError.failure(failures.joined(separator: "\n")) }
    print("All \(scenarios.count) WebKit table layout scenarios passed.")
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
