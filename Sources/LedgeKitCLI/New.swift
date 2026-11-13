import AppKit
import Foundation
import LedgeKit

// ledgekit new: a working add-on in a new folder, laid out the way LedgeAddOns takes it.
//
// The add-on is split in two: <Name>Core holds its state and builds what Ledge shows, so tests can check every
// surface against Ledge's own limits without Ledge; the executable only runs the session and sends what Core builds.

func newAddOn(_ given: [String]) throws {
    var arguments = given
    let display = option("--name", in: &arguments)
    let into = option("--into", in: &arguments)
    let page = flag("--page", in: &arguments)
    let activity = flag("--activity", in: &arguments)
    // A widget unless something else was asked for, so a bare `ledgekit new` still shows something.
    let widget = flag("--widget", in: &arguments) || (!page && !activity)
    guard arguments.count == 1, let id = arguments.first else {
        throw CLIError("Usage: ledgekit new <id> [--name \"Name\"] [--page] [--widget] [--activity] [--into <folder>]")
    }
    guard !id.isEmpty, id.count <= 64, id.first?.isLetter == true,
          id.allSatisfy({ $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-") }), !id.hasSuffix("-") else {
        throw CLIError("An id is lowercase letters, digits and hyphens, starting with a letter, like battery-cycles. It's permanent once published.")
    }
    let type = id.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
    let name = display ?? id.split(separator: "-").enumerated()
        .map { $0.offset == 0 ? $0.element.prefix(1).uppercased() + $0.element.dropFirst() : String($0.element) }
        .joined(separator: " ")
    let folder = URL(fileURLWithPath: into ?? id, isDirectory: true).standardizedFileURL
    guard !FileManager.default.fileExists(atPath: folder.path) else {
        throw CLIError("\(folder.path) already exists. Choose another id, or --into a new folder.")
    }
    let author = (try? output("git", ["config", "user.name"])).flatMap { $0.isEmpty ? nil : $0 } ?? "Your name"

    let scaffold = Scaffold(id: id, type: type, name: name, author: author, page: page, widget: widget, activity: activity)
    for (path, text) in scaffold.files {
        let file = folder.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
    }
    try FileManager.default.createDirectory(at: folder.appendingPathComponent("Assets"), withIntermediateDirectories: true)
    try drawPlaceholderIcon(to: folder.appendingPathComponent("Assets/Icon.png"))
    try FileManager.default.createDirectory(at: folder.appendingPathComponent("Store"), withIntermediateDirectories: true)
    // The brief and MCP wiring for a coding agent, kept out of git and of a submission.
    for (path, text) in agentFiles(for: folder) {
        let file = folder.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
    }
    try ignoreLocalFiles(in: folder)

    print("""
    Wrote \(name) (\(id)) in \(folder.path)

    Next:
      cd \(folder.lastPathComponent)
      swift test          # Core's tests, including every surface against Ledge's limits
      ledgekit build      # a .ledgeaddon to load in Ledge: Settings, Add-on Store, Load Add-on…
      ledgekit validate   # what LedgeAddOns checks

    A coding agent reads AGENTS.md (Claude Code: CLAUDE.md) and gets the loop as tools from .mcp.json.

    Before you submit, replace what's yours to write: summary and description in addon.json, the listing,
    README.md, the first CHANGELOG.md entry, Assets/Icon.png (a placeholder), and screenshots in Store/.
    """)
}

/// The files of a new add-on, by path.
private struct Scaffold {
    let id, type, name, author: String
    let page, widget, activity: Bool

    var surfaces: [String] {
        ["settings-page"] + (widget ? ["widget"] : []) + (page ? ["notch-page"] : []) + (activity ? ["activity"] : [])
    }

    var files: [(String, String)] {
        [
            ("Package.swift", packageSwift),
            ("Sources/\(type)Core/\(type)Model.swift", core),
            ("Sources/\(type)/main.swift", main),
            ("Tests/\(type)Tests/\(type)Tests.swift", tests),
            ("addon.json", manifest),
            ("listing.json", listing),
            ("README.md", readme),
            ("CHANGELOG.md", changelog),
            (".gitignore", ".build/\n.swiftpm/\n*.ledgeaddon\nshots/\n"),
        ]
    }

    var packageSwift: String {
        """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "\(type)",
            platforms: [.macOS(.v14)],
            dependencies: [.package(url: "https://github.com/Ammyy9908/LedgeKit.git", exact: "\(SessionProtocol.apiLevel)")],
            targets: [
                // What the add-on knows and what it shows, testable without Ledge.
                .target(name: "\(type)Core", dependencies: [.product(name: "LedgeKit", package: "LedgeKit")]),
                // The program Ledge runs: a session that sends what Core builds.
                .executableTarget(name: "\(type)", dependencies: ["\(type)Core", .product(name: "LedgeKit", package: "LedgeKit")]),
                .testTarget(name: "\(type)Tests", dependencies: ["\(type)Core", .product(name: "LedgeKit", package: "LedgeKit")]),
            ]
        )

        """
    }

    var manifest: String {
        let object: [String: Any] = [
            "id": id, "version": "0.1.0", "protocolVersion": SessionProtocol.version, "name": name,
            "summary": "One line about what \(name) does",
            "description": "What \(name) does, what it shows and where, and what it needs. Replace this.",
            "author": author, "capabilities": [String](), "surfaces": surfaces, "executable": type,
            "icon": "Assets/Icon.png", "kit": ["minAPI": SessionProtocol.apiLevel], "category": "Productivity",
        ]
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    var listing: String {
        """
        {
          "developer": "\(author)",
          "category": "Productivity",
          "availability": "Free · needs a Ledge with LedgeKit \(SessionProtocol.apiLevel) · macOS 14 or later",
          "description": "Describe what \(name) does, how to set it up, and what it doesn't do.",
          "feedbackURL": "https://github.com/Ammyy9908/LedgeAddOns/issues/new",
          "screenshots": []
        }

        """
    }

    var readme: String {
        """
        # \(name)

        What \(name) does, for someone deciding whether to install it. Replace this.

        ## Setting it up

        What to turn on, and where.

        ## What it asks for

        \(surfaces.map { "- The `\($0)` surface." }.joined(separator: "\n"))

        ## What it doesn't do

        Say what someone might expect and won't find.

        """
    }

    var changelog: String {
        """
        # Changelog

        Newest version first. Every new `version` in addon.json needs an entry here.

        ## 0.1.0

        - Say what \(name) does in its first release, not only "First release".

        """
    }

    var core: String {
        var parts: [String] = []
        if widget {
            parts.append("""

                /// The widget on the open notch's Widgets page.
                public func widget() -> Widget {
                    Widget("main", title: "\(name)", symbol: "sparkles", content: .vstack(spacing: 8, children: [
                        .text("\\(count)", style: .title),
                        .hstack(spacing: 8, children: [
                            .button(id: "add", title: "Add one", symbol: "plus"),
                            .button(id: "reset", title: "Reset", symbol: "arrow.counterclockwise"),
                        ]),
                    ]))
                }
            """)
        }
        if page {
            parts.append("""

                /// The add-on's page in the open notch.
                public func page() -> NotchPage {
                    let content: PageNode = count == 0
                        ? .empty(symbol: "sparkles", title: "Nothing yet", detail: "Press plus to add one")
                        : .text("\\(count)", style: .title)
                    return NotchPage(title: "\(name)", symbol: "sparkles", size: .small, screen: PageScreen("main", title: "\(name)",
                        actions: [PageAction("add", symbol: "plus", label: "Add one")], content: content))
                }
            """)
        }
        if activity {
            parts.append("""

                /// Beside the notch while the count isn't zero; taken down when it is.
                public func activities() -> [LiveActivity] {
                    count == 0 ? [] : [LiveActivity("count", symbol: "sparkles", text: "\\(count)")]
                }
            """)
        }
        return """
        import Foundation
        import LedgeKit

        /// What \(name) knows, and what it shows from that. Here it's a count the user can raise; replace it with yours.
        /// Everything Ledge draws is built here, so the tests can check it against Ledge's limits.
        public struct \(type)Model: Sendable, Equatable {
            public private(set) var count = 0

            public init(count: Int = 0) {
                self.count = count
            }

            /// Applies a press. Returns true when something changed and the surfaces need sending again.
            public mutating func handle(_ event: SurfaceEvent) -> Bool {
                switch (event.control, event.action) {
                case ("add", .pressed):
                    count += 1
                    return true
                case ("reset", .pressed):
                    count = 0
                    return true
                default:
                    return false
                }
            }

            /// The add-on's page in Ledge's Settings.
            public func settingsPage() -> SettingsPage {
                SettingsPage([
                    SettingsSection("main", title: "\(name)", footer: "Say what \(name) keeps, and that it stays on this Mac.", rows: [
                        .value("count", "Count", "\\(count)"),
                        .button("reset", "Reset", destructive: true,
                                confirm: .init("Reset the count?", message: "It goes back to zero.", confirmTitle: "Reset")),
                    ]),
                ])
            }
        \(parts.joined(separator: "\n"))
        }

        """
    }

    var main: String {
        var sends = ["        AddOnSession.show(model.settingsPage())"]
        if widget { sends.append("        AddOnSession.show(widgets: [model.widget()])") }
        if page { sends.append("        AddOnSession.show(notchPage: model.page())") }
        if activity { sends.append("        AddOnSession.show(activities: model.activities())") }
        return """
        import Foundation
        import LedgeKit
        import \(type)Core

        // \(name): the program Ledge runs. It keeps the model and sends what the model builds whenever it changes.

        actor \(type) {
            private var model = \(type)Model()

            func start() {
                send()
            }

            func handle(_ event: SurfaceEvent) {
                if model.handle(event) { send() }
            }

            /// Which of the add-on's surfaces are on screen changed. Refresh what's seen while it's seen.
            func visibilityChanged(_ visibility: SurfaceVisibility) {}

            private func send() {
        \(sends.joined(separator: "\n"))
            }
        }

        let addOn = \(type)()
        var handlers = AddOnHandlers()
        handlers.activate = { await addOn.start() }
        handlers.onEvent = { event in await addOn.handle(event) }
        handlers.onVisibilityChange = { visibility in await addOn.visibilityChanged(visibility) }
        exit(await AddOnSession.run(id: "\(id)", handlers: handlers))

        """
    }

    var tests: String {
        var checks = ["    try model.settingsPage().validate()"]
        if widget { checks.append("    try model.widget().validate()") }
        if page { checks.append("    try model.page().validate()") }
        if activity { checks.append("    try LiveActivity.validate(model.activities())") }
        return """
        import LedgeKit
        import Testing
        @testable import \(type)Core

        private func press(_ control: String, _ surface: String = Surface.widget) -> SurfaceEvent {
            SurfaceEvent(surface: surface, control: control, action: .pressed)
        }

        @Test func pressesChangeTheCount() {
            var model = \(type)Model()
            let added = [model.handle(press("add")), model.handle(press("add"))]
            #expect(added == [true, true])
            #expect(model.count == 2)
            let reset = model.handle(press("reset", Surface.settingsPage))
            #expect(reset && model.count == 0)
            let ignored = model.handle(press("unknown"))
            #expect(!ignored)
        }

        /// Ledge refuses a surface over its limits and draws nothing, so check every one, empty and full.
        @Test(arguments: [0, 1, 99_999])
        func everySurfaceIsOneLedgeDraws(count: Int) throws {
            let model = \(type)Model(count: count)
        \(checks.joined(separator: "\n"))
        }

        """
    }
}

/// A plain icon so the package builds and loads. Replace it with the add-on's own before submitting.
private func drawPlaceholderIcon(to file: URL) throws {
    guard let png = placeholderIcon().representation(using: .png, properties: [:]) else { throw CLIError("Couldn't save the icon.") }
    try png.write(to: file)
}

/// The placeholder icon, drawn at 1024 pixels.
func placeholderIcon() -> NSBitmapImageRep {
    let size = 1024
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let side = CGFloat(size)
    NSColor(white: 0.165, alpha: 1).setFill()
    NSBezierPath(roundedRect: CGRect(x: 0, y: 0, width: side, height: side), xRadius: side * 0.22, yRadius: side * 0.22).fill()
    let config = NSImage.SymbolConfiguration(pointSize: 460, weight: .semibold).applying(.init(paletteColors: [NSColor(white: 0.62, alpha: 1)]))
    if let glyph = NSImage(systemSymbolName: "puzzlepiece.extension.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let scale = min(520 / glyph.size.width, 520 / glyph.size.height)
        let w = glyph.size.width * scale, h = glyph.size.height * scale
        glyph.draw(in: CGRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// Whether an icon is still the placeholder: both shrunk to 16 pixels, they differ by almost nothing. Small
/// changes in how macOS draws the symbol don't hide it; any real icon does.
func isPlaceholderIcon(_ icon: NSImageRep) -> Bool {
    func tiny(_ image: NSImageRep) -> [UInt8] {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 64, bitsPerPixel: 32)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: CGRect(x: 0, y: 0, width: 16, height: 16))
        NSGraphicsContext.restoreGraphicsState()
        return Array(UnsafeBufferPointer(start: rep.bitmapData, count: 16 * 64))
    }
    let a = tiny(icon), b = tiny(placeholderIcon())
    let difference = zip(a, b).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
    return Double(difference) / Double(a.count) < 3
}
