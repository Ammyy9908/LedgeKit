import Darwin
import Foundation
import LedgeKit
import Testing
@testable import LedgeKitHost

/// Finds the fixture add-on SwiftPM builds next to the test bundle.
private final class Locator {}
private let fixture = Bundle(for: Locator.self).bundleURL.deletingLastPathComponent().appendingPathComponent("LedgeKitHostFixture")

private actor Events {
    var all: [AddOnRuntime.Event] = []
    func add(_ event: AddOnRuntime.Event) { all.append(event) }
}

private func runtime(_ mode: String = "session", events: Events? = nil, restarts: Int = 3) -> AddOnRuntime {
    var limits = AddOnRuntime.Limits()
    limits.handshake = 1
    limits.request = 1
    limits.stopGrace = 0.5
    limits.restarts = restarts
    return AddOnRuntime(addOnID: "fixture", executable: fixture, arguments: [mode], limits: limits) { event in
        Task { await events?.add(event) }
    }
}

private func isAlive(_ pid: pid_t) -> Bool { kill(pid, 0) == 0 || errno == EPERM }

private func waitUntil(_ timeout: TimeInterval = 3, _ condition: () async -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() { return true }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    return await condition()
}

@Test func startsAnswersAndStopsWithoutLeavingAProcess() async throws {
    let addOn = runtime()
    try await addOn.start()
    #expect(await addOn.state == .running)
    let pid = try #require(await addOn.processID)
    let reply = try await addOn.request("echo", ["text": "hi"], as: [String: String].self)
    #expect(reply == ["text": "hi"])
    await addOn.stop()
    #expect(await addOn.state == .stopped)
    #expect(await waitUntil { !isAlive(pid) })
}

@Test func aSilentAddOnFailsTheHandshakeAndIsStopped() async {
    let addOn = runtime("silent")
    let started = Date()
    await #expect(throws: AddOnRuntimeError.self) { try await addOn.start() }
    #expect(Date().timeIntervalSince(started) < 3)
    #expect(await addOn.processID == nil)
    if case .failed = await addOn.state {} else { Issue.record("Expected failed state") }
}

@Test func anAddOnAnsweringAsSomeoneElseIsRefused() async {
    let addOn = runtime("wrong-id")
    do {
        try await addOn.start()
        Issue.record("Started an add-on that answered with another id")
    } catch let error as AddOnRuntimeError {
        guard case .handshakeFailed(let reason) = error else { Issue.record("Unexpected \(error)"); return }
        #expect(reason.contains("someone-else"))
    } catch { Issue.record("Unexpected \(error)") }
}

@Test func aSlowRequestTimesOutAndTheSessionKeepsWorking() async throws {
    let addOn = runtime()
    try await addOn.start()
    let started = Date()
    await #expect(throws: AddOnRuntimeError.timedOut) { _ = try await addOn.request("slow", params: .object([:])) }
    #expect(Date().timeIntervalSince(started) < 2)
    #expect(try await addOn.request("echo", params: .object(["a": .string("b")])) == .object(["a": .string("b")]))
    await addOn.stop()
}

@Test func aCrashFailsItsRequestAndTheAddOnIsRestarted() async throws {
    let events = Events()
    let addOn = runtime(events: events)
    try await addOn.start()
    let firstGeneration = await addOn.generation
    await #expect(throws: AddOnRuntimeError.self) { _ = try await addOn.request("crash", params: .object([:])) }
    let restarted = await waitUntil {
        let running = await addOn.state == .running
        let generation = await addOn.generation
        return running && generation > firstGeneration
    }
    #expect(restarted)
    #expect(try await addOn.request("echo", params: .object([:])) == .object([:]))
    #expect(await events.all.contains(.exited(status: 3, restarting: true)))
    await addOn.stop()
}

@Test func repeatedCrashesEndInFailed() async throws {
    let events = Events()
    let addOn = runtime(events: events, restarts: 2)
    try await addOn.start()
    for _ in 0..<3 {
        _ = await waitUntil { await addOn.state == .running }
        _ = try? await addOn.request("crash", params: .object([:]))
    }
    #expect(await waitUntil {
        if case .failed = await addOn.state { return true }
        return false
    })
    #expect(await addOn.processID == nil)
    #expect(await events.all.contains { if case .failed = $0 { return true }; return false })
}

@Test func anOversizedMessageStopsTheAddOn() async throws {
    let addOn = runtime("flood", restarts: 0)
    // The flood fixture answers hello, then floods instead of activating.
    await #expect(throws: AddOnRuntimeError.self) { try await addOn.start() }
    #expect(await addOn.processID == nil)
}

@Test func stoppingAlsoStopsWhatTheAddOnStarted() async throws {
    let addOn = runtime()
    try await addOn.start()
    let reply = try await addOn.request("child", [String: String](), as: [String: Int].self)
    let child = try #require(reply["pid"].map(pid_t.init))
    #expect(child > 0 && isAlive(child))
    await addOn.stop()
    #expect(await waitUntil { !isAlive(child) })
}

@Test func anAddOnIgnoringTheEndOfItsSessionIsKilled() async throws {
    let addOn = runtime("linger")
    try await addOn.start()
    let pid = try #require(await addOn.processID)
    let started = Date()
    await addOn.stop()
    #expect(Date().timeIntervalSince(started) < 3)
    #expect(await waitUntil { !isAlive(pid) })
}

@Test func logFloodsAreThrottled() async throws {
    let events = Events()
    let addOn = runtime(events: events)
    try await addOn.start()
    _ = try await addOn.request("logs", params: .object([:]))
    try await Task.sleep(nanoseconds: 300_000_000)
    let logs = await events.all.filter { if case .log = $0 { return true }; return false }
    #expect(logs.count <= 25)
    #expect(try await addOn.request("echo", params: .object([:])) == .object([:]))
    await addOn.stop()
}

@Test func diagnosticsAreKeptAndRequestsNeedARunningAddOn() async throws {
    let addOn = runtime()
    await #expect(throws: AddOnRuntimeError.notRunning) { _ = try await addOn.request("echo") }
    try await addOn.start()
    _ = try await addOn.request("diagnose", params: .object([:]))
    #expect(await waitUntil { await addOn.recentDiagnostics.contains("fixture diagnostic") })
    await #expect(throws: AddOnRuntimeError.self) { _ = try await addOn.request(SessionProtocol.Method.activate) }
    await addOn.stop()
}

@Test func updatesSentWhileActivatingArrive() async throws {
    let events = Events()
    let addOn = runtime("surfaces-on-activate", events: events)
    try await addOn.start()
    #expect(await waitUntil { await events.all.contains { if case .update(topic: "fixture.hello", _) = $0 { return true }; return false } })
    await addOn.stop()
}

@Test func addOnsCanCallLedgeServices() async throws {
    var limits = AddOnRuntime.Limits()
    limits.handshake = 1
    limits.request = 3
    let addOn = AddOnRuntime(addOnID: "fixture", executable: fixture, arguments: ["session"], limits: limits,
                             services: { method, params in
                                 guard method == "ledge.settings.get", params == .object(["key": .string("city")]) else {
                                     throw AddOnRuntimeError.addOnError("not allowed")
                                 }
                                 return .string("Pune")
                             })
    try await addOn.start()
    #expect(try await addOn.request("ask", ["key": "city"], as: [String: String].self) == ["got": "Pune"])
    #expect(try await addOn.request("ask", ["key": "secret"], as: [String: String].self) == ["refused": "not allowed"])
    await addOn.stop()
}

@Test func environmentChangesReachTheSession() async throws {
    let events = Events()
    let addOn = runtime("session", events: events)
    try await addOn.start()
    try await addOn.environmentChanged(HostEnvironment(ledgeVersion: "1.0", apiLevel: SessionProtocol.apiLevel,
                                                       appearance: "dark", accentColor: "#0A84FF", hasNotch: true))
    #expect(await waitUntil { await events.all.contains { if case .update(topic: "fixture.environment", .string("dark")) = $0 { return true }; return false } })
    await addOn.stop()
}
