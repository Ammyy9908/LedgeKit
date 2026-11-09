import Foundation
import LedgeKit

// Validation is deliberately metadata-only. Host installation validates package files.
let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 2, arguments[0] == "validate" else {
    FileHandle.standardError.write(Data("Usage: ledgekit validate <addon.json>\n".utf8))
    exit(2)
}
do {
    let data = try Data(contentsOf: URL(fileURLWithPath: arguments[1]))
    let manifest = try JSONDecoder().decode(AddOnManifest.self, from: data)
    try manifest.validate()
    print("Valid manifest: \(manifest.id) \(manifest.version) (protocol \(manifest.protocolVersion))")
} catch let error as ManifestValidationError {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(1)
} catch {
    FileHandle.standardError.write(Data("Cannot read or decode manifest JSON.\n".utf8))
    exit(1)
}
