import Darwin
import Foundation

/// A note, on disk, of every add-on session Ledge has running, so the next launch can stop what a crash left behind.
///
/// When Ledge quits normally it ends each session and removes its note. When Ledge crashes, a well-behaved add-on
/// sees its stdin close and exits on its own, but one that ignores that keeps running with nothing to stop it.
/// `sweep()` runs at launch, before any add-on starts, and stops whatever the notes still point to.
///
/// A note names the program's pid, its start time and its path. Pids are reused, so a note only counts while that
/// pid is still the same program started at the same moment; anything else is left alone and the note dropped.
public struct AddOnSessionRecords: Sendable {
    public struct Record: Codable, Sendable, Equatable {
        public let addOnID: String
        public let pid: Int32
        public let startSeconds: UInt64
        public let startMicroseconds: UInt64
        public let executable: String
    }

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Notes a running session. Failing to write only loses the crash cleanup, so it never stops the add-on.
    public func record(addOnID: String, pid: pid_t, executable: URL) {
        guard let start = Self.startTime(of: pid) else { return }
        let record = Record(addOnID: addOnID, pid: pid, startSeconds: start.seconds, startMicroseconds: start.microseconds,
                            executable: executable.resolvingSymlinksInPath().path)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(record).write(to: file(for: pid), options: .atomic)
    }

    /// Forgets a session that ended normally.
    public func remove(pid: pid_t) {
        try? FileManager.default.removeItem(at: file(for: pid))
    }

    public var records: [Record] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap { try? JSONDecoder().decode(Record.self, from: Data(contentsOf: $0)) }
    }

    /// Stops every session a previous run of Ledge left behind, and clears the notes. Returns the ids of the
    /// add-ons whose leftovers were stopped.
    @discardableResult
    public func sweep() -> [String] {
        var stopped: [String] = []
        for record in records {
            defer { remove(pid: record.pid) }
            let leaderAlive = kill(record.pid, 0) == 0 || errno == EPERM
            if leaderAlive {
                // The pid is in use: only act if it is still the add-on we started.
                guard let start = Self.startTime(of: record.pid),
                      start.seconds == record.startSeconds, start.microseconds == record.startMicroseconds,
                      Self.path(of: record.pid) == record.executable else { continue }
            }
            // With the leader gone, anything still in its session is the add-on's: macOS doesn't hand out a pid
            // that is still in use as a session id.
            let members = Self.sessionMembers(record.pid)
            guard leaderAlive || !members.isEmpty else { continue }
            for pid in members { _ = kill(pid, SIGKILL) }
            if leaderAlive { _ = kill(record.pid, SIGKILL) }
            stopped.append(record.addOnID)
        }
        return stopped
    }

    private func file(for pid: pid_t) -> URL {
        directory.appendingPathComponent("\(pid).json")
    }

    static func startTime(of pid: pid_t) -> (seconds: UInt64, microseconds: UInt64)? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return (info.pbi_start_tvsec, info.pbi_start_tvusec)
    }

    static func path(of pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        let text = String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
        return URL(fileURLWithPath: text).resolvingSymlinksInPath().path
    }

    /// Every process whose session id is `leader`, the leader excluded.
    static func sessionMembers(_ leader: pid_t) -> [pid_t] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        return pids.prefix(Int(max(filled, 0))).filter { $0 > 1 && $0 != leader && getsid($0) == leader }
    }
}
