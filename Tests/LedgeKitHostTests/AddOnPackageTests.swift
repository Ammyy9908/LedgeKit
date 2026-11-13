import Foundation
import Testing
import LedgeKitHost

private func withPackage(_ body: (URL) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let manifest: [String: Any] = [
        "id": "community-example", "version": "1.0.0", "protocolVersion": 1,
        "name": "Example", "summary": "Example", "description": "Example package",
        "author": "Community", "capabilities": ["spotify-library"], "executable": "Example"
    ]
    try JSONSerialization.data(withJSONObject: manifest).write(to: root.appendingPathComponent("addon.json"))
    let executable = root.appendingPathComponent("Example")
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    try body(root)
}

@Test func readsPackageWithoutSpotifyIdentityCoupling() throws {
    try withPackage { root in
        let package = try AddOnPackage(contentsOf: root)
        #expect(package.manifest.id == "community-example")
        #expect(package.iconData == nil)
    }
}

@Test func rejectsLinkedExecutable() throws {
    try withPackage { root in
        let executable = root.appendingPathComponent("Example")
        let other = root.appendingPathComponent("Other")
        try FileManager.default.moveItem(at: executable, to: other)
        try FileManager.default.createSymbolicLink(at: executable, withDestinationURL: other)
        #expect(throws: (any Error).self) { try AddOnPackage(contentsOf: root) }
    }
}

@Test func rejectsNonExecutablePackage() throws {
    try withPackage { root in
        try FileManager.default.setAttributes([.posixPermissions: 0o644],
            ofItemAtPath: root.appendingPathComponent("Example").path)
        #expect(throws: (any Error).self) { try AddOnPackage(contentsOf: root) }
    }
}

@Test func validatesHostQueueCapabilityThroughPackageReader() throws {
    try withPackage { root in
        let url = root.appendingPathComponent("addon.json")
        var manifest = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        // Capabilities are open since LedgeKit 0.4.0: an unknown name reads fine and is simply never granted
        // (see AddOnRegistryTests). Duplicates and malformed names are still refused.
        for capabilities in [["apple-music-queue"], ["apple-music-queue", "apple-music-controls"], ["apple-music-queue", "unknown"],
                             ["apple-music-queue", "apple-music-queue"], ["Not Valid"]] {
            manifest["capabilities"] = capabilities
            try JSONSerialization.data(withJSONObject: manifest).write(to: url)
            if Set(capabilities).count == capabilities.count && capabilities != ["Not Valid"] {
                #expect(try AddOnPackage(contentsOf: root).manifest.capabilities == capabilities)
            } else {
                #expect(throws: (any Error).self) { try AddOnPackage(contentsOf: root) }
            }
        }
        manifest["capabilities"] = ["apple-music-queue"]
        manifest["executable"] = "../Example"
        try JSONSerialization.data(withJSONObject: manifest).write(to: url)
        #expect(throws: (any Error).self) { try AddOnPackage(contentsOf: root) }
    }
}

@Test func validatesBuiltQueuePackageWhenPresent() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    let packageURL = root.appendingPathComponent(".build/AppleMusicQueue.ledgeaddon")
    guard FileManager.default.fileExists(atPath: packageURL.path) else { return }
    let package = try AddOnPackage(contentsOf: packageURL)
    #expect(package.manifest.id == "apple-music-queue")
    #expect(package.manifest.capabilities == ["apple-music-queue", "apple-music-controls"])
    #expect(package.manifest.executable == "AppleMusicQueue")
}
