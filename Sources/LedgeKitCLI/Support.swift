import Foundation
import LedgeKit

/// A failure the user can act on, printed as it is.
struct CLIError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message.hasSuffix("\n") ? message : message + "\n").utf8))
    exit(1)
}

/// Pulls `--name value` out of the arguments.
func option(_ name: String, in arguments: inout [String]) -> String? {
    guard let index = arguments.firstIndex(of: name) else { return nil }
    guard index + 1 < arguments.count else { fail("\(name) needs a value.") }
    let value = arguments[index + 1]
    arguments.removeSubrange(index...(index + 1))
    return value
}

/// Pulls a `--flag` out of the arguments.
func flag(_ name: String, in arguments: inout [String]) -> Bool {
    guard let index = arguments.firstIndex(of: name) else { return false }
    arguments.remove(at: index)
    return true
}

/// The folder a command works on: the one given, or the current one.
func packageFolder(_ arguments: [String]) -> URL {
    let path = arguments.first ?? FileManager.default.currentDirectoryPath
    return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
}

func readManifest(in folder: URL) throws -> AddOnManifest {
    let file = folder.appendingPathComponent("addon.json")
    guard let data = FileManager.default.contents(atPath: file.path) else {
        throw CLIError("No addon.json in \(folder.path). Run this in an add-on's folder, or name the folder.")
    }
    do {
        return try JSONDecoder().decode(AddOnManifest.self, from: data)
    } catch {
        throw CLIError("addon.json isn't a manifest LedgeKit can read: \(error)")
    }
}

/// Runs a tool, passing its output through, and throws when it fails.
func run(_ tool: String, _ arguments: [String], in folder: URL? = nil) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [tool] + arguments
    if let folder { process.currentDirectoryURL = folder }
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw CLIError("\(tool) \(arguments.joined(separator: " ")) failed (exit \(process.terminationStatus)).")
    }
}

/// Runs a tool and returns what it printed.
func output(_ tool: String, _ arguments: [String], in folder: URL? = nil) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [tool] + arguments
    if let folder { process.currentDirectoryURL = folder }
    let pipe = Pipe()
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw CLIError("\(tool) \(arguments.joined(separator: " ")) failed (exit \(process.terminationStatus)).")
    }
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}
