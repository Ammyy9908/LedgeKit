import Foundation

/// Protocol version 2: a long-lived session between Ledge and an add-on's program.
///
/// Ledge starts the program once while the add-on is enabled and talks to it over stdin and stdout, one JSON
/// message per line (JSON escapes newlines inside strings, so a line is always one message). stderr is for the
/// add-on's own diagnostics; Ledge keeps the last lines of it for the log and never parses it.
///
/// The order is fixed:
/// 1. Ledge sends `hello`. The add-on answers `ready` with the same add-on id, or Ledge stops it.
/// 2. Ledge sends `request`s; the add-on answers each with a `response` carrying the same `id`, in any order.
///    The lifecycle is requests too: `ledge.activate` first, `ledge.deactivate` last, and
///    `ledge.prepareForRemoval`, whose `true` or `false` result lets the add-on refuse a removal.
/// 3. The add-on may send `log` lines and `update`s at any time after `ready`.
/// 4. Ledge closes stdin to end the session. The add-on exits; if it doesn't, Ledge stops its process group.
public enum SessionProtocol {
    public static let version = 2
    /// The LedgeKit API level this build speaks. Ledge refuses an add-on that needs a newer one.
    public static let apiLevel = "0.14.0"
    /// This LedgeKit's release, which add-ons pin in Package.swift. A patch release changes only this: add-ons'
    /// API, and so `kit.minAPI`, stay at ``apiLevel``, so an add-on built with it runs in every Ledge that has it.
    public static let release = "0.14.1"
    /// The longest message in either direction, newline excluded.
    public static let maximumMessageBytes = 1_048_576

    /// Reserved request methods. Methods starting `ledge.` are Ledge's; an add-on names its own anything else.
    public enum Method {
        public static let activate = "ledge.activate"
        public static let deactivate = "ledge.deactivate"
        public static let prepareForRemoval = "ledge.prepareForRemoval"
        /// Ledge's environment changed, such as light or dark; the params are the new `HostEnvironment`.
        public static let environmentChanged = "ledge.environmentChanged"
        /// Which of the add-on's surfaces someone can see changed; the params are the new `SurfaceVisibility`. 0.13.0.
        public static let visibilityChanged = "ledge.visibilityChanged"
    }
}

/// One message on a session, in either direction.
public enum SessionMessage: Codable, Sendable, Equatable {
    /// Ledge → add-on, first. `generation` counts the add-on's sessions since Ledge started.
    case hello(protocolVersion: Int, apiLevel: String, addOnID: String, generation: Int)
    /// Add-on → Ledge, in answer to `hello`.
    case ready(protocolVersion: Int, apiLevel: String, addOnID: String)
    /// Ledge → add-on.
    case request(id: Int, method: String, params: JSONValue)
    /// Add-on → Ledge: `result` or `error`, never both.
    case response(id: Int, result: JSONValue?, error: String?)
    /// Add-on → Ledge. Never log credentials or what the user typed.
    case log(level: LogLevel, message: String)
    /// Add-on → Ledge: state for a surface or service, by topic. Reserved for surfaces; Ledge ignores topics it
    /// doesn't know.
    case update(topic: String, payload: JSONValue)

    public enum LogLevel: String, Codable, Sendable { case debug, info, error }

    private enum Key: String, CodingKey {
        case type, protocolVersion, apiLevel, addOnID, generation, id, method, params, result, error, level, message, topic, payload
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        switch try c.decode(String.self, forKey: .type) {
        case "hello":
            self = .hello(protocolVersion: try c.decode(Int.self, forKey: .protocolVersion),
                          apiLevel: try c.decode(String.self, forKey: .apiLevel),
                          addOnID: try c.decode(String.self, forKey: .addOnID),
                          generation: try c.decode(Int.self, forKey: .generation))
        case "ready":
            self = .ready(protocolVersion: try c.decode(Int.self, forKey: .protocolVersion),
                          apiLevel: try c.decode(String.self, forKey: .apiLevel),
                          addOnID: try c.decode(String.self, forKey: .addOnID))
        case "request":
            self = .request(id: try c.decode(Int.self, forKey: .id), method: try c.decode(String.self, forKey: .method),
                            params: try c.decodeIfPresent(JSONValue.self, forKey: .params) ?? .null)
        case "response":
            // A result of JSON null is a result (an unset value, say); only a missing key means there's none.
            let result: JSONValue? = c.contains(.result)
                ? (try c.decodeNil(forKey: .result) ? .null : c.decode(JSONValue.self, forKey: .result)) : nil
            let error = try c.decodeIfPresent(String.self, forKey: .error)
            guard (result == nil) != (error == nil) else {
                throw DecodingError.dataCorruptedError(forKey: .error, in: c, debugDescription: "A response carries a result or an error.")
            }
            self = .response(id: try c.decode(Int.self, forKey: .id), result: result, error: error)
        case "log":
            self = .log(level: try c.decode(LogLevel.self, forKey: .level), message: try c.decode(String.self, forKey: .message))
        case "update":
            self = .update(topic: try c.decode(String.self, forKey: .topic), payload: try c.decodeIfPresent(JSONValue.self, forKey: .payload) ?? .null)
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown message type \(other).")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        switch self {
        case let .hello(version, api, id, generation):
            try c.encode("hello", forKey: .type); try c.encode(version, forKey: .protocolVersion)
            try c.encode(api, forKey: .apiLevel); try c.encode(id, forKey: .addOnID); try c.encode(generation, forKey: .generation)
        case let .ready(version, api, id):
            try c.encode("ready", forKey: .type); try c.encode(version, forKey: .protocolVersion)
            try c.encode(api, forKey: .apiLevel); try c.encode(id, forKey: .addOnID)
        case let .request(id, method, params):
            try c.encode("request", forKey: .type); try c.encode(id, forKey: .id)
            try c.encode(method, forKey: .method); try c.encode(params, forKey: .params)
        case let .response(id, result, error):
            try c.encode("response", forKey: .type); try c.encode(id, forKey: .id)
            try c.encodeIfPresent(result, forKey: .result); try c.encodeIfPresent(error, forKey: .error)
        case let .log(level, message):
            try c.encode("log", forKey: .type); try c.encode(level, forKey: .level); try c.encode(message, forKey: .message)
        case let .update(topic, payload):
            try c.encode("update", forKey: .type); try c.encode(topic, forKey: .topic); try c.encode(payload, forKey: .payload)
        }
    }

    /// The message as one line, newline included.
    public func encodedLine() throws -> Data {
        var data = try JSONEncoder().encode(self)
        guard data.count <= SessionProtocol.maximumMessageBytes else { throw SessionFramingError.messageTooLarge }
        data.append(0x0A)
        return data
    }
}

public enum SessionFramingError: Error, Equatable {
    case messageTooLarge
}

/// Splits a byte stream into messages, one per line, refusing any line longer than the limit before it has
/// been buffered in full.
public struct SessionFrameReader: Sendable {
    private var buffer = Data()
    private let limit: Int

    public init(limit: Int = SessionProtocol.maximumMessageBytes) {
        self.limit = limit
    }

    /// Adds bytes and returns every complete line, empty lines skipped.
    public mutating func feed(_ bytes: Data) throws -> [Data] {
        buffer.append(bytes)
        var lines: [Data] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            guard line.count <= limit else { throw SessionFramingError.messageTooLarge }
            if !line.isEmpty { lines.append(Data(line)) }
            buffer.removeSubrange(buffer.startIndex...newline)
        }
        guard buffer.count <= limit else { throw SessionFramingError.messageTooLarge }
        return lines
    }
}
