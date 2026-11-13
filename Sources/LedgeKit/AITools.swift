import Foundation

// Tools for AI apps (LedgeKit 0.16.0): actions an add-on offers to AI apps such as Claude, Cursor or Codex, through
// the MCP server Ledge runs. Nothing reaches an add-on until the person turns AI apps on in Ledge, allows the app, and
// turns the add-on's tools on. Declare `"ai-tool"` in the manifest's surfaces, send the list with
// `AddOnSession.show(tools:)`, and answer calls in `AddOnHandlers.onTool`.
//
// Arguments come from a model, which may have read them in a web page or a file. Ledge checks them against the
// tool's declared arguments before the add-on sees them, but treat them as untrusted all the same: never run or open
// anything an argument names without checking it.

extension Surface {
    /// Actions for AI apps the person allows. Needs 0.16.0.
    public static let aiTool = "ai-tool"
    public static let aiToolsTopic = "surface.ai-tools"
    /// Ledge asks the add-on to run one of its tools.
    public static let toolMethod = "ledge.tool"
    public static let maximumTools = 16
    public static let maximumToolArguments = 10
    /// A result larger than this is refused.
    public static let maximumToolResultBytes = 65_536
    /// A call that takes longer is cancelled, and the AI app is told it took too long.
    public static let toolTimeout: Double = 30
}

/// One action an AI app can ask the add-on for, like "add a note".
public struct AddOnTool: Codable, Sendable, Equatable {
    /// Lowercase, like `add_note`: a letter, then letters, digits or underscores, at most 32 characters.
    public var name: String
    /// What a person reads in Ledge, like "Add a note".
    public var title: String
    /// What the AI app reads to decide when to use it: what it does, what it takes, what it returns. One or two
    /// sentences, written for a reader who has never seen the add-on.
    public var summary: String
    public var arguments: [Argument]
    /// It deletes, overwrites or sends something that can't be taken back. Ledge asks the person before every call.
    public var destructive: Bool

    public init(_ name: String, title: String, summary: String, arguments: [Argument] = [], destructive: Bool = false) {
        self.name = name
        self.title = title
        self.summary = summary
        self.arguments = arguments
        self.destructive = destructive
    }

    public struct Argument: Codable, Sendable, Equatable {
        public var name: String
        public var summary: String
        public var kind: Kind
        public var required: Bool

        public init(_ name: String, summary: String, kind: Kind, required: Bool = true) {
            self.name = name
            self.summary = summary
            self.kind = kind
            self.required = required
        }
    }

    /// What an argument holds. Ledge refuses a call whose argument doesn't fit.
    public enum Kind: Codable, Sendable, Equatable {
        /// Text of at most `maximumLength` characters.
        case text(maximumLength: Int)
        /// A number, whole if `whole`, between the bounds when given.
        case number(minimum: Double?, maximum: Double?, whole: Bool)
        case boolean
        /// One of these.
        case choice([String])
    }

    private enum CodingKeys: String, CodingKey { case name, title, summary, arguments, destructive }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        title = try container.decode(String.self, forKey: .title)
        summary = try container.decode(String.self, forKey: .summary)
        arguments = try container.decodeIfPresent([Argument].self, forKey: .arguments) ?? []
        destructive = try container.decodeIfPresent(Bool.self, forKey: .destructive) ?? false
    }

    /// The JSON Schema an MCP client reads for this tool's arguments.
    public var inputSchema: JSONValue {
        var properties: [String: JSONValue] = [:]
        for argument in arguments {
            var property: [String: JSONValue] = ["description": .string(argument.summary)]
            switch argument.kind {
            case let .text(maximumLength):
                property["type"] = .string("string")
                property["maxLength"] = .number(Double(maximumLength))
            case let .number(minimum, maximum, whole):
                property["type"] = .string(whole ? "integer" : "number")
                if let minimum { property["minimum"] = .number(minimum) }
                if let maximum { property["maximum"] = .number(maximum) }
            case .boolean:
                property["type"] = .string("boolean")
            case let .choice(options):
                property["type"] = .string("string")
                property["enum"] = .array(options.map(JSONValue.string))
            }
            properties[argument.name] = .object(property)
        }
        return .object([
            "type": .string("object"),
            "properties": .object(properties),
            "required": .array(arguments.filter(\.required).map { .string($0.name) }),
            "additionalProperties": .bool(false),
        ])
    }

    /// Checks a call's arguments against this tool's, as Ledge does before the add-on sees them.
    public func check(_ given: JSONValue) throws -> [String: JSONValue] {
        let object: [String: JSONValue]
        switch given {
        case .null: object = [:]
        case .object(let value): object = value
        default: throw AddOnError("The arguments must be an object.")
        }
        let known = Dictionary(uniqueKeysWithValues: arguments.map { ($0.name, $0) })
        for key in object.keys.sorted() where known[key] == nil {
            throw AddOnError("\(name) takes no argument named \(key).")
        }
        for argument in arguments {
            guard let value = object[argument.name], value != .null else {
                if argument.required { throw AddOnError("\(name) needs \(argument.name).") }
                continue
            }
            switch (argument.kind, value) {
            case let (.text(maximumLength), .string(text)):
                guard text.count <= maximumLength else { throw AddOnError("\(argument.name) is longer than \(maximumLength) characters.") }
            case let (.number(minimum, maximum, whole), .number(number)):
                guard number.isFinite else { throw AddOnError("\(argument.name) must be a number.") }
                if whole, number.rounded() != number { throw AddOnError("\(argument.name) must be a whole number.") }
                if let minimum, number < minimum { throw AddOnError("\(argument.name) must be at least \(minimum.formatted()).") }
                if let maximum, number > maximum { throw AddOnError("\(argument.name) must be at most \(maximum.formatted()).") }
            case (.boolean, .bool):
                break
            case let (.choice(options), .string(choice)):
                guard options.contains(choice) else { throw AddOnError("\(argument.name) must be one of \(options.joined(separator: ", ")).") }
            default:
                throw AddOnError("\(argument.name) isn't the right kind of value.")
            }
        }
        return object
    }
}

/// A call from an AI app, with its arguments already checked against the tool's.
public struct ToolCall: Codable, Sendable, Equatable {
    public var tool: String
    public var arguments: [String: JSONValue]
    /// The AI app asking, as Ledge identified it, like "Claude".
    public var app: String?

    public init(tool: String, arguments: [String: JSONValue] = [:], app: String? = nil) {
        self.tool = tool
        self.arguments = arguments
        self.app = app
    }

    public func text(_ name: String) -> String? { if case .string(let value)? = arguments[name] { value } else { nil } }
    public func number(_ name: String) -> Double? { if case .number(let value)? = arguments[name] { value } else { nil } }
    public func boolean(_ name: String) -> Bool? { if case .bool(let value)? = arguments[name] { value } else { nil } }
}

/// What a tool returns to the AI app.
public enum ToolResult: Codable, Sendable, Equatable {
    /// Words the AI app reads.
    case text(String)
    /// Structured data, for an app that reads JSON.
    case json(JSONValue)

    private enum CodingKeys: String, CodingKey { case text, json }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let text = try container.decodeIfPresent(String.self, forKey: .text) {
            self = .text(text)
        } else {
            self = .json(try container.decode(JSONValue.self, forKey: .json))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text): try container.encode(text, forKey: .text)
        case .json(let value): try container.encode(value, forKey: .json)
        }
    }

    /// The checks Ledge runs before passing a result on.
    public func validate() throws {
        let size = (try? JSONEncoder().encode(self).count) ?? .max
        guard size <= Surface.maximumToolResultBytes else {
            throw SurfaceValidationError.tooLarge("a tool result over \(Surface.maximumToolResultBytes) bytes")
        }
    }
}

extension AddOnTool {
    /// The checks Ledge runs on an add-on's tools.
    public static func validate(_ tools: [AddOnTool]) throws {
        guard tools.count <= Surface.maximumTools else { throw SurfaceValidationError.tooLarge("more than \(Surface.maximumTools) tools") }
        var names = Set<String>()
        for tool in tools {
            guard isName(tool.name) else { throw SurfaceValidationError.invalid("tool name \(tool.name): a lowercase letter, then letters, digits or _, at most 32") }
            guard names.insert(tool.name).inserted else { throw SurfaceValidationError.duplicateID(tool.name) }
            guard !tool.title.isEmpty, tool.title.count <= 60 else { throw SurfaceValidationError.invalid("\(tool.name): a title of 1 to 60 characters") }
            guard !tool.summary.isEmpty, tool.summary.count <= 300 else { throw SurfaceValidationError.invalid("\(tool.name): a summary of 1 to 300 characters") }
            guard tool.arguments.count <= Surface.maximumToolArguments else {
                throw SurfaceValidationError.tooLarge("\(tool.name): more than \(Surface.maximumToolArguments) arguments")
            }
            var argumentNames = Set<String>()
            for argument in tool.arguments {
                guard isName(argument.name), argumentNames.insert(argument.name).inserted else {
                    throw SurfaceValidationError.invalid("\(tool.name): argument \(argument.name) must be a unique lowercase name")
                }
                guard !argument.summary.isEmpty, argument.summary.count <= 200 else {
                    throw SurfaceValidationError.invalid("\(tool.name).\(argument.name): a summary of 1 to 200 characters")
                }
                switch argument.kind {
                case let .text(maximumLength):
                    guard (1...20_000).contains(maximumLength) else { throw SurfaceValidationError.invalid("\(tool.name).\(argument.name): maximumLength from 1 to 20000") }
                case let .number(minimum, maximum, _):
                    if let minimum, let maximum, minimum > maximum { throw SurfaceValidationError.invalid("\(tool.name).\(argument.name): minimum above maximum") }
                case .boolean:
                    break
                case let .choice(options):
                    guard (1...20).contains(options.count), Set(options).count == options.count, options.allSatisfy({ (1...60).contains($0.count) }) else {
                        throw SurfaceValidationError.invalid("\(tool.name).\(argument.name): 1 to 20 different choices of up to 60 characters")
                    }
                }
            }
        }
    }

    private static func isName(_ name: String) -> Bool {
        guard let first = name.first, first.isASCII, first.isLowercase, (1...32).contains(name.count) else { return false }
        return name.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "_") }
    }
}
