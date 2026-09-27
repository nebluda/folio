import XCTest
import AppKit

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

    func testFinderQuickLookAndDefaultOpen() throws {
        let products = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let appURL = products.appendingPathComponent("Folio.app")
        XCTAssertTrue(FileManager.default.fileExists(atPath: appURL.path))
        for arguments in [["-a", appURL.appendingPathComponent("Contents/PlugIns/FolioPreview.appex").path], ["-e", "use", "-i", "io.github.nebluda.folio.preview"]] {
            let command = Process(); command.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit"); command.arguments = arguments
            try command.run(); command.waitUntilExit(); XCTAssertEqual(command.terminationStatus, 0)
        }
        let associated = expectation(description: "Associate test file")
        NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenFileAt: file) { error in
            XCTAssertNil(error); associated.fulfill()
        }
        wait(for: [associated], timeout: 10)
        app.terminate()
        NSWorkspace.shared.activateFileViewerSelecting([file])
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        finder.typeKey(" ", modifierFlags: [])
        XCTAssertTrue(finder.buttons["QLControlOpen"].firstMatch.waitForExistence(timeout: 15))
        // Keep the actual system preview for visual inspection, including extension failures.
        let screenshot = XCTAttachment(screenshot: finder.screenshot())
        screenshot.name = "Finder Quick Look"; screenshot.lifetime = .keepAlways; add(screenshot)
        finder.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(NSWorkspace.shared.open(file))
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 10))
    }
}
