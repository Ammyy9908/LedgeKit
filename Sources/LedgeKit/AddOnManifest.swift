import Foundation

/// Metadata for an executable package: protocol 1 runs the program once per request, protocol 2 keeps a
/// session open. New optional fields preserve old packages.
public struct AddOnManifest: Codable, Sendable {
    public let id: String
    public let version: String
    public let protocolVersion: Int
    public let name: String
    public let summary: String
    public let description: String
    public let author: String
    public let capabilities: [String]
    /// Relative PNG path under Assets, or nil to use the host fallback.
    public let icon: String?
    public let executable: String

    /// Creates metadata. Call validate before writing or installing it.
    public init(id: String, version: String, protocolVersion: Int = 1,
                name: String, summary: String, description: String, author: String,
                capabilities: [String], icon: String? = nil, executable: String) {
        self.id = id
        self.version = version
        self.protocolVersion = protocolVersion
        self.name = name
        self.summary = summary
        self.description = description
        self.author = author
        self.capabilities = capabilities
        self.icon = icon
        self.executable = executable
    }

    /// Checks metadata only. Package file checks and user trust belong to the host.
    public func validate() throws {
        guard !id.isEmpty, id.count <= 64,
              id.allSatisfy({ $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-") })
        else { throw ManifestValidationError.invalidField("id") }
        // 1: one program run per request (AddOnWorker). 2: a long-lived session (AddOnSession).
        guard [1, SessionProtocol.version].contains(protocolVersion) else { throw ManifestValidationError.unsupportedProtocol(protocolVersion) }
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({
            !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) && Int($0) != nil
        }) else { throw ManifestValidationError.invalidField("version") }
        guard !executable.isEmpty, executable != ".", executable != "..",
              !executable.contains("/"), !executable.contains("\\"),
              !executable.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { throw ManifestValidationError.invalidField("executable") }
        for (field, value) in [("name", name), ("author", author)] {
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { throw ManifestValidationError.invalidField(field) }
        }
        for capability in capabilities where !["spotify-library", "notification-banners"].contains(capability) {
            throw ManifestValidationError.unsupportedCapability(capability)
        }
        guard Set(capabilities).count == capabilities.count
        else { throw ManifestValidationError.invalidField("capabilities") }
        if let icon {
            let parts = icon.split(separator: "/", omittingEmptySubsequences: false)
            guard parts.count == 2, parts[0] == "Assets", parts[1].count > 4,
                  !icon.contains("\\"), icon.lowercased().hasSuffix(".png"),
                  !icon.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
            else { throw ManifestValidationError.invalidField("icon") }
        }
    }
}

/// Stable validation categories suitable for tests and developer diagnostics.
public enum ManifestValidationError: Error, Equatable, LocalizedError {
    case invalidField(String)
    case unsupportedProtocol(Int)
    case unsupportedCapability(String)

    public var errorDescription: String? {
        switch self {
        case .invalidField(let field): return "Invalid manifest field: \(field)."
        case .unsupportedProtocol(let version): return "Unsupported protocol version: \(version). Supported: 1 and 2."
        case .unsupportedCapability(let capability): return "Unsupported capability: \(capability)."
        }
    }
}
