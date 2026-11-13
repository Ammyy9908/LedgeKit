import Foundation

/// Metadata for an executable package: protocol 1 runs the program once per request, protocol 2 keeps a
/// session open.
///
/// Manifest v2 (LedgeKit 0.4.0) adds optional fields: `surfaces`, `kit`, `minLedge`, `minMacOS`, `category`,
/// `creator`, `source` and `keywords`. All are optional, so a v1 manifest still decodes and validates.
public struct AddOnManifest: Codable, Sendable, Equatable {
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

    // Manifest v2.
    /// Surfaces the add-on provides, such as a settings page or a widget. Ledge mounts only surfaces it supports
    /// and the add-on declares.
    public let surfaces: [String]?
    /// The oldest LedgeKit API level the add-on needs.
    public let kit: Kit?
    /// The oldest Ledge that runs it, for example "0.2.0".
    public let minLedge: String?
    /// The oldest macOS that runs it, for example "14.0", when it needs more than Ledge does.
    public let minMacOS: String?
    /// The Store section it belongs in: AI, Productivity, Media, Capture, Files or System.
    public let category: String?
    public let creator: Creator?
    public let source: Source?
    /// Search words beyond the name and summary.
    public let keywords: [String]?

    public struct Kit: Codable, Sendable, Equatable {
        public let minAPI: String
        public init(minAPI: String) { self.minAPI = minAPI }
    }

    public struct Creator: Codable, Sendable, Equatable {
        public let name: String
        public let url: String?
        public let avatar: String?
        public init(name: String, url: String? = nil, avatar: String? = nil) {
            self.name = name
            self.url = url
            self.avatar = avatar
        }
    }

    public struct Source: Codable, Sendable, Equatable {
        public let repository: String?
        /// An SPDX identifier such as "MIT", or "SEE LICENSE" for the add-on's own LICENSE file.
        public let license: String?
        public init(repository: String? = nil, license: String? = nil) {
            self.repository = repository
            self.license = license
        }
    }

    /// Creates metadata. Call validate before writing or installing it.
    public init(id: String, version: String, protocolVersion: Int = 1,
                name: String, summary: String, description: String, author: String,
                capabilities: [String], icon: String? = nil, executable: String,
                surfaces: [String]? = nil, kit: Kit? = nil, minLedge: String? = nil, minMacOS: String? = nil,
                category: String? = nil, creator: Creator? = nil, source: Source? = nil, keywords: [String]? = nil) {
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
        self.surfaces = surfaces
        self.kit = kit
        self.minLedge = minLedge
        self.minMacOS = minMacOS
        self.category = category
        self.creator = creator
        self.source = source
        self.keywords = keywords
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
        // Capabilities are open: any well-formed name validates, and the host grants only those it knows and the
        // user approved. A package built for a newer Ledge still loads; what this Ledge lacks just isn't granted.
        for capability in capabilities where !AddOnCapability.isWellFormed(capability) {
            throw ManifestValidationError.unsupportedCapability(capability)
        }
        for surface in surfaces ?? [] where !AddOnCapability.isWellFormed(surface) {
            throw ManifestValidationError.invalidField("surfaces")
        }
        for (field, value) in [("kit.minAPI", kit?.minAPI), ("minLedge", minLedge)] {
            if let value, !Self.isReleaseVersion(value) { throw ManifestValidationError.invalidField(field) }
        }
        if let minMacOS, Self.versionParts(minMacOS) == nil { throw ManifestValidationError.invalidField("minMacOS") }
        if let creator, creator.name.trimmingCharacters(in: .whitespaces).isEmpty {
            throw ManifestValidationError.invalidField("creator.name")
        }
        if let keywords, keywords.count > 20 || keywords.contains(where: { $0.count > 40 }) {
            throw ManifestValidationError.invalidField("keywords")
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

extension AddOnManifest {
    /// Why this host can't run an add-on, or nil when it can.
    public enum Incompatibility: Error, Equatable, CustomStringConvertible {
        case needsNewerKit(String)
        case needsNewerLedge(String)
        case needsNewerMacOS(String)
        case unsupportedProtocol(Int)

        public var description: String {
            switch self {
            case .needsNewerKit(let level): return "Needs a Ledge that supports LedgeKit \(level)."
            case .needsNewerLedge(let version): return "Needs Ledge \(version) or later."
            case .needsNewerMacOS(let version): return "Needs macOS \(version) or later."
            case .unsupportedProtocol(let version): return "Uses add-on protocol \(version), which this Ledge doesn't support."
            }
        }
    }

    /// Checks the manifest's requirements against a host. `apiLevel` is the LedgeKit API the host was built with.
    public func incompatibility(ledgeVersion: String, apiLevel: String = SessionProtocol.apiLevel,
                                macOS: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) -> Incompatibility? {
        guard [1, SessionProtocol.version].contains(protocolVersion) else { return .unsupportedProtocol(protocolVersion) }
        if let minAPI = kit?.minAPI, Self.compare(minAPI, apiLevel) == .orderedDescending { return .needsNewerKit(minAPI) }
        if let minLedge, Self.compare(minLedge, ledgeVersion) == .orderedDescending { return .needsNewerLedge(minLedge) }
        if let minMacOS {
            let host = "\(macOS.majorVersion).\(macOS.minorVersion).\(macOS.patchVersion)"
            if Self.compare(minMacOS, host) == .orderedDescending { return .needsNewerMacOS(minMacOS) }
        }
        return nil
    }

    /// Numeric dotted versions compared part by part; missing parts count as zero.
    public static func compare(_ left: String, _ right: String) -> ComparisonResult {
        let a = versionParts(left) ?? [], b = versionParts(right) ?? []
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0, y = index < b.count ? b[index] : 0
            if x != y { return x < y ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    static func isReleaseVersion(_ text: String) -> Bool {
        (versionParts(text)?.count ?? 0) == 3
    }

    static func versionParts(_ text: String) -> [Int]? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }) else { return nil }
        return parts.compactMap { Int($0) }
    }
}

/// Capability and surface names: lowercase letters, digits and hyphens. Hosts publish which ones they grant.
public enum AddOnCapability {
    /// Capabilities this LedgeKit release documents. Not exhaustive at runtime: a newer package may name one a host
    /// has never heard of, which loads and is treated as not granted.
    public static let known: Set<String> = ["spotify-library", "notification-banners", "apple-music-queue", "apple-music-controls",
                                            "clipboard-write", "hud", "notch-control"]

    public static func isWellFormed(_ name: String) -> Bool {
        (1...64).contains(name.count) && name.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-") }
            && name.first != "-"
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
        case .unsupportedCapability(let capability): return "Malformed capability name: \(capability)."
        }
    }
}
