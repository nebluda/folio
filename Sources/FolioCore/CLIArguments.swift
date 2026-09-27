import Foundation

public enum CLIAction: Equatable {
    case help, version, open([URL])
}

public enum CLIArguments {
    public static let version = "0.1.0"
    public static let help = """
    Folio — Preview for Markdown
    Usage: folio [--] [file.md …]
           folio --help
           folio --version

    Opens Markdown in a native window. With no files, shows the Open dialog.
    Use -- before filenames beginning with a dash. No server or browser is started.
    """

    public static func parse(_ arguments: [String], directory: URL) throws -> CLIAction {
        if arguments == ["--help"] || arguments == ["-h"] { return .help }
        if arguments == ["--version"] { return .version }
        var files: [URL] = []
        var positionalOnly = false
        for argument in arguments {
            if !positionalOnly && argument == "--" { positionalOnly = true; continue }
            if !positionalOnly && argument.hasPrefix("-") {
                throw FolioError.invalidArgument("Unknown option: \(argument). Use --help for usage.")
            }
            let url = URL(fileURLWithPath: argument, relativeTo: directory).standardizedFileURL.resolvingSymlinksInPath()
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue,
                  FileManager.default.isReadableFile(atPath: url.path) else {
                throw FolioError.invalidArgument("Cannot read file: \(argument)")
            }
            guard ["md", "markdown"].contains(url.pathExtension.lowercased()) else {
                throw FolioError.invalidArgument("Expected a .md or .markdown file: \(argument)")
            }
            if !files.contains(url) { files.append(url) }
        }
        return .open(files)
    }
}
