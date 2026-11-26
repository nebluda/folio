import Foundation

/// The file-to-HTML path used by the Finder preview extension.
public enum QuickLookHTML {
    private static let queue = DispatchQueue(label: "app.folio.quick-look.render", qos: .userInitiated)
    private static let renderer = MarkdownRenderer()

    public static func render(fileURL: URL) throws -> Data {
        let file = try TextFile(url: fileURL)
        return queue.sync {
            let preview = renderer.renderPreview(file.text, fileURL: fileURL, presentation: .quickLook)
            return Data(preview.html.utf8)
        }
    }
}
