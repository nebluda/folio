import AppKit
import XCTest
import FolioCore
@testable import FolioApp

final class EditorHighlighterTests: XCTestCase {
    func testHighlightingLeavesTextSelectionAndUndoUntouched() {
        let editor = NSTextView()
        editor.isRichText = false
        editor.allowsUndo = true
        editor.string = "# Heading\n\n**Bold** and `code`"
        let source = editor.string
        let selected = NSRange(location: 3, length: 4)
        editor.setSelectedRange(selected)
        let couldUndo = editor.undoManager?.canUndo
        let storedAttributes = editor.textStorage!.attributes(at: 2, effectiveRange: nil) as NSDictionary
        EditorHighlighter.apply(MarkdownSyntax.spans(in: source), to: editor)
        XCTAssertEqual(editor.string, source)
        XCTAssertEqual(editor.selectedRange(), selected)
        XCTAssertEqual(editor.undoManager?.canUndo, couldUndo)
        XCTAssertNotNil(editor.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: 2, effectiveRange: nil))
        XCTAssertEqual(editor.textStorage!.attributes(at: 2, effectiveRange: nil) as NSDictionary, storedAttributes)
        // Removing Markdown syntax also removes its old display style.
        EditorHighlighter.apply([], to: editor)
        XCTAssertNil(editor.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: 2, effectiveRange: nil))
    }
}
