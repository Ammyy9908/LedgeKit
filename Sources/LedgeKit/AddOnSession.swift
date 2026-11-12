import Foundation

/// What an add-on does in a session: its lifecycle hooks and one handler per request method.
///
/// ```swift
/// var handlers = AddOnHandlers()
/// handlers.on("banner") { (request: NotificationBannerRequest) in
///     NotificationBannerResponse(request: request)
/// }
/// exit(await AddOnSession.run(id: "notifications", handlers: handlers))
/// ```
public struct AddOnHandlers: Sendable {
    /// Runs once, after the handshake and before any other request. Start timers and observers here.
    /// Throwing ends the session and Ledge shows the add-on as failed.
    public var activate: @Sendable () async throws -> Void = {}
    /// Runs once, when the user turns the add-on off or Ledge quits. Stop everything `activate` started.
    public var deactivate: @Sendable () async -> Void = {}
    /// Return `false` to refuse a removal that would lose something, such as a transfer in flight.
    public var prepareForRemoval: @Sendable () async -> Bool = { true }
    /// The user acted on a control in one of the add-on's surfaces. Events arrive in order, one at a time.
    public var onEvent: @Sendable (SurfaceEvent) async -> Void = { _ in }
    /// Ledge asks a player action's state for a song, or the user pressed it. Return the state after it, or nil
    /// when it isn't known. Requests run side by side, like other methods. Throw `AddOnError` to say why it failed.
    public var onPlayerAction: @Sendable (PlayerActionRequest) async throws -> Bool? = { _ in nil }

    var methods: [String: @Sendable (JSONValue) async throws -> JSONValue] = [:]

    public init() {}

    /// The handler for a request method: the player action handler for Ledge's player requests, else the add-on's own.
    func handler(for method: String) -> (@Sendable (JSONValue) async throws -> JSONValue)? {
        guard method == Surface.playerActionMethod else { return methods[method] }
        let onPlayerAction = self.onPlayerAction
        return { params in
            guard let state = try await onPlayerAction(try params.decode(PlayerActionRequest.self)) else { return .null }
            return .bool(state)
        }
    }

    /// Handles one request method with your own `Codable` types. Methods starting `ledge.` are reserved.
    public mutating func on<Request: Decodable & Sendable, Response: Encodable & Sendable>(
        _ method: String, _ handler: @escaping @Sendable (Request) async throws -> Response
    ) {
        precondition(!method.hasPrefix("ledge."), "Methods starting ledge. are reserved for Ledge.")
        methods[method] = { params in try JSONValue(encoding: try await handler(try params.decode(Request.self))) }
    }
}

/// An error whose message is safe to show to the user. Any other error a handler throws reaches Ledge as a
/// generic failure, because error text can carry credentials or a provider's response body.
public struct AddOnError: Error, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
}

/// The add-on's side of a protocol-2 session. See `SessionProtocol` for the exchange.
public enum AddOnSession {
    /// Exit status for a session that ended because Ledge broke the protocol, or sent another add-on's id.
    public static let protocolFailure: Int32 = 65

    /// Runs the session on stdin and stdout until Ledge closes stdin, and returns the exit status for `exit`.
    public static func run(id: String, handlers: AddOnHandlers) async -> Int32 {
        let output = StandardOutput()
        current = output
        return await run(id: id, handlers: handlers, input: standardInputLines(), write: { await output.write($0) })
    }

    /// Writes a line to Ledge's log, tagged with the add-on's id. Never log credentials or what the user typed.
    public static func log(_ message: String, level: SessionMessage.LogLevel = .info) {
        guard let current else { return }
        Task { await current.send(.log(level: level, message: String(message.prefix(4096)))) }
    }

    /// Shows the add-on's settings page, replacing the last one sent. Needs `"settings-page"` in `surfaces`.
    public static func show(_ page: SettingsPage) {
        guard let payload = try? JSONValue(encoding: page) else { return }
        update(topic: Surface.settingsTopic, payload: payload)
    }

    /// Shows the add-on's widgets, replacing the last ones sent. Needs `"widget"` in `surfaces`.
    public static func show(widgets: [Widget]) {
        guard let payload = try? JSONValue(encoding: widgets) else { return }
        update(topic: Surface.widgetsTopic, payload: payload)
    }

    /// Shows the add-on's buttons in Ledge's players. The manifest must declare `player-action`.
    public static func show(playerActions: [PlayerAction]) {
        guard let payload = try? JSONValue(encoding: playerActions) else { return }
        update(topic: Surface.playerActionsTopic, payload: payload)
    }

    /// Sends state for a surface or service by topic. `show(_:)` and `show(widgets:)` cover the surfaces.
    public static func update(topic: String, payload: JSONValue) {
        guard let current else { return }
        Task { await current.send(.update(topic: topic, payload: payload)) }
    }

    nonisolated(unsafe) private static var current: StandardOutput?

    /// The session loop, with its input and output passed in so it can be tested without a process.
    public static func run(
        id: String, handlers: AddOnHandlers,
        input: AsyncThrowingStream<Data, Error>, write: @escaping @Sendable (Data) async -> Void
    ) async -> Int32 {
        let calls = HostCalls(writer: write)
        let status = await HostCalls.$current.withValue(calls) {
            await loop(id: id, handlers: handlers, input: input, write: write, calls: calls)
        }
        await calls.endSession()
        return status
    }

    private static func loop(
        id: String, handlers: AddOnHandlers, input: AsyncThrowingStream<Data, Error>,
        write: @escaping @Sendable (Data) async -> Void, calls: HostCalls
    ) async -> Int32 {
        func send(_ message: SessionMessage) async {
            if let line = try? message.encodedLine() { await write(line) }
        }
        // Calls the add-on makes to Ledge (LedgeHost) go out on the same output. Ledge's answers to them are taken
        // off the input as they arrive, so a handler waiting on one (in activate, say) never blocks the loop that
        // reads it.
        let (messages, forward) = AsyncThrowingStream<Data, Error>.makeStream()
        let pump = Task {
            do {
                for try await line in input {
                    if case let .response(id, result, error)? = try? JSONDecoder().decode(SessionMessage.self, from: line) {
                        await calls.resolve(id, result: result, error: error)
                    } else {
                        forward.yield(line)
                    }
                }
                forward.finish()
            } catch {
                forward.finish(throwing: error)
            }
        }
        defer { pump.cancel() }
        var greeted = false
        var active = false
        var running: [Task<Void, Never>] = []
        defer { running.forEach { $0.cancel() } }
        do {
            for try await line in messages {
                guard let message = try? JSONDecoder().decode(SessionMessage.self, from: line) else {
                    await send(.log(level: .error, message: "Ledge sent a message this add-on can't read; ending the session."))
                    return protocolFailure
                }
                if !greeted {
                    guard case let .hello(version, _, addOnID, _) = message, version == SessionProtocol.version, addOnID == id else {
                        return protocolFailure
                    }
                    greeted = true
                    await send(.ready(protocolVersion: SessionProtocol.version, apiLevel: SessionProtocol.apiLevel, addOnID: id))
                    continue
                }
                guard case let .request(requestID, method, params) = message else { continue }
                switch method {
                // Lifecycle requests run in order, before anything sent after them.
                case SessionProtocol.Method.activate:
                    do {
                        try await handlers.activate()
                        active = true
                        await send(.response(id: requestID, result: .bool(true), error: nil))
                    } catch {
                        await send(.response(id: requestID, result: nil, error: safeMessage(for: error)))
                        return 1
                    }
                case SessionProtocol.Method.deactivate:
                    if active { await handlers.deactivate(); active = false }
                    await send(.response(id: requestID, result: .bool(true), error: nil))
                case SessionProtocol.Method.prepareForRemoval:
                    await send(.response(id: requestID, result: .bool(await handlers.prepareForRemoval()), error: nil))
                case Surface.eventMethod:
                    // Events run in order, before anything sent after them.
                    guard active, let event = try? params.decode(SurfaceEvent.self) else {
                        await send(.response(id: requestID, result: nil, error: "The add-on couldn't read the event."))
                        continue
                    }
                    await handlers.onEvent(event)
                    await send(.response(id: requestID, result: .bool(true), error: nil))
                default:
                    guard active, let handler = handlers.handler(for: method) else {
                        await send(.response(id: requestID, result: nil,
                                             error: active ? "This add-on doesn't handle \(method)." : "The add-on isn't active."))
                        continue
                    }
                    // Requests run side by side; each answers with its own id when it finishes.
                    running.removeAll { $0.isCancelled }
                    running.append(Task {
                        do {
                            let result = try await handler(params)
                            await send(.response(id: requestID, result: result, error: nil))
                        } catch {
                            await send(.response(id: requestID, result: nil, error: safeMessage(for: error)))
                        }
                    })
                }
            }
        } catch {
            if active { await handlers.deactivate() }
            return protocolFailure
        }
        // Ledge closed stdin: the session is over.
        if active { await handlers.deactivate() }
        return 0
    }

    private static func safeMessage(for error: Error) -> String {
        (error as? AddOnError)?.message ?? "Add-on could not complete the request."
    }

    /// Lines from stdin, read on a thread of their own so a blocked read never holds up the session's tasks.
    private static func standardInputLines() -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let thread = Thread {
                var reader = SessionFrameReader()
                while true {
                    let chunk = FileHandle.standardInput.availableData
                    if chunk.isEmpty { continuation.finish(); return }
                    do {
                        for line in try reader.feed(chunk) { continuation.yield(line) }
                    } catch {
                        continuation.finish(throwing: error)
                        return
                    }
                }
            }
            thread.start()
        }
    }
}

/// Serialises writes to stdout, so two responses finishing together never interleave on one line.
private actor StandardOutput {
    func write(_ data: Data) {
        try? FileHandle.standardOutput.write(contentsOf: data)
    }

    func send(_ message: SessionMessage) {
        if let line = try? message.encodedLine() { write(line) }
    }
}
