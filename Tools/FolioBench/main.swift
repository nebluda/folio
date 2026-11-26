import Foundation
import FolioCore
let unit = """
## A readable section

Markdown deserves a quiet window. **Folio** opens local files, with *native controls* and `simple editing`.

| Feature | Status |
| --- | --- |
| Native reader | Ready |
| Quick Look | Ready |

- [x] Read the document
- [ ] Make a small edit

```swift
let greeting = "Hello, Folio."
print(greeting)
```

"""
let arguments = CommandLine.arguments.dropFirst()
if arguments.first == "--quick-look" {
    let paths = arguments.dropFirst()
    precondition(!paths.isEmpty, "Pass Markdown files after --quick-look.")
    for path in paths {
        let url = URL(fileURLWithPath: path)
        var before: [Double] = []
        var after: [Double] = []
        for trial in 0..<20 {
            // Alternate order to reduce the effect of filesystem and framework warmup.
            for usePreview in (trial.isMultiple(of: 2) ? [false, true] : [true, false]) {
                let start = DispatchTime.now().uptimeNanoseconds
                let data: Data
                if usePreview {
                    data = try QuickLookHTML.render(fileURL: url)
                } else {
                    let file = try TextFile(url: url)
                    data = Data(MarkdownRenderer().render(file.text, fileURL: url).utf8)
                }
                let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                precondition(data.starts(with: "<!doctype html>".utf8))
                if usePreview { after.append(elapsed) }
                else { before.append(elapsed) }
            }
        }
        func statistics(_ times: [Double]) -> String {
            let sorted = times.sorted()
            let median = (sorted[9] + sorted[10]) / 2
            return String(format: "median %.1f ms / p95 %.1f ms", median, sorted[18])
        }
        print("\(url.lastPathComponent): before \(statistics(before)); after \(statistics(after))")
    }
    exit(0)
}
let fixturesOnly = arguments.first == "--fixtures-only"
let outputPath = fixturesOnly ? arguments.dropFirst().first : arguments.first
var report: [String: Any] = [:]
for target in [100_000, 1_000_000] {
    let text = String(repeating: unit, count: target / unit.utf8.count + 1)
    if !fixturesOnly {
        let renderer = MarkdownRenderer()
        var samples: [Double] = []
        for _ in 0..<20 {
            let start = DispatchTime.now().uptimeNanoseconds
            let html = renderer.render(text)
            precondition(html.contains("<table>") && html.contains("hljs-keyword"))
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        }
        samples.sort()
        let middle = samples.count / 2
        report["\(text.utf8.count)_bytes"] = [
            "median_ms": (samples[middle - 1] + samples[middle]) / 2,
            "p95_ms": samples[Int(ceil(Double(samples.count) * 0.95)) - 1],
            "runs": samples.count
        ]
    }
    if let outputPath {
        let directory = URL(fileURLWithPath: outputPath, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try text.write(to: directory.appendingPathComponent("\(target).md"), atomically: true, encoding: .utf8)
    }
}
if !fixturesOnly {
    let result = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: result, as: UTF8.self))
}
