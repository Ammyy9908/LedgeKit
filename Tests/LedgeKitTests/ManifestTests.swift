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

// MARK: Manifest v2

private func v2(_ extra: [String: Any]) throws -> AddOnManifest {
    var object: [String: Any] = [
        "id": "moon-phase", "version": "1.0.0", "protocolVersion": 2,
        "name": "Moon Phase", "summary": "Tonight's moon", "description": "Shows the moon phase.",
        "author": "Jane", "capabilities": [], "executable": "MoonPhase"
    ]
    extra.forEach { object[$0.key] = $0.value }
    return try JSONDecoder().decode(AddOnManifest.self, from: JSONSerialization.data(withJSONObject: object))
}

@Test func v1ManifestsStillDecodeWithoutTheNewFields() throws {
    let value = try manifest()
    try value.validate()
    #expect(value.surfaces == nil && value.kit == nil && value.creator == nil)
    // Encoding a v1 manifest doesn't add empty v2 keys.
    let keys = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any]
    #expect(keys?["surfaces"] == nil && keys?["kit"] == nil)
}

@Test func v2FieldsRoundTrip() throws {
    let value = try v2([
        "surfaces": ["settings-page", "widget"], "kit": ["minAPI": "0.4.0"], "minLedge": "0.2.0", "minMacOS": "14.0",
        "category": "Productivity", "creator": ["name": "Jane", "url": "https://jane.example", "avatar": "Assets/Creator.png"],
        "source": ["repository": "https://github.com/jane/moon", "license": "MIT"], "keywords": ["moon", "astronomy"]
    ])
    try value.validate()
    let decoded = try JSONDecoder().decode(AddOnManifest.self, from: JSONEncoder().encode(value))
    #expect(decoded == value)
    #expect(decoded.creator?.name == "Jane" && decoded.source?.license == "MIT" && decoded.kit?.minAPI == "0.4.0")
}

@Test func unknownCapabilitiesValidateButMalformedOnesDont() throws {
    try v2(["capabilities": ["calendar-read", "spotify-library"]]).validate()
    #expect(throws: ManifestValidationError.unsupportedCapability("Calendar Read")) {
        try v2(["capabilities": ["Calendar Read"]]).validate()
    }
    #expect(throws: (any Error).self) { try v2(["capabilities": ["-leading"]]).validate() }
}

@Test func malformedV2FieldsAreRefused() throws {
    #expect(throws: ManifestValidationError.invalidField("kit.minAPI")) { try v2(["kit": ["minAPI": "1.0"]]).validate() }
    #expect(throws: ManifestValidationError.invalidField("minLedge")) { try v2(["minLedge": "next"]).validate() }
    #expect(throws: ManifestValidationError.invalidField("minMacOS")) { try v2(["minMacOS": "14.x"]).validate() }
    #expect(throws: ManifestValidationError.invalidField("creator.name")) { try v2(["creator": ["name": " "]]).validate() }
    #expect(throws: ManifestValidationError.invalidField("surfaces")) { try v2(["surfaces": ["Widget!"]]).validate() }
}

@Test func compatibilityNamesWhatIsMissing() throws {
    let macOS14 = OperatingSystemVersion(majorVersion: 14, minorVersion: 5, patchVersion: 0)
    #expect(try v2([:]).incompatibility(ledgeVersion: "0.1.0", macOS: macOS14) == nil)
    #expect(try v2(["kit": ["minAPI": "0.9.0"]]).incompatibility(ledgeVersion: "1.0.0", apiLevel: "0.4.0", macOS: macOS14) == .needsNewerKit("0.9.0"))
    #expect(try v2(["minLedge": "0.3.0"]).incompatibility(ledgeVersion: "0.2.9", macOS: macOS14) == .needsNewerLedge("0.3.0"))
    #expect(try v2(["minLedge": "0.3.0"]).incompatibility(ledgeVersion: "0.10.0", macOS: macOS14) == nil)
    #expect(try v2(["minMacOS": "15.0"]).incompatibility(ledgeVersion: "1.0.0", macOS: macOS14) == .needsNewerMacOS("15.0"))
    #expect(try v2(["minMacOS": "14.5"]).incompatibility(ledgeVersion: "1.0.0", macOS: macOS14) == nil)
}

@Test func versionsCompareNumerically() {
    #expect(AddOnManifest.compare("0.10.0", "0.9.0") == .orderedDescending)
    #expect(AddOnManifest.compare("1.0", "1.0.0") == .orderedSame)
    #expect(AddOnManifest.compare("1.2.3", "1.2.4") == .orderedAscending)
}
