import Foundation

/// Services Ledge offers a running add-on (protocol 2). Each call is a request from the add-on to Ledge, the
/// reverse of the requests Ledge sends; Ledge answers it, or refuses with a reason.
///
/// Stored settings and the environment need nothing. The rest need a capability the user granted:
/// `clipboard-write` for `copy(_:)`, `hud` for `notify(title:message:symbol:)`. A refused call throws
/// `LedgeHostError`, so handle it: a capability can be off.
public enum LedgeHost {
    /// Request methods, from the add-on to Ledge.
    public enum Method {
        public static let settingsGet = "ledge.settings.get"
        public static let settingsSet = "ledge.settings.set"
        public static let settingsRemove = "ledge.settings.remove"
        public static let environment = "ledge.environment"
        public static let open = "ledge.open"
        public static let copy = "ledge.copy"
        public static let notify = "ledge.notify"
        public static let account = "ledge.account"
        public static let http = "ledge.http"
        public static let dataFolder = "ledge.dataFolder"
        public static let showPage = "ledge.showPage"
        public static let openSettings = "ledge.openSettings"
        public static let holdOpen = "ledge.holdOpen"
    }

    /// The longest Ledge takes to answer a call before it throws.
    public static let timeout: TimeInterval = 10

    // MARK: Stored settings

    /// A value stored for this add-on, kept across restarts, updates and reinstalls. Nil when unset.
    public static func value(forKey key: String) async throws -> JSONValue? {
        let result = try await call(Method.settingsGet, ["key": .string(key)])
        return result == .null ? nil : result
    }

    public static func value<Value: Decodable>(_ type: Value.Type, forKey key: String) async throws -> Value? {
        try await value(forKey: key)?.decode(type)
    }

    /// Stores a value for this add-on. Keys are up to 128 characters; all values together up to 256 KB.
    public static func set<Value: Encodable>(_ value: Value, forKey key: String) async throws {
        _ = try await call(Method.settingsSet, ["key": .string(key), "value": try JSONValue(encoding: value)])
    }

    public static func removeValue(forKey key: String) async throws {
        _ = try await call(Method.settingsRemove, ["key": .string(key)])
    }

    // MARK: Environment

    public static func environment() async throws -> HostEnvironment {
        try await call(Method.environment, [:]).decode(HostEnvironment.self)
    }

    // MARK: Files

    /// A folder of the add-on's own for files it keeps, such as documents or a cache: created when first asked for,
    /// kept through updates and reinstalls, and deleted only when the user removes the add-on and asks for its data
    /// to go too. Nothing else writes there. Needs 0.13.0.
    public static func dataFolder() async throws -> URL {
        guard case .string(let path) = try await call(Method.dataFolder, [:]), path.hasPrefix("/") else {
            throw LedgeHostError("Ledge didn't say where the data folder is.")
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    // MARK: The notch and Settings

    /// Opens the notch on the add-on's page. Ledge allows it within two seconds of the user using one of the
    /// add-on's controls, or while one of its activities is `.attention`, so a page can't pop open on a timer.
    /// Refused while the notch is hidden, such as over a full-screen app, or while the user types in another page.
    /// Needs the `notch-control` capability and the `notch-page` surface. Needs 0.13.0.
    public static func showPage() async throws {
        _ = try await call(Method.showPage, [:])
    }

    /// Opens Ledge's Settings on the add-on's page, for a "Set up" button in an empty state. Allowed within two
    /// seconds of the user using one of the add-on's controls. Needs 0.13.0.
    public static func openSettings() async throws {
        _ = try await call(Method.openSettings, [:])
    }

    /// Keeps the open notch from closing when the pointer leaves, while something the user watches runs: a
    /// countdown, a teleprompter. It counts only while the add-on's page is the tab showing, a click elsewhere still
    /// closes the notch, and Ledge lets go when the add-on stops. Release it the moment the work ends.
    /// Needs the `notch-control` capability. Needs 0.13.0.
    public static func holdOpen(_ on: Bool) async throws {
        _ = try await call(Method.holdOpen, ["on": .bool(on)])
    }

    // MARK: Actions

    /// Opens a web or mail link (`https`, `http`, `mailto`) in the user's default app.
    public static func open(_ url: URL) async throws {
        _ = try await call(Method.open, ["url": .string(url.absoluteString)])
    }

    /// Puts text on the clipboard. Needs the `clipboard-write` capability.
    public static func copy(_ text: String) async throws {
        _ = try await call(Method.copy, ["text": .string(text)])
    }

    /// Shows a short message in the notch. Needs the `hud` capability.
    public static func notify(title: String, message: String? = nil, symbol: String? = nil) async throws {
        var params: [String: JSONValue] = ["title": .string(title)]
        if let message { params["message"] = .string(message) }
        if let symbol { params["symbol"] = .string(symbol) }
        _ = try await call(Method.notify, params)
    }

    // MARK: Accounts

    /// Whether the user has connected an account Ledge manages, such as "spotify". Ledge does the sign-in and keeps
    /// the credentials; an add-on never sees them.
    public static func account(_ provider: String) async throws -> HostAccount {
        try await call(Method.account, ["provider": .string(provider)]).decode(HostAccount.self)
    }

    /// Asks Ledge to call a provider's API with the user's account. Ledge adds the credentials, and only allows the
    /// endpoints it lists for the capability the add-on was granted (for "spotify", `spotify-library`: the
    /// library's contains, save and remove endpoints). The answer has the status and the body, never headers.
    public static func request(provider: String, method: String, path: String,
                               query: [String: String] = [:], body: JSONValue? = nil) async throws -> HostResponse {
        var params: [String: JSONValue] = ["provider": .string(provider), "method": .string(method), "path": .string(path),
                                           "query": .object(query.mapValues { .string($0) })]
        if let body { params["body"] = body }
        return try await call(Method.http, params).decode(HostResponse.self)
    }

    static func call(_ method: String, _ params: [String: JSONValue]) async throws -> JSONValue {
        guard let calls = HostCalls.current else { throw LedgeHostError("Not running in a Ledge session.") }
        return try await calls.call(method, params: .object(params), timeout: timeout)
    }
}

/// What a running add-on can know about the Ledge it runs in.
public struct HostEnvironment: Codable, Sendable, Equatable {
    public let ledgeVersion: String
    public let apiLevel: String
    /// "light" or "dark".
    public let appearance: String
    /// The accent colour as "#RRGGBB".
    public let accentColor: String
    /// Whether the main display has a camera notch, rather than the floating island.
    public let hasNotch: Bool

    public init(ledgeVersion: String, apiLevel: String, appearance: String, accentColor: String, hasNotch: Bool) {
        self.ledgeVersion = ledgeVersion
        self.apiLevel = apiLevel
        self.appearance = appearance
        self.accentColor = accentColor
        self.hasNotch = hasNotch
    }
}

/// Which of an add-on's surfaces someone can see right now, sent to `AddOnHandlers.onVisibilityChange` whenever it
/// changes. A surface counts while it's on screen: the notch page while its tab is open, widgets while the Widgets
/// page is open, the settings page while it's shown in Settings, and menu bar tiles while the panel is open.
/// Live activities, lock screen pills and the player aren't listed: they're up while you send them.
public struct SurfaceVisibility: Codable, Sendable, Equatable {
    /// Surface names from `Surface`, such as `Surface.notchPage`.
    public var visible: Set<String>

    public init(visible: Set<String> = []) {
        self.visible = visible
    }

    public func isVisible(_ surface: String) -> Bool { visible.contains(surface) }

    /// True while anything of the add-on's is on screen.
    public var isAnythingVisible: Bool { !visible.isEmpty }
}

public struct HostAccount: Codable, Sendable, Equatable {
    public let connected: Bool
    /// The account's display name, when connected.
    public let name: String?
    public init(connected: Bool, name: String?) {
        self.connected = connected
        self.name = name
    }
}

public struct HostResponse: Codable, Sendable, Equatable {
    public let status: Int
    /// The response body: JSON when it parses as JSON, otherwise text; nil when empty.
    public let body: JSONValue?
    public init(status: Int, body: JSONValue?) {
        self.status = status
        self.body = body
    }
}

/// Ledge refused a service call, or didn't answer.
public struct LedgeHostError: Error, Equatable, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

/// Calls from the add-on to Ledge that are waiting for an answer, by id. One per session: handlers reach the
/// session they run in through the task-local `current`.
actor HostCalls {
    @TaskLocal static var current: HostCalls?

    private var writer: (@Sendable (Data) async -> Void)?
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]

    init(writer: @escaping @Sendable (Data) async -> Void) {
        self.writer = writer
    }

    func call(_ method: String, params: JSONValue, timeout: TimeInterval) async throws -> JSONValue {
        guard let writer else { throw LedgeHostError("Not running in a Ledge session.") }
        let id = nextID
        nextID += 1
        let line = try SessionMessage.request(id: id, method: method, params: params).encodedLine()
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            Task {
                await writer(line)
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self.resolve(id, result: nil, error: "Ledge didn't answer in time.")
            }
        }
    }

    func resolve(_ id: Int, result: JSONValue?, error: String?) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        if let result { continuation.resume(returning: result) }
        else { continuation.resume(throwing: LedgeHostError(error ?? "Ledge refused the call.")) }
    }

    /// The session ended: nothing more will be answered.
    func endSession() {
        let waiting = pending
        pending.removeAll()
        writer = nil
        waiting.values.forEach { $0.resume(throwing: LedgeHostError("The session ended.")) }
    }
}
