import XCTest
@testable import FolioCore

final class CLIArgumentsTests: XCTestCase {
    var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in ["hello world.md", "日本語.markdown", "-dash.md", "UPPER.MD"] { try Data().write(to: directory.appendingPathComponent(name)) }
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }
    func testMultipleRelativeUnicodeAndDuplicatePaths() throws {
        let action = try CLIArguments.parse(["hello world.md", "日本語.markdown", "./hello world.md"], directory: directory)
        XCTAssertEqual(action, .open(["hello world.md", "日本語.markdown"].map { directory.appendingPathComponent($0).resolvingSymlinksInPath() }))
    }
    func testOptionsAndNoFiles() throws {
        XCTAssertEqual(try CLIArguments.parse([], directory: directory), .open([]))
        XCTAssertEqual(try CLIArguments.parse(["--help"], directory: directory), .help)
        XCTAssertEqual(try CLIArguments.parse(["--version"], directory: directory), .version)
        XCTAssertNoThrow(try CLIArguments.parse(["--", "-dash.md"], directory: directory))
        XCTAssertNoThrow(try CLIArguments.parse(["UPPER.MD"], directory: directory))
    }
    func testInvalidArguments() {
        for args in [["--wat"], ["missing.md"], ["."], ["--help", "hello world.md"]] {
            XCTAssertThrowsError(try CLIArguments.parse(args, directory: directory))
        }
    }
}
