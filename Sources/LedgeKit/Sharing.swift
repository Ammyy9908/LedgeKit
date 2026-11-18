import Foundation

// Sharing files with an add-on, and handing files back (LedgeKit 0.20.0), for add-ons that send files somewhere:
// to a phone on the same network, a cloud folder, a printer.
//
// The person shares: they choose "Send with ‹title›" and one of the add-on's destinations on a shelf item, or drop
// files on a notch page list row that accepts them. Either way `AddOnHandlers.onShare` gets the destination's id
// and the files. Both need the `shared-files` capability. The add-on publishes its destinations with
// `AddOnSession.show(shareTarget:)`, and the `share-target` surface.
//
// `LedgeHost.addToShelf(_:)` puts files the add-on received on the person's shelf (`shelf-add`), and
// `LedgeHost.ask(_:)` asks the person a yes-or-no question in the notch, such as whether to accept a transfer
// (`questions`). An add-on that talks to other devices on the network declares `local-network`, so the person sees
// it before installing.

extension Surface {
    /// The add-on's destinations in the shelf's share menu. Needs 0.20.0 and the `shared-files` capability.
    public static let shareTarget = "share-target"
    public static let shareTargetTopic = "surface.shareTarget"
    /// Ledge hands the add-on files the person shared, as `SharedFiles`.
    public static let sharedMethod = "ledge.shared"
    /// Files the person chooses to share: from the shelf's menu, or dropped on a list row.
    public static let sharedFilesCapability = "shared-files"
    /// Putting files on the person's shelf.
    public static let shelfAddCapability = "shelf-add"
    /// Asking the person a yes-or-no question in the notch.
    public static let questionsCapability = "questions"
    /// Finding and talking to other devices on the local network. Ledge can't hold an add-on to it; it's declared so
    /// the person knows before installing.
    public static let localNetworkCapability = "local-network"
    public static let maximumShareDestinations = 24
    public static let maximumSharedFiles = 100
}

/// Where the add-on can send files, listed under "Send with ‹title›" on a shelf item. Send it again as destinations
/// come and go, such as devices appearing on the network; send nil to take the menu away.
public struct ShareTarget: Codable, Sendable, Equatable {
    /// What follows "Send with", like "LocalSend".
    public var title: String
    /// An SF Symbol for the menu item.
    public var symbol: String?
    /// The choices under it, such as nearby devices. With none, the item shows dimmed with `emptyNote`.
    public var destinations: [ShareDestination]
    /// What the dimmed item says while there are no destinations, like "No devices nearby".
    public var emptyNote: String?

    public init(title: String, symbol: String? = nil, destinations: [ShareDestination], emptyNote: String? = nil) {
        self.title = title
        self.symbol = symbol
        self.destinations = destinations
        self.emptyNote = emptyNote
    }

    public func validate() throws {
        func invalid(_ reason: String) -> SurfaceValidationError { .invalid("share target: \(reason)") }
        guard !title.isEmpty, title.count <= 40, (emptyNote?.count ?? 0) <= 80 else {
            throw invalid("a title of 1 to 40 characters, and a note of at most 80")
        }
        guard destinations.count <= Surface.maximumShareDestinations else {
            throw invalid("at most \(Surface.maximumShareDestinations) destinations")
        }
        guard Set(destinations.map(\.id)).count == destinations.count else { throw invalid("each destination id once") }
        for destination in destinations {
            guard !destination.id.isEmpty, destination.id.count <= 64, !destination.title.isEmpty, destination.title.count <= 60,
                  (destination.subtitle?.count ?? 0) <= 80 else {
                throw invalid("a destination's id, title and subtitle: at most 64, 60 and 80 characters")
            }
        }
    }
}

/// One place to send to, such as a phone.
public struct ShareDestination: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    /// A grey line, such as "iPhone · 192.168.1.20".
    public var subtitle: String?
    /// An SF Symbol, such as "iphone" or "desktopcomputer".
    public var symbol: String?

    public init(_ id: String, title: String, subtitle: String? = nil, symbol: String? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
    }
}

/// Files the person shared with the add-on: chosen from the shelf's menu, or dropped on a list row.
public struct SharedFiles: Codable, Sendable, Equatable {
    /// The `ShareDestination` they chose, or the id of the list row they dropped on.
    public var destination: String
    /// The files' paths. Read them now: the person may move or delete them afterwards.
    public var files: [String]

    public init(destination: String, files: [String]) {
        self.destination = destination
        self.files = files
    }

    public var urls: [URL] { files.map { URL(fileURLWithPath: $0) } }

    public func validate() throws {
        guard !destination.isEmpty, destination.count <= 64, !files.isEmpty, files.count <= Surface.maximumSharedFiles,
              files.allSatisfy({ $0.hasPrefix("/") }) else {
            throw SurfaceValidationError.invalid("shared files: a destination and 1 to \(Surface.maximumSharedFiles) absolute paths")
        }
    }
}

/// A yes-or-no question for `LedgeHost.ask(_:)`, such as "Accept 3 files from Pixel 9?".
public struct HostQuestion: Codable, Sendable, Equatable {
    public var title: String
    /// More about it, such as the file names and their size.
    public var message: String?
    /// The button that answers yes, like "Accept".
    public var accept: String
    /// The button that answers no, like "Decline".
    public var decline: String
    /// How long Ledge waits before it counts as no, from 5 to 120 seconds.
    public var timeout: TimeInterval

    public init(title: String, message: String? = nil, accept: String, decline: String = "Decline", timeout: TimeInterval = 60) {
        self.title = title
        self.message = message
        self.accept = accept
        self.decline = decline
        self.timeout = timeout
    }

    public func validate() throws {
        guard !title.isEmpty, title.count <= 120, (message?.count ?? 0) <= 500, !accept.isEmpty, accept.count <= 30,
              !decline.isEmpty, decline.count <= 30, (5...120).contains(timeout) else {
            throw SurfaceValidationError.invalid("question: a title of at most 120 characters, a message of at most 500, buttons of at most 30, and 5 to 120 seconds")
        }
    }
}

extension PageNode {
    /// Every list row in the node, however deep.
    public var listRows: [ListRow] {
        switch self {
        case .vstack(_, let children), .hstack(_, let children): children.flatMap(\.listRows)
        case .list(_, let rows): rows
        default: []
        }
    }

    /// Whether a slider is anywhere in it, which needs 0.22.0.
    public var hasSlider: Bool {
        switch self {
        case .vstack(_, let children), .hstack(_, let children): children.contains(where: \.hasSlider)
        case .slider: true
        default: false
        }
    }

    /// Whether an image is anywhere in it, which needs 0.21.0.
    public var hasImage: Bool {
        switch self {
        case .vstack(_, let children), .hstack(_, let children): children.contains(where: \.hasImage)
        case .image: true
        default: false
        }
    }
}

extension WidgetNode {
    /// Whether a slider or an image is anywhere in it, which needs 0.22.0.
    public var needsSliderOrImage: Bool {
        switch self {
        case .vstack(_, let children), .hstack(_, let children): children.contains(where: \.needsSliderOrImage)
        case .slider, .image: true
        default: false
        }
    }
}
