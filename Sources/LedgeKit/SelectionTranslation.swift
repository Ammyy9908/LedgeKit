import Foundation

/// The languages for Ledge's on-device selection translator. Needs LedgeKit 0.24.0 and macOS 15.
/// Ledge reads the selection, draws the card, translates, and handles Copy/Replace; selected text never goes
/// to the add-on. No text is kept after dismissal. Language models may need a system-approved download.
public struct SelectionTranslation: Codable, Sendable, Equatable {
    public static let capability = "selection-translation"
    /// A BCP-47 language identifier, such as `en` or `zh-Hans`.
    public var target: String
    /// Used when the source is already in the target language. Must be a different language.
    public var secondary: String
    /// Shows a small Translate button after a mouse selection. Off by default; never enable without user opt-in.
    public var selectionButton: Bool

    public init(target: String, secondary: String, selectionButton: Bool = false) {
        self.target = target
        self.secondary = secondary
        self.selectionButton = selectionButton
    }

    public func validate() throws {
        for code in [target, secondary] {
            let parts = code.split(separator: "-", omittingEmptySubsequences: false)
            guard code.count <= 35, let first = parts.first, (2...3).contains(first.count),
                  parts.allSatisfy({ !$0.isEmpty && $0.count <= 8 && $0.allSatisfy({ $0.isASCII && $0.isLetter }) }) else {
                throw SurfaceValidationError.invalid("Translation languages must be BCP-47 language identifiers.")
            }
        }
        guard target.split(separator: "-").first?.lowercased() != secondary.split(separator: "-").first?.lowercased() else {
            throw SurfaceValidationError.invalid("Choose two different translation languages.")
        }
    }
}

extension LedgeHost.Method {
    public static let configureTranslation = "ledge.translation.configure"
    public static let translateSelection = "ledge.translation.show"
}

extension LedgeHost {
    /// Sets the languages and optional selection button; nil disables it and dismisses its card.
    /// Requires `selection-translation`. Configuration doesn't read selected text. Ledge drops it when the
    /// session ends or the capability is revoked. The optional button requires Accessibility.
    public static func configureTranslation(_ options: SelectionTranslation?) async throws {
        try options?.validate()
        let value = try options.map { try JSONValue(encoding: $0) } ?? .null
        _ = try await call(Method.configureTranslation, ["options": value])
    }

    /// Translates the current app's selection in a floating card. Requires `selection-translation`, Accessibility
    /// and a recent explicit user action, such as the add-on's shortcut. Secure fields and oversized selections
    /// are refused. Copy and Replace are always user actions; Replace rechecks the original app and selection.
    /// Returns once the card opens, not when translation finishes; errors and language downloads appear in it.
    public static func translateSelection() async throws {
        _ = try await call(Method.translateSelection, [:])
    }
}
