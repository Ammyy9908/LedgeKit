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
    /// A button in Ledge's players, such as a heart for liking the playing song.
    public static let playerAction = "player-action"
    /// A ••• menu entry and Playing Next in Ledge's players, for the players an add-on covers.
    public static let player = "player"

    /// Update topics an add-on sends surfaces on.
    public static let settingsTopic = "surface.settings-page"
    public static let widgetsTopic = "surface.widgets"
    public static let playerActionsTopic = "surface.player-actions"
    public static let playerTopic = "surface.player"
    /// The request Ledge sends when the user acts on a control.
    public static let eventMethod = "ledge.surfaceEvent"
    /// The request Ledge sends to read or set a player action's state for a song. See `PlayerActionRequest`.
    public static let playerActionMethod = "ledge.playerAction"
    /// The requests Ledge sends for a `PlayerExtension`'s menu and queue.
    public static let playerMenuMethod = "ledge.playerMenu"
    public static let playerQueueMethod = "ledge.playerQueue"
    public static let maximumMenuItems = 500
    public static let maximumQueueEntries = 50

    /// Limits Ledge enforces before drawing anything.
    public static let maximumRows = 200
    public static let maximumWidgets = 8
    public static let maximumNodes = 100
    public static let maximumDepth = 6
    public static let maximumText = 1000
    public static let maximumPlayerActions = 4
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
        /// Ledge's own sign-in for an account it manages, such as `spotify`. The credentials stay in Ledge;
        /// the add-on uses the account through `LedgeHost.request`. Needs LedgeKit 0.7.0.
        case account(provider: String)
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
    public static func account(_ id: String, _ title: String, provider: String) -> SettingsRow {
        SettingsRow(id, title: title, control: .account(provider: provider))
    }
}

// MARK: Player action

/// A button Ledge puts in its players (notch, menu bar, floating player, lock screen) while a song from one of
/// `sources` plays. Ledge draws it in its own place, with its own layout and focus; the add-on decides whether it
/// is selected for each song. Ledge asks with a `PlayerActionRequest` and draws `selectedSymbol` while the add-on
/// says true.
public struct PlayerAction: Codable, Sendable, Equatable {
    public var id: String
    /// Read by VoiceOver and shown as the button's tooltip.
    public var label: String
    public var symbol: String
    public var selectedSymbol: String
    /// Bundle ids of the players it applies to, such as `com.spotify.client`.
    public var sources: [String]

    public init(_ id: String, label: String, symbol: String, selectedSymbol: String, sources: [String]) {
        self.id = id
        self.label = label
        self.symbol = symbol
        self.selectedSymbol = selectedSymbol
        self.sources = sources
    }
}

/// The song a player action is asked about.
public struct PlayerTrack: Codable, Sendable, Equatable {
    /// The player's bundle id.
    public var source: String
    /// The player's own id for the song, when it gives one, such as a Spotify track id.
    public var id: String?
    public var title: String
    public var artist: String?
    public var album: String?

    public init(source: String, id: String? = nil, title: String, artist: String? = nil, album: String? = nil) {
        self.source = source
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
    }
}

/// Ledge asks for a player action's state for a song (`set` is nil), or the user pressed it (`set` is the state
/// they asked for). Answer the state after it, or nil when it isn't known, which Ledge draws as unavailable.
public struct PlayerActionRequest: Codable, Sendable, Equatable {
    public var action: String
    public var track: PlayerTrack
    public var set: Bool?

    public init(action: String, track: PlayerTrack, set: Bool? = nil) {
        self.action = action
        self.track = track
        self.set = set
    }
}

// MARK: Player extension

/// More of Ledge's players for the players an add-on covers: an entry in the ••• menu whose choices the add-on
/// lists when it opens (such as Add to Playlist), and Playing Next. Show it with `AddOnSession.show(player:)`;
/// declare `"player"` in the manifest's surfaces. Ledge draws both and asks the add-on for their contents.
public struct PlayerExtension: Codable, Sendable, Equatable {
    /// Bundle ids of the players it applies to, such as `com.apple.Music`.
    public var sources: [String]
    public var menu: PlayerMenu?
    /// The add-on answers `PlayerQueueRequest`s with the songs after the playing one.
    public var queue: Bool

    public init(sources: [String], menu: PlayerMenu? = nil, queue: Bool = false) {
        self.sources = sources
        self.menu = menu
        self.queue = queue
    }
}

/// An entry in the player's ••• menu that opens a list of choices.
public struct PlayerMenu: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var symbol: String?

    public init(_ id: String, title: String, symbol: String? = nil) {
        self.id = id
        self.title = title
        self.symbol = symbol
    }

    public struct Item: Codable, Sendable, Equatable {
        public var id: String
        public var title: String
        public init(_ id: String, title: String) {
            self.id = id
            self.title = title
        }
    }
}

/// Ledge opened the menu (`choose` is nil: answer its items), or the user picked an item (`choose` is its id:
/// do it, and answer the items again or an empty list).
public struct PlayerMenuRequest: Codable, Sendable, Equatable {
    public var menu: String
    public var track: PlayerTrack
    public var choose: String?

    public init(menu: String, track: PlayerTrack, choose: String? = nil) {
        self.menu = menu
        self.track = track
        self.choose = choose
    }
}

/// Ledge wants Playing Next (`playNext` is nil), or the user picked an upcoming song to play next (its id).
/// Answer the upcoming songs, after the change. Throw `AddOnError` with a reason Ledge can show when there's none.
public struct PlayerQueueRequest: Codable, Sendable, Equatable {
    public var track: PlayerTrack
    public var playNext: String?

    public init(track: PlayerTrack, playNext: String? = nil) {
        self.track = track
        self.playNext = playNext
    }
}

/// A song in Playing Next. Ledge loads `artworkURL` (https only), or looks the store id up in Apple's catalog.
public struct PlayerQueueEntry: Codable, Sendable, Equatable {
    public var id: String?
    public var title: String
    public var artist: String
    public var artworkURL: String?
    public var storeID: String?

    public init(id: String? = nil, title: String, artist: String, artworkURL: String? = nil, storeID: String? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.artworkURL = artworkURL
        self.storeID = storeID
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
                case let .account(provider):
                    guard !provider.isEmpty, provider.count <= 64 else { throw SurfaceValidationError.invalid("account \(row.id)") }
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

extension PlayerAction {
    /// The checks Ledge runs before showing a set of player actions.
    public static func validate(_ actions: [PlayerAction]) throws {
        guard actions.count <= Surface.maximumPlayerActions else { throw SurfaceValidationError.tooLarge("\(actions.count) player actions") }
        var ids = Set<String>()
        for action in actions {
            guard !action.id.isEmpty, ids.insert(action.id).inserted else { throw SurfaceValidationError.duplicateID(action.id) }
            guard !action.label.isEmpty, action.label.count <= 100 else { throw SurfaceValidationError.invalid("label of \(action.id)") }
            guard !action.symbol.isEmpty, !action.selectedSymbol.isEmpty, action.symbol.count <= 100, action.selectedSymbol.count <= 100
            else { throw SurfaceValidationError.invalid("symbol of \(action.id)") }
            guard !action.sources.isEmpty, action.sources.count <= 8,
                  action.sources.allSatisfy({ !$0.isEmpty && $0.count <= 255 && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" } })
            else { throw SurfaceValidationError.invalid("sources of \(action.id)") }
        }
    }
}

extension PlayerExtension {
    /// The checks Ledge runs before using an add-on's player extension.
    public func validate() throws {
        guard !sources.isEmpty, sources.count <= 8,
              sources.allSatisfy({ !$0.isEmpty && $0.count <= 255 && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" } })
        else { throw SurfaceValidationError.invalid("player sources") }
        if let menu {
            guard !menu.id.isEmpty, !menu.title.isEmpty, menu.title.count <= 100, (menu.symbol?.count ?? 0) <= 100
            else { throw SurfaceValidationError.invalid("player menu") }
        }
    }
}

extension PlayerMenu.Item {
    /// The checks Ledge runs on each item before showing a menu.
    public static func validate(_ items: [PlayerMenu.Item]) throws {
        guard items.count <= Surface.maximumMenuItems else { throw SurfaceValidationError.tooLarge("\(items.count) menu items") }
        for item in items {
            guard !item.id.isEmpty, item.id.count <= 1024, !item.title.isEmpty, item.title.count <= 512
            else { throw SurfaceValidationError.invalid("menu item") }
        }
    }
}

extension PlayerQueueEntry {
    /// The checks Ledge runs on Playing Next before drawing it.
    public static func validate(_ entries: [PlayerQueueEntry]) throws {
        guard entries.count <= Surface.maximumQueueEntries else { throw SurfaceValidationError.tooLarge("\(entries.count) queue entries") }
        for entry in entries {
            guard !entry.title.isEmpty, entry.title.count <= 512, entry.artist.count <= 512, (entry.id?.count ?? 0) <= 1024,
                  (entry.storeID ?? "").allSatisfy({ $0.isASCII && $0.isNumber }), (entry.storeID?.count ?? 0) <= 32
            else { throw SurfaceValidationError.invalid("queue entry") }
            if let url = entry.artworkURL {
                guard url.count <= 4096, URL(string: url)?.scheme == "https" else { throw SurfaceValidationError.invalid("queue artwork") }
            }
        }
    }
}

private func checkText(_ text: String?) throws {
    if let text, text.count > Surface.maximumText { throw SurfaceValidationError.tooLarge("text over \(Surface.maximumText) characters") }
}
