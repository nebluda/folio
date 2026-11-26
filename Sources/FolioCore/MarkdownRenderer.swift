import Foundation
import JavaScriptCore
import Markdown

public struct PreviewHeading: Sendable, Equatable {
    public let title: String
    public let id: String
    public let level: Int
}

public struct RenderedMarkdown: Sendable {
    public let html: String
    public let headings: [PreviewHeading]
    public let hasDeferredCode: Bool
}

/// Create one renderer per serial queue. No document JavaScript is ever evaluated.
public final class MarkdownRenderer {
    public enum Presentation {
        case full, reader, quickLook
    }

    private struct CodeKey: Hashable {
        let language: String
        let code: String
    }

    private lazy var highlighter = Self.makeHighlighter()
    private static let highlightLibrary = resource("highlight.min", "js")
    private var defersCode = false
    private var hasDeferredCode = false
    private var remainingHighlights = Int.max
    private var remainingHighlightBytes = Int.max
    private var highlightedCode: [CodeKey: String] = [:]
    private let stylesheet: String
    private var headings: [PreviewHeading] = []
    private var headingIDs: Set<String> = []
    private var nextSuffix: [String: Int] = [:]
    private var baseURL: URL?

    public init() {
        stylesheet = Self.resource("style", "css")
    }

    private static func makeHighlighter() -> (context: JSContext, function: JSValue)? {
        guard let context = JSContext() else { return nil }
        context.evaluateScript(highlightLibrary)
        guard let function = context.evaluateScript("""
            (function (code, language) {
                if (!hljs.getLanguage(language)) return null;
                return hljs.highlight(code, {language:language, ignoreIllegals:true}).value;
            })
            """) else { return nil }
        return (context, function)
    }

    /// Inject only into the reader's isolated WebKit content world.
    public static let deferredCodeScript = highlightLibrary + """

        (() => {
            const observer = new IntersectionObserver(entries => {
                for (const entry of entries) {
                    if (!entry.isIntersecting) continue;
                    const code = entry.target;
                    observer.unobserve(code);
                    const language = code.getAttribute('data-folio-language');
                    if (hljs.getLanguage(language)) {
                        code.innerHTML = hljs.highlight(code.textContent,
                            {language, ignoreIllegals: true}).value;
                    }
                }
            }, {rootMargin: '300px 0px'});
            document.querySelectorAll('code[data-folio-language]').forEach(code => observer.observe(code));
        })();
        """

    private static func resource(_ name: String, _ ext: String) -> String {
        let bundle = Bundle.main.url(forResource: "Folio_FolioCore", withExtension: "bundle").flatMap(Bundle.init(url:)) ?? Bundle.module
        guard let url = bundle.url(forResource: name, withExtension: ext) else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    public func render(_ source: String, fileURL: URL? = nil) -> String {
        renderPreview(source, fileURL: fileURL).html
    }

    public func renderPreview(
        _ source: String, fileURL: URL? = nil, presentation: Presentation = .full
    ) -> RenderedMarkdown {
        defer {
            headings = []
            headingIDs.removeAll(keepingCapacity: true)
            nextSuffix.removeAll(keepingCapacity: true)
            highlightedCode.removeAll(keepingCapacity: true)
            baseURL = nil
        }
        baseURL = fileURL?.deletingLastPathComponent()
        let largeDocument = source.utf8.count >= 256 * 1024
        defersCode = largeDocument && presentation == .reader
        hasDeferredCode = false
        let limitsHighlighting = largeDocument && presentation == .quickLook
        remainingHighlights = limitsHighlighting ? 64 : .max
        remainingHighlightBytes = limitsHighlighting ? 32 * 1024 : .max
        // Older WebKit releases can skip offscreen content during Find.
        var main = "<main>"
        if largeDocument, presentation != .full, #available(macOS 26, *) {
            main = "<main class=\"long-document\">"
        }
        var html = """
        <!doctype html><html lang="en"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data:; script-src 'none'; base-uri 'none'; form-action 'none'">
        <style>\(stylesheet)</style></head><body>\(main)
        """
        html.reserveCapacity(html.utf8.count + source.utf8.count)
        renderChildren(Document(parsing: source), into: &html)
        html += "</main></body></html>"
        return RenderedMarkdown(html: html, headings: headings, hasDeferredCode: hasDeferredCode)
    }

    public static func escape(_ string: String) -> String {
        let bytes = string.utf8
        var start = bytes.startIndex
        var escaped = ""
        for index in bytes.indices {
            let entity: String
            switch bytes[index] {
            case 38: entity = "&amp;"
            case 60: entity = "&lt;"
            case 62: entity = "&gt;"
            case 34: entity = "&quot;"
            case 39: entity = "&#39;"
            default: continue
            }
            escaped += String(decoding: bytes[start..<index], as: UTF8.self)
            escaped += entity
            start = bytes.index(after: index)
        }
        guard start != bytes.startIndex else { return string }
        escaped += String(decoding: bytes[start...], as: UTF8.self)
        return escaped
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

    private func renderChildren(_ node: Markup, into html: inout String) {
        for child in node.children { renderNode(child, into: &html) }
    }

    private func plain(_ node: Markup) -> String {
        if let text = node as? Text { return text.string }
        if let code = node as? InlineCode { return code.code }
        if node is SoftBreak || node is LineBreak { return " " }
        return node.children.map { plain($0) }.joined()
    }

    private func heading(_ node: Heading) -> PreviewHeading {
        let text = plain(node)
        let slug = text.lowercased().filter { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" || $0 == "_" }
            .replacingOccurrences(of: " ", with: "-")
        let base = slug.isEmpty ? "section" : slug
        var id = base
        if !headingIDs.insert(id).inserted {
            var suffix = nextSuffix[base, default: 1]
            repeat {
                id = "\(base)-\(suffix)"
                suffix += 1
            } while !headingIDs.insert(id).inserted
            nextSuffix[base] = suffix
        }
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return PreviewHeading(title: title.isEmpty ? "Untitled heading" : title, id: id, level: node.level)
    }

    private func codeHTML(_ code: String, language: String) -> String {
        let size = code.utf8.count
        // Long fences still render as readable code.
        guard size < 100_000, !language.isEmpty else { return Self.escape(code) }
        let key = CodeKey(language: language, code: code)
        let cacheable = size <= 1024 && language.utf8.count <= 64
        if cacheable, let cached = highlightedCode[key] { return cached }
        guard remainingHighlights > 0, remainingHighlightBytes >= size else { return Self.escape(code) }
        remainingHighlights -= 1
        remainingHighlightBytes -= size
        let value = highlighter?.function.call(withArguments: [code, language])
        let rendered: String
        if let value, !value.isNull, !value.isUndefined, let highlight = value.toString() {
            rendered = highlight
        } else {
            rendered = Self.escape(code)
        }
        if cacheable, rendered.utf8.count <= 4096 {
            if highlightedCode.count == 256 { highlightedCode.removeAll(keepingCapacity: true) }
            highlightedCode[key] = rendered
        }
        return rendered
    }

    private func wrap(_ tag: String, _ node: Markup, into html: inout String) {
        html += "<\(tag)>"
        renderChildren(node, into: &html)
        html += "</\(tag)>"
    }

    private func renderNode(_ node: Markup, into html: inout String) {
        switch node {
        case let n as Text:
            html += Self.escape(n.string)
        case let n as Heading:
            let entry = heading(n)
            headings.append(entry)
            html += "<h\(n.level) id=\"\(Self.escape(entry.id))\">"
            renderChildren(n, into: &html)
            html += "</h\(n.level)>"
        case is Paragraph: wrap("p", node, into: &html)
        case is Strong: wrap("strong", node, into: &html)
        case is Emphasis: wrap("em", node, into: &html)
        case is Strikethrough: wrap("del", node, into: &html)
        case let n as InlineCode:
            html += "<code>\(Self.escape(n.code))</code>"
        case let n as CodeBlock:
            let language = n.language?.split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
            let code = n.code
            if defersCode, !language.isEmpty, code.utf8.count < 100_000 {
                hasDeferredCode = true
                html += "<pre><code data-folio-language=\"\(Self.escape(language))\">"
                html += Self.escape(code)
            } else {
                html += "<pre><code>"
                html += codeHTML(code, language: language)
            }
            html += "</code></pre>"
        case is UnorderedList: wrap("ul", node, into: &html)
        case let n as OrderedList:
            html += "<ol start=\"\(n.startIndex)\">"
            renderChildren(n, into: &html)
            html += "</ol>"
        case let n as ListItem:
            guard let checkbox = n.checkbox else {
                wrap("li", node, into: &html)
                return
            }
            let checked = checkbox == .checked
            html += "<li class=\"task\"><span class=\"checkbox\" role=\"img\" aria-label=\"\(checked ? "Complete" : "Incomplete")\">\(checked ? "☑" : "☐")</span>"
            for (index, child) in n.children.enumerated() {
                if index == 0 && child is Paragraph { renderChildren(child, into: &html) }
                else { renderNode(child, into: &html) }
            }
            html += "</li>"
        case is BlockQuote: wrap("blockquote", node, into: &html)
        case is ThematicBreak: html += "<hr>"
        case is SoftBreak: html += "\n"
        case is LineBreak: html += "<br>"
        case let n as Link:
            guard let dest = n.destination, let url = Self.safeLink(dest, relativeTo: baseURL) else {
                renderChildren(n, into: &html)
                return
            }
            html += "<a href=\"\(Self.escape(url.absoluteString))\">"
            renderChildren(n, into: &html)
            html += "</a>"
        case let n as Image: html += image(n)
        case let n as InlineHTML: html += Self.escape(n.rawHTML)
        case let n as HTMLBlock: html += "<pre>\(Self.escape(n.rawHTML))</pre>"
        case let n as Table:
            let alignments = n.columnAlignments
            func row(_ cells: MarkupChildren, tag: String, into html: inout String) {
                html += "<tr>"
                for (index, cell) in cells.enumerated() {
                    let alignment = index < alignments.count ? alignments[index] : nil
                    let css = alignment == .right ? "align-right" : alignment == .center ? "align-center" : "align-left"
                    html += "<\(tag) class=\"\(css)\">"
                    renderChildren(cell, into: &html)
                    html += "</\(tag)>"
                }
                html += "</tr>"
            }
            html += "<div class=\"table-wrap\"><table><thead>"
            row(n.head.children, tag: "th", into: &html)
            html += "</thead><tbody>"
            for item in n.body.children { row(item.children, tag: "td", into: &html) }
            html += "</tbody></table></div>"
        default: renderChildren(node, into: &html)
        }
    }

    private func image(_ node: Image) -> String {
        let text = plain(node)
        let alt = Self.escape(text.isEmpty ? "Image" : text)
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
