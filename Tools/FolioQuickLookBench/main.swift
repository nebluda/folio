import AppKit
import QuickLookUI
import WebKit

// This probe owns the preview view and inspects only its generated fixture HTML.
// QLPreviewView has no public ready callback; an HTML Quick Look preview embeds a WKWebView.
func webView(in view: NSView) -> WKWebView? {
    if let view = view as? WKWebView { return view }
    return view.subviews.lazy.compactMap { webView(in: $0) }.first
}

enum ProbeError: Error {
    case invalidArguments
    case missingPreview
    case timedOut(String)
    case tailNotVisible
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard !arguments.isEmpty, arguments.count.isMultiple(of: 2) else { throw ProbeError.invalidArguments }

    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let frame = NSRect(x: 0, y: 0, width: 800, height: 650)
    let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
    guard let preview = QLPreviewView(frame: frame, style: .normal) else { throw ProbeError.missingPreview }
    window.contentView = preview
    window.orderBack(nil)
    defer { preview.close() }

    for index in stride(from: 0, to: arguments.count, by: 2) {
        let path = arguments[index]
        let heading = arguments[index + 1]
        let start = DispatchTime.now()
        preview.previewItem = URL(fileURLWithPath: path) as NSURL

        var result: Double?
        var pending = false
        let deadline = start + .seconds(15)
        while result == nil, DispatchTime.now() < deadline {
            if let page = webView(in: preview), !page.isLoading, !pending {
                pending = true
                page.evaluateJavaScript("""
                    document.readyState === 'complete' &&
                    document.querySelector('main h2')?.textContent
                    """) { value, _ in
                    pending = false
                    guard value as? String == heading else { return }
                    result = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
                }
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.005))
        }
        guard let result else { throw ProbeError.timedOut(heading) }
        print(result)
    }
    if ProcessInfo.processInfo.environment["FOLIO_QL_VERIFY_TAIL"] == "1" {
        guard let page = webView(in: preview) else { throw ProbeError.missingPreview }
        var visible: Bool?
        page.callAsyncJavaScript("""
            const heading = Array.from(document.querySelectorAll('main h2')).at(-1);
            heading.scrollIntoView();
            const rect = heading.getBoundingClientRect();
            return { scrollY, top: rect.top, bottom: rect.bottom, height: innerHeight };
            """, arguments: [:], in: nil, in: .defaultClient) { result in
            if case .success(let value) = result, let geometry = value as? [String: Double] {
                visible = geometry["scrollY", default: 0] > 0 &&
                    geometry["bottom", default: 0] > 0 &&
                    geometry["top", default: .infinity] < geometry["height", default: 0]
            } else {
                FileHandle.standardError.write(Data("Tail probe returned \(result)\n".utf8))
                visible = false
            }
        }
        let deadline = Date(timeIntervalSinceNow: 5)
        while visible == nil, Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.005))
        }
        guard visible == true else { throw ProbeError.tailNotVisible }
    }
    // Keep the window alive through the last WebKit callback.
    withExtendedLifetime(window) {}
} catch {
    FileHandle.standardError.write(Data("Quick Look probe failed: \(error)\n".utf8))
    exit(1)
}
