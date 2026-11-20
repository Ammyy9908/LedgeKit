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
    public init(_ id: String, title: String, role: Role = .normal, symbol: String? = nil, accessibilityLabel: String? = nil) {
        self.id = id; self.title = title; self.role = role; self.symbol = symbol; self.accessibilityLabel = accessibilityLabel
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

extension PageNode {
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
