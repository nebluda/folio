import AppKit
import XCTest
@testable import FolioApp

final class DocumentTests: XCTestCase {
    func testReadEditSerialize() throws {
        let document = MarkdownDocument()
        try document.read(from: Data("# original\r\n".utf8), ofType: "net.daringfireball.markdown")
        document.edit("# edited\n")
        XCTAssertEqual(try document.data(ofType: "net.daringfireball.markdown"), Data("# edited\r\n".utf8))
        XCTAssertFalse(MarkdownDocument.autosavesInPlace)
    }
    func testExternalChangeReloadsCleanDocument() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".md")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("original".utf8).write(to: url)
        let document = MarkdownDocument()
        try document.read(from: url, ofType: "net.daringfireball.markdown")
        document.fileURL = url
        try Data("external".utf8).write(to: url, options: .atomic)
        document.checkExternalChanges()
        XCTAssertEqual(document.source, "external")
        document.close()
    }
    func testSafeWriteRejectsStaleDocument() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".md")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("original".utf8).write(to: url)
        let document = MarkdownDocument()
        try document.read(from: url, ofType: "net.daringfireball.markdown")
        document.fileURL = url
        document.edit("my edit")
        try Data("external".utf8).write(to: url, options: .atomic)
        XCTAssertThrowsError(try document.writeSafely(to: url, ofType: "net.daringfireball.markdown", for: .saveOperation))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "external")
        document.close()
    }
}
