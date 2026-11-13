import Darwin
import Foundation
import LedgeKit

/// Runs one protocol-2 add-on as a long-lived program and talks to it. See `SessionProtocol` for the exchange.
///
/// The add-on runs in a session of its own, so stopping it also stops anything it started. Ledge never
/// waits on it: output is read on threads of its own as it arrives, every request has a deadline, and a reply
/// that arrives after its deadline, or from an earlier session, is dropped. A program that crashes is started
/// again a limited number of times; after that the runtime reports it as failed and stays stopped.
public actor AddOnRuntime {
    public struct Limits: Sendable {
        /// Time for the program to answer `hello` and finish `ledge.activate`.
        public var handshake: TimeInterval = 5
        /// Default deadline for a request.
        public var request: TimeInterval = 10
        /// Time between asking the process group to stop and killing it.
        public var stopGrace: TimeInterval = 2
        /// Restarts after an unexpected exit, per `start()`.
        public var restarts: Int = 3
        /// Log lines forwarded per second; the rest are dropped.
        public var logLinesPerSecond: Int = 20
        public init() {}
    }

    public enum State: Sendable, Equatable {
        case stopped, starting, running
        case failed(String)
    }

    public enum Event: Sendable, Equatable {
        case log(level: SessionMessage.LogLevel, message: String)
        case update(topic: String, payload: JSONValue)
        /// The program exited without being asked to; `restarting` says whether the runtime is starting it again.
        case exited(status: Int32, restarting: Bool)
        case failed(String)
    }

    public let addOnID: String
    public private(set) var state: State = .stopped
    /// The running program's process id, which is also its process group.
    public private(set) var processID: pid_t?
    /// Counts sessions; a reply carries the generation it was sent in.
    public private(set) var generation = 0
    /// The last lines the program wrote to stderr, for the log and the Store's failure message.
    public var recentDiagnostics: [String] { diagnostics.lines }

    private let executable: URL
    private let arguments: [String]
    private let limits: Limits
    private let onEvent: @Sendable (Event) -> Void
    private let records: AddOnSessionRecords?
    /// Answers the add-on's own requests (LedgeKit's `LedgeHost`): method and params in, result out; a thrown
    /// error goes back as its description.
    public typealias ServiceHandler = @Sendable (_ method: String, _ params: JSONValue) async throws -> JSONValue
    private let services: ServiceHandler?
    private var callsInFlight = 0
    private var process: RunningProcess?
    private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]
    private var nextRequestID = 1
    private var restartsLeft = 0
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var stopping = false
    private var logWindow = (start: Date.distantPast, count: 0)
    private let diagnostics = DiagnosticsBuffer()

    /// `records` is where running sessions are noted for the next launch's sweep; nil keeps no notes.
    public init(addOnID: String, executable: URL, arguments: [String] = [], limits: Limits = Limits(),
                records: AddOnSessionRecords? = nil, onEvent: @escaping @Sendable (Event) -> Void = { _ in },
                services: ServiceHandler? = nil) {
        self.addOnID = addOnID
        self.records = records
        self.services = services
        self.executable = executable
        self.arguments = arguments
        self.limits = limits
        self.onEvent = onEvent
    }

    // MARK: Lifecycle

    /// Starts the program, completes the handshake and activates it. Throws if any of that fails, with the
    /// program stopped.
    public func start() async throws {
        guard state != .running, state != .starting else { return }
        restartsLeft = limits.restarts
        try await launch()
    }

    /// Asks the add-on to deactivate, ends the session and stops its process group. Safe to call at any time.
    public func stop() async {
        guard let process else { state = .stopped; return }
        stopping = true
        if state == .running {
            _ = try? await send(SessionProtocol.Method.deactivate, params: .null, timeout: min(limits.stopGrace, 1))
        }
        await terminate(process)
        stopping = false
        state = .stopped
    }

    /// Asks the add-on whether it can be removed now. A program that doesn't answer in time is treated as yes.
    public func prepareForRemoval() async -> Bool {
        guard state == .running,
              case .bool(let allowed)? = try? await send(SessionProtocol.Method.prepareForRemoval, params: .null, timeout: limits.handshake)
        else { return true }
        return allowed
    }

    // MARK: Requests

    /// Sends a request and waits for its reply, up to `timeout` (the limit's default when nil).
    public func request(_ method: String, params: JSONValue = .null, timeout: TimeInterval? = nil) async throws -> JSONValue {
        guard !method.hasPrefix("ledge.") else { throw AddOnRuntimeError.protocolViolation("Reserved method \(method).") }
        guard state == .running else { throw AddOnRuntimeError.notRunning }
        return try await send(method, params: params, timeout: timeout ?? limits.request)
    }

    /// Sends a surface event (`ledge.surfaceEvent`), the one reserved method the app sends during a session.
    public func sendEvent(_ params: JSONValue, timeout: TimeInterval? = nil) async throws -> JSONValue {
        guard state == .running else { throw AddOnRuntimeError.notRunning }
        return try await send(Surface.eventMethod, params: params, timeout: timeout ?? limits.request)
    }

    /// Asks a player action's state for a song, or sets it (`ledge.playerAction`). Nil when the add-on doesn't know.
    public func playerAction(_ request: PlayerActionRequest, timeout: TimeInterval? = nil) async throws -> Bool? {
        guard state == .running else { throw AddOnRuntimeError.notRunning }
        let result = try await send(Surface.playerActionMethod, params: JSONValue(encoding: request), timeout: timeout ?? limits.request)
        switch result {
        case .bool(let value): return value
        case .null: return nil
        default: throw AddOnRuntimeError.protocolViolation("A player action answered something other than true, false or null.")
        }
    }

    /// Tells the add-on where one of its live activities is now (`ledge.activityPlacement`).
    public func activityPlacement(_ change: ActivityPlacementChange) async throws {
        guard state == .running else { throw AddOnRuntimeError.notRunning }
        _ = try await send(Surface.activityPlacementMethod, params: JSONValue(encoding: change), timeout: limits.request)
    }

    /// Tells the add-on Ledge's environment changed (`ledge.environmentChanged`). Add-ons built with LedgeKit before
    /// 0.9.0 answer that they don't handle it, which is fine: they ask `environment()` when they need it.
    public func environmentChanged(_ environment: HostEnvironment) async throws {
        guard state == .running else { throw AddOnRuntimeError.notRunning }
        _ = try await send(SessionProtocol.Method.environmentChanged, params: JSONValue(encoding: environment), timeout: limits.request)
    }

    /// Tells the add-on which of its surfaces are on screen (`ledge.visibilityChanged`, LedgeKit 0.13.0).
    public func visibilityChanged(_ visibility: SurfaceVisibility) async throws {
        guard state == .running else { throw AddOnRuntimeError.notRunning }
        _ = try await send(SessionProtocol.Method.visibilityChanged, params: JSONValue(encoding: visibility), timeout: limits.request)
    }

    /// Sends one of Ledge's player requests (`ledge.playerMenu`, `ledge.playerQueue`) and decodes the answer.
    public func player<Result: Decodable & Sendable>(_ method: String, _ params: some Encodable & Sendable, as type: Result.Type,
                                                     timeout: TimeInterval? = nil) async throws -> Result {
        guard [Surface.playerMenuMethod, Surface.playerQueueMethod].contains(method) else {
            throw AddOnRuntimeError.protocolViolation("Not a player method: \(method).")
        }
        guard state == .running else { throw AddOnRuntimeError.notRunning }
        return try await send(method, params: JSONValue(encoding: params), timeout: timeout ?? limits.request).decode(Result.self)
    }

    /// `request` with your own `Codable` types.
    public func request<Params: Encodable & Sendable, Result: Decodable & Sendable>(
        _ method: String, _ params: Params, as type: Result.Type, timeout: TimeInterval? = nil
    ) async throws -> Result {
        try await request(method, params: JSONValue(encoding: params), timeout: timeout).decode(Result.self)
    }

    private func send(_ method: String, params: JSONValue, timeout: TimeInterval) async throws -> JSONValue {
        guard let process else { throw AddOnRuntimeError.notRunning }
        let id = nextRequestID
        nextRequestID += 1
        let line = try SessionMessage.request(id: id, method: method, params: params).encodedLine()
        let sentIn = generation
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            process.write(line)
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                await self?.expire(id, generation: sentIn)
            }
        }
    }

    private func expire(_ id: Int, generation: Int) {
        guard generation == self.generation, let continuation = pending.removeValue(forKey: id) else { return }
        continuation.resume(throwing: AddOnRuntimeError.timedOut)
    }

    // MARK: Process

    private func launch() async throws {
        state = .starting
        generation += 1
        let session = generation
        let spawned: RunningProcess
        do {
            spawned = try RunningProcess(executable: executable, arguments: arguments, diagnostics: diagnostics) { [weak self] input in
                Task { await self?.handle(input, generation: session) }
            }
        } catch {
            state = .failed("Couldn't start the add-on: \(error.localizedDescription)")
            throw AddOnRuntimeError.launchFailed(error.localizedDescription)
        }
        process = spawned
        processID = spawned.pid
        records?.record(addOnID: addOnID, pid: spawned.pid, executable: executable)
        do {
            try await handshake(spawned, generation: session)
            _ = try await send(SessionProtocol.Method.activate, params: .null, timeout: limits.handshake)
            guard session == generation else { throw AddOnRuntimeError.stopped }
            state = .running
        } catch {
            await terminate(spawned)
            let reason = (error as? AddOnRuntimeError) ?? .handshakeFailed(error.localizedDescription)
            state = .failed(reason.description)
            throw reason
        }
    }

    private func handshake(_ process: RunningProcess, generation session: Int) async throws {
        let hello = try SessionMessage.hello(protocolVersion: SessionProtocol.version, apiLevel: SessionProtocol.apiLevel,
                                             addOnID: addOnID, generation: session).encodedLine()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            readyContinuation = continuation
            process.write(hello)
            Task { [weak self, limits] in
                try? await Task.sleep(nanoseconds: UInt64(limits.handshake * 1_000_000_000))
                await self?.failHandshake(generation: session, "The add-on didn't answer in \(Int(limits.handshake)) seconds.")
            }
        }
    }

    private func failHandshake(generation session: Int, _ reason: String) {
        guard session == generation, let continuation = readyContinuation else { return }
        readyContinuation = nil
        continuation.resume(throwing: AddOnRuntimeError.handshakeFailed(reason))
    }

    /// Asks the process group to stop, then kills it if it hasn't after the grace period, and waits for the
    /// program's exit to be collected.
    private func terminate(_ target: RunningProcess) async {
        if process === target {
            process = nil
            processID = nil
        }
        failPending(AddOnRuntimeError.stopped)
        target.closeInput()
        target.signalGroup(SIGTERM)
        let deadline = Date().addingTimeInterval(limits.stopGrace)
        while !target.hasExited, Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        // Always kill the group: the program may be gone while something it started is still running.
        target.signalGroup(SIGKILL)
        while !target.hasExited { try? await Task.sleep(nanoseconds: 10_000_000) }
        records?.remove(pid: target.pid)
    }

    private func failPending(_ error: AddOnRuntimeError) {
        let waiting = pending
        pending.removeAll()
        waiting.values.forEach { $0.resume(throwing: error) }
        if let readyContinuation {
            self.readyContinuation = nil
            readyContinuation.resume(throwing: error)
        }
    }

    // MARK: Input

    private func handle(_ input: RunningProcess.Input, generation session: Int) async {
        // Anything from an earlier session is late, and dropped.
        guard session == generation else { return }
        switch input {
        case .line(let data):
            guard let message = try? JSONDecoder().decode(SessionMessage.self, from: data) else {
                await violation("The add-on sent a message Ledge can't read.")
                return
            }
            receive(message)
        case .tooLarge:
            await violation("The add-on sent a message larger than \(SessionProtocol.maximumMessageBytes / 1024) KB.")
        case .exited(let status):
            await exited(status: status)
        }
    }

    private func receive(_ message: SessionMessage) {
        switch message {
        case let .ready(version, _, id):
            guard let continuation = readyContinuation else { return }
            readyContinuation = nil
            if version == SessionProtocol.version, id == addOnID {
                continuation.resume()
            } else {
                continuation.resume(throwing: AddOnRuntimeError.handshakeFailed("The add-on answered as \(id), protocol \(version)."))
            }
        case let .response(id, result, error):
            guard let continuation = pending.removeValue(forKey: id) else { return }
            if let result { continuation.resume(returning: result) }
            else { continuation.resume(throwing: AddOnRuntimeError.addOnError(error ?? "")) }
        case let .log(level, text):
            let now = Date()
            if now.timeIntervalSince(logWindow.start) >= 1 { logWindow = (now, 0) }
            logWindow.count += 1
            if logWindow.count <= limits.logLinesPerSecond {
                onEvent(.log(level: level, message: String(text.prefix(4096))))
            } else if logWindow.count == limits.logLinesPerSecond + 1 {
                onEvent(.log(level: .info, message: "More log lines this second were dropped."))
            }
        case let .update(topic, payload):
            // Accepted from the handshake on: an add-on naturally sends its surfaces while it activates, before
            // Ledge marks the session running.
            guard state == .running || (state == .starting && readyContinuation == nil) else { return }
            onEvent(.update(topic: topic, payload: payload))
        case let .request(id, method, params):
            answer(id: id, method: method, params: params)
        case .hello:
            // Only Ledge sends this.
            break
        }
    }

    /// A request from the add-on to Ledge. Answered from the handshake on, at most 16 at a time.
    private func answer(id: Int, method: String, params: JSONValue) {
        guard let process, readyContinuation == nil, state != .stopped else { return }
        let session = generation
        func reply(_ message: SessionMessage) {
            if let line = try? message.encodedLine() { process.write(line) }
        }
        guard let services, method.hasPrefix("ledge.") else {
            reply(.response(id: id, result: nil, error: "Ledge has no service called \(method)."))
            return
        }
        guard callsInFlight < 16 else {
            reply(.response(id: id, result: nil, error: "Too many calls at once."))
            return
        }
        callsInFlight += 1
        Task {
            let message: SessionMessage
            do {
                message = .response(id: id, result: try await services(method, params), error: nil)
            } catch {
                message = .response(id: id, result: nil, error: String(describing: error))
            }
            self.finishCall(message, generation: session)
        }
    }

    private func finishCall(_ message: SessionMessage, generation session: Int) {
        callsInFlight -= 1
        // An answer for a session that has since ended has nobody to read it.
        guard session == generation, let process, let line = try? message.encodedLine() else { return }
        process.write(line)
    }

    private func violation(_ reason: String) async {
        guard let process else { return }
        onEvent(.log(level: .error, message: reason))
        await terminate(process)
        await recover(reason: reason, status: -1)
    }

    private func exited(status: Int32) async {
        guard let process, !stopping else { return }
        await terminate(process)
        await recover(reason: "The add-on quit unexpectedly (status \(status)).", status: status)
    }

    /// After an unexpected end: start again while restarts are left, otherwise report the add-on as failed.
    private func recover(reason: String, status: Int32) async {
        let wasRunning = state == .running
        guard wasRunning, restartsLeft > 0 else {
            if state != .starting {
                state = .failed(reason)
                onEvent(.failed(reason))
            }
            return
        }
        restartsLeft -= 1
        onEvent(.exited(status: status, restarting: true))
        do {
            try await launch()
        } catch {
            onEvent(.failed(state.failureReason ?? reason))
        }
    }
}

public enum AddOnRuntimeError: Error, Equatable, CustomStringConvertible {
    case launchFailed(String)
    case handshakeFailed(String)
    case notRunning
    case timedOut
    case stopped
    case addOnError(String)
    case protocolViolation(String)

    public var description: String {
        switch self {
        case .launchFailed(let reason): return "Couldn't start the add-on: \(reason)"
        case .handshakeFailed(let reason): return "The add-on didn't start: \(reason)"
        case .notRunning: return "The add-on isn't running."
        case .timedOut: return "The add-on didn't answer in time."
        case .stopped: return "The add-on stopped."
        case .addOnError(let message): return message
        case .protocolViolation(let reason): return reason
        }
    }
}

private extension AddOnRuntime.State {
    var failureReason: String? {
        if case .failed(let reason) = self { return reason }
        return nil
    }
}

/// The last 40 lines of stderr, at most 512 bytes each.
final class DiagnosticsBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []

    var lines: [String] { lock.withLock { stored } }

    func append(_ data: Data) {
        let text = String(decoding: data, as: UTF8.self)
        lock.withLock {
            for line in text.split(separator: "\n") where !line.isEmpty {
                stored.append(String(line.prefix(512)))
            }
            if stored.count > 40 { stored.removeFirst(stored.count - 40) }
        }
    }
}

/// A spawned program in a process group of its own, with its stdin, stdout and stderr on pipes. Output is read
/// on threads, so a program that writes faster than Ledge reads, or never stops writing, can't block Ledge.
final class RunningProcess: @unchecked Sendable {
    enum Input: Sendable {
        case line(Data)
        case tooLarge
        case exited(Int32)
    }

    let pid: pid_t
    private let inputFD: Int32
    private let writes = DispatchQueue(label: "app.ledge.addon.stdin")
    private let lock = NSLock()
    private var exited = false
    private var inputClosed = false

    var hasExited: Bool { lock.withLock { exited } }

    init(executable: URL, arguments: [String], diagnostics: DiagnosticsBuffer,
         deliver: @escaping @Sendable (Input) -> Void) throws {
        var stdinPipe: [Int32] = [0, 0], stdoutPipe: [Int32] = [0, 0], stderrPipe: [Int32] = [0, 0]
        guard pipe(&stdinPipe) == 0, pipe(&stdoutPipe) == 0, pipe(&stderrPipe) == 0 else { throw POSIXError(.EMFILE) }

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, stdinPipe[0], STDIN_FILENO)
        posix_spawn_file_actions_adddup2(&actions, stdoutPipe[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, stderrPipe[1], STDERR_FILENO)

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // A session of its own (which is also a process group), and none of Ledge's other file descriptors.
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT))

        // A minimal environment: nothing of Ledge's leaks in.
        let environment = [
            "PATH=/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME=\(NSHomeDirectory())",
            "TMPDIR=\(NSTemporaryDirectory())",
            "LANG=en_US.UTF-8"
        ]
        let argv = [executable.path] + arguments
        var spawned: pid_t = 0
        let result = withCStrings(argv) { argvPointers in
            withCStrings(environment) { envPointers in
                posix_spawn(&spawned, executable.path, &actions, &attributes, argvPointers, envPointers)
            }
        }
        for fd in [stdinPipe[0], stdoutPipe[1], stderrPipe[1]] { close(fd) }
        guard result == 0 else {
            for fd in [stdinPipe[1], stdoutPipe[0], stderrPipe[0]] { close(fd) }
            throw POSIXError(POSIXErrorCode(rawValue: result) ?? .EIO)
        }
        pid = spawned
        inputFD = stdinPipe[1]
        // Writing to a program that has quit returns an error instead of sending Ledge SIGPIPE.
        _ = fcntl(inputFD, F_SETNOSIGPIPE, 1)

        let stdoutFD = stdoutPipe[0], stderrFD = stderrPipe[0]
        Thread.detachNewThread {
            var reader = SessionFrameReader()
            var buffer = [UInt8](repeating: 0, count: 65_536)
            while true {
                let count = read(stdoutFD, &buffer, buffer.count)
                if count < 0, errno == EINTR { continue }
                if count <= 0 { break }
                do {
                    for line in try reader.feed(Data(buffer[0..<count])) { deliver(.line(line)) }
                } catch {
                    deliver(.tooLarge)
                    // Keep draining so the program never blocks on a full pipe before it's stopped.
                    while read(stdoutFD, &buffer, buffer.count) > 0 {}
                    break
                }
            }
            close(stdoutFD)
        }
        Thread.detachNewThread {
            var buffer = [UInt8](repeating: 0, count: 8_192)
            while true {
                let count = read(stderrFD, &buffer, buffer.count)
                if count < 0, errno == EINTR { continue }
                if count <= 0 { break }
                diagnostics.append(Data(buffer[0..<count]))
            }
            close(stderrFD)
        }
        Thread.detachNewThread { [weak self, spawned] in
            var status: Int32 = 0
            while waitpid(spawned, &status, 0) < 0, errno == EINTR {}
            self?.lock.withLock { self?.exited = true }
            // Exit code when it exited, otherwise the negated signal that ended it.
            let code = (status & 0x7f) == 0 ? (status >> 8) & 0xff : -(status & 0x7f)
            deliver(.exited(code))
        }
    }

    deinit {
        // Queued writes hold this object, so none are pending here; close directly rather than queueing a block
        // that would capture an object being destroyed.
        if !inputClosed { close(inputFD) }
    }

    func write(_ data: Data) {
        writes.async { [self] in
            guard !lock.withLock({ inputClosed }) else { return }
            data.withUnsafeBytes { raw in
                var offset = 0
                while offset < raw.count {
                    let written = Darwin.write(inputFD, raw.baseAddress! + offset, raw.count - offset)
                    if written < 0 { if errno == EINTR { continue }; return }
                    offset += written
                }
            }
        }
    }

    /// Closes stdin once every queued write has gone, which is how a session ends.
    func closeInput() {
        writes.async { [self] in
            let shouldClose = lock.withLock { () -> Bool in
                defer { inputClosed = true }
                return !inputClosed
            }
            if shouldClose { close(inputFD) }
        }
    }

    /// Signals the program and everything still in its session. Foundation's `Process` starts children in
    /// process groups of their own, so the group alone misses them; the session is kept unless a child calls
    /// `setsid` itself, which review looks for.
    func signalGroup(_ signal: Int32) {
        _ = killpg(pid, signal)
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        for candidate in pids.prefix(Int(max(filled, 0))) where candidate > 1 && getsid(candidate) == pid {
            _ = kill(candidate, signal)
        }
    }
}

private func withCStrings<Result>(_ strings: [String], _ body: ([UnsafeMutablePointer<CChar>?]) -> Result) -> Result {
    var pointers = strings.map { strdup($0) }
    pointers.append(nil)
    defer { pointers.forEach { free($0) } }
    return body(pointers)
}
