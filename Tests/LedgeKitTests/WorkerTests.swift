import Foundation
import Testing
import LedgeKit

@Test func workerDispatchesCompatibleRequest() async throws {
    let input = try JSONEncoder().encode(AddOnRequest(operation: "read", trackID: "123", liked: nil, accessToken: "fixture"))
    let response = await AddOnWorker.respond(to: input) { request in
        #expect(request.trackID == "123")
        return AddOnResponse(value: true)
    }
    #expect(response.value == true)
    #expect(response.error == nil)
}

@Test func workerRejectsMalformedAndOversizedInput() async {
    for data in [Data("invalid".utf8), Data(repeating: 32, count: AddOnWorker.maximumRequestBytes + 1)] {
        let response = await AddOnWorker.respond(to: data) { _ in
            Issue.record("Invalid input reached handler")
            return AddOnResponse(value: true)
        }
        #expect(response.value == nil)
        #expect(response.error != nil)
    }
}

@Test func workerRejectsFutureProtocol() async {
    let data = Data(#"{"protocolVersion":2,"operation":"read","trackID":"1","accessToken":"fixture"}"#.utf8)
    let response = await AddOnWorker.respond(to: data) { _ in
        Issue.record("Unsupported protocol reached handler")
        return AddOnResponse(value: true)
    }
    #expect(response.error == "Unsupported protocol version.")
}

@Test func workerRedactsHandlerErrors() async throws {
    let input = try JSONEncoder().encode(AddOnRequest(operation: "read", trackID: "1", liked: nil, accessToken: "fixture"))
    let response = await AddOnWorker.respond(to: input) { _ in
        throw NSError(domain: "secret-token", code: 1)
    }
    #expect(response.error == "Add-on could not complete the request.")
}
