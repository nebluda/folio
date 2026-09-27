import XCTest

final class FolioUITests: XCTestCase {
    private var app: XCUIApplication!
    private var file: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        file = FileManager.default.temporaryDirectory.appendingPathComponent("Folio UI \(UUID()).md")
        try Data("# Original heading\n\nReadable paragraph.\n".utf8).write(to: file)
        app = XCUIApplication()
        app.launchArguments = [file.path]
        app.launch()
    }
    override func tearDownWithError() throws {
        app.terminate()
        try? FileManager.default.removeItem(at: file)
    }
    func testReadEditUndoSaveAndReopen() throws {
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 10))
        app.typeKey("e", modifierFlags: .command)
        let source = app.textViews["MarkdownSource"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.click()
        app.typeKey("a", modifierFlags: .command)
        source.typeText("# Changed heading\n\nHello again.\n")
        app.typeKey("z", modifierFlags: .command)
        app.typeKey("z", modifierFlags: [.command, .shift])
        app.typeKey("s", modifierFlags: .command)
        let saved = NSPredicate { _, _ in (try? String(contentsOf: self.file, encoding: .utf8)) == "# Changed heading\n\nHello again.\n" }
        expectation(for: saved, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
        app.typeKey("e", modifierFlags: .command)
        XCTAssertTrue(app.webViews.firstMatch.exists)
        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(app.searchFields["Find in document"].exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 5))
    }
    func testClosingUnsavedEditsOffersCancelAndDiscard() {
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 10))
        app.typeKey("e", modifierFlags: .command)
        let source = app.textViews["MarkdownSource"]
        source.click(); source.typeText("unsaved")
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(app.sheets.buttons["Cancel"].waitForExistence(timeout: 5))
        app.sheets.buttons["Cancel"].click()
        XCTAssertTrue(source.exists)
        app.typeKey("w", modifierFlags: .command)
        app.sheets.buttons["Don’t Save"].click()
        XCTAssertEqual(try? String(contentsOf: file, encoding: .utf8), "# Original heading\n\nReadable paragraph.\n")
    }
}
