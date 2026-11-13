import Darwin
import Foundation
import LedgeKit
import Testing
@testable import LedgeKitHost

private final class Locator {}
private let fixture = Bundle(for: Locator.self).bundleURL.deletingLastPathComponent().appendingPathComponent("LedgeKitHostFixture")

private func withRecords(_ body: (AddOnSessionRecords) async throws -> Void) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try await body(AddOnSessionRecords(directory: directory))
}

private func runtime(_ mode: String, records: AddOnSessionRecords) -> AddOnRuntime {
    var limits = AddOnRuntime.Limits()
    limits.handshake = 1
    limits.stopGrace = 0.5
    limits.restarts = 0
    return AddOnRuntime(addOnID: "fixture", executable: fixture, arguments: [mode], limits: limits, records: records)
}

private func isAlive(_ pid: pid_t) -> Bool { kill(pid, 0) == 0 || errno == EPERM }

private func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<150 where !condition() { try? await Task.sleep(nanoseconds: 20_000_000) }
    return condition()
}

@Test func aCleanStopLeavesNoRecord() async throws {
    try await withRecords { records in
        let addOn = runtime("session", records: records)
        try await addOn.start()
        let pid = try #require(await addOn.processID)
        #expect(records.records.map(\.pid) == [pid])
        await addOn.stop()
        #expect(records.records.isEmpty)
    }
}

@Test func theSweepStopsASessionLeftRunningAndWhatItStarted() async throws {
    try await withRecords { records in
        // "linger" ignores the end of its session and SIGTERM, as a misbehaving add-on would after Ledge crashed.
        let addOn = runtime("linger", records: records)
        try await addOn.start()
        let pid = try #require(await addOn.processID)
        let child = pid_t(try await addOn.request("child", [String: String](), as: [String: Int].self)["pid"] ?? 0)
        #expect(child > 0 && isAlive(child))

        // What the next launch does, with the previous run's runtime gone.
        #expect(records.sweep() == ["fixture"])
        #expect(await eventually { !isAlive(pid) && !isAlive(child) })
        #expect(records.records.isEmpty)
        await addOn.stop()
    }
}

@Test func aRecordWhosePidNowBelongsToAnotherProgramIsDroppedWithoutStoppingIt() async throws {
    try await withRecords { records in
        // This test process stands in for an unrelated program that was given the recorded pid.
        let stale = AddOnSessionRecords.Record(addOnID: "fixture", pid: getpid(), startSeconds: 1, startMicroseconds: 0,
                                               executable: fixture.path)
        try FileManager.default.createDirectory(at: records.directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(stale).write(to: records.directory.appendingPathComponent("\(getpid()).json"))
        #expect(records.sweep().isEmpty)
        #expect(isAlive(getpid()))
        #expect(records.records.isEmpty)
    }
}

@Test func aRecordForAProgramThatIsGoneIsDropped() async throws {
    try await withRecords { records in
        let addOn = runtime("session", records: records)
        try await addOn.start()
        let pid = try #require(await addOn.processID)
        // Copy the note, end the session normally, then put the note back as if the removal had been lost.
        let note = try Data(contentsOf: records.directory.appendingPathComponent("\(pid).json"))
        await addOn.stop()
        #expect(await eventually { !isAlive(pid) })
        try note.write(to: records.directory.appendingPathComponent("\(pid).json"))
        #expect(records.sweep().isEmpty)
        #expect(records.records.isEmpty)
    }
}
