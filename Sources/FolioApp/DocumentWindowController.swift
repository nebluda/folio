import AppKit
import WebKit
import FolioCore
import os

final class DocumentWindowController: NSWindowController, NSToolbarDelegate, NSTextViewDelegate, WKNavigationDelegate, NSWindowDelegate, NSSearchFieldDelegate {
    private static let websiteDataStore = WKWebsiteDataStore.nonPersistent()
    private static let renderQueue = DispatchQueue(label: "app.folio.render", qos: .userInitiated)
    // Accessed exclusively on renderQueue. Share parser/highlighter setup across windows.
    private static var sharedRenderer: MarkdownRenderer?
    private let preview: WKWebView
    private let editor = NSTextView()
    private let editorScroll = NSScrollView()
    private let search = NSSearchField()
    private let searchRow = NSStackView()
    private let content = NSView()
    private let mode = NSSegmentedControl(images: [
        NSImage(systemSymbolName: "eye", accessibilityDescription: "Read")!,
        NSImage(systemSymbolName: "pencil", accessibilityDescription: "Edit")!
    ], trackingMode: .selectOne, target: nil, action: nil)
    private var generation = 0
    private var renderedSource: String?
    private var readingY = 0.0
    private var selection = NSRange(location: 0, length: 0)
    private var editing = false
    private var applying = false
    private var zoom = 1.0
    private var renderStarted = CFAbsoluteTimeGetCurrent()
    private let log = Logger(subsystem: "io.github.nebluda.folio", category: "render")
    private var markdown: MarkdownDocument? { document as? MarkdownDocument }

    init(document: MarkdownDocument) {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.websiteDataStore = Self.websiteDataStore
        preview = WKWebView(frame: .zero, configuration: configuration)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 850, height: 760), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.animationBehavior = .none
        window.minSize = NSSize(width: 420, height: 300)
        window.title = "Untitled"
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.setFrameAutosaveName("FolioDocument")
        window.center()
        window.delegate = self
        setupViews()
        let toolbar = NSToolbar(identifier: "FolioToolbar")
        toolbar.delegate = self; toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
    }
    required init?(coder: NSCoder) { fatalError("Programmatic window") }

    private func setupViews() {
        guard let window else { return }
        let root = NSStackView()
        root.orientation = .vertical; root.spacing = 0; root.alignment = .leading
        window.contentView = root
        search.placeholderString = "Find in document"
        search.setAccessibilityLabel("Find in document")
        search.delegate = self
        search.target = self; search.action = #selector(findNext(_:))
        search.sendsSearchStringImmediately = false
        let next = NSButton(title: "Next", target: self, action: #selector(findNext(_:)))
        let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close Find")!, target: self, action: #selector(closeFind(_:)))
        close.bezelStyle = .inline
        searchRow.orientation = .horizontal; searchRow.spacing = 10
        searchRow.edgeInsets = NSEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        [search, next, close].forEach { searchRow.addArrangedSubview($0) }
        root.addArrangedSubview(searchRow); root.addArrangedSubview(content)
        searchRow.isHidden = true
        for view in [searchRow, content] {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        }
        content.heightAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true
        preview.navigationDelegate = self
        preview.setAccessibilityLabel("Markdown preview")
        preview.identifier = NSUserInterfaceItemIdentifier("MarkdownPreview")
        editorScroll.hasVerticalScroller = true
        editorScroll.autohidesScrollers = true
        editorScroll.borderType = .noBorder
        editor.isRichText = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isContinuousSpellCheckingEnabled = false
        editor.isGrammarCheckingEnabled = false
        editor.allowsUndo = true
        editor.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        editor.textContainerInset = NSSize(width: 32, height: 28)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.delegate = self
        editor.setAccessibilityLabel("Markdown source")
        editor.identifier = NSUserInterfaceItemIdentifier("MarkdownSource")
        editorScroll.documentView = editor
        for view in [preview, editorScroll] {
            content.addSubview(view); view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo: content.leadingAnchor), view.trailingAnchor.constraint(equalTo: content.trailingAnchor), view.topAnchor.constraint(equalTo: content.topAnchor), view.bottomAnchor.constraint(equalTo: content.bottomAnchor)])
        }
        editorScroll.isHidden = true
        mode.selectedSegment = 0; mode.target = self; mode.action = #selector(changeMode(_:))
        mode.setAccessibilityLabel("Reading or editing mode")
        mode.setToolTip("Read Markdown (⌘E)", forSegment: 0)
        mode.setToolTip("Edit source (⌘E)", forSegment: 1)
        mode.setWidth(34, forSegment: 0)
        mode.setWidth(34, forSegment: 1)
    }

    func refreshFromDocument() {
        guard let markdown else { return }
        applying = true; editor.string = markdown.source; applying = false
        renderedSource = nil
        renderPreview()
        if markdown.fileURL == nil { setEditing(true) }
    }

    private func renderPreview() {
        guard let markdown, renderedSource != markdown.source else { return }
        let text = markdown.source, url = markdown.fileURL
        generation += 1; let requested = generation
        renderStarted = CFAbsoluteTimeGetCurrent()
        Self.renderQueue.async { [weak self] in
            guard self != nil else { return }
            if Self.sharedRenderer == nil { Self.sharedRenderer = MarkdownRenderer() }
            let html = Self.sharedRenderer!.render(text, fileURL: url)
            DispatchQueue.main.async { [weak self] in
                guard let self, generation == requested else { return }
                renderedSource = text
                preview.loadHTMLString(html, baseURL: nil)
            }
        }
    }

    @objc func changeMode(_ sender: Any?) { setEditing(mode.selectedSegment == 1) }
    @objc func toggleEditing(_ sender: Any?) { setEditing(!editing) }
    private func setEditing(_ value: Bool) {
        guard editing != value else { return }
        editing = value; mode.selectedSegment = value ? 1 : 0
        if value {
            preview.evaluateJavaScript("window.scrollY") { [weak self] result, _ in
                if let y = result as? Double { self?.readingY = y }
            }
            if editor.string != markdown?.source {
                applying = true; editor.string = markdown?.source ?? ""; applying = false
            }
            editor.setSelectedRange(NSIntersectionRange(selection, NSRange(location: 0, length: editor.string.utf16.count)))
            editorScroll.isHidden = false; preview.isHidden = true
            window?.makeFirstResponder(editor)
        } else {
            selection = editor.selectedRange()
            editor.breakUndoCoalescing()
            editorScroll.isHidden = true; preview.isHidden = false
            renderPreview(); window?.makeFirstResponder(preview)
        }
    }

    func textDidChange(_ notification: Notification) {
        guard !applying else { return }
        markdown?.edit(editor.string)
        // NSTextView registers edits with NSDocument's undo manager; NSDocument tracks dirtiness.
    }
    func undoManager(for view: NSTextView) -> UndoManager? { markdown?.undoManager }

    @objc func showFind(_ sender: Any?) { searchRow.isHidden = false; window?.makeFirstResponder(search) }
    @objc func closeFind(_ sender: Any?) { searchRow.isHidden = true; window?.makeFirstResponder(editing ? editor : preview) }
    @objc func findNext(_ sender: Any?) {
        let query = search.stringValue
        guard !query.isEmpty else { return }
        if editing {
            let text = editor.string as NSString
            let start = min(NSMaxRange(editor.selectedRange()), text.length)
            var range = text.range(of: query, options: [.caseInsensitive], range: NSRange(location: start, length: text.length - start))
            if range.location == NSNotFound { range = text.range(of: query, options: [.caseInsensitive]) }
            if range.location != NSNotFound { editor.setSelectedRange(range); editor.scrollRangeToVisible(range) } else { NSSound.beep() }
        } else {
            let configuration = WKFindConfiguration(); configuration.wraps = true
            preview.find(query, configuration: configuration) { if !$0.matchFound { NSSound.beep() } }
        }
    }
    @objc func zoomIn(_ sender: Any?) { setZoom(min(zoom + 0.1, 2.0)) }
    @objc func zoomOut(_ sender: Any?) { setZoom(max(zoom - 0.1, 0.7)) }
    @objc func resetZoom(_ sender: Any?) { setZoom(1) }
    private func setZoom(_ value: Double) {
        zoom = value; preview.pageZoom = value
        editor.font = .monospacedSystemFont(ofSize: 14 * value, weight: .regular)
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.flexibleSpace, .init("mode"), .init("find")] }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarAllowedItemIdentifiers(toolbar) }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)
        if identifier.rawValue == "mode" { item.view = mode; item.label = "Read or Edit" }
        else if identifier.rawValue == "find" {
            item.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Find")
            item.label = "Find"; item.target = self; item.action = #selector(showFind(_:))
        }
        return item
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        preview.evaluateJavaScript("window.scrollTo(0, \(readingY))", completionHandler: nil)
        let ms = (CFAbsoluteTimeGetCurrent() - renderStarted) * 1000
        log.info("Rendered in \(ms, privacy: .public) ms")
        if let path = ProcessInfo.processInfo.environment["FOLIO_PERF_LOG"] {
            let line = "\(Date().timeIntervalSince1970),\(ms)\n"
            if let handle = FileHandle(forWritingAtPath: path) {
                _ = try? handle.seekToEnd(); try? handle.write(contentsOf: Data(line.utf8)); try? handle.close()
            }
        }
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard action.navigationType == .linkActivated else { decisionHandler(.allow); return }
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        if url.fragment != nil && (url.scheme == "about" || url.scheme == nil) { decisionHandler(.allow); return }
        decisionHandler(.cancel)
        guard let safe = MarkdownRenderer.safeLink(url.absoluteString, relativeTo: markdown?.fileURL?.deletingLastPathComponent()) else { return }
        if safe.isFileURL {
            NSDocumentController.shared.openDocument(withContentsOf: safe, display: true) { _, _, error in
                if let error { NSApp.presentError(error) }
            }
        } else { NSWorkspace.shared.open(safe) }
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { renderedSource = nil; renderPreview() }
    func windowDidBecomeKey(_ notification: Notification) { markdown?.checkExternalChanges() }
}
