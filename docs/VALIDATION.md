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

## Opening performance

### Plan

1. Benchmark the previous release with a fresh app process and with Folio already running. Include small, 100 KB, and 1 MB documents.
2. Reduce the work required to open a reader window. Measure HTML generation and WebKit loading separately to see where time goes.
3. Build a native table of contents from the same Markdown parse that produces the preview. Keep it collapsed by default and check keyboard navigation, duplicate headings, and Unicode anchors.
4. Alternate baseline and updated bundles on the same Mac, then check the shared renderer, CLI, and native reader.

### Benchmark method

The app benchmark measures from process launch (fresh process) or CLI invocation (running app) to WebKit's navigation completion. The fresh-process trial starts the app executable directly and uses normal macOS filesystem caches. The CLI trials open a new file and window each time. The benchmark uses the 773-byte Welcome fixture and generated mixed Markdown with headings, tables, tasks, and fenced code. The varied 1 MB case gives each section a distinct heading and code snippet to exercise syntax highlighting with fewer cache hits.

The report includes individual runs, the median, and the nearest-rank 95th percentile. Updated builds also report preview preparation from render dispatch through completion, HTML generation on the render queue, and WebKit loading from the HTML request. HTML generation overlaps window setup. The local performance log records timing and the Markdown byte count. The benchmark disables macOS window restoration and rejects samples that predate the open request or have the wrong byte count.

### Results · 2026-11-25

Twenty trials per build on the same Apple M1 Pro running macOS 26.6.2. The baseline was the previously installed Folio 0.1.1. Values are in milliseconds.

| Open scenario | Baseline median | Updated median | Baseline p95 | Updated p95 |
| --- | ---: | ---: | ---: | ---: |
| Fresh process, 100 KB | 534 | 480 | 583 | 555 |
| Running app via CLI, 773 bytes | 230 | 197 | 239 | 211 |
| Running app via CLI, 100 KB | 304 | 202 | 321 | 218 |
| Running app via CLI, 1 MB, repeated code | 1,476 | 738 | 1,676 | 775 |
| Running app via CLI, 1 MB, varied code | 1,399 | 1,114 | 1,447 | 1,146 |

The warm 100 KB open met the 300 ms target at both the median and p95. HTML generation took a median 25 ms and WebKit loading took 54 ms in that case. For 1 MB of varied code, those stages took 563 ms and 441 ms respectively.

In 20 renderer-only runs on the repeated-code fixtures, the 100 KB median fell from 88 to 23 ms and the 1 MB median from 812 to 238 ms.

Folio starts rendering while it builds the window, creates the source editor on demand, and prepares one spare WebKit view after a preview finishes. The renderer builds HTML in one buffer and reuses the highlighting of identical short code fences within a document. LF files skip line-ending normalization. The outline uses headings collected during that render.

### Reproduce

Quit Folio, build the release bundle, then run the two benchmarks:

```sh
python3 scripts/package.py
swift run -c release FolioBench
python3 scripts/benchmark-app.py
```

The app benchmark defaults to 20 trials and writes `build/app-performance.json`. Pass `--baseline /path/to/previous/Folio.app` to alternate two builds or `--trials 5` for a shorter check. The script uses each bundle's own CLI, opens generated fixtures in temporary directories, and stops its own app processes.

### Outline validation

`Fixtures/Outline.md` covers nested and duplicate headings, explicitly suffixed headings, a fenced example, and Unicode. The WebKit check compares outline IDs with rendered headings and checks the scroll position after jumping to a Unicode heading. The native UI test covers opening the outline with the keyboard, collapsing and expanding a branch, jumping to a heading, and closing the outline with the toolbar. Local checks also verified the native accessibility tree and that switching between Read and Edit restores the sidebar and reading area.

The local release bundle passed the eight WebKit table scenarios, the WebKit outline check, and all six CLI process checks. The installed app, CLI, and registered Quick Look extension were checked against the release build. XCTest requires full Xcode and runs in macOS CI.

## Follow-up profiling

Captured 1 ms stack samples with macOS `sample` on the M1 Pro. The cold trace covers creation of the first window. Constructing the first `WKWebView` is a distinct main-thread cost. A warm trace of repeatedly opening a varied 1 MB file attributes 1,849 of 3,037 render-queue samples to fenced-code highlighting. The same work accounts for 1,016 of 1,743 samples inside the actual Quick Look extension's data callback. These are inclusive stack counts. They can overlap work on other threads and do not measure wall-clock latency.

The reader now renders documents of 256 KiB or more with readable code immediately and colors eligible code blocks as they approach the viewport. The highlighter runs in an isolated WebKit content world. For large files, Quick Look colors up to 64 new eligible blocks within a 32 KiB code budget and can reuse their cached results. All code remains in the static preview. The extension reuses its renderer within the extension process. On macOS 26 or later, WebKit lays out large documents' offscreen tables and code blocks as needed. The layout check exercises a section near the end, Find, escaped code, and a table after scrolling. [WebKit's Safari 26 Find fix for offscreen content](https://webkit.org/blog/17333/webkit-features-in-safari-26-0/)

Starting the first WebKit view earlier regressed the cold experiment, so the build uses the previous startup order. A warm-open experiment with macOS `open` and Folio's CLI had medians of 153 and 157 ms respectively. Both still go through Launch Services and AppKit. After a preview loads, Folio now keeps one spare reader window with its native controls and WebKit view ready for the next open.

### App results

Medians and p95 in milliseconds over 20 interleaved trials, against the previous installed build.

| Open scenario | Before median | After median | Before p95 | After p95 |
| --- | ---: | ---: | ---: | ---: |
| Fresh process, 100 KB | 428 | 441 | 472 | 497 |
| Running Folio, 773 bytes | 160 | 153 | 174 | 168 |
| Running Folio, 100 KB | 178 | 170 | 196 | 182 |
| Running Folio, 1 MB, repeated code | 714 | 642 | 737 | 664 |
| Running Folio, 1 MB, varied code | 1,068 | 638 | 1,088 | 665 |

For the varied fixture, HTML preparation fell from 555 ms to 240 ms and WebKit loading fell from 426 ms to 297 ms. The opening metric ends at navigation completion. The reader colors visible code immediately afterward and colors other blocks as the user scrolls.

### Quick Look measurement

The Quick Look benchmark uses a native `QLPreviewView` to invoke the installed extension. It times from setting the file through WebKit loading that file's unique heading. A first preview starts in a fresh host, then the same host switches to other fixtures. Install each build in turn and benchmark at the same install location. This covers the actual extension, the system handoff, and WebKit loading. Finder's keyboard and panel animation happen outside the probe. [Apple's data-based Quick Look API](https://developer.apple.com/documentation/quicklookui/qlpreviewreply)

| Quick Look | Before median | After median | Before p95 | After p95 |
| --- | ---: | ---: | ---: | ---: |
| First in host, 100 KB | 440 | 447 | 506 | 513 |
| Switch to 773 bytes | 98 | 82 | 112 | 91 |
| Switch to 100 KB | 164 | 145 | 175 | 158 |
| Switch to 1 MB, repeated code | 843 | 774 | 902 | 860 |
| Switch to 1 MB, varied code | 1,164 | 752 | 1,241 | 786 |

These are milliseconds over 20 trials per installed build. File-to-HTML preparation in isolation fell from 593 ms to 252 ms for the varied fixture. The native preview also displayed the last heading when asked to scroll to it.

The Finder Space check opened the varied 1 MB fixture and displayed its headings, tables, task items, and highlighted code. The macOS extension log confirmed that Finder launched the extension bundled in the installed Folio app.

```sh
python3 scripts/benchmark-quick-look.py
FOLIO_QL_VERIFY_TAIL=1 python3 scripts/benchmark-quick-look.py --trials 1
swift run -c release FolioBench --quick-look Fixtures/Welcome.md path/to/large-file.md
```

The optional tail check scrolls to the last heading of the varied fixture in the actual hosted Quick Look preview. The renderer-only command measures the extension's file-to-HTML work independently of the host. Use `python3 scripts/flamegraph.py --help` to turn saved `sample` call trees into SVGs.

### Finder Space key to first render

On Nov 25, 2026, Finder opened fresh copies of the 1 MB varied-code Markdown fixture on the M1 Pro. The stopwatch started immediately before sending Space. The endpoint was WebKit's first meaningful paint in Finder's own Quick Look panel. Finder's request timestamp provides a second start point and separates key dispatch from preview work. Screenshots confirmed the output and stayed outside the timed interval.

| Actual Finder Space preview | Before median | After median | Valid trials before / after |
| --- | ---: | ---: | ---: |
| Cold Folio extension | 1,798 ms | 1,404 ms | 3 / 4 |
| Warm Folio extension | 1,943 ms | 1,347 ms | 4 / 4 |

Starting from Finder's request timestamp instead, the cold medians were 1,778 and 1,371 ms. The warm medians were 1,877 and 1,298 ms. A cold trial required a new `FolioPreview` process after Space. A warm trial closed the panel and pressed Space on a fresh file with the same extension process. Finder and its system caches stayed running. The previous and current bundles took turns at the same install path, followed by restoration of the current Folio build.

The sample covers one size and workload. Cold dispatch-to-paint runs ranged from 1,528 to 2,377 ms before and 1,261 to 1,811 ms after. Warm runs ranged from 1,883 to 2,047 ms before and 1,115 to 1,878 ms after. The paint milestone is logged by WebKit and measures when it renders content, independent of the display's final refresh. The local raw timings are in `build/profile/finder-space-performance.json`.

## Remaining release work

- Developer ID signing, notarization, and an automatic update process. Release archives are currently ad-hoc signed.
- Validate on physical macOS 14 and Intel hardware; the deployment target is macOS 14, but local validation used Apple Silicon on macOS 26 and CI uses macOS 15.
- Mixed line endings round-trip exactly without edits; editing normalizes them to the detected convention. Quick Look can show placeholders for local images blocked by its sandbox. Remote images, SVG, raw HTML execution, diagrams, and math are intentionally unsupported.
