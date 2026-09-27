import Foundation
import QuickLookUI
import UniformTypeIdentifiers
import FolioCore

@objc(PreviewProvider)
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest, completionHandler handler: @escaping (QLPreviewReply?, Error?) -> Void) {
        let url = request.fileURL
        let reply = QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 800, height: 900)) { reply in
            reply.stringEncoding = .utf8
            let file = try TextFile(url: url)
            let html = MarkdownRenderer().render(file.text, fileURL: url)
            return Data(html.utf8)
        }
        handler(reply, nil)
    }
}
