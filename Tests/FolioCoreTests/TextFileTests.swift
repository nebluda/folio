import XCTest
@testable import FolioCore

final class TextFileTests: XCTestCase {
    func testUneditedRoundTripsAreByteExact() throws {
        for text in ["", "# café 日本語\n", "one\r\ntwo\r\n", "one\rtwo\r", "one\r\ntwo\nthree\r", "\u{feff}# heading\r\n"] {
            let data = Data(text.utf8)
            let file = try TextFile(data: data)
            XCTAssertEqual(file.encoded(file.text), data)
        }
    }
    func testEditsKeepBOMAndLineConvention() throws {
        let file = try TextFile(data: Data("\u{feff}hello\r\nworld\r\n".utf8))
        XCTAssertEqual(file.text, "hello\nworld\n")
        XCTAssertEqual(file.encoded("hello\nnew\nworld\n"), Data("\u{feff}hello\r\nnew\r\nworld\r\n".utf8))
    }
    func testRejectsInvalidTextAndOversizedFiles() {
        XCTAssertThrowsError(try TextFile(data: Data([0xff, 0xfe, 0x80])))
        XCTAssertThrowsError(try TextFile(data: Data([0])))
        XCTAssertThrowsError(try TextFile(data: Data(repeating: 65, count: TextFile.maximumBytes + 1)))
    }
    func testAtomicSaveAndExternalConflict() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".md")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("old\r\n".utf8).write(to: url)
        var file = try TextFile(url: url)
        file = try file.save("new\n", to: url)
        XCTAssertEqual(try Data(contentsOf: url), Data("new\r\n".utf8))
        try Data("external".utf8).write(to: url, options: .atomic)
        XCTAssertThrowsError(try file.save("mine", to: url))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "external")
    }
    func testMissingDestinationDoesNotLoseOriginal() throws {
        let file = try TextFile(data: Data("original".utf8))
        XCTAssertThrowsError(try file.save("edited", to: URL(fileURLWithPath: "/missing-\(UUID())/file.md")))
        XCTAssertEqual(file.original, Data("original".utf8))
    }
}
