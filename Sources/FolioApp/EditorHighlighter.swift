import AppKit
import FolioCore

/// Temporary layout attributes never enter the saved file or undo history.
final class EditorHighlighter {
    private static func color(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        }
    }
    private static let heading = color(0x175EA8, 0x82B4FF)
    private static let strong = color(0x945100, 0xE7B776)
    private static let emphasis = color(0x7742A7, 0xCB9BF3)
    private static let link = color(0x006C77, 0x70C5C9)
    private static let code = color(0xA42D61, 0xEF9BBB)
    private let queue = DispatchQueue(label: "app.folio.editor-highlighting", qos: .userInitiated)
    private var pending: DispatchWorkItem?
    private var generation = 0

    func update(_ editor: NSTextView, immediately: Bool = false) {
        pending?.cancel()
        generation += 1
        let requested = generation
        let source = editor.string
        let work = DispatchWorkItem { [weak self, weak editor] in
            let spans = MarkdownSyntax.spans(in: source)
            DispatchQueue.main.async { [weak self, weak editor] in
                guard let self, let editor, generation == requested,
                      editor.string == source else { return }
                Self.apply(spans, to: editor)
            }
        }
        pending = work
        queue.asyncAfter(deadline: .now() + (immediately ? 0 : 0.12), execute: work)
    }

    static func apply(_ spans: [MarkdownSyntax.Span], to editor: NSTextView) {
        guard let layout = editor.layoutManager else { return }
        let whole = NSRange(location: 0, length: (editor.string as NSString).length)
        for key in [NSAttributedString.Key.foregroundColor, .backgroundColor, .strikethroughStyle] {
            layout.removeTemporaryAttribute(key, forCharacterRange: whole)
        }
        for span in spans where NSMaxRange(span.range) <= whole.length {
            let color: NSColor
            switch span.kind {
            case .heading: color = heading
            case .strong: color = strong
            case .emphasis: color = emphasis
            case .link: color = link
            case .code: color = code
            case .quote, .strikethrough: color = .secondaryLabelColor
            case .marker: color = emphasis
            }
            layout.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: span.range)
            if span.kind == .code {
                layout.addTemporaryAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor, forCharacterRange: span.range)
            }
            if span.kind == .strikethrough {
                layout.addTemporaryAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, forCharacterRange: span.range)
            }
        }
    }

    deinit { pending?.cancel() }
}
