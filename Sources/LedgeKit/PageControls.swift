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

extension PageNode {
    /// Whether the node uses 0.26.0 controls: a tape, a display or a tinted button.
    public var needsTapeOrTint: Bool {
        switch self {
        case .tape, .display: true
        case .control(let button): button.tint != nil
        case .buttonGrid(_, _, let buttons): buttons.contains { $0.tint != nil }
        case .vstack(_, let children), .hstack(_, let children): children.contains(where: \.needsTapeOrTint)
        default: false
        }
    }

    /// Whether the node uses 0.23.0 native controls.
    public var hasNativeControls: Bool {
        switch self {
        case .control, .buttonGrid, .readout: true
        case .list(_, let rows): rows.contains { $0.emphasizesSubtitle == true }
        case .vstack(_, let children), .hstack(_, let children): children.contains(where: \.hasNativeControls)
        default: false
        }
    }
}
