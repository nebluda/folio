# Folio validation

## Rendering-change checklist

The table regression escaped because the existing renderer tests checked HTML structure without measuring the layout. `overflow-wrap:anywhere` allowed WebKit to treat individual characters as valid minimum column widths, so long descriptions crowded out short labels. Expanding the table alone did not guarantee readable columns.

For future changes to HTML, CSS, or preview sizing:

1. Reproduce the reported failure with a small, anonymized Markdown fixture. Confirm that a layout assertion fails before applying the fix; keep the fixture as a regression case. Do not publish private document content or screenshots.
2. Validate the actual shared renderer in WebKit. Assert user-visible outcomes such as intact short labels, sensible space allocation, no overlapping/clipped content, and usable overflow scrolling. HTML string checks and CSS declaration checks are not substitutes for layout checks.
3. Exercise uneven content: short labels beside long prose, compact numbers, inline code, long unbroken tokens/URLs, and many columns. Test narrow and wide windows, zoom, and light/dark appearance. Extend `FolioLayoutCheck` when a new failure is not covered.
4. Preserve readable content before forcing a table to fit. Let descriptions wrap, keep compact columns compact, and use the table's horizontal scroller when readable columns cannot fit. Avoid blanket character-breaking rules or equal-width columns that ignore content.
5. Run `swift run FolioLayoutCheck build/layout-screenshots` and inspect representative screenshots. Geometry assertions catch measurable failures; visual review catches awkward results the assertions do not yet cover. Require the existing Swift, layout, CLI, and native UI CI checks before publishing.
6. Verify the installed app, CLI, and registered Quick Look extension versions after an update. Reopen existing previews to avoid mistaking cached rendering for the newly installed behavior.

These checks prevent the known failure and make similar issues easier to detect; they do not prove that every possible Markdown document will lay out well.

## 0.1.1 table layout regression — 2026-11-01

`Fixtures/TableLayout.md` covers a short label column beside a long description, inline code, compact numeric columns, seven-column tables, and long unbroken code/URLs. `swift run FolioLayoutCheck build/layout-screenshots` renders it with the shared renderer in a real `WKWebView` and checks text line fragments, column allocation, viewport containment, and horizontal scrolling. The same HTML and CSS are used by the app and Quick Look; no document scripts are enabled.

The original `overflow-wrap:anywhere` reduced the first column to 41 CSS pixels at an 800-pixel viewport and failed the readable-label checks at all six tested width/zoom combinations. Changing it to `break-word` preserves word-sized intrinsic minimums: the same table now allocates 141 / 225 / 337 pixels across its three columns and fits without scrolling. This follows the [CSS Text intrinsic sizing rules](https://www.w3.org/TR/css-text-3/#overflow-wrap-property). Tables exceeding the viewport remain in their own horizontal scroller.

Eight scenarios pass locally: widths 360, 540, 800, and 1280 at 100%; an 800-pixel window at 150% and 200%; and dark appearance at 1280/100% and 800/200%. The light 800-pixel and dark 1280-pixel snapshots were visually reviewed. CI now runs these layout checks and retains the screenshots alongside its existing Swift, CLI, and native UI checks.

## 0.1.0 baseline

Recorded 2026-09-27. This is an installable local prototype, ad-hoc signed, not a notarized public release.

## Automated checks

The [macOS workflow](https://github.com/nebluda/folio/actions/workflows/ci.yml) builds both the complete release bundle and the Xcode app with its embedded Quick Look extension. It runs:

- 23 Swift tests for Markdown rendering, unsafe HTML/URLs, malformed input, tables/tasks/code, image restrictions, UTF-8/BOM and line endings, atomic file operations, external changes, stale writes, CLI argument parsing, Unicode syntax ranges, and highlighting without text/selection/undo changes.
- 6 CLI process checks for help/version, invalid options, missing files, directories, and launch failures. Argument tests include multiple files, relative paths, spaces, Unicode, and deduplication.
- 5 native UI scenarios: read/edit/undo/redo/save/reopen/find; cancel/discard unsaved close; clean external reload and unsaved conflict; actual Finder Space rendering and double-click launch with Folio closed; cancelling Share preserves unsaved edits and leaves the disk file untouched.

CI exports XCTest results and screenshots as artifacts. Local Command Line Tools can build the app but do not include XCTest; full Xcode CI supplies the test runtime.

## Local checks

Apple M1 Pro, macOS 26.6.2, Swift 6.3.2 Command Line Tools:

- Installed release app and CLI outside the build directory; verified signatures, bundled resources, CLI launches, and native document rendering.
- Verified the native Share toolbar popover and File → Share menu with the bundled fixture.
- Checked light and dark appearance, Read/Edit controls, keyboard shortcuts, source accessibility label, and unsaved-close sheet.
- Verified real Finder Space preview of `Fixtures/Welcome.md` with Folio closed. MarkEdit's competing preview extension needed disabling. Both the app and Quick Look use the same renderer and stylesheet.
- Set the default Markdown handler through Folio's Help command and verified Launch Services opening the fixture in Folio.

Screenshots contain only the included sample document. The Quick Look screenshot was captured before changing the default editor, so its Open With label still says MarkEdit; its rendered content is Folio's preview.

## Release performance

Three app trials on the same Mac, with generated mixed Markdown containing headings, tables, task lists, and fenced code. Timing ends at WKWebView navigation completion. A cold trial starts a fresh process; it does not flush macOS filesystem caches. Warm trials start at CLI invocation and include opening a new window. These are observed timings, not hard guarantees.

| Scenario | Median | Individual trials | Target |
| --- | ---: | --- | --- |
| Fresh process, 100 KB | 702.6 ms | 1261.3, 702.6, 622.2 ms | < 2000 ms: met |
| Running app via CLI, 100 KB | 354.7 ms | 602.3, 338.0, 354.7 ms | < 300 ms: not yet met |
| Running app via CLI, 1 MB | 1417.0 ms | 1408.2, 1568.9, 1417.0 ms | Observed |

Ten renderer-only trials: 100,082 bytes median 72.1 ms (maximum 84.2); 1,000,168 bytes median 736.1 ms (maximum 867.9). Rendering runs off the main thread; the app keeps native controls available while preparing large documents. The app bundle is approximately 6 MB, excluding system frameworks.

Reproduce after quitting Folio:

```sh
swift run -c release FolioBench
python3 scripts/benchmark-app.py
```

The app benchmark opens temporary fixture windows and terminates only its own process. Results go to `build/app-performance.json`.

## Remaining release work

- Reduce warm window-open latency below 300 ms.
- Developer ID signing, notarization, and an automatic update process. Release archives are currently ad-hoc signed.
- Validate on physical macOS 14 and Intel hardware; the deployment target is macOS 14, but local validation used Apple Silicon on macOS 26 and CI uses macOS 15.
- Mixed line endings round-trip exactly without edits; editing normalizes them to the detected convention. Quick Look can show placeholders for local images blocked by its sandbox. Remote images, SVG, raw HTML execution, diagrams, and math are intentionally unsupported.
