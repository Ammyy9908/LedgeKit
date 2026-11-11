import Foundation
import Testing
@testable import LedgeKit

private func manifest(executable: String = "SpotifyLikes", protocolVersion: Int = 1) throws -> AddOnManifest {
    let data = try JSONSerialization.data(withJSONObject: [
        "id": "spotify-likes", "version": "1.0.0", "protocolVersion": protocolVersion,
        "name": "Spotify Likes", "summary": "Like songs", "description": "Like songs from Ledge",
        "author": "Ledge", "capabilities": ["spotify-library"], "executable": executable
    ])
    return try JSONDecoder().decode(AddOnManifest.self, from: data)
}

@Test func acceptsCompatibleManifest() throws {
    try manifest().validate()
}

@Test func rejectsExecutableTraversal() throws {
    let value = try manifest(executable: "../SpotifyLikes")
    #expect(throws: (any Error).self) { try value.validate() }
}

@Test func rejectsUnsupportedProtocol() throws {
    let value = try manifest(protocolVersion: 3)
    #expect(throws: (any Error).self) { try value.validate() }
}

@Test func acceptsSessionProtocol() throws {
    try manifest(protocolVersion: 2).validate()
}

@Test func publicManifestRoundTrips() throws {
    let value = AddOnManifest(id: "example", version: "1.2.3", name: "Example",
        summary: "Example", description: "Example package", author: "Community",
        capabilities: [], icon: "Assets/Icon.png", executable: "Example")
    let decoded = try JSONDecoder().decode(AddOnManifest.self, from: JSONEncoder().encode(value))
    try decoded.validate()
    #expect(decoded.icon == "Assets/Icon.png")
    #expect(decoded.id == "example")
}

@Test func rejectsMalformedVersions() throws {
    for version in ["-1.0.0", "1..0.0", "1.0.", "+1.0.0", "1.0.0."] {
        let value = AddOnManifest(id: "example", version: version, name: "Example",
            summary: "", description: "", author: "Author", capabilities: [], executable: "Example")
        #expect(throws: ManifestValidationError.invalidField("version")) { try value.validate() }
    }
}

@Test func rejectsUnsafeIconPaths() throws {
    for icon in ["../Icon.png", "Assets/../Icon.png", "Assets\\Icon.png", "Assets/.png"] {
        let value = AddOnManifest(id: "example", version: "1.0.0", name: "Example",
            summary: "", description: "", author: "Author", capabilities: [],
            icon: icon, executable: "Example")
        #expect(throws: ManifestValidationError.invalidField("icon")) { try value.validate() }
    }
}
