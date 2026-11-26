import AppKit
import FolioCore

final class TableOfContentsView: NSVisualEffectView, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private final class Entry {
        let heading: PreviewHeading
        var children: [Entry] = []

        init(_ heading: PreviewHeading) { self.heading = heading }
    }

    private let outline = NSOutlineView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private var entries: [Entry] = []
    private weak var previousResponder: NSResponder?
    private var updating = false
    var onNavigate: ((PreviewHeading) -> Void)?

    init() {
        super.init(frame: .zero)
        material = .sidebar
        blendingMode = .withinWindow

        let title = NSTextField(labelWithString: "Table of Contents")
        title.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.lineBreakMode = .byTruncatingTail

        let column = NSTableColumn(identifier: .init("Heading"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        outline.style = .sourceList
        outline.rowSizeStyle = .small
        outline.headerView = nil
        outline.backgroundColor = .clear
        outline.indentationPerLevel = 12
        outline.stronglyReferencesItems = true
        outline.floatsGroupRows = false
        outline.setAccessibilityLabel("Document headings")
        outline.identifier = .init("DocumentHeadings")
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.doubleAction = #selector(navigateToSelection)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.documentView = outline

        for view in [title, emptyLabel, scroll] {
            addSubview(view)
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            title.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            emptyLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: title.trailingAnchor),
            emptyLabel.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            scroll.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("Programmatic view") }

    func showHeadings(_ headings: [PreviewHeading]?) {
        var parents: [Entry] = []
        entries = []
        for heading in headings ?? [] {
            while let previous = parents.last, previous.heading.level >= heading.level {
                parents.removeLast()
            }
            let entry = Entry(heading)
            if let parent = parents.last { parent.children.append(entry) }
            else { entries.append(entry) }
            parents.append(entry)
        }

        emptyLabel.stringValue = headings == nil ? "Loading headings…" : "No headings"
        emptyLabel.isHidden = !entries.isEmpty
        outline.enclosingScrollView?.isHidden = entries.isEmpty
        updating = true
        outline.deselectAll(nil)
        outline.reloadData()
        outline.expandItem(nil, expandChildren: true)
        updating = false
        if !isHidden, let previousResponder, window?.firstResponder === previousResponder {
            focusHeadings()
        }
        self.previousResponder = nil
    }

    func focusHeadings() {
        if entries.isEmpty {
            previousResponder = window?.firstResponder
        } else {
            window?.makeFirstResponder(outline)
        }
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        ((item as? Entry)?.children ?? entries).count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        ((item as? Entry)?.children ?? entries)[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        !(item as! Entry).children.isEmpty
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let entry = item as! Entry
        let identifier = NSUserInterfaceItemIdentifier("HeadingLabel")
        let label = outlineView.makeView(withIdentifier: identifier, owner: nil) as? NSTextField
            ?? NSTextField(labelWithString: "")
        label.identifier = identifier
        label.stringValue = entry.heading.title
        label.toolTip = entry.heading.title
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        if !updating { navigateToSelection() }
    }

    @objc private func navigateToSelection() {
        guard outline.selectedRow >= 0, let entry = outline.item(atRow: outline.selectedRow) as? Entry else { return }
        onNavigate?(entry.heading)
    }
}
