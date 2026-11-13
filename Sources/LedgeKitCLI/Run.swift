import Darwin
import Foundation
import LedgeKit

// ledgekit run and ledgekit shots: the add-on in your own Ledge, through developer mode.
//
// Ledge listens on a socket only your account can open while Developer Mode is on (Add-on Store, ⋯, Developer
// Mode). `run` installs the build there without the trust prompt and says whether it started; `shots` does the same,
// then asks Ledge to draw each of the add-on's surfaces into PNGs, exactly as Ledge draws them.

private let socketPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("Ledge/Developer/ledge.sock").path

func runInLedge(_ given: [String]) throws {
    var arguments = given
    let skipBuild = flag("--no-build", in: &arguments)
    let (bundle, _) = try builtBundle(arguments, build: !skipBuild)
    try install(bundle)
}

func shots(_ given: [String]) throws {
    var arguments = given
    let skipBuild = flag("--no-build", in: &arguments)
    let skipInstall = flag("--no-install", in: &arguments)
    let out = URL(fileURLWithPath: option("--out", in: &arguments) ?? "shots", isDirectory: true).standardizedFileURL
    let shapes = try choices(option("--shape", in: &arguments), from: ["notch", "pill"], for: "--shape")
    let widths = try choices(option("--width", in: &arguments), from: ["compact", "regular", "large"], for: "--width")
    let (bundle, manifest) = try builtBundle(arguments, build: !skipBuild && !skipInstall)
    if !skipInstall { try install(bundle) }
    let reply = try ask(["command": "shots", "id": manifest.id, "out": out.path, "shapes": shapes, "widths": widths])
    guard reply["ok"] as? Bool == true else { throw CLIError("Ledge couldn't draw it: \(reply["error"] as? String ?? "no reason given")") }
    let files = reply["files"] as? [String] ?? []
    print(files.isEmpty ? "Ledge holds nothing of \(manifest.name)'s to draw yet." : "Drew \(files.count) picture\(files.count == 1 ? "" : "s") in \(out.path):")
    // One line per surface: its name, then each shape and width it was drawn in.
    let grouped = Dictionary(grouping: files.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }) {
        $0.split(separator: "@").first.map(String.init) ?? $0
    }
    for (surface, names) in grouped.sorted(by: { $0.key < $1.key }) {
        let variants = names.compactMap { $0.split(separator: "@").dropFirst().first.map(String.init) }.sorted()
        print("  \(surface)" + (variants.isEmpty ? "" : ": " + variants.joined(separator: ", ")))
    }
    for (surface, reason) in (reply["skipped"] as? [String: String] ?? [:]).sorted(by: { $0.key < $1.key }) {
        print("! \(surface): \(reason)")
    }
}

/// A comma-separated choice, like "notch,pill"; every one when it's missing or "all".
private func choices(_ given: String?, from all: [String], for name: String) throws -> [String] {
    guard let given, given != "all" else { return all }
    let picked = given.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    for value in picked where !all.contains(value) {
        throw CLIError("\(name) takes \(all.joined(separator: ", ")) or all, not \"\(value)\".")
    }
    return picked
}

/// The .ledgeaddon to send: the one given, or the folder's, built first.
private func builtBundle(_ arguments: [String], build shouldBuild: Bool) throws -> (URL, AddOnManifest) {
    let path = arguments.first.map { URL(fileURLWithPath: $0).standardizedFileURL } ?? packageFolder([])
    if path.pathExtension == "ledgeaddon" { return (path, try readManifest(in: path)) }
    let manifest = try readManifest(in: path)
    if shouldBuild { try build([path.path]) }
    return (path.appendingPathComponent(".build/addons/\(manifest.executable).ledgeaddon"), manifest)
}

private func install(_ bundle: URL) throws {
    let reply = try ask(["command": "install", "path": bundle.path])
    let id = reply["id"] as? String ?? "it"
    if reply["ok"] as? Bool == true {
        print("✓ \(id) is running in Ledge.")
    } else {
        throw CLIError("✗ \(id) didn't start in Ledge: \(reply["error"] as? String ?? "no reason given")")
    }
}

/// One request to Ledge's developer socket, and its reply.
private func ask(_ request: [String: Any]) throws -> [String: Any] {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw CLIError("Couldn't open a socket.") }
    defer { close(fd) }
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(socketPath.utf8)
    withUnsafeMutableBytes(of: &address.sun_path) { buffer in
        buffer.copyBytes(from: bytes.prefix(buffer.count - 1))
        buffer[min(bytes.count, buffer.count - 1)] = 0
    }
    let connected = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    guard connected == 0 else {
        throw CLIError("""
        Ledge isn't listening. Turn on developer mode: in Ledge, open Settings, then Add-on Store, ⋯, Developer Mode.
        It turns off whenever Ledge quits.
        """)
    }
    var line = try JSONSerialization.data(withJSONObject: request)
    line.append(10)
    _ = line.withUnsafeBytes { write(fd, $0.baseAddress, line.count) }
    var reply = Data()
    var byte: UInt8 = 0
    while read(fd, &byte, 1) == 1, byte != 10 { reply.append(byte) }
    guard let object = (try? JSONSerialization.jsonObject(with: reply)) as? [String: Any] else {
        throw CLIError("Ledge's reply wasn't readable.")
    }
    return object
}
