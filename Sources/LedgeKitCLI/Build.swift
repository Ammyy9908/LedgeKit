import Foundation
import LedgeKit

// ledgekit build: the add-on as a .ledgeaddon folder Ledge can load. Built for this Mac and ad-hoc signed, like
// LedgeAddOns' package.py; the Store's own builds come from its CI.

func build(_ arguments: [String]) throws {
    let folder = packageFolder(arguments)
    let manifest = try readManifest(in: folder)
    do { try manifest.validate() } catch { throw CLIError("addon.json: \(describe(error))") }

    try run("swift", ["build", "--package-path", folder.path, "-c", "release"])
    let bin = URL(fileURLWithPath: try output("swift", ["build", "--package-path", folder.path, "-c", "release", "--show-bin-path"]))
    let program = bin.appendingPathComponent(manifest.executable)
    guard FileManager.default.isExecutableFile(atPath: program.path) else {
        throw CLIError("The build made no \(manifest.executable). addon.json's executable must name the package's executable target.")
    }

    let bundle = folder.appendingPathComponent(".build/addons/\(manifest.executable).ledgeaddon", isDirectory: true)
    try? FileManager.default.removeItem(at: bundle)
    try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: program, to: bundle.appendingPathComponent(manifest.executable))
    try FileManager.default.copyItem(at: folder.appendingPathComponent("addon.json"), to: bundle.appendingPathComponent("addon.json"))
    if let icon = manifest.icon {
        let source = folder.appendingPathComponent(icon)
        guard FileManager.default.fileExists(atPath: source.path) else { throw CLIError("addon.json names \(icon), which isn't there.") }
        try FileManager.default.createDirectory(at: bundle.appendingPathComponent("Assets"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: bundle.appendingPathComponent(icon))
    }
    try run("codesign", ["--force", "--sign", "-", bundle.appendingPathComponent(manifest.executable).path])
    print("""

    Built \(manifest.name) \(manifest.version): \(bundle.path)
    Load it in Ledge: Settings, Add-on Store, Load Add-on…
    """)
}

/// A manifest or surface error in words.
func describe(_ error: Error) -> String {
    (error as? LocalizedError)?.errorDescription ?? String(describing: error)
}
