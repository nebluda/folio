import AppKit
import FolioCore

final class MarkdownDocument: NSDocument {
    var source = ""
    private(set) var snapshot = try! TextFile(data: Data())
    private var watcher: DispatchSourceFileSystemObject?
    private var fileWatcher: DispatchSourceFileSystemObject?
    private var directoryWatchGeneration = 0
    private var fileWatchGeneration = 0
    private var conflictVisible = false
    private var ignoredExternalData: Data?

    override class var autosavesInPlace: Bool { false }
    override var fileURL: URL? { didSet { watchDirectory() } }

    override func makeWindowControllers() {
        let controller = DocumentWindowController(document: self)
        addWindowController(controller)
        controller.refreshFromDocument()
    }

    override func read(from data: Data, ofType typeName: String) throws {
        snapshot = try TextFile(data: data)
        source = snapshot.text
    }
    override func read(from url: URL, ofType typeName: String) throws {
        snapshot = try TextFile(url: url)
        source = snapshot.text
    }
    override func data(ofType typeName: String) throws -> Data { snapshot.encoded(source) }

    override func writeSafely(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType) throws {
        // NSDocument performs its coordinated safe-write. Refuse stale source before it starts.
        if let fileURL, fileURL.standardizedFileURL == url.standardizedFileURL,
           try Data(contentsOf: url) != snapshot.original { throw FolioError.changedOnDisk }
        try super.writeSafely(to: url, ofType: typeName, for: saveOperation)
        if saveOperation == .saveOperation || saveOperation == .saveAsOperation {
            snapshot = try TextFile(data: snapshot.encoded(source))
            ignoredExternalData = nil
        }
    }

    func edit(_ text: String) { source = text }

    private func watchDirectory() {
        watcher?.cancel(); watcher = nil
        directoryWatchGeneration += 1
        let generation = directoryWatchGeneration
        watchFile()
        guard let url = fileURL else { return }
        // Opening a parent folder can wait for macOS privacy authorization even
        // when the user has granted access to the individual document.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let descriptor = open(url.deletingLastPathComponent().path, O_EVTONLY)
            guard descriptor >= 0 else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, directoryWatchGeneration == generation else { Darwin.close(descriptor); return }
                let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
                source.setEventHandler { [weak self] in
                    self?.checkExternalChanges()
                    // Atomic saves replace the inode, so follow the new file.
                    self?.watchFile()
                }
                source.setCancelHandler { Darwin.close(descriptor) }
                watcher = source; source.resume()
                checkExternalChanges()
            }
        }
    }

    private func watchFile() {
        fileWatcher?.cancel(); fileWatcher = nil
        fileWatchGeneration += 1
        let generation = fileWatchGeneration
        guard let url = fileURL else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let descriptor = open(url.path, O_EVTONLY)
            guard descriptor >= 0 else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, fileWatchGeneration == generation else { Darwin.close(descriptor); return }
                let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
                    eventMask: [.write, .rename, .delete, .attrib], queue: .main)
                source.setEventHandler { [weak self] in self?.checkExternalChanges() }
                source.setCancelHandler { Darwin.close(descriptor) }
                fileWatcher = source; source.resume()
                checkExternalChanges()
            }
        }
    }

    func checkExternalChanges() {
        guard !conflictVisible, let url = fileURL, let latest = try? TextFile(url: url),
              latest.original != snapshot.original, latest.original != ignoredExternalData else { return }
        if !isDocumentEdited {
            applyExternal(latest)
            return
        }
        guard let window = windowControllers.first?.window else { return }
        conflictVisible = true
        let alert = NSAlert()
        alert.messageText = "“\(displayName ?? "Document")” changed on disk"
        alert.informativeText = "Your unsaved edits are still here. Reload the disk version, or keep your edits and use Save As to save a separate copy."
        alert.addButton(withTitle: "Keep My Edits")
        alert.addButton(withTitle: "Reload From Disk")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            conflictVisible = false
            if response == .alertSecondButtonReturn {
                do { applyExternal(try TextFile(url: url)) } catch { presentError(error) }
            } else { ignoredExternalData = latest.original }
        }
    }

    private func applyExternal(_ latest: TextFile) {
        snapshot = latest; source = latest.text; ignoredExternalData = nil
        undoManager?.removeAllActions()
        updateChangeCount(.changeCleared)
        for controller in windowControllers { (controller as? DocumentWindowController)?.refreshFromDocument() }
    }

    override func close() {
        directoryWatchGeneration += 1; fileWatchGeneration += 1
        watcher?.cancel(); watcher = nil
        fileWatcher?.cancel(); fileWatcher = nil
        super.close()
    }
    deinit { watcher?.cancel(); fileWatcher?.cancel() }
}
