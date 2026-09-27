// SwiftPM equivalent of the entry point used by Xcode app-extension targets.
// Excluded from the Xcode target, which supplies this entry point itself.
import Foundation
@_silgen_name("NSExtensionMain")
func extensionMain(_ argc: Int32, _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int32
exit(extensionMain(CommandLine.argc, CommandLine.unsafeArgv))
