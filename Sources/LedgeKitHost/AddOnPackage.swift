import Foundation
import AppKit
import LedgeKit

/// Reads and validates a local package without presenting UI or executing code.
/// The caller owns trust approval and supported-capability policy.
/// Validation does not establish publisher identity or sandbox native code.
public struct AddOnPackage {
    public let manifest: AddOnManifest
    public let manifestData: Data
    public let executableURL: URL
    public let iconData: Data?

    public init(contentsOf source: URL) throws {
        let manager = FileManager.default
        let manifestURL = source.appendingPathComponent("addon.json")
        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(AddOnManifest.self, from: data)
        try manifest.validateForLedgeHost()
        let executable = source.appendingPathComponent(manifest.executable)
        guard manager.isExecutableFile(atPath: executable.path),
              try executable.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == false,
              try manifestURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == false else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var iconData: Data?
        if let path = manifest.icon {
            let assets = source.appendingPathComponent("Assets")
            let iconURL = source.appendingPathComponent(path)
            let values = try iconURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard try assets.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == false,
                  values.isSymbolicLink == false, values.isRegularFile == true,
                  (values.fileSize ?? Int.max) <= 4_194_304 else { throw CocoaError(.fileReadCorruptFile) }
            let data = try Data(contentsOf: iconURL)
            guard data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]),
                  let image = NSBitmapImageRep(data: data),
                  image.pixelsWide > 0, image.pixelsWide <= 2048,
                  image.pixelsHigh > 0, image.pixelsHigh <= 2048 else {
                throw CocoaError(.fileReadCorruptFile)
            }
            iconData = data
        }

        self.manifest = manifest
        self.manifestData = data
        self.executableURL = executable
        self.iconData = iconData
    }
}
