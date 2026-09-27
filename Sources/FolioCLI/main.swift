import AppKit
import FolioCore

func fail(_ error: Error) -> Never {
    FileHandle.standardError.write(Data("folio: \(error.localizedDescription)\n".utf8))
    exit(1)
}

do {
    let action = try CLIArguments.parse(Array(CommandLine.arguments.dropFirst()), directory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true))
    switch action {
    case .help: print(CLIArguments.help)
    case .version: print("Folio \(CLIArguments.version)")
    case .open(let files):
        let ownPath = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let bundled = ownPath.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let candidates = [bundled, FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Folio.app"), URL(fileURLWithPath: "/Applications/Folio.app")]
        let app = ProcessInfo.processInfo.environment["FOLIO_APP_PATH"].map { URL(fileURLWithPath: $0) }
            ?? candidates.first { $0.pathExtension == "app" && FileManager.default.fileExists(atPath: $0.path) }
        guard let app, FileManager.default.fileExists(atPath: app.path) else {
            throw FolioError.invalidArgument("Folio.app is not installed. Run scripts/install.sh first.")
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        var completed = false
        var launchError: Error?
        NSWorkspace.shared.open(files.isEmpty ? [URL(string: "folio://open")!] : files, withApplicationAt: app, configuration: configuration) { _, error in
            launchError = error
            completed = true
        }
        let deadline = Date(timeIntervalSinceNow: 15)
        while !completed && Date() < deadline { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.005)) }
        guard completed else { throw FolioError.invalidArgument("Timed out opening Folio.") }
        if let launchError { throw launchError }

    }
} catch { fail(error) }
