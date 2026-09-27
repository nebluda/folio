import AppKit
import FolioCore
import UniformTypeIdentifiers

@main
struct FolioApplication {
    static func main() {
        let app = NSApplication.shared
        // A process-local override for reproducible screenshots; normal launches follow macOS.
        if let appearance = ProcessInfo.processInfo.environment["FOLIO_APPEARANCE"] {
            app.appearance = NSAppearance(named: appearance == "light" ? .aqua : .darkAqua)
        }
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let documents = FolioDocumentController()
    private var receivedOpen = false

    func applicationWillFinishLaunching(_ notification: Notification) { buildMenus() }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        let paths = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") && ["md", "markdown"].contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }
        if !paths.isEmpty { application(NSApp, open: paths.map { URL(fileURLWithPath: $0) }) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
            if !receivedOpen && documents.documents.isEmpty { documents.openDocument(nil) }
        }
    }
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { documents.openDocument(nil) }
        return true
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        receivedOpen = true
        for url in urls {
            if url.scheme == "folio" { documents.openDocument(nil); continue }
            documents.openDocument(withContentsOf: url.resolvingSymlinksInPath(), display: true) { _, _, error in
                if let error { NSApp.presentError(error) }
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildMenus() {
        let main = NSMenu()
        NSApp.mainMenu = main
        func menu(_ title: String) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: title); item.submenu = submenu; main.addItem(item); return submenu
        }
        func item(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String = "", shift: Bool = false, target: AnyObject? = nil) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = target
            if shift { item.keyEquivalentModifierMask = [.command, .shift] }
            menu.addItem(item)
        }
        let app = menu("Folio")
        item(app, "About Folio", #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
        app.addItem(.separator())
        item(app, "Hide Folio", #selector(NSApplication.hide(_:)), "h")
        item(app, "Quit Folio", #selector(NSApplication.terminate(_:)), "q")
        let file = menu("File")
        item(file, "New", #selector(NSDocumentController.newDocument(_:)), "n", target: documents)
        item(file, "Open…", #selector(NSDocumentController.openDocument(_:)), "o", target: documents)
        let recent = NSMenu(title: "Open Recent")
        recent.delegate = self
        let recentItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: ""); recentItem.submenu = recent; file.addItem(recentItem)
        item(recent, "Clear Menu", #selector(NSDocumentController.clearRecentDocuments(_:)), target: documents)
        file.addItem(.separator())
        item(file, "Close", #selector(NSWindow.performClose(_:)), "w")
        item(file, "Save", #selector(NSDocument.save(_:)), "s")
        item(file, "Save As…", #selector(NSDocument.saveAs(_:)), "s", shift: true)
        file.addItem(.separator())
        file.addItem(documents.standardShareMenuItem())
        let edit = menu("Edit")
        item(edit, "Undo", Selector(("undo:")), "z")
        item(edit, "Redo", Selector(("redo:")), "z", shift: true)
        edit.addItem(.separator())
        item(edit, "Cut", #selector(NSText.cut(_:)), "x")
        item(edit, "Copy", #selector(NSText.copy(_:)), "c")
        item(edit, "Paste", #selector(NSText.paste(_:)), "v")
        item(edit, "Select All", #selector(NSText.selectAll(_:)), "a")
        item(edit, "Find…", #selector(DocumentWindowController.showFind(_:)), "f")
        let view = menu("View")
        item(view, "Edit / Preview", #selector(DocumentWindowController.toggleEditing(_:)), "e")
        item(view, "Zoom In", #selector(DocumentWindowController.zoomIn(_:)), "+")
        item(view, "Zoom Out", #selector(DocumentWindowController.zoomOut(_:)), "-")
        item(view, "Actual Size", #selector(DocumentWindowController.resetZoom(_:)), "0")
        let window = menu("Window"); NSApp.windowsMenu = window
        item(window, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
        item(window, "Bring All to Front", #selector(NSApplication.arrangeInFront(_:)))
        let help = menu("Help")
        item(help, "Use Folio for Markdown Files…", #selector(makeDefault), target: self)
        item(help, "Set Up Finder Preview…", #selector(openQuickLookSettings), target: self)
    }

    @objc private func openQuickLookSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences?extensionPointIdentifier=com.apple.quicklook.preview")!)
    }

    @objc private func makeDefault() {
        // Resolve the preferred types on this Mac; other editors can register
        // different identifiers for these extensions.
        let types = Set(["md", "markdown"].compactMap { UTType(filenameExtension: $0) })
        for type in types {
            NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: type) { error in
                DispatchQueue.main.async {
                    if let error { NSApp.presentError(error) }
                }
            }
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for url in documents.recentDocumentURLs {
            let item = NSMenuItem(title: url.lastPathComponent, action: #selector(openRecent(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = url; item.toolTip = url.path
            menu.addItem(item)
        }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        let clear = NSMenuItem(title: "Clear Menu", action: #selector(NSDocumentController.clearRecentDocuments(_:)), keyEquivalent: "")
        clear.target = documents; menu.addItem(clear)
    }
    @objc private func openRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        application(NSApp, open: [url])
    }
}

final class FolioDocumentController: NSDocumentController {
    override var defaultType: String? { "net.daringfireball.markdown" }
    override func documentClass(forType typeName: String) -> AnyClass? { MarkdownDocument.self }
    override func typeForContents(of url: URL) throws -> String { "net.daringfireball.markdown" }
}
