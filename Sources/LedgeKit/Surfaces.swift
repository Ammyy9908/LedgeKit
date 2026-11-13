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
    /// A live activity beside the notch.
    public static let activity = "activity"
    /// A pill on the lock screen, under the clock.
    public static let lockScreenRow = "lock-screen-row"
    /// A row in the menu bar panel.
    public static let menuBarTile = "menu-bar-tile"
    /// The add-on's own page in the open notch, with an icon in the pill under it. Needs LedgeKit 0.12.0.
    public static let notchPage = "notch-page"

    /// Update topics an add-on sends surfaces on.
    public static let settingsTopic = "surface.settings-page"
    public static let widgetsTopic = "surface.widgets"
    public static let playerActionsTopic = "surface.player-actions"
    public static let playerTopic = "surface.player"
    public static let activitiesTopic = "surface.activities"
    public static let lockScreenRowTopic = "surface.lock-screen-row"
    public static let menuBarTilesTopic = "surface.menu-bar-tiles"
    public static let notchPageTopic = "surface.notch-page"
    public static let maximumMenuBarTiles = 2
    /// The request Ledge sends when the user acts on a control.
    public static let eventMethod = "ledge.surfaceEvent"
    /// The request Ledge sends to read or set a player action's state for a song. See `PlayerActionRequest`.
    public static let playerActionMethod = "ledge.playerAction"
    /// The requests Ledge sends for a `PlayerExtension`'s menu and queue.
    public static let playerMenuMethod = "ledge.playerMenu"
    public static let playerQueueMethod = "ledge.playerQueue"
    public static let maximumMenuItems = 500
    public static let maximumQueueEntries = 50
    /// The request Ledge sends when an activity's place beside the notch changes. See `ActivityPlacementChange`.
    public static let activityPlacementMethod = "ledge.activityPlacement"
    public static let maximumActivities = 2
    public static let maximumActivityText = 60

    /// Limits Ledge enforces before drawing anything.
    public static let maximumRows = 200
    public static let maximumWidgets = 8
    public static let maximumNodes = 100
    public static let maximumDepth = 6
    public static let maximumText = 1000
    public static let maximumPlayerActions = 4

    /// Limits for a notch page's screen. A screen may hold more parts than a widget, since it has the page to itself.
    public static let maximumPageNodes = 200
    public static let maximumListRows = 100
    public static let maximumPageActions = 3
    public static let maximumEditorText = 50_000
}

// MARK: Settings page

/// The add-on's settings page: sections of rows, drawn in Ledge's own cards under the add-on's header.
public struct SettingsPage: Codable, Sendable, Equatable {
    public var sections: [SettingsSection]
    /// Words that find the page in Ledge's Settings search besides the add-on's name, like "markdown" for Notes.
    /// Up to 20, each up to 40 characters. Needs 0.13.0.
    public var keywords: [String]?
    public init(_ sections: [SettingsSection], keywords: [String] = []) {
        self.sections = sections
        self.keywords = keywords.isEmpty ? nil : keywords
    }
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
    /// A grey line under the title. For a button, the label beside it: the button itself reads `title`, like
    /// "Delete all notes…" beside "Notes in the Trash are kept 30 days".
    public var detail: String?
    public var control: Control
    /// For a button: Ledge asks first, in its own alert, and sends `pressed` only when the user confirms.
    /// Needs 0.13.0.
    public var confirm: Confirmation?

    public init(_ id: String, title: String, detail: String? = nil, control: Control, confirm: Confirmation? = nil) {
        self.id = id
        self.title = title
        self.detail = detail
        self.control = control
        self.confirm = confirm
    }

    /// What Ledge asks before a button runs: "Delete all notes?", what it means, and the word on the button.
    public struct Confirmation: Codable, Sendable, Equatable {
        public var title: String
        public var message: String?
        /// The button that goes ahead, like "Delete". Cancel is always there too.
        public var confirmTitle: String
        public init(_ title: String, message: String? = nil, confirmTitle: String) {
            self.title = title
            self.message = message
            self.confirmTitle = confirmTitle
        }
    }

    public enum Control: Codable, Sendable, Equatable {
        case toggle(isOn: Bool)
        case picker(options: [Option], selected: String)
        case slider(minimum: Double, maximum: Double, step: Double?, value: Double, unit: String?)
        case textField(text: String, placeholder: String?)
        /// A button reading the row's `title`, with the row's `detail` as the label beside it. Sends `pressed`.
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
    public static func button(_ id: String, _ title: String, detail: String? = nil, destructive: Bool = false,
                              confirm: Confirmation? = nil) -> SettingsRow {
        SettingsRow(id, title: title, detail: detail, control: .button(destructive: destructive), confirm: confirm)
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

// MARK: Live activity

/// A compact row beside the notch, like Ledge's own volume or charging activities: a symbol, a short text and an
/// optional progress ring. Show the add-on's current activities with `AddOnSession.show(activities:)`; each send
/// replaces the last, and an activity left out is taken down. Declare `"activity"` in the manifest's surfaces.
///
/// Ledge's own activities always come first: an add-on's activity takes the centre only when nothing of Ledge's is
/// showing, and otherwise a side pill or nothing. Ledge says where each one is with `onActivityPlacement`. Take an
/// activity down as soon as it has nothing to say.
public struct LiveActivity: Codable, Sendable, Equatable {
    public var id: String
    public var symbol: String
    /// Up to 60 characters; keep it to a few words.
    public var text: String
    public var progress: Progress?
    public var importance: Importance
    /// Seconds it stays after this send, or nil to stay until the add-on takes it down.
    public var lasts: Double?
    /// What the activity is about, when it's one of the things Ledge shows itself. Nil is anything else. Needs 0.13.0.
    public var kind: Kind?
    /// What VoiceOver says for the activity, when the text alone doesn't, like "4 minutes 59 seconds left" for
    /// "4:59". Up to 120 characters. Needs 0.13.0.
    public var accessibilityValue: String?

    public init(_ id: String, symbol: String, text: String, progress: Progress? = nil,
                importance: Importance = .normal, lasts: Double? = nil, kind: Kind? = nil, accessibilityValue: String? = nil) {
        self.id = id
        self.symbol = symbol
        self.text = text
        self.progress = progress
        self.importance = importance
        self.lasts = lasts
        self.kind = kind
        self.accessibilityValue = accessibilityValue
    }

    /// Kinds of activity Ledge has of its own. While Ledge's own of the same kind is up, the add-on's isn't shown,
    /// with the placement `duplicatesBuiltIn`, so there are never two of the same thing beside the notch. Declare a
    /// kind only when the activity really is one: it never wins a place, it only steps aside.
    public enum Kind: String, Codable, Sendable, Equatable {
        /// A song or podcast playing. Ledge's own is the song in the notch.
        case nowPlaying
        /// A download in progress. Ledge's own is the download ring.
        case download
        /// The screen or audio being recorded. Ledge's own is the recording indicator.
        case recording
    }

    public enum Progress: Codable, Sendable, Equatable {
        case indeterminate
        case fraction(Double)
        case done
    }

    /// Orders an add-on's activity among other add-ons'. All of them rank below Ledge's own.
    public enum Importance: String, Codable, Sendable, Comparable {
        case low, normal, high
        /// Something to act on now: a timer that rang, a build that failed. Above `.high`, still below Ledge's own,
        /// and it lets the add-on open its page without a click (`LedgeHost.showPage()`). Use it only while that's
        /// true. Needs 0.13.0.
        case attention
        public static func < (a: Importance, b: Importance) -> Bool {
            let order: [Importance] = [.low, .normal, .high, .attention]
            return order.firstIndex(of: a)! < order.firstIndex(of: b)!
        }
    }
}

/// Where an activity is now.
public enum ActivityPlacement: String, Codable, Sendable, Equatable {
    /// In the centre, beside the notch.
    case center
    /// In a side pill, next to a higher-ranked activity.
    case side
    /// Waiting: higher-ranked activities fill every place.
    case outranked
    /// The user turned off this add-on's activities; Ledge won't show them.
    case suppressed
    /// Not up: it ended, ran out its time, or was taken down.
    case idle
    /// Not shown while Ledge's own activity of the same `kind` is up. It comes back when that one ends. 0.13.0.
    case duplicatesBuiltIn
    /// Stepped aside after saying the same thing for half an hour at `.high` or `.attention`. Sending something
    /// different brings it back. Only for add-ons built for 0.13.0 or later. 0.13.0.
    case stale
}

/// Sent to `AddOnHandlers.onActivityPlacement` when an activity's place changes.
public struct ActivityPlacementChange: Codable, Sendable, Equatable {
    public var activity: String
    public var placement: ActivityPlacement
    public init(activity: String, placement: ActivityPlacement) {
        self.activity = activity
        self.placement = placement
    }
}

// MARK: Lock screen row

/// A pill on the lock screen, under the clock, like the macOS timer's: a symbol, a label and a value, such as
/// "Timer 4:59". One per add-on. Ledge shows it only while the Mac is locked; send it whenever it changes, and nil
/// to take it down. Declare `"lock-screen-row"` in the manifest's surfaces.
public struct LockScreenRow: Codable, Sendable, Equatable {
    public var symbol: String
    /// A word or two, up to 30 characters.
    public var label: String
    /// The part to read at a glance, up to 20 characters.
    public var value: String

    public init(symbol: String, label: String, value: String) {
        self.symbol = symbol
        self.label = label
        self.value = value
    }

    /// The checks Ledge runs before showing it.
    public func validate() throws {
        guard !symbol.isEmpty, symbol.count <= 100 else { throw SurfaceValidationError.invalid("lock screen row symbol") }
        guard label.count <= 30 else { throw SurfaceValidationError.tooLarge("lock screen row label over 30 characters") }
        guard !value.isEmpty, value.count <= 20 else { throw SurfaceValidationError.invalid("lock screen row value") }
    }
}

// MARK: Menu bar tile

/// A row in the menu bar panel, under Ledge's own (Shelf, Clipboard, Settings): a symbol, a title and a grey detail
/// line. Clicking it sends a `SurfaceEvent` with `surface` `"menu-bar-tile"`, `control` the tile's id and `.pressed`.
/// Up to two per add-on. Declare `"menu-bar-tile"` in the manifest's surfaces.
public struct MenuBarTile: Codable, Sendable, Equatable {
    public var id: String
    public var symbol: String
    /// Up to 40 characters.
    public var title: String
    /// Up to 60 characters.
    public var detail: String?

    public init(_ id: String, symbol: String, title: String, detail: String? = nil) {
        self.id = id
        self.symbol = symbol
        self.title = title
        self.detail = detail
    }

    /// The checks Ledge runs before showing an add-on's tiles.
    public static func validate(_ tiles: [MenuBarTile]) throws {
        guard tiles.count <= Surface.maximumMenuBarTiles else { throw SurfaceValidationError.tooLarge("\(tiles.count) menu bar tiles") }
        var ids = Set<String>()
        for tile in tiles {
            guard !tile.id.isEmpty, tile.id.count <= 64, ids.insert(tile.id).inserted else { throw SurfaceValidationError.duplicateID(tile.id) }
            guard !tile.symbol.isEmpty, tile.symbol.count <= 100 else { throw SurfaceValidationError.invalid("symbol of \(tile.id)") }
            guard !tile.title.isEmpty, tile.title.count <= 40 else { throw SurfaceValidationError.invalid("title of \(tile.id)") }
            guard (tile.detail?.count ?? 0) <= 60 else { throw SurfaceValidationError.invalid("detail of \(tile.id)") }
        }
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
    /// How tall the Widgets page is while this widget is open. Small, the default, is the size every widget had before
    /// LedgeKit 0.15.0, and a Ledge older than that draws every widget small. Needs 0.15.0.
    public var size: Size {
        get { storedSize ?? .small }
        set { storedSize = newValue == .small ? nil : newValue }
    }
    /// Nil for small, so a small widget sends exactly what it did before sizes existed.
    private var storedSize: Size?

    public init(_ id: String, title: String, symbol: String, size: Size = .small, content: WidgetNode) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.content = content
        self.size = size
    }

    /// The room under the widget's title, at the notch's Regular width (Compact is 60 points narrower, Large 80
    /// wider): small 348 × 78 points, medium 348 × 138, large 348 × 198. Content taller than that is cut off at the
    /// bottom.
    public enum Size: String, Codable, Sendable, CaseIterable {
        case small, medium, large
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, symbol, content
        case storedSize = "size"
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

// MARK: Notch page

/// The add-on's own page in the open notch. It gets an icon in the pill under the notch, after Ledge's Shelf,
/// Clipboard and Widgets, and shows one `PageScreen` at a time. Declare `"notch-page"` in the manifest and send it
/// with `AddOnSession.show(notchPage:)`; sending nil takes the page down. Needs LedgeKit 0.12.0.
public struct NotchPage: Codable, Sendable, Equatable {
    /// The page's name, read out for the pill's icon and shown as its tooltip.
    public var title: String
    /// An SF Symbol for the page's icon in the pill.
    public var symbol: String
    /// How tall the open notch is on this page. Ledge sets the exact height, the same for every add-on.
    public var size: Size
    /// What the page shows now. Send a new screen to move to it.
    public var screen: PageScreen

    public init(title: String, symbol: String, size: Size = .medium, screen: PageScreen) {
        self.title = title
        self.symbol = symbol
        self.size = size
        self.screen = screen
    }

    public enum Size: String, Codable, Sendable {
        case small, medium, large
    }
}

/// One screen of a notch page: a header and what's under it. Moving between screens is the add-on's to decide:
/// it sends the next screen, and Ledge slides forward when the new one's `depth` is greater, back when it's less,
/// and swaps in place when it's the same. A screen sent again with the same `id` updates in place.
public struct PageScreen: Codable, Sendable, Equatable {
    /// The `control` of the header's back button.
    public static let backControl = "back"

    /// Stable for as long as the screen shows the same thing, such as `"list"` or `"note-42"`.
    public var id: String
    /// 0 for the page's first screen, 1 for one opened from it, and so on.
    public var depth: Int
    /// A title at the top left, like "Notes". Leave it out on a screen whose caption says enough.
    public var title: String?
    /// A small grey line in the middle of the header, like "Edited 11:35 PM".
    public var caption: String?
    /// Shows a back button at the left of the header. Pressing it sends `pressed` with `PageScreen.backControl`.
    public var back: Bool
    /// Up to three round buttons at the right of the header, such as New, Copy and Delete.
    public var actions: [PageAction]
    public var content: PageNode

    public init(_ id: String, depth: Int = 0, title: String? = nil, caption: String? = nil, back: Bool = false,
                actions: [PageAction] = [], content: PageNode) {
        self.id = id
        self.depth = depth
        self.title = title
        self.caption = caption
        self.back = back
        self.actions = actions
        self.content = content
    }
}

/// A round button in a notch page's header. Pressing it sends `pressed` with its id.
public struct PageAction: Codable, Sendable, Equatable {
    public var id: String
    /// An SF Symbol.
    public var symbol: String
    /// What the button does, for VoiceOver and its tooltip.
    public var label: String
    /// Draws the button in red, for something like Delete.
    public var destructive: Bool

    public init(_ id: String, symbol: String, label: String, destructive: Bool = false) {
        self.id = id
        self.symbol = symbol
        self.label = label
        self.destructive = destructive
    }
}

/// What a notch page's screen is made of: a widget's parts, plus a list, an empty state and a text editor.
public indirect enum PageNode: Codable, Sendable, Equatable {
    case vstack(spacing: Double?, children: [PageNode])
    case hstack(spacing: Double?, children: [PageNode])
    case text(String, style: WidgetNode.TextStyle?)
    case symbol(String, size: Double?)
    /// 0 to 1.
    case progress(Double, label: String?)
    /// Sends a `pressed` event with this id.
    case button(id: String, title: String, symbol: String?)
    case spacer
    /// Rows that each open something. Pressing one sends `pressed` with the list's id as `control` and the row's
    /// id as `item`. Ledge scrolls the list when it's taller than the page.
    case list(id: String, rows: [ListRow])
    /// What a screen shows when there's nothing in it yet: a symbol, a title and an optional line under it.
    case empty(symbol: String, title: String, detail: String?)
    /// A text editor that fills the space it's given, with a formatting bar. The text is Markdown: Ledge styles it
    /// as it's typed and hands it back as Markdown. While someone is typing, Ledge keeps their text even if the
    /// add-on sends the screen again, so keep the editor's `id` the same. Sends `edited` as they type and `ended`
    /// when the editor loses the keyboard. At most one editor per screen.
    case editor(id: String, text: String, placeholder: String?, autofocus: Bool)
}

/// A row in a notch page's list.
public struct ListRow: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    /// A grey line under the title, such as the start of a note.
    public var subtitle: String?
    /// A short grey label before the subtitle, such as "12:41 PM".
    public var detail: String?
    /// An optional SF Symbol at the start of the row.
    public var symbol: String?

    public init(_ id: String, title: String, subtitle: String? = nil, detail: String? = nil, symbol: String? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.detail = detail
        self.symbol = symbol
    }
}

// MARK: Events

/// What the user did, sent to `AddOnHandlers.onEvent`.
public struct SurfaceEvent: Codable, Sendable, Equatable {
    /// `Surface.settingsPage`, `Surface.widget` or `Surface.notchPage`.
    public var surface: String
    /// The widget's id, for widget events.
    public var widget: String?
    /// The row, button, list or editor id. On a notch page, the header's back button is `PageScreen.backControl`.
    public var control: String
    public var action: Action
    /// For notch page events: the id of the screen the event came from. An event from a screen the add-on has
    /// already moved on from can be ignored.
    public var screen: String?
    /// For a list on a notch page: the id of the row that was pressed. `control` is then the list's id.
    public var item: String?

    public init(surface: String, widget: String? = nil, control: String, action: Action, screen: String? = nil, item: String? = nil) {
        self.surface = surface
        self.widget = widget
        self.control = control
        self.action = action
        self.screen = screen
        self.item = item
    }

    public enum Action: Codable, Sendable, Equatable {
        case toggled(Bool)
        case picked(String)
        case changed(Double)
        case edited(String)
        case pressed
        /// An editor on a notch page lost the keyboard, with its final text: the moment to save. Needs 0.12.0.
        case ended(String)
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
        if let keywords {
            guard keywords.count <= 20, keywords.allSatisfy({ !$0.isEmpty && $0.count <= 40 })
            else { throw SurfaceValidationError.invalid("keywords") }
        }
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
                if let confirm = row.confirm {
                    guard case .button = row.control else { throw SurfaceValidationError.invalid("confirm on \(row.id), which isn't a button") }
                    guard !confirm.title.isEmpty, confirm.title.count <= 120, !confirm.confirmTitle.isEmpty, confirm.confirmTitle.count <= 30
                    else { throw SurfaceValidationError.invalid("confirm of \(row.id)") }
                    try checkText(confirm.message)
                }
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

extension NotchPage {
    /// The checks Ledge runs before drawing the page.
    public func validate() throws {
        guard !title.isEmpty, title.count <= 40 else { throw SurfaceValidationError.invalid("notch page title") }
        guard !symbol.isEmpty, symbol.count <= 100 else { throw SurfaceValidationError.invalid("notch page symbol") }
        try screen.validate()
    }
}

extension PageScreen {
    /// The checks Ledge runs before drawing the screen.
    public func validate() throws {
        guard !id.isEmpty, id.count <= 128 else { throw SurfaceValidationError.invalid("screen id") }
        guard (0...16).contains(depth) else { throw SurfaceValidationError.invalid("screen depth \(depth)") }
        guard (title?.count ?? 0) <= 60, (caption?.count ?? 0) <= 60 else { throw SurfaceValidationError.tooLarge("screen title or caption over 60 characters") }
        guard actions.count <= Surface.maximumPageActions else { throw SurfaceValidationError.tooLarge("\(actions.count) header buttons") }
        // Ids are unique across the whole screen: the header's buttons, the back button, lists, rows' parents and
        // controls all name themselves in the same events.
        var ids: Set<String> = back ? [Self.backControl] : []
        for action in actions {
            guard !action.id.isEmpty, ids.insert(action.id).inserted else { throw SurfaceValidationError.duplicateID(action.id) }
            guard !action.symbol.isEmpty, action.symbol.count <= 100 else { throw SurfaceValidationError.invalid("symbol of \(action.id)") }
            guard !action.label.isEmpty, action.label.count <= 60 else { throw SurfaceValidationError.invalid("label of \(action.id)") }
        }
        var count = 0
        var editors = 0
        func walk(_ node: PageNode, depth: Int) throws {
            count += 1
            guard depth <= Surface.maximumDepth else { throw SurfaceValidationError.tooLarge("nesting deeper than \(Surface.maximumDepth)") }
            guard count <= Surface.maximumPageNodes else { throw SurfaceValidationError.tooLarge("more than \(Surface.maximumPageNodes) parts") }
            switch node {
            case let .vstack(_, children), let .hstack(_, children):
                for child in children { try walk(child, depth: depth + 1) }
            case let .text(text, _):
                try checkText(text)
            case let .progress(value, label):
                guard (0...1).contains(value) else { throw SurfaceValidationError.invalid("progress \(value)") }
                try checkText(label)
            case let .button(id, title, _):
                guard !id.isEmpty, ids.insert(id).inserted else { throw SurfaceValidationError.duplicateID(id) }
                try checkText(title)
            case let .list(id, rows):
                guard !id.isEmpty, ids.insert(id).inserted else { throw SurfaceValidationError.duplicateID(id) }
                guard rows.count <= Surface.maximumListRows else { throw SurfaceValidationError.tooLarge("\(rows.count) rows in list \(id)") }
                var rowIDs = Set<String>()
                for row in rows {
                    guard !row.id.isEmpty, rowIDs.insert(row.id).inserted else { throw SurfaceValidationError.duplicateID(row.id) }
                    guard !row.title.isEmpty else { throw SurfaceValidationError.invalid("title of row \(row.id)") }
                    try checkText(row.title)
                    try checkText(row.subtitle)
                    guard (row.detail?.count ?? 0) <= 30 else { throw SurfaceValidationError.tooLarge("detail of row \(row.id) over 30 characters") }
                }
            case let .empty(symbol, title, detail):
                guard !symbol.isEmpty, !title.isEmpty else { throw SurfaceValidationError.invalid("empty state") }
                try checkText(title)
                try checkText(detail)
            case let .editor(id, text, placeholder, _):
                guard !id.isEmpty, ids.insert(id).inserted else { throw SurfaceValidationError.duplicateID(id) }
                editors += 1
                guard editors <= 1 else { throw SurfaceValidationError.invalid("more than one editor on a screen") }
                guard text.count <= Surface.maximumEditorText else { throw SurfaceValidationError.tooLarge("editor text over \(Surface.maximumEditorText) characters") }
                try checkText(placeholder)
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

extension LiveActivity {
    /// The checks Ledge runs before showing an add-on's activities.
    public static func validate(_ activities: [LiveActivity]) throws {
        guard activities.count <= Surface.maximumActivities else { throw SurfaceValidationError.tooLarge("\(activities.count) activities") }
        var ids = Set<String>()
        for activity in activities {
            guard !activity.id.isEmpty, activity.id.count <= 64, ids.insert(activity.id).inserted
            else { throw SurfaceValidationError.duplicateID(activity.id) }
            guard !activity.symbol.isEmpty, activity.symbol.count <= 100 else { throw SurfaceValidationError.invalid("symbol of \(activity.id)") }
            guard !activity.text.isEmpty, activity.text.count <= Surface.maximumActivityText
            else { throw SurfaceValidationError.invalid("text of \(activity.id)") }
            if case .fraction(let value)? = activity.progress, !(0...1).contains(value) {
                throw SurfaceValidationError.invalid("progress of \(activity.id)")
            }
            if let lasts = activity.lasts, !(1...600).contains(lasts) { throw SurfaceValidationError.invalid("lasts of \(activity.id)") }
            if let value = activity.accessibilityValue, value.isEmpty || value.count > 120 {
                throw SurfaceValidationError.invalid("accessibilityValue of \(activity.id)")
            }
        }
    }
}

private func checkText(_ text: String?) throws {
    if let text, text.count > Surface.maximumText { throw SurfaceValidationError.tooLarge("text over \(Surface.maximumText) characters") }
}
