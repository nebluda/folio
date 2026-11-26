import AppKit
import WebKit
import FolioCore
import os

final class DocumentWindowController: NSWindowController, NSToolbarDelegate, NSSharingServicePickerToolbarItemDelegate, NSTextViewDelegate, WKNavigationDelegate, NSWindowDelegate, NSSearchFieldDelegate {
    private static let websiteDataStore = WKWebsiteDataStore.nonPersistent()
    private static let performanceLogPath = ProcessInfo.processInfo.environment["FOLIO_PERF_LOG"]
    private static let renderQueue = DispatchQueue(label: "app.folio.render", qos: .userInitiated)
    // Main thread only. At most one unattached reader window, prepared after a preview loads.
    private static var spareController: DocumentWindowController?
    // Accessed exclusively on renderQueue. Share parser/highlighter setup across windows.
    private static var sharedRenderer: MarkdownRenderer?
    private lazy var preview: WKWebView = {
        let view = Self.makeWebView()
        view.navigationDelegate = self
        view.setAccessibilityLabel("Markdown preview")
        view.identifier = NSUserInterfaceItemIdentifier("MarkdownPreview")
        return view
    }()
    private lazy var editorScroll = makeEditor()
    private var editor: NSTextView { editorScroll.documentView as! NSTextView }
    private let editorHighlighter = EditorHighlighter()
    private var editorWasOpened = false
    private let search = NSSearchField()
    private let searchRow = NSStackView()
    private let documentRow = NSStackView()
    private let content = NSView()
    private let mode = NSSegmentedControl(images: [
        NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "Read")!,
        NSImage(systemSymbolName: "pencil", accessibilityDescription: "Edit")!
    ], trackingMode: .selectOne, target: nil, action: nil)
    private var generation = 0
    private var renderedSource: String?
    private var headings: [PreviewHeading]?
    private var tableOfContents: TableOfContentsView?
    private var showsTableOfContents = false
    private var previewLoad: PreviewLoad?
    private var readingY = 0.0
    private var selection = NSRange(location: 0, length: 0)
    private var editing = false
    private var applying = false
    private var zoom = 1.0
    private let log = Logger(subsystem: "io.github.nebluda.folio", category: "render")
    private var markdown: MarkdownDocument? { document as? MarkdownDocument }

    private struct PreviewLoad {
        let navigation: WKNavigation
        let headings: [PreviewHeading]
        let hasDeferredCode: Bool
        let started: DispatchTime
        let htmlMilliseconds: Double
        let webKitStarted: DispatchTime
    }

    private static func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.websiteDataStore = websiteDataStore
        return WKWebView(frame: .zero, configuration: configuration)
    }

    private static func prepareNextWindow() {
        guard spareController == nil else { return }
        DispatchQueue.main.async {
            guard spareController == nil else { return }
            let controller = DocumentWindowController(document: nil)
            controller.preview.loadHTMLString("<!doctype html>", baseURL: nil)
            spareController = controller
        }
    }

    static func make(for document: MarkdownDocument) -> DocumentWindowController {
        let controller: DocumentWindowController
        if let spare = spareController {
            spareController = nil
            controller = spare
            if document.fileURL != nil { controller.renderPreview(document) }
        } else {
            controller = DocumentWindowController(document: document)
        }
        controller.window?.setFrameAutosaveName("FolioDocument")
        controller.window?.center()
        return controller
    }

    private init(document: MarkdownDocument?) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 850, height: 760), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        // Prepare Markdown while the main thread builds the window and WebKit view.
        if let document, document.fileURL != nil { renderPreview(document) }
        window.animationBehavior = .none
        window.minSize = NSSize(width: 420, height: 300)
        window.title = "Untitled"
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
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
        documentRow.orientation = .horizontal; documentRow.alignment = .top; documentRow.spacing = 0
        documentRow.addArrangedSubview(content)
        root.addArrangedSubview(searchRow); root.addArrangedSubview(documentRow)
        searchRow.isHidden = true
        for view in [searchRow, documentRow] {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        }
        content.heightAnchor.constraint(equalTo: documentRow.heightAnchor).isActive = true
        content.heightAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true
        pinToContent(preview)
        mode.selectedSegment = 0; mode.target = self; mode.action = #selector(changeMode(_:))
        mode.setAccessibilityLabel("Reading or editing mode")
        mode.setToolTip("Read Markdown (⌘E)", forSegment: 0)
        mode.setToolTip("Edit source (⌘E)", forSegment: 1)
        mode.setWidth(34, forSegment: 0)
        mode.setWidth(34, forSegment: 1)
    }

    private func pinToContent(_ view: NSView) {
        content.addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            view.topAnchor.constraint(equalTo: content.topAnchor),
            view.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
    }

    private func makeEditor() -> NSScrollView {
        let editorScroll = NSScrollView()
        let editor = NSTextView()
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
        editor.font = .monospacedSystemFont(ofSize: 14 * zoom, weight: .regular)
        editor.textContainerInset = NSSize(width: 32, height: 28)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.delegate = self
        editor.setAccessibilityLabel("Markdown source")
        editor.identifier = NSUserInterfaceItemIdentifier("MarkdownSource")
        editorScroll.documentView = editor
        pinToContent(editorScroll)
        return editorScroll
    }

    func refreshFromDocument() {
        guard let markdown else { return }
        if editing {
            applying = true; editor.string = markdown.source; applying = false
            editorHighlighter.update(editor, immediately: true)
        }
        renderedSource = nil
        if !editing { renderPreview() }
    }

    private static func milliseconds(from start: DispatchTime, to end: DispatchTime = .now()) -> Double {
        Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    }

    private func renderPreview(_ document: MarkdownDocument? = nil) {
        guard let markdown = document ?? markdown, renderedSource != markdown.source else { return }
        let text = markdown.source, url = markdown.fileURL
        generation += 1; let requested = generation
        let started = DispatchTime.now()
        Self.renderQueue.async { [weak self] in
            guard self != nil else { return }
            let htmlStarted = DispatchTime.now()
            if Self.sharedRenderer == nil { Self.sharedRenderer = MarkdownRenderer() }
            let rendered = Self.sharedRenderer!.renderPreview(text, fileURL: url, presentation: .reader)
            let htmlMilliseconds = Self.milliseconds(from: htmlStarted)
            DispatchQueue.main.async { [weak self] in
                guard let self, generation == requested else { return }
                renderedSource = text
                let webKitStarted = DispatchTime.now()
                if let navigation = preview.loadHTMLString(rendered.html, baseURL: nil) {
                    previewLoad = PreviewLoad(navigation: navigation, headings: rendered.headings,
                                              hasDeferredCode: rendered.hasDeferredCode, started: started,
                                              htmlMilliseconds: htmlMilliseconds, webKitStarted: webKitStarted)
                }
            }
        }
    }

    @objc func changeMode(_ sender: Any?) { setEditing(mode.selectedSegment == 1) }
    @objc func toggleEditing(_ sender: Any?) { setEditing(!editing) }

    private func setEditing(_ value: Bool) {
        guard editing != value else { return }
        editing = value; mode.selectedSegment = value ? 1 : 0
        if value {
            editorWasOpened = true
            tableOfContents?.isHidden = true
            preview.evaluateJavaScript("window.scrollY") { [weak self] result, _ in
                if let y = result as? Double { self?.readingY = y }
            }
            if editor.string != markdown?.source {
                applying = true; editor.string = markdown?.source ?? ""; applying = false
            }
            editor.setSelectedRange(NSIntersectionRange(selection, NSRange(location: 0, length: editor.string.utf16.count)))
            editorScroll.isHidden = false; preview.isHidden = true
            editorHighlighter.update(editor, immediately: true)
            window?.makeFirstResponder(editor)
        } else {
            selection = editor.selectedRange()
            editor.breakUndoCoalescing()
            editorScroll.isHidden = true; preview.isHidden = false
            tableOfContents?.isHidden = !showsTableOfContents
            renderPreview(); window?.makeFirstResponder(preview)
        }
    }

    @objc func toggleTableOfContents(_ sender: Any?) {
        showsTableOfContents = tableOfContents?.isHidden != false
        if showsTableOfContents {
            if editing { setEditing(false) }
            let sidebar = tableOfContents ?? makeTableOfContents()
            sidebar.isHidden = false
            sidebar.focusHeadings()
        } else {
            tableOfContents?.isHidden = true
            window?.makeFirstResponder(preview)
        }
    }

    private func makeTableOfContents() -> TableOfContentsView {
        let sidebar = TableOfContentsView()
        sidebar.onNavigate = { [weak self] heading in self?.navigate(to: heading) }
        tableOfContents = sidebar
        documentRow.insertArrangedSubview(sidebar, at: 0)
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        let preferredWidth = sidebar.widthAnchor.constraint(equalToConstant: 230)
        preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            preferredWidth,
            sidebar.widthAnchor.constraint(lessThanOrEqualTo: documentRow.widthAnchor, multiplier: 0.4),
            sidebar.heightAnchor.constraint(equalTo: documentRow.heightAnchor),
        ])
        sidebar.showHeadings(headings)
        return sidebar
    }

    private func navigate(to heading: PreviewHeading) {
        guard !editing, previewLoad == nil, renderedSource == markdown?.source else { return }
        preview.callAsyncJavaScript("document.getElementById(id)?.scrollIntoView({block: 'start'});",
                                    arguments: ["id": heading.id], in: nil, in: .defaultClient,
                                    completionHandler: nil)
    }

    func textDidChange(_ notification: Notification) {
        guard !applying else { return }
        markdown?.edit(editor.string)
        editorHighlighter.update(editor)
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
        if editorWasOpened { editor.font = .monospacedSystemFont(ofSize: 14 * value, weight: .regular) }
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.init("contents"), .flexibleSpace, .init("mode"), .init("share"), .init("find")]
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarAllowedItemIdentifiers(toolbar) }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if identifier.rawValue == "share" {
            let item = NSSharingServicePickerToolbarItem(itemIdentifier: identifier)
            item.delegate = self
            item.label = "Share"
            item.toolTip = "Share Markdown file"
            return item
        }
        let item = NSToolbarItem(itemIdentifier: identifier)
        if identifier.rawValue == "mode" { item.view = mode; item.label = "Read or Edit" }
        else if identifier.rawValue == "contents" {
            item.image = NSImage(systemSymbolName: "sidebar.leading", accessibilityDescription: "Table of Contents")
            item.label = "Table of Contents"
            item.toolTip = "Toggle Table of Contents (⇧⌘O)"
            item.target = self
            item.action = #selector(toggleTableOfContents(_:))
        }
        else if identifier.rawValue == "find" {
            item.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Find")
            item.label = "Find"; item.target = self; item.action = #selector(showFind(_:))
        }
        return item
    }
    func items(for pickerToolbarItem: NSSharingServicePickerToolbarItem) -> [Any] {
        // NSDocument saves current edits (or asks for a location) before sharing.
        markdown.map { [$0] } ?? []
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let load = previewLoad, navigation === load.navigation else { return }
        previewLoad = nil
        let now = DispatchTime.now()
        let previewMS = Self.milliseconds(from: load.started, to: now)
        let webKitMS = Self.milliseconds(from: load.webKitStarted, to: now)
        log.info("Preview ready in \(previewMS, privacy: .public) ms")
        if let path = Self.performanceLogPath {
            let bytes = renderedSource?.utf8.count ?? 0
            let line = "\(Date().timeIntervalSince1970),\(previewMS),\(load.htmlMilliseconds),\(webKitMS),\(bytes)\n"
            if let handle = FileHandle(forWritingAtPath: path) {
                _ = try? handle.seekToEnd(); try? handle.write(contentsOf: Data(line.utf8)); try? handle.close()
            }
        }
        if readingY != 0 { preview.evaluateJavaScript("window.scrollTo(0, \(readingY))", completionHandler: nil) }
        headings = load.headings
        tableOfContents?.showHeadings(load.headings)
        if load.hasDeferredCode {
            preview.evaluateJavaScript(MarkdownRenderer.deferredCodeScript, in: nil, in: .defaultClient,
                                       completionHandler: nil)
        }
        Self.prepareNextWindow()
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
