import Foundation
import Testing
import LedgeKit

private struct Echo: Codable, Sendable, Equatable { let text: String }

/// Runs a session against scripted input and returns the exit status and every message the add-on wrote.
private func session(_ handlers: AddOnHandlers, id: String = "example", messages: [SessionMessage]) async -> (Int32, [SessionMessage]) {
    let collected = Collected()
    let input = AsyncThrowingStream<Data, Error> { continuation in
        for message in messages { continuation.yield(try! JSONEncoder().encode(message)) }
        continuation.finish()
    }
    let status = await AddOnSession.run(id: id, handlers: handlers, input: input) { data in
        await collected.add(try! JSONDecoder().decode(SessionMessage.self, from: data.dropLast()))
    }
    // Requests answer from their own tasks; give them a moment to finish writing.
    try? await Task.sleep(nanoseconds: 50_000_000)
    return (status, await collected.messages)
}

private actor Collected {
    var messages: [SessionMessage] = []
    func add(_ message: SessionMessage) { messages.append(message) }
}

private let hello = SessionMessage.hello(protocolVersion: 2, apiLevel: SessionProtocol.apiLevel, addOnID: "example", generation: 1)

@Test func frameReaderSplitsLinesAcrossChunks() throws {
    var reader = SessionFrameReader(limit: 16)
    #expect(try reader.feed(Data("{\"a\":".utf8)) == [])
    #expect(try reader.feed(Data("1}\n\n{\"b\":2}\n".utf8)) == [Data("{\"a\":1}".utf8), Data("{\"b\":2}".utf8)])
}

@Test func frameReaderRefusesAnOversizedLineBeforeItEnds() {
    var reader = SessionFrameReader(limit: 8)
    #expect(throws: SessionFramingError.messageTooLarge) { try reader.feed(Data(repeating: 0x61, count: 9)) }
}

@Test func messagesRoundTrip() throws {
    let messages: [SessionMessage] = [
        hello,
        .ready(protocolVersion: 2, apiLevel: "0.3.0", addOnID: "example"),
        .request(id: 3, method: "echo", params: .object(["text": .string("line\nbreak")])),
        .response(id: 3, result: .array([.null, .bool(true), .number(1.5)]), error: nil),
        .response(id: 4, result: nil, error: "Nope"),
        .log(level: .info, message: "hi"),
        .update(topic: "widget", payload: .object([:]))
    ]
    for message in messages {
        let line = try message.encodedLine()
        #expect(line.last == 0x0A)
        #expect(line.dropLast().contains(0x0A) == false)
        #expect(try JSONDecoder().decode(SessionMessage.self, from: line.dropLast()) == message)
    }
}

@Test func responseWithBothResultAndErrorIsRefused() {
    let data = Data(#"{"type":"response","id":1,"result":true,"error":"x"}"#.utf8)
    #expect(throws: (any Error).self) { try JSONDecoder().decode(SessionMessage.self, from: data) }
}

@Test func sessionHandshakesActivatesAndAnswersRequests() async {
    var handlers = AddOnHandlers()
    handlers.on("echo") { (request: Echo) in Echo(text: request.text.uppercased()) }
    let (status, out) = await session(handlers, messages: [
        hello,
        .request(id: 1, method: SessionProtocol.Method.activate, params: .null),
        .request(id: 2, method: "echo", params: .object(["text": .string("hi")]))
    ])
    #expect(status == 0)
    #expect(out.first == .ready(protocolVersion: 2, apiLevel: SessionProtocol.apiLevel, addOnID: "example"))
    #expect(out.contains(.response(id: 1, result: .bool(true), error: nil)))
    #expect(out.contains(.response(id: 2, result: .object(["text": .string("HI")]), error: nil)))
}

@Test func sessionRefusesAnotherAddOnsHello() async {
    let (status, out) = await session(AddOnHandlers(), messages: [
        .hello(protocolVersion: 2, apiLevel: SessionProtocol.apiLevel, addOnID: "someone-else", generation: 1)
    ])
    #expect(status == AddOnSession.protocolFailure)
    #expect(out.isEmpty)
}

@Test func requestsBeforeActivationAndUnknownMethodsGetErrors() async {
    var handlers = AddOnHandlers()
    handlers.on("echo") { (request: Echo) in request }
    let (_, out) = await session(handlers, messages: [
        hello,
        .request(id: 1, method: "echo", params: .object(["text": .string("early")])),
        .request(id: 2, method: SessionProtocol.Method.activate, params: .null),
        .request(id: 3, method: "missing", params: .null)
    ])
    #expect(out.contains(.response(id: 1, result: nil, error: "The add-on isn't active.")))
    #expect(out.contains(.response(id: 3, result: nil, error: "This add-on doesn't handle missing.")))
}

@Test func handlerErrorsStayGenericUnlessMarkedSafe() async {
    struct Secret: Error {}
    var handlers = AddOnHandlers()
    handlers.on("leaky") { (_: Echo) -> Echo in throw Secret() }
    handlers.on("safe") { (_: Echo) -> Echo in throw AddOnError("Spotify isn't connected.") }
    let params = JSONValue.object(["text": .string("x")])
    let (_, out) = await session(handlers, messages: [
        hello,
        .request(id: 1, method: SessionProtocol.Method.activate, params: .null),
        .request(id: 2, method: "leaky", params: params),
        .request(id: 3, method: "safe", params: params)
    ])
    #expect(out.contains(.response(id: 2, result: nil, error: "Add-on could not complete the request.")))
    #expect(out.contains(.response(id: 3, result: nil, error: "Spotify isn't connected.")))
}

@Test func closingInputDeactivatesAnActiveSession() async {
    let deactivated = Collected()
    var handlers = AddOnHandlers()
    handlers.deactivate = { await deactivated.add(.log(level: .info, message: "stopped")) }
    let (status, _) = await session(handlers, messages: [hello, .request(id: 1, method: SessionProtocol.Method.activate, params: .null)])
    #expect(status == 0)
    #expect(await deactivated.messages.count == 1)
}

@Test func prepareForRemovalCanRefuse() async {
    var handlers = AddOnHandlers()
    handlers.prepareForRemoval = { false }
    let (_, out) = await session(handlers, messages: [hello, .request(id: 9, method: SessionProtocol.Method.prepareForRemoval, params: .null)])
    #expect(out.contains(.response(id: 9, result: .bool(false), error: nil)))
}
