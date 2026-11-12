import Foundation
import Testing
import LedgeKit

/// Plays Ledge: answers the add-on's calls through the input it feeds the session.
private actor FakeLedge {
    var calls: [String] = []
    let input: AsyncThrowingStream<Data, Error>.Continuation
    init(_ input: AsyncThrowingStream<Data, Error>.Continuation) { self.input = input }

    func received(_ line: Data) {
        guard case let .request(id, method, params)? = try? JSONDecoder().decode(SessionMessage.self, from: line.dropLast()) else { return }
        calls.append(method)
        let reply: SessionMessage
        switch method {
        case LedgeHost.Method.settingsGet:
            reply = .response(id: id, result: params == .object(["key": .string("city")]) ? .string("Pune") : .null, error: nil)
        case LedgeHost.Method.copy:
            reply = .response(id: id, result: nil, error: "This add-on can't use the clipboard.")
        default:
            reply = .response(id: id, result: .bool(true), error: nil)
        }
        input.yield(try! JSONEncoder().encode(reply))
    }

    func send(_ message: SessionMessage) { input.yield(try! JSONEncoder().encode(message)) }
    func finish() { input.finish() }
}

private actor Results {
    var values: [String] = []
    func add(_ value: String) { values.append(value) }
}

@Test func activateCanCallLedgeAndRefusalsThrow() async throws {
    let (input, continuation) = AsyncThrowingStream<Data, Error>.makeStream()
    let ledge = FakeLedge(continuation)
    let results = Results()
    var handlers = AddOnHandlers()
    handlers.activate = {
        // Waiting on Ledge inside activate must not block the session from reading the answer.
        await results.add(try await LedgeHost.value(String.self, forKey: "city") ?? "none")
        await results.add(try await LedgeHost.value(String.self, forKey: "missing") ?? "none")
        try await LedgeHost.set(["a": 1], forKey: "prefs")
        do {
            try await LedgeHost.copy("hi")
        } catch let error as LedgeHostError {
            await results.add("refused: " + error.message)
        }
    }
    let session = Task {
        await AddOnSession.run(id: "moon", handlers: handlers, input: input) { line in await ledge.received(line) }
    }
    await ledge.send(.hello(protocolVersion: 2, apiLevel: SessionProtocol.apiLevel, addOnID: "moon", generation: 1))
    await ledge.send(.request(id: 1, method: SessionProtocol.Method.activate, params: .null))
    for _ in 0..<200 where await results.values.count < 3 { try await Task.sleep(nanoseconds: 10_000_000) }
    await ledge.finish()
    _ = await session.value
    #expect(await results.values == ["Pune", "none", "refused: This add-on can't use the clipboard."])
    #expect(await ledge.calls == [LedgeHost.Method.settingsGet, LedgeHost.Method.settingsGet, LedgeHost.Method.settingsSet, LedgeHost.Method.copy])
}

@Test func callsOutsideASessionFail() async {
    await #expect(throws: LedgeHostError.self) { _ = try await LedgeHost.environment() }
}
