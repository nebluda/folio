import Foundation
import JavaScriptCore
import Markdown

/// Create one renderer per serial queue. No document JavaScript is ever evaluated.
public final class MarkdownRenderer {
    private let highlighter: JSContext?
    private let stylesheet: String
    private var headings: [String: Int] = [:]
    private var baseURL: URL?

    public init() {
        stylesheet = Self.resource("style", "css")
        highlighter = JSContext()
        highlighter?.evaluateScript(Self.resource("highlight.min", "js"))
        highlighter?.evaluateScript("function folioHighlight(code, language) { if (!hljs.getLanguage(language)) return null; return hljs.highlight(code, {language:language, ignoreIllegals:true}).value; }")
    }

    private static func resource(_ name: String, _ ext: String) -> String {
        let bundle = Bundle.main.url(forResource: "Folio_FolioCore", withExtension: "bundle").flatMap(Bundle.init(url:)) ?? Bundle.module
        guard let url = bundle.url(forResource: name, withExtension: ext) else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    public func render(_ source: String, fileURL: URL? = nil) -> String {
        headings = [:]
        baseURL = fileURL?.deletingLastPathComponent()
        let content = children(Document(parsing: source))
        return """
        <!doctype html><html lang="en"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data:; script-src 'none'; base-uri 'none'; form-action 'none'">
        <style>\(stylesheet)</style></head><body><main>\(content)</main></body></html>
        """
    }

    public static func escape(_ string: String) -> String {
        string.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    public static func safeLink(_ destination: String, relativeTo base: URL?) -> URL? {
        guard !destination.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let url = URL(string: destination, relativeTo: base)?.absoluteURL else { return nil }
        if destination.hasPrefix("#") { return URL(string: destination) }
        guard let scheme = url.scheme?.lowercased(), ["http", "https", "mailto", "file"].contains(scheme) else { return nil }
        // A document link must never launch local executables or arbitrary applications.
        if scheme == "file" && !["md", "markdown"].contains(url.pathExtension.lowercased()) { return nil }
        return url
    }

    private func children(_ node: Markup) -> String { node.children.map { renderNode($0) }.joined() }
    private func plain(_ node: Markup) -> String {
        if let text = node as? Text { return text.string }
        if let code = node as? InlineCode { return code.code }
        return node.children.map { plain($0) }.joined()
    }

    private func renderNode(_ node: Markup) -> String {
        switch node {
        case let n as Text: return Self.escape(n.string)
        case let n as Heading:
            let slug = plain(n).lowercased().filter { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" || $0 == "_" }.replacingOccurrences(of: " ", with: "-")
            let count = headings[slug, default: 0]; headings[slug] = count + 1
            let id = slug + (count == 0 ? "" : "-\(count)")
            return "<h\(n.level) id=\"\(Self.escape(id))\">\(children(n))</h\(n.level)>"
        case let n as Paragraph: return "<p>\(children(n))</p>"
        case let n as Strong: return "<strong>\(children(n))</strong>"
        case let n as Emphasis: return "<em>\(children(n))</em>"
        case let n as Strikethrough: return "<del>\(children(n))</del>"
        case let n as InlineCode: return "<code>\(Self.escape(n.code))</code>"
        case let n as CodeBlock:
            let language = (n.language ?? "").split(separator: " ").first.map(String.init) ?? ""
            var html = Self.escape(n.code)
            // Bound highlighting work; long fences still render as readable code.
            if n.code.utf8.count < 100_000, !language.isEmpty,
               let value = highlighter?.objectForKeyedSubscript("folioHighlight")?.call(withArguments: [n.code, language]),
               !value.isNull, !value.isUndefined, let highlighted = value.toString() { html = highlighted }
            return "<pre><code>\(html)</code></pre>"
        case let n as UnorderedList: return "<ul>\(children(n))</ul>"
        case let n as OrderedList: return "<ol start=\"\(n.startIndex)\">\(children(n))</ol>"
        case let n as ListItem:
            if let checkbox = n.checkbox {
                let checked = checkbox == .checked
                let body = n.children.enumerated().map { index, child in
                    index == 0 && child is Paragraph ? children(child) : renderNode(child)
                }.joined()
                return "<li class=\"task\"><span class=\"checkbox\" role=\"img\" aria-label=\"\(checked ? "Complete" : "Incomplete")\">\(checked ? "☑" : "☐")</span>\(body)</li>"
            }
            return "<li>\(children(n))</li>"
        case let n as BlockQuote: return "<blockquote>\(children(n))</blockquote>"
        case is ThematicBreak: return "<hr>"
        case is SoftBreak: return "\n"
        case is LineBreak: return "<br>"
        case let n as Link:
            guard let dest = n.destination, let url = Self.safeLink(dest, relativeTo: baseURL) else { return children(n) }
            return "<a href=\"\(Self.escape(url.absoluteString))\">\(children(n))</a>"
        case let n as Image: return image(n)
        case let n as InlineHTML: return Self.escape(n.rawHTML)
        case let n as HTMLBlock: return "<pre>\(Self.escape(n.rawHTML))</pre>"
        case let n as Table:
            func row(_ cells: MarkupChildren, tag: String) -> String {
                "<tr>" + cells.enumerated().map { index, cell in
                    let alignment = index < n.columnAlignments.count ? n.columnAlignments[index] : nil
                    let css = alignment == .right ? "align-right" : alignment == .center ? "align-center" : "align-left"
                    return "<\(tag) class=\"\(css)\">\(children(cell))</\(tag)>"
                }.joined() + "</tr>"
            }
            return "<div class=\"table-wrap\"><table><thead>" + row(n.head.children, tag: "th") + "</thead><tbody>" + n.body.children.map { row($0.children, tag: "td") }.joined() + "</tbody></table></div>"
        default: return children(node)
        }
    }

    private func image(_ node: Image) -> String {
        let alt = Self.escape(plain(node).isEmpty ? "Image" : plain(node))
        func placeholder(_ reason: String) -> String { "<span class=\"image-placeholder\" role=\"img\" aria-label=\"\(alt)\">\(alt) · \(reason)</span>" }
        guard let source = node.source, let baseURL,
              let url = URL(string: source, relativeTo: baseURL)?.absoluteURL, url.isFileURL else {
            return placeholder("image not loaded")
        }
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
        let root = baseURL.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        guard resolved.path.hasPrefix(root) else { return placeholder("outside document folder") }
        let types = ["png":"image/png", "jpg":"image/jpeg", "jpeg":"image/jpeg", "gif":"image/gif", "webp":"image/webp"]
        guard let mime = types[resolved.pathExtension.lowercased()],
              let size = try? resolved.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 5 * 1024 * 1024,
              let data = try? Data(contentsOf: resolved) else { return placeholder("image unavailable") }
        return "<img alt=\"\(alt)\" src=\"data:\(mime);base64,\(data.base64EncodedString())\">"
    }
}
