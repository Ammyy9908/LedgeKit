import Foundation

/// A native page button. Roles are semantic; the host owns colors, focus and pressed feedback. Needs 0.23.0.
public struct PageButton: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var role: Role
    /// Optional SF Symbol, replacing the title visually when the title is empty.
    public var symbol: String?
    /// Spoken name when the short visible title is a mathematical symbol.
    public var accessibilityLabel: String?
    /// The colour of an accent or selected button. Nil keeps Ledge's accent; other roles ignore it. Needs 0.26.0.
    public var tint: PageTint?
    public init(_ id: String, title: String, role: Role = .normal, symbol: String? = nil, accessibilityLabel: String? = nil,
                tint: PageTint? = nil) {
        self.id = id; self.title = title; self.role = role; self.symbol = symbol; self.accessibilityLabel = accessibilityLabel
        self.tint = tint
    }
    public enum Role: String, Codable, Sendable { case normal, secondary, accent, selected }

    func validate(ids: inout Set<String>) throws {
        guard !id.isEmpty, id.count <= 128, ids.insert(id).inserted else { throw SurfaceValidationError.duplicateID(id) }
        guard (!title.isEmpty || (symbol?.isEmpty == false && accessibilityLabel?.isEmpty == false)), title.count <= 30,
              (symbol?.count ?? 0) <= 100, (accessibilityLabel?.count ?? 0) <= 80 else { throw SurfaceValidationError.invalid("page button text") }
    }
}

/// An inline expression and large value. Editing sends `edited`/`ended` with `id`; Return sends `pressed` with
/// that same id. Clicking the value sends `pressed` with `copyControl`. Focus is local to this page, never global.
/// An autofocus request takes effect only when this page is opened. Needs 0.23.0.
public struct PageReadout: Codable, Sendable, Equatable {
    public var id: String
    public var expression: String
    public var value: String
    public var copyControl: String
    public var autofocus: Bool
    /// A short status beside the expression, updated without ending typing. At most 120 characters.
    public var status: String?
    public init(_ id: String, expression: String, value: String, copyControl: String, autofocus: Bool = false, status: String? = nil) {
        self.id = id; self.expression = expression; self.value = value; self.copyControl = copyControl; self.autofocus = autofocus
        self.status = status
    }
}

/// A named colour for page controls; Ledge picks the exact shade for the notch. Needs 0.26.0.
public enum PageTint: String, Codable, Sendable, CaseIterable { case orange, blue, green, purple, pink, red, yellow }

/// A ruler of whole numbers under a fixed centre pointer, like a kitchen timer's dial laid flat: a tick for each
/// number, a longer one with a label every `labelEvery`. Dragging it sideways (or scrolling, or the arrow keys
/// through VoiceOver) moves the ruler under the pointer and sends `changed` with the new whole number each time it
/// passes one. Ledge owns the drag, so the ruler keeps moving smoothly while the add-on answers. Needs 0.26.0.
public struct PageTape: Codable, Sendable, Equatable {
    public var id: String
    public var value: Int
    public var minimum: Int
    public var maximum: Int
    /// A labelled, longer tick every this many numbers, 1 to 1,000.
    public var labelEvery: Int
    /// The pointer's colour; nil is Ledge's accent.
    public var tint: PageTint?
    /// What VoiceOver calls it, such as "Length in minutes".
    public var accessibilityLabel: String
    public init(_ id: String, value: Int, minimum: Int, maximum: Int, labelEvery: Int = 5, tint: PageTint? = nil,
                accessibilityLabel: String) {
        self.id = id; self.value = value; self.minimum = minimum; self.maximum = maximum; self.labelEvery = labelEvery
        self.tint = tint; self.accessibilityLabel = accessibilityLabel
    }
}

/// A ring filled part of the way round a picture or symbol, with a title and a caption under it: how much of a plan
/// is left, a battery, a goal. `value` runs 0 to 1 clockwise from the top. With `value` nil the ring is dotted, for
/// "nothing known yet", like an account that isn't signed in. With an `id` the ring is a button: pressing it sends
/// `pressed` with that id, such as to open a screen with the plan's details. Needs 0.27.0.
public struct PageRing: Codable, Sendable, Equatable {
    /// Up to 128 characters; nil draws a ring that can't be pressed.
    public var id: String?
    public var value: Double?
    /// A small PNG in the middle, up to ``Surface/maximumPageImageBytes``; it wins over `symbol`.
    public var image: Data?
    /// An SF Symbol in the middle when there's no image.
    public var symbol: String?
    /// Up to 30 characters, under the ring.
    public var title: String
    /// Up to 30 characters under the title, such as "6% left", in `tint`.
    public var caption: String?
    /// The ring's and caption's colour; nil is white.
    public var tint: PageTint?
    /// What VoiceOver says for the ring, such as "Codex, weekly limit, 6% left". Up to 120 characters.
    public var accessibilityLabel: String

    public init(id: String? = nil, value: Double?, image: Data? = nil, symbol: String? = nil, title: String,
                caption: String? = nil, tint: PageTint? = nil, accessibilityLabel: String) {
        self.id = id; self.value = value; self.image = image; self.symbol = symbol; self.title = title; self.caption = caption
        self.tint = tint; self.accessibilityLabel = accessibilityLabel
    }
}

/// A line of text after a small symbol, both in `tint`, or only the symbol when `tintsText` is false: a status
/// such as "● Working" in orange, or a step with an orange tick before white text. Up to 200 characters on one
/// line; Ledge cuts what doesn't fit. Needs 0.27.0.
public struct PageLabel: Codable, Sendable, Equatable {
    public var text: String
    /// An SF Symbol before the text.
    public var symbol: String?
    /// The symbol's colour, and the text's when `tintsText` is true; nil is white.
    public var tint: PageTint?
    public var tintsText: Bool
    /// The text's size and weight; nil is body text.
    public var style: WidgetNode.TextStyle?

    public init(_ text: String, symbol: String? = nil, tint: PageTint? = nil, tintsText: Bool = true,
                style: WidgetNode.TextStyle? = nil) {
        self.text = text; self.symbol = symbol; self.tint = tint; self.tintsText = tintsText; self.style = style
    }
}

extension PageNode {
    /// Whether the node uses 0.27.0 controls: a ring, a label or a panel.
    public var needsRingLabelOrPanel: Bool {
        switch self {
        case .ring, .label, .panel: true
        case .vstack(_, let children), .hstack(_, let children): children.contains(where: \.needsRingLabelOrPanel)
        default: false
        }
    }

    /// Whether the node uses 0.26.0 controls: a tape, a display or a tinted button.
    public var needsTapeOrTint: Bool {
        switch self {
        case .tape, .display: true
        case .control(let button): button.tint != nil
        case .buttonGrid(_, _, let buttons): buttons.contains { $0.tint != nil }
        case .vstack(_, let children), .hstack(_, let children): children.contains(where: \.needsTapeOrTint)
        case .panel(let child): child.needsTapeOrTint
        default: false
        }
    }

    /// Whether the node uses 0.23.0 native controls.
    public var hasNativeControls: Bool {
        switch self {
        case .control, .buttonGrid, .readout: true
        case .list(_, let rows): rows.contains { $0.emphasizesSubtitle == true }
        case .vstack(_, let children), .hstack(_, let children): children.contains(where: \.hasNativeControls)
        case .panel(let child): child.hasNativeControls
        default: false
        }
    }
}
