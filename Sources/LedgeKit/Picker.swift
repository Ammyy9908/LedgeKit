import Foundation

// A quick picker (LedgeKit 0.19.0): a floating panel that opens on a shortcut from any app, with a search field over
// the add-on's items, like emoji, symbols or snippets. The add-on sends the items; Ledge draws the panel, searches it
// as the person types, and puts the chosen item's text into the app they were in. Declare `"picker"` in the
// manifest's surfaces and send it with `AddOnSession.show(picker:)`.
//
// Ledge types the text in for the person only with the `insert-text` capability, which they approve, and macOS's
// Accessibility permission; otherwise it copies it. Either way the add-on learns what was picked in
// `AddOnHandlers.onPicked`, to keep Recents. The person picks the shortcut in Ledge's Settings.

extension Surface {
    /// A floating panel of items to pick from, on a shortcut. Needs 0.19.0.
    public static let picker = "picker"
    public static let pickerTopic = "surface.picker"
    /// Ledge says what the person picked, as `PickedItem`.
    public static let pickedMethod = "ledge.picked"
    /// The capability that lets Ledge type the picked text into the app the person was in.
    public static let insertTextCapability = "insert-text"
    public static let maximumPickerItems = 5000
    public static let maximumPickerSections = 24
    public static let maximumPickedText = 1000
}

/// The panel's items, in sections. Send it again to change them, as when Recents changes.
public struct Picker: Codable, Sendable, Equatable {
    /// The panel's name, like "Emoji": read out when it opens.
    public var title: String
    /// The search field's placeholder, like "Search emoji".
    public var placeholder: String
    public var style: Style
    public var sections: [Section]

    public init(title: String, placeholder: String, style: Style = .glyphs, sections: [Section]) {
        self.title = title
        self.placeholder = placeholder
        self.style = style
        self.sections = sections
    }

    public enum Style: String, Codable, Sendable {
        /// A grid of large single characters, like emoji, with the selected one's name underneath.
        case glyphs
        /// One row per item: its label, and its text in grey, like snippets.
        case rows
    }

    /// A titled group, like "Recents" or "Animals & Nature". An empty section isn't shown.
    public struct Section: Codable, Sendable, Equatable {
        public var id: String
        public var title: String
        /// An SF Symbol for the section's tab.
        public var symbol: String?
        public var items: [PickerItem]

        public init(_ id: String, title: String, symbol: String? = nil, items: [PickerItem]) {
            self.id = id
            self.title = title
            self.symbol = symbol
            self.items = items
        }
    }

    public func validate() throws {
        func invalid(_ reason: String) -> SurfaceValidationError { .invalid("picker: \(reason)") }
        guard !title.isEmpty, title.count <= 40, placeholder.count <= 60 else { throw invalid("a title of 1 to 40 characters, a placeholder of at most 60") }
        guard sections.count <= Surface.maximumPickerSections else { throw invalid("at most \(Surface.maximumPickerSections) sections") }
        guard Set(sections.map(\.id)).count == sections.count else { throw invalid("each section id once") }
        let count = sections.reduce(0) { $0 + $1.items.count }
        guard count <= Surface.maximumPickerItems else { throw invalid("at most \(Surface.maximumPickerItems) items") }
        for section in sections {
            guard !section.id.isEmpty, section.id.count <= 64, !section.title.isEmpty, section.title.count <= 40 else {
                throw invalid("a section's id and title, at most 64 and 40 characters")
            }
            guard Set(section.items.map(\.id)).count == section.items.count else { throw invalid("each item id once in its section") }
            try section.items.forEach { try $0.validate() }
        }
    }
}

/// One thing to pick: the text it puts in, its name, and the words that find it.
public struct PickerItem: Codable, Sendable, Equatable {
    public var id: String
    /// What goes into the app, like "❤️" or a snippet.
    public var text: String
    /// Its name, like "red heart": shown under the grid, and searched.
    public var label: String
    /// More words that find it, like "love". Ledge matches the start of any word in the label or these.
    public var keywords: [String]

    public init(_ id: String, text: String, label: String, keywords: [String] = []) {
        self.id = id
        self.text = text
        self.label = label
        self.keywords = keywords
    }

    public func validate() throws {
        guard !id.isEmpty, id.count <= 64 else { throw SurfaceValidationError.invalid("picker item: an id of 1 to 64 characters") }
        guard !text.isEmpty, text.count <= Surface.maximumPickedText else {
            throw SurfaceValidationError.invalid("picker item \(id): text of 1 to \(Surface.maximumPickedText) characters")
        }
        guard !label.isEmpty, label.count <= 100 else { throw SurfaceValidationError.invalid("picker item \(id): a label of 1 to 100 characters") }
        guard keywords.count <= 12, keywords.allSatisfy({ !$0.isEmpty && $0.count <= 40 }) else {
            throw SurfaceValidationError.invalid("picker item \(id): at most 12 keywords of 1 to 40 characters")
        }
    }

    /// Whether a search finds it: every word of the query starts a word of the label or a keyword. Ledge and
    /// `ledgekit check` search this way, so an add-on can test what its words find.
    public func matches(_ query: String) -> Bool {
        let wanted = Self.words(query)
        guard !wanted.isEmpty else { return true }
        let own = Self.words(label) + keywords.flatMap(Self.words)
        return wanted.allSatisfy { word in own.contains { $0.hasPrefix(word) } }
    }

    static func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}

/// What the person picked, so the add-on can keep Recents.
public struct PickedItem: Codable, Sendable, Equatable {
    public var section: String
    public var id: String

    public init(section: String, id: String) {
        self.section = section
        self.id = id
    }
}
