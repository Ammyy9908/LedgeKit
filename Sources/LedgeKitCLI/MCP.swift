import Foundation
import LedgeKit

// ledgekit mcp: a Model Context Protocol server on stdio, so a coding agent (Claude Code, Codex, Cursor) has the
// add-on loop as tools. Each tool runs the same ledgekit command a person would, in the add-on's folder, and hands
// back its output; check returns its JSON report, shots returns the pictures themselves.

func mcp(_ given: [String]) {
    var arguments = given
    let folder = option("--package", in: &arguments).map { URL(fileURLWithPath: $0, isDirectory: true) }
        ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let server = MCPServer(folder: folder.standardizedFileURL)
    while let line = readLine(strippingNewline: true) {
        guard let data = line.data(using: .utf8),
              let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }
        guard let id = message["id"] else { continue }   // a notification: nothing to answer
        let reply: [String: Any]
        do {
            reply = ["jsonrpc": "2.0", "id": id, "result": try server.answer(message["method"] as? String ?? "", message["params"] as? [String: Any] ?? [:])]
        } catch let error as MCPError {
            reply = ["jsonrpc": "2.0", "id": id, "error": ["code": error.code, "message": error.message]]
        } catch {
            reply = ["jsonrpc": "2.0", "id": id, "error": ["code": -32603, "message": String(describing: error)]]
        }
        if let out = try? JSONSerialization.data(withJSONObject: reply, options: [.withoutEscapingSlashes]) {
            FileHandle.standardOutput.write(out + Data([10]))
        }
    }
}

private struct MCPError: Error {
    let code: Int
    let message: String
}

private struct MCPServer {
    let folder: URL
    let tool = ledgekitPath()

    func answer(_ method: String, _ params: [String: Any]) throws -> [String: Any] {
        switch method {
        case "initialize":
            return ["protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
                    "capabilities": ["tools": [:] as [String: Any]],
                    "serverInfo": ["name": "ledgekit", "version": SessionProtocol.release],
                    "instructions": "Tools for building a Ledge add-on in \(folder.path). Run ledgekit_doctor first, and after every change: ledgekit_test, ledgekit_check, then ledgekit_shots to look. Read ledgekit_docs for the rules."]
        case "ping":
            return [:]
        case "tools/list":
            return ["tools": tools]
        case "tools/call":
            guard let name = params["name"] as? String else { throw MCPError(code: -32602, message: "tools/call needs a name.") }
            return try call(name, params["arguments"] as? [String: Any] ?? [:])
        default:
            throw MCPError(code: -32601, message: "Unknown method \(method).")
        }
    }

    private var tools: [[String: Any]] {
        func schema(_ properties: [String: [String: Any]] = [:], required: [String] = []) -> [String: Any] {
            ["type": "object", "properties": properties, "required": required]
        }
        return [
            ["name": "ledgekit_doctor", "description": "Swift and ledgekit versions, the add-on's manifest, and whether the user's Ledge has Developer Mode on. Run first.", "inputSchema": schema()],
            ["name": "ledgekit_new", "description": "Write a new add-on in a new folder beside the current one: package, Core library, tests, manifest, listing, README, changelog, icon and agent files.",
             "inputSchema": schema(["id": ["type": "string", "description": "lowercase-with-hyphens, permanent once published"],
                                    "name": ["type": "string"], "page": ["type": "boolean"], "widget": ["type": "boolean"], "activity": ["type": "boolean"]], required: ["id"])],
            ["name": "ledgekit_test", "description": "swift test: Core's tests, including every surface against Ledge's limits.", "inputSchema": schema()],
            ["name": "ledgekit_build", "description": "Build the .ledgeaddon Ledge loads.", "inputSchema": schema()],
            ["name": "ledgekit_check", "description": "Run the add-on with no Ledge, the way Ledge would, and return the JSON report: surfaces sent and refused, calls to Ledge allowed or refused, problems and warnings. Not done while problems isn't empty.",
             "inputSchema": schema(["script": ["type": "array", "description": "Steps: {\"wait\":1}, {\"visible\":[\"notch-page\"]}, {\"press\":\"id\",\"on\":\"notch-page\",\"screen\":\"list\",\"item\":\"row\"}, {\"edit\":\"body\",\"text\":\"…\"}, {\"end\":\"body\",\"text\":\"…\"}, {\"toggle\":\"id\",\"on\":\"settings-page\",\"to\":true}, {\"pick\":\"id\",\"value\":\"x\"}, {\"change\":\"id\",\"value\":0.5}, {\"tool\":\"add_note\",\"arguments\":{\"text\":\"…\"}} (an AI app's call; the report's tools has each result)", "items": ["type": "object"]],
                                    "deny": ["type": "array", "items": ["type": "string"], "description": "Capabilities to turn off, as a person can in Ledge, such as [\"hud\"], or [\"all\"]. Refused calls are expected then; check the add-on keeps running and shows what it can't do"]])],
            ["name": "ledgekit_run", "description": "Install the build in the user's Ledge and say whether it started. Needs Developer Mode on in Ledge.", "inputSchema": schema()],
            ["name": "ledgekit_shots", "description": "Install the build in the user's Ledge, have Ledge draw each surface, and return the pictures. Look at them, the narrowest first: the notch page and widgets at Compact and Regular width beside a camera, and every live activity shape. Needs Developer Mode on in Ledge.",
             "inputSchema": schema(["all": ["type": "boolean", "description": "Also return the Large width and the pill display, which are drawn but left out by default"]])],
            ["name": "ledgekit_validate", "description": "Check the folder the way LedgeAddOns does. submit: true makes the to-dos errors, as before a pull request.",
             "inputSchema": schema(["submit": ["type": "boolean"]])],
            ["name": "ledgekit_lint", "description": "What review would send back, read from the sources with no build, as JSON: each finding's rule, severity, file, line and what to do instead. Fix them; don't add ledgekit:allow waivers yourself.", "inputSchema": schema()],
            ["name": "ledgekit_update", "description": "Move the add-on to this ledgekit's LedgeKit: Package.swift's pin and Package.resolved. kit.minAPI stays unless raise is true, which moves it to the new API level; raise only when the add-on uses something new (ledgekit_check says so).",
             "inputSchema": schema(["raise": ["type": "boolean"]])],
            ["name": "ledgekit_docs", "description": "The rules and the loop for building a Ledge add-on, and where the full docs are.", "inputSchema": schema()],
        ]
    }

    private func call(_ name: String, _ input: [String: Any]) throws -> [String: Any] {
        switch name {
        case "ledgekit_doctor":
            var lines = ["ledgekit \(SessionProtocol.release) at \(tool)"]
            lines.append(run("swift", ["--version"]).text.split(separator: "\n").first.map(String.init) ?? "swift: not found")
            if let manifest = try? readManifest(in: folder) {
                if let pin = pinnedKit(in: folder) {
                    lines.append(AddOnManifest.compare(pin, SessionProtocol.release) == .orderedAscending
                        ? "It pins LedgeKit \(pin); this ledgekit is \(SessionProtocol.release). ledgekit_update moves it."
                        : "It pins LedgeKit \(pin).")
                }
                lines.append("Add-on: \(manifest.name) (\(manifest.id)) \(manifest.version), surfaces \((manifest.surfaces ?? []).joined(separator: ", ")), capabilities \(manifest.capabilities.isEmpty ? "none" : manifest.capabilities.joined(separator: ", ")), minAPI \(manifest.kit?.minAPI ?? "unset")")
            } else {
                lines.append("No addon.json in \(folder.path). ledgekit_new makes an add-on.")
            }
            lines.append(developerModeIsOn()
                ? "Ledge's Developer Mode is on: ledgekit_run and ledgekit_shots work."
                : "Ledge's Developer Mode is off: ask the user to turn it on (Settings, Add-on Store, ⋯, Developer Mode) for ledgekit_run and ledgekit_shots.")
            return text(lines.joined(separator: "\n"))
        case "ledgekit_new":
            guard let id = input["id"] as? String else { throw MCPError(code: -32602, message: "ledgekit_new needs an id.") }
            var args = ["new", id, "--into", folder.deletingLastPathComponent().appendingPathComponent(id).path]
            if let name = input["name"] as? String { args += ["--name", name] }
            for flag in ["page", "widget", "activity"] where input[flag] as? Bool == true { args.append("--\(flag)") }
            return result(run(tool, args))
        case "ledgekit_test":
            return result(run("swift", ["test"]))
        case "ledgekit_build":
            return result(run(tool, ["build"]))
        case "ledgekit_validate":
            return result(run(tool, ["validate"] + (input["submit"] as? Bool == true ? ["--submit"] : [])))
        case "ledgekit_check":
            let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("ledgekit-mcp-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: scratch) }
            let report = scratch.appendingPathComponent("report.json")
            var args = ["check", "--report", report.path]
            if let script = input["script"] as? [Any] {
                let file = scratch.appendingPathComponent("steps.json")
                try JSONSerialization.data(withJSONObject: script).write(to: file)
                args += ["--script", file.path]
            }
            if let deny = input["deny"] as? [String], !deny.isEmpty { args += ["--deny", deny.joined(separator: ",")] }
            let outcome = run(tool, args)
            let json = (try? String(contentsOf: report, encoding: .utf8)) ?? "No report: the check didn't get that far.\n\n\(outcome.text)"
            return ["content": [["type": "text", "text": json]], "isError": outcome.status != 0]
        case "ledgekit_run":
            return result(run(tool, ["run"]))
        case "ledgekit_shots":
            let out = folder.appendingPathComponent("shots", isDirectory: true)
            try? FileManager.default.removeItem(at: out)
            let outcome = run(tool, ["shots", "--out", out.path])
            var content: [[String: Any]] = [["type": "text", "text": outcome.text]]
            let drawn = ((try? FileManager.default.contentsOfDirectory(atPath: out.path)) ?? []).filter { $0.hasSuffix(".png") }.sorted()
            // By default the pictures that find the most: the narrowest notch widths beside a camera, where a page's
            // header is tightest, and every activity shape. The rest are named, so the agent can ask for them.
            let everything = input["all"] as? Bool == true
            let files = everything ? drawn : drawn.filter {
                !$0.contains("@") || $0.hasPrefix("activity-") || $0.contains("@notch-compact") || $0.contains("@notch-regular")
            }
            let left = drawn.filter { !files.contains($0) }
            if !left.isEmpty { content.append(["type": "text", "text": "Also drawn, in \(out.path): \(left.joined(separator: ", ")). Pass all: true to see them."]) }
            for file in files {
                guard let data = FileManager.default.contents(atPath: out.appendingPathComponent(file).path) else { continue }
                content.append(["type": "text", "text": file])
                content.append(["type": "image", "data": data.base64EncodedString(), "mimeType": "image/png"])
            }
            return ["content": content, "isError": outcome.status != 0]
        case "ledgekit_lint":
            let outcome = run(tool, ["lint", "--json"])
            return ["content": [["type": "text", "text": outcome.text]], "isError": outcome.status != 0]
        case "ledgekit_update":
            return result(run(tool, ["update"] + (input["raise"] as? Bool == true ? ["--raise"] : [])))
        case "ledgekit_docs":
            return text(brief)
        default:
            throw MCPError(code: -32602, message: "Unknown tool \(name).")
        }
    }

    private func text(_ string: String) -> [String: Any] { ["content": [["type": "text", "text": string]]] }

    private func result(_ outcome: (status: Int32, text: String)) -> [String: Any] {
        ["content": [["type": "text", "text": outcome.text.isEmpty ? "(no output)" : outcome.text]], "isError": outcome.status != 0]
    }

    /// Runs a command in the add-on's folder and returns its exit status and output, trimmed to what an agent reads.
    private func run(_ command: String, _ args: [String]) -> (status: Int32, text: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.hasPrefix("/") ? command : "/usr/bin/env")
        process.arguments = command.hasPrefix("/") ? args : [command] + args
        process.currentDirectoryURL = FileManager.default.fileExists(atPath: folder.path) ? folder : folder.deletingLastPathComponent()
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return (127, "Couldn't run \(command): \(error)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        // SwiftPM's progress lines say nothing an agent needs.
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
            .filter { line in
                !line.hasPrefix("[") && !line.contains("Compiling") && !line.contains("Write swift-version")
                    && !["Building for", "Fetching ", "Fetched ", "Computing version", "Computed ", "Creating working copy", "Working copy of"]
                        .contains(where: { line.hasPrefix($0) })
            }
        var text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count > 20_000 { text = "…\n" + text.suffix(20_000) }
        return (process.terminationStatus, text)
    }
}
