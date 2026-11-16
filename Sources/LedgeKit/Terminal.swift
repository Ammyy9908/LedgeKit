import Foundation

// A terminal in the notch (LedgeKit 0.18.0). The add-on runs a program on a pseudo-terminal, usually the person's
// shell, and Ledge draws its screen: Ledge sends what the person types and the terminal's size, and the add-on sends
// back what the program writes. Ledge never starts a program itself. Declare `"terminal"` in the manifest's surfaces
// and in its capabilities, since the person approves an add-on that runs programs as them before it starts.
// `AddOnTerminal` does the pseudo-terminal work; see it for a whole add-on in a few lines.
//
// What the person types arrives in `AddOnHandlers.onTerminalInput`, in order. It's theirs: never log it, store it or
// send it anywhere. The program's output goes to Ledge with `AddOnSession.terminal(output:)`, in order.

extension Surface {
    /// A terminal page in the open notch. Needs 0.18.0, and `"terminal"` in the manifest's capabilities too.
    public static let terminal = "terminal"
    /// The capability a terminal needs: running programs as the person.
    public static let terminalCapability = "terminal"
    /// The program's output, in order, as `TerminalOutput`.
    public static let terminalOutputTopic = "terminal.output"
    /// The terminal's title and folder, as `TerminalState`.
    public static let terminalStateTopic = "terminal.state"
    /// Ledge sends what the person typed or pasted, as `TerminalOutput`'s bytes. Answered in order.
    public static let terminalInputMethod = "ledge.terminalInput"
    /// Ledge sends the terminal's size in characters whenever it changes, first when the page first shows.
    public static let terminalResizeMethod = "ledge.terminalResize"
    /// The most output one update carries. `AddOnSession.terminal(output:)` splits larger writes.
    public static let maximumTerminalChunk = 32_768
    /// Sizes Ledge sends and accepts.
    public static let maximumTerminalColumns = 500
    public static let maximumTerminalRows = 200
}

/// Bytes on the terminal, in either direction: what the program wrote, or what the person typed.
public struct TerminalOutput: Codable, Sendable, Equatable {
    public var data: Data

    public init(_ data: Data) { self.data = data }

    public func validate() throws {
        guard data.count <= Surface.maximumTerminalChunk else {
            throw SurfaceValidationError.invalid("terminal output: at most \(Surface.maximumTerminalChunk) bytes in one update")
        }
    }
}

/// The terminal's size in characters.
public struct TerminalSize: Codable, Sendable, Equatable {
    public var columns: Int
    public var rows: Int

    public init(columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
    }

    public func validate() throws {
        guard (1...Surface.maximumTerminalColumns).contains(columns), (1...Surface.maximumTerminalRows).contains(rows) else {
            throw SurfaceValidationError.invalid("terminal size: 1 to \(Surface.maximumTerminalColumns) columns, 1 to \(Surface.maximumTerminalRows) rows")
        }
    }
}

/// What Ledge shows around the terminal: the folder the program is in, in the page's corner, and whether it's
/// running. Send it when either changes.
public struct TerminalState: Codable, Sendable, Equatable {
    /// An absolute path, like the shell's working folder. Ledge shows the end of it, and its "Open in" button
    /// opens it in the person's terminal app.
    public var folder: String?
    /// False once the program has ended. Ledge says so, and the next key the person presses is sent as usual, so
    /// the add-on can start a new one.
    public var running: Bool

    public init(folder: String? = nil, running: Bool = true) {
        self.folder = folder
        self.running = running
    }

    public func validate() throws {
        if let folder {
            guard folder.hasPrefix("/"), folder.utf8.count <= 1024, !folder.contains("\0") else {
                throw SurfaceValidationError.invalid("terminal folder: an absolute path, at most 1024 bytes")
            }
        }
    }
}
