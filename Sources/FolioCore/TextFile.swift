import Foundation

public enum FolioError: LocalizedError, Equatable {
    case invalidUTF8, tooLarge, changedOnDisk, invalidArgument(String)
    public var errorDescription: String? {
        switch self {
        case .invalidUTF8: return "This file is not valid UTF-8. Folio did not change it."
        case .tooLarge: return "This file is larger than Folio’s 20 MB limit."
        case .changedOnDisk: return "This file changed on disk. Reload it or save your edits as a separate file."
        case .invalidArgument(let message): return message
        }
    }
}

/// Keeps the original bytes until an actual edit, including BOM and mixed line endings.
public struct TextFile: Sendable {
    public static let maximumBytes = 20 * 1024 * 1024
    public let original: Data
    public let text: String
    public let newline: String
    public let hasBOM: Bool

    public init(data: Data) throws {
        guard data.count <= Self.maximumBytes else { throw FolioError.tooLarge }
        original = data
        hasBOM = data.starts(with: [0xef, 0xbb, 0xbf])
        let bytes = hasBOM ? data.dropFirst(3) : data[...]
        guard let decoded = String(data: bytes, encoding: .utf8), !decoded.contains("\0") else {
            throw FolioError.invalidUTF8
        }
        newline = decoded.contains("\r\n") ? "\r\n" : decoded.contains("\r") ? "\r" : "\n"
        text = decoded.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    public init(url: URL) throws {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= Self.maximumBytes else { throw FolioError.tooLarge }
        try self.init(data: Data(contentsOf: url))
    }

    public func encoded(_ edited: String) -> Data {
        if edited == text { return original }
        let normalized = edited.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        return Data((hasBOM ? "\u{feff}" : "").utf8) + Data(normalized.replacingOccurrences(of: "\n", with: newline).utf8)
    }

    /// Compare inside file coordination so other cooperating editors cannot be overwritten.
    public func save(_ edited: String, to url: URL) throws -> TextFile {
        let data = encoded(edited)
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
            do {
                guard try Data(contentsOf: target) == original else { throw FolioError.changedOnDisk }
                try data.write(to: target, options: .atomic)
            } catch { writeError = error }
        }
        if let error = coordinationError ?? writeError as NSError? { throw error }
        return try TextFile(data: data)
    }
}
