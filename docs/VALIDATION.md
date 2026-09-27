# Folio 0.1.0 validation

Recorded 2026-09-27. This is an installable local prototype, ad-hoc signed, not a notarized public release.

## Automated checks

The [macOS workflow](https://github.com/nebluda/folio/actions/workflows/ci.yml) builds both the complete release bundle and the Xcode app with its embedded Quick Look extension. It runs:

- 23 Swift tests for Markdown rendering, unsafe HTML/URLs, malformed input, tables/tasks/code, image restrictions, UTF-8/BOM and line endings, atomic file operations, external changes, stale writes, CLI argument parsing, Unicode syntax ranges, and highlighting without text/selection/undo changes.
- 6 CLI process checks for help/version, invalid options, missing files, directories, and launch failures. Argument tests include multiple files, relative paths, spaces, Unicode, and deduplication.
- 4 native UI scenarios: read/edit/undo/redo/save/reopen/find; cancel/discard unsaved close; clean external reload and unsaved conflict; actual Finder Space rendering and double-click launch with Folio closed.

CI exports XCTest results and screenshots as artifacts. Local Command Line Tools can build the app but do not include XCTest; full Xcode CI supplies the test runtime.

## Local checks

Apple M1 Pro, macOS 26.6.2, Swift 6.3.2 Command Line Tools:

- Installed release app and CLI outside the build directory; verified signatures, bundled resources, CLI launches, and native document rendering.
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
- Developer ID signing, notarization, and a public binary distribution/update process.
- Validate on physical macOS 14 and Intel hardware; the deployment target is macOS 14, but local validation used Apple Silicon on macOS 26 and CI uses macOS 15.
- Mixed line endings round-trip exactly without edits; editing normalizes them to the detected convention. Quick Look can show placeholders for local images blocked by its sandbox. Remote images, SVG, raw HTML execution, diagrams, and math are intentionally unsupported.
