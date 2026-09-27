import Foundation
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
        // LaunchServices runs in the system launcher, keeping this CLI out of the app lifecycle.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", app.path, "--"] + (files.isEmpty ? ["folio://open"] : files.map(\.path))
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 { throw FolioError.invalidArgument("macOS could not open Folio (exit \(process.terminationStatus)).") }
    }
} catch { fail(error) }
