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
var report: [String: Any] = [:]
for target in [100_000, 1_000_000] {
    let text = String(repeating: unit, count: target / unit.utf8.count + 1)
    let renderer = MarkdownRenderer()
    var samples: [Double] = []
    for _ in 0..<10 {
        let start = Date()
        let html = renderer.render(text)
        precondition(html.contains("<table>") && html.contains("hljs-keyword"))
        samples.append(Date().timeIntervalSince(start) * 1000)
    }
    samples.sort()
    report["\(text.utf8.count)_bytes"] = ["median_ms": samples[5], "max_ms": samples.last!, "runs": samples.count]
    if CommandLine.arguments.count > 1 {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try text.write(to: directory.appendingPathComponent("\(target).md"), atomically: true, encoding: .utf8)
    }
}
let result = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
print(String(decoding: result, as: UTF8.self))
