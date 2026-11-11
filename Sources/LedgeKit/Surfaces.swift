import Foundation

/// What an add-on can put on screen, described as data. Ledge draws every surface with its own views, so an
/// add-on looks like the rest of Ledge and can't draw outside the space it's given.
///
/// A session add-on declares the surfaces it provides in `addon.json` (`"surfaces": ["settings-page", "widget"]`),
/// then sends them whenever they change with `AddOnSession.show(_:)`. Each send replaces the last; Ledge keeps
/// controls that keep their id, so a field being edited isn't reset. When the user acts on a control, Ledge sends
/// a `SurfaceEvent` to `AddOnHandlers.onEvent`. Ledge draws only surfaces the manifest declares.
public enum Surface {
    public static let settingsPage = "settings-page"
    public static let widget = "widget"

    /// Update topics an add-on sends surfaces on.
    public static let settingsTopic = "surface.settings-page"
    public static let widgetsTopic = "surface.widgets"
    /// The request Ledge sends when the user acts on a control.
    public static let eventMethod = "ledge.surfaceEvent"

    /// Limits Ledge enforces before drawing anything.
    public static let maximumRows = 200
    public static let maximumWidgets = 8
    public static let maximumNodes = 100
    public static let maximumDepth = 6
    public static let maximumText = 1000
}

// MARK: Settings page

/// The add-on's settings page: sections of rows, drawn in Ledge's own cards under the add-on's header.
public struct SettingsPage: Codable, Sendable, Equatable {
    public var sections: [SettingsSection]
    public init(_ sections: [SettingsSection]) { self.sections = sections }
}

public struct SettingsSection: Codable, Sendable, Equatable {
    public var id: String
    public var title: String?
    /// A grey note under the card.
    public var footer: String?
    public var rows: [SettingsRow]
    public init(_ id: String, title: String? = nil, footer: String? = nil, rows: [SettingsRow]) {
        self.id = id
        self.title = title
        self.footer = footer
        self.rows = rows
    }
}

public struct SettingsRow: Codable, Sendable, Equatable {
    /// Stable within the page; events name the row by it.
    public var id: String
    public var title: String
    /// A grey line under the title.
    public var detail: String?
    public var control: Control

    public init(_ id: String, title: String, detail: String? = nil, control: Control) {
        self.id = id
        self.title = title
        self.detail = detail
        self.control = control
    }

    public enum Control: Codable, Sendable, Equatable {
        case toggle(isOn: Bool)
        case picker(options: [Option], selected: String)
        case slider(minimum: Double, maximum: Double, step: Double?, value: Double, unit: String?)
        case textField(text: String, placeholder: String?)
        case button(destructive: Bool)
        case link(url: String)
        /// Read-only text on the right.
        case value(text: String)
        /// The row's title as a paragraph, no control.
        case note
    }

    public struct Option: Codable, Sendable, Equatable {
        public var id: String
        public var title: String
        public init(_ id: String, _ title: String) {
            self.id = id
            self.title = title
        }
    }

    public static func toggle(_ id: String, _ title: String, detail: String? = nil, isOn: Bool) -> SettingsRow {
        SettingsRow(id, title: title, detail: detail, control: .toggle(isOn: isOn))
    }
    public static func picker(_ id: String, _ title: String, detail: String? = nil, options: [Option], selected: String) -> SettingsRow {
        SettingsRow(id, title: title, detail: detail, control: .picker(options: options, selected: selected))
    }
    public static func slider(_ id: String, _ title: String, detail: String? = nil, range: ClosedRange<Double>,
                              step: Double? = nil, value: Double, unit: String? = nil) -> SettingsRow {
        SettingsRow(id, title: title, detail: detail,
                    control: .slider(minimum: range.lowerBound, maximum: range.upperBound, step: step, value: value, unit: unit))
    }
    public static func textField(_ id: String, _ title: String, detail: String? = nil, text: String, placeholder: String? = nil) -> SettingsRow {
        SettingsRow(id, title: title, detail: detail, control: .textField(text: text, placeholder: placeholder))
    }
    public static func button(_ id: String, _ title: String, detail: String? = nil, destructive: Bool = false) -> SettingsRow {
        SettingsRow(id, title: title, detail: detail, control: .button(destructive: destructive))
    }
    public static func link(_ id: String, _ title: String, url: String) -> SettingsRow {
        SettingsRow(id, title: title, control: .link(url: url))
    }
    public static func value(_ id: String, _ title: String, _ text: String) -> SettingsRow {
        SettingsRow(id, title: title, control: .value(text: text))
    }
    public static func note(_ id: String, _ text: String) -> SettingsRow {
        SettingsRow(id, title: text, control: .note)
    }
}

// MARK: Widget

/// A tile on the Widgets page of the open notch.
public struct Widget: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    /// An SF Symbol for the Widgets page's icon row.
    public var symbol: String
    public var content: WidgetNode
    public init(_ id: String, title: String, symbol: String, content: WidgetNode) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.content = content
    }
}

public indirect enum WidgetNode: Codable, Sendable, Equatable {
    case vstack(spacing: Double?, children: [WidgetNode])
    case hstack(spacing: Double?, children: [WidgetNode])
    case text(String, style: TextStyle?)
    case symbol(String, size: Double?)
    /// 0 to 1.
    case progress(Double, label: String?)
    /// Sends a `pressed` event with this id.
    case button(id: String, title: String, symbol: String?)
    case spacer

    public enum TextStyle: String, Codable, Sendable {
        case title, body, caption, secondary, monospaced
    }
}

// MARK: Events

/// What the user did, sent to `AddOnHandlers.onEvent`.
public struct SurfaceEvent: Codable, Sendable, Equatable {
    /// `Surface.settingsPage` or `Surface.widget`.
    public var surface: String
    /// The widget's id, for widget events.
    public var widget: String?
    /// The row or button id.
    public var control: String
    public var action: Action

    public init(surface: String, widget: String? = nil, control: String, action: Action) {
        self.surface = surface
        self.widget = widget
        self.control = control
        self.action = action
    }

    public enum Action: Codable, Sendable, Equatable {
        case toggled(Bool)
        case picked(String)
        case changed(Double)
        case edited(String)
        case pressed
    }
}

// MARK: Validation

public enum SurfaceValidationError: Error, Equatable, CustomStringConvertible {
    case duplicateID(String)
    case tooLarge(String)
    case invalid(String)

    public var description: String {
        switch self {
        case .duplicateID(let id): return "The id \(id) is used twice."
        case .tooLarge(let what): return "Too large: \(what)."
        case .invalid(let what): return "Invalid: \(what)."
        }
    }
}

extension SettingsPage {
    /// The checks Ledge runs before drawing the page.
    public func validate() throws {
        var ids = Set<String>()
        var rows = 0
        for section in sections {
            guard ids.insert("section:" + section.id).inserted else { throw SurfaceValidationError.duplicateID(section.id) }
            try checkText(section.title)
            try checkText(section.footer)
            for row in section.rows {
                rows += 1
                guard ids.insert(row.id).inserted else { throw SurfaceValidationError.duplicateID(row.id) }
                try checkText(row.title)
                try checkText(row.detail)
                switch row.control {
                case let .picker(options, selected):
                    guard !options.isEmpty, options.count <= 50, options.contains(where: { $0.id == selected }),
                          Set(options.map(\.id)).count == options.count else { throw SurfaceValidationError.invalid("picker \(row.id)") }
                case let .slider(minimum, maximum, step, value, _):
                    guard minimum < maximum, (minimum...maximum).contains(value), (step ?? 1) > 0
                    else { throw SurfaceValidationError.invalid("slider \(row.id)") }
                case let .link(url):
                    guard let scheme = URL(string: url)?.scheme?.lowercased(), ["https", "http", "mailto"].contains(scheme)
                    else { throw SurfaceValidationError.invalid("link \(row.id)") }
                case let .textField(text, placeholder):
                    try checkText(text)
                    try checkText(placeholder)
                case let .value(text):
                    try checkText(text)
                default:
                    break
                }
            }
        }
        guard rows <= Surface.maximumRows else { throw SurfaceValidationError.tooLarge("\(rows) rows") }
    }
}

extension Widget {
    /// The checks Ledge runs before drawing the widget.
    public func validate() throws {
        try checkText(title)
        var ids = Set<String>()
        var count = 0
        func walk(_ node: WidgetNode, depth: Int) throws {
            count += 1
            guard depth <= Surface.maximumDepth else { throw SurfaceValidationError.tooLarge("nesting deeper than \(Surface.maximumDepth)") }
            guard count <= Surface.maximumNodes else { throw SurfaceValidationError.tooLarge("more than \(Surface.maximumNodes) parts") }
            switch node {
            case let .vstack(_, children), let .hstack(_, children):
                for child in children { try walk(child, depth: depth + 1) }
            case let .text(text, _):
                try checkText(text)
            case let .progress(value, label):
                guard (0...1).contains(value) else { throw SurfaceValidationError.invalid("progress \(value)") }
                try checkText(label)
            case let .button(id, title, _):
                guard ids.insert(id).inserted else { throw SurfaceValidationError.duplicateID(id) }
                try checkText(title)
            case .symbol, .spacer:
                break
            }
        }
        try walk(content, depth: 1)
    }
}

private func checkText(_ text: String?) throws {
    if let text, text.count > Surface.maximumText { throw SurfaceValidationError.tooLarge("text over \(Surface.maximumText) characters") }
}
