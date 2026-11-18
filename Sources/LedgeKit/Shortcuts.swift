import Foundation

// Shortcuts (LedgeKit 0.22.0): actions an add-on offers on a keyboard shortcut from any app, like muting every
// microphone. The add-on names each action and a letter; the person picks the keys for it in the add-on's Settings
// (Control-Option, Option-Command or Control-Option-Command with that letter), and Ledge sends `pressed` with the
// shortcut's id, on `Surface.shortcut`, when they're pressed. Declare `"shortcut"` in the manifest's surfaces and send
// them with `AddOnSession.show(shortcuts:)`.

extension Surface {
    /// Actions on a keyboard shortcut. Needs 0.22.0.
    public static let shortcut = "shortcut"
    public static let shortcutsTopic = "surface.shortcuts"
    public static let maximumShortcuts = 4
}

/// One action on a shortcut.
public struct AddOnShortcut: Codable, Sendable, Equatable {
    /// Sent back as the event's `control`.
    public var id: String
    /// What it does, shown in Settings beside the keys, like "Mute microphones". Up to 40 characters.
    public var title: String
    /// The letter the shortcut uses, A to Z, like "M".
    public var key: String

    public init(_ id: String, title: String, key: String) {
        self.id = id
        self.title = title
        self.key = key
    }

    public static func validate(_ shortcuts: [AddOnShortcut]) throws {
        guard shortcuts.count <= Surface.maximumShortcuts else {
            throw SurfaceValidationError.tooLarge("more than \(Surface.maximumShortcuts) shortcuts")
        }
        var ids = Set<String>()
        for shortcut in shortcuts {
            guard !shortcut.id.isEmpty, shortcut.id.count <= 64, ids.insert(shortcut.id).inserted else {
                throw SurfaceValidationError.duplicateID(shortcut.id)
            }
            guard !shortcut.title.isEmpty, shortcut.title.count <= 40 else { throw SurfaceValidationError.invalid("title of shortcut \(shortcut.id)") }
            guard shortcut.key.count == 1, let letter = shortcut.key.unicodeScalars.first, ("A"..."Z").contains(letter) else {
                throw SurfaceValidationError.invalid("key of shortcut \(shortcut.id): one letter, A to Z")
            }
        }
    }
}
