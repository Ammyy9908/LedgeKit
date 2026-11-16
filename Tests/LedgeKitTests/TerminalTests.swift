import Foundation
import Testing
import LedgeKit

/// Collects a terminal's output until it holds `text`, or a few seconds pass.
private final class Screen: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes = Data()
    private var exits: [Int32] = []
    var text: String { lock.withLock { String(decoding: bytes, as: UTF8.self) } }
    var exitCodes: [Int32] { lock.withLock { exits } }
    func add(_ data: Data) { lock.withLock { bytes.append(data) } }
    func exited(_ code: Int32) { lock.withLock { exits.append(code) } }

    func waitFor(_ text: String, seconds: Double = 5) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if self.text.contains(text) { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return false
    }

    func waitForExit(seconds: Double = 5) async -> Int32? {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if let code = exitCodes.first { return code }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return nil
    }
}

private func terminal() -> (AddOnTerminal, Screen) {
    let terminal = AddOnTerminal()
    let screen = Screen()
    terminal.onOutput = { screen.add($0) }
    terminal.onExit = { screen.exited($0) }
    return (terminal, screen)
}

@Suite(.serialized) struct AddOnTerminalTests {
    @Test func aProgramsOutputArrivesAndItsExitIsReported() async throws {
        let (terminal, screen) = terminal()
        try terminal.start(size: .init(columns: 80, rows: 24), program: "/bin/echo", arguments: ["hello from the pty"])
        #expect(await screen.waitFor("hello from the pty"))
        #expect(await screen.waitForExit() == 0)
        #expect(!terminal.isRunning)
    }

    @Test func theProgramSeesTheSizeAndItsChanges() async throws {
        let (terminal, screen) = terminal()
        try terminal.start(size: .init(columns: 100, rows: 30), program: "/bin/sh",
                           arguments: ["-c", "stty size; read line; stty size"])
        #expect(await screen.waitFor("30 100"))
        terminal.resize(.init(columns: 120, rows: 40))
        terminal.write(Data("\r".utf8))
        #expect(await screen.waitFor("40 120"))
        #expect(await screen.waitForExit() == 0)
    }

    @Test func typingReachesTheProgram() async throws {
        let (terminal, screen) = terminal()
        try terminal.start(size: .init(columns: 80, rows: 24), program: "/bin/sh", arguments: ["-c", "read a; echo got:$a"])
        terminal.write(Data("oat milk\r".utf8))
        #expect(await screen.waitFor("got:oat milk"))
        #expect(await screen.waitForExit() == 0)
    }

    @Test func itStartsInTheFolderAndReadsTheFolderBack() async throws {
        let (terminal, screen) = terminal()
        try terminal.start(size: .init(columns: 80, rows: 24), program: "/bin/sh", arguments: ["-c", "pwd; read a"], directory: "/tmp")
        #expect(await screen.waitFor("/tmp"))
        #expect(terminal.folder == "/private/tmp")
        terminal.stop()
        #expect(await screen.waitForExit() != nil)
    }

    @Test func theTerminalLooksLikeOne() async throws {
        let (terminal, screen) = terminal()
        try terminal.start(size: .init(columns: 80, rows: 24), program: "/bin/sh",
                           arguments: ["-c", "echo term=$TERM color=$COLORTERM program=$TERM_PROGRAM; test -t 0 && echo tty=yes"])
        #expect(await screen.waitFor("tty=yes"))
        #expect(screen.text.contains("term=xterm-256color color=truecolor program=Ledge"))
    }

    @Test func stopHangsUpTheProgram() async throws {
        let (terminal, screen) = terminal()
        try terminal.start(size: .init(columns: 80, rows: 24), program: "/bin/sleep", arguments: ["30"])
        #expect(terminal.isRunning)
        terminal.stop()
        #expect(await screen.waitForExit() == 128 + SIGHUP)
    }

    @Test func aSizeOutsideTheLimitsIsRefused() {
        let terminal = AddOnTerminal()
        #expect(throws: (any Error).self) { try terminal.start(size: .init(columns: 0, rows: 24), program: "/bin/echo") }
        #expect(throws: (any Error).self) { try terminal.start(size: .init(columns: 80, rows: 900), program: "/bin/echo") }
    }
}

@Test func terminalMessagesRoundTripAndAreChecked() throws {
    let output = TerminalOutput(Data([0x1b, 0x5b, 0x33, 0x31, 0x6d, 0x00, 0xff]))
    #expect(try JSONDecoder().decode(TerminalOutput.self, from: JSONEncoder().encode(output)) == output)
    #expect(throws: (any Error).self) { try TerminalOutput(Data(count: Surface.maximumTerminalChunk + 1)).validate() }
    try TerminalState(folder: "/Users/a", running: true).validate()
    #expect(throws: (any Error).self) { try TerminalState(folder: "relative/path").validate() }
}

@Test func aTerminalSurfaceNeedsItsCapability() throws {
    func manifest(_ capabilities: [String]) -> AddOnManifest {
        AddOnManifest(id: "terminal", version: "1.0.0", name: "Terminal", summary: "A shell", description: "A shell in the notch.",
                      author: "Ledge", capabilities: capabilities, executable: "Terminal", surfaces: ["terminal"])
    }
    try manifest(["terminal"]).validate()
    #expect(throws: (any Error).self) { try manifest([]).validate() }
}

private actor Lines {
    var messages: [SessionMessage] = []
    func add(_ message: SessionMessage) { messages.append(message) }
}

@Test func aSessionCarriesTypingInAndOutputOutInOrder() async throws {
    let terminal = AddOnTerminal()
    var handlers = AddOnHandlers()
    terminal.connect(&handlers) { terminal, size in try terminal.start(size: size, program: "/bin/cat") }
    let id = "terminal"
    let lines = Lines()
    let keys = (0..<40).map { "line \($0)\r" }
    let input = AsyncThrowingStream<Data, Error> { continuation in
        Task {
            var messages: [SessionMessage] = [
                .hello(protocolVersion: 2, apiLevel: SessionProtocol.apiLevel, addOnID: id, generation: 1),
                .request(id: 1, method: SessionProtocol.Method.activate, params: .null),
                .request(id: 2, method: Surface.terminalResizeMethod, params: try JSONValue(encoding: TerminalSize(columns: 80, rows: 24))),
            ]
            for (index, key) in keys.enumerated() {
                messages.append(.request(id: 10 + index, method: Surface.terminalInputMethod,
                                         params: try JSONValue(encoding: TerminalOutput(Data(key.utf8)))))
            }
            for message in messages { continuation.yield(try JSONEncoder().encode(message)) }
            // Give cat a moment to echo before Ledge ends the session.
            try await Task.sleep(nanoseconds: 800_000_000)
            continuation.finish()
        }
    }
    let status = await AddOnSession.run(id: id, handlers: handlers, input: input) { data in
        await lines.add(try! JSONDecoder().decode(SessionMessage.self, from: data.dropLast()))
    }
    #expect(status == 0)
    var screen = Data()
    for case let .update(topic, payload) in await lines.messages where topic == Surface.terminalOutputTopic {
        screen.append(try payload.decode(TerminalOutput.self).data)
    }
    let text = String(decoding: screen, as: UTF8.self)
    // Every line, in the order typed: the pty echoes each, then cat writes it back.
    var cursor = text.startIndex
    for index in 0..<40 {
        guard let found = text.range(of: "line \(index)\r\n", range: cursor..<text.endIndex) else {
            Issue.record("line \(index) missing or out of order")
            return
        }
        cursor = found.upperBound
    }
    // Turning the add-on off hung up the program.
    for _ in 0..<100 where terminal.isRunning { try await Task.sleep(nanoseconds: 20_000_000) }
    #expect(!terminal.isRunning)
}
