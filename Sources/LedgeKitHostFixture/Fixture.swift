import Foundation
import LedgeKit

// The first argument picks how this add-on behaves. Anything but the modes below runs a well-behaved session.
@main
struct Fixture {
    static func main() async {
        let mode = CommandLine.arguments.dropFirst().first ?? "session"
        func raw(_ line: String) { FileHandle.standardOutput.write(Data((line + "\n").utf8)) }
        switch mode {
        case "silent":
            // Never answers hello.
            while true { sleep(60) }
        case "wrong-id":
            _ = readLine()
            raw(#"{"type":"ready","protocolVersion":2,"apiLevel":"0.3.0","addOnID":"someone-else"}"#)
            while true { sleep(60) }
        case "flood":
            // Answers hello, then writes one line far over the size limit.
            _ = readLine()
            raw(#"{"type":"ready","protocolVersion":2,"apiLevel":"0.3.0","addOnID":"fixture"}"#)
            _ = readLine()
            raw(String(repeating: "x", count: 3_000_000))
            while true { sleep(60) }
        default:
            break
        }
        var handlers = AddOnHandlers()
        if mode == "surfaces-on-activate" {
            handlers.activate = { AddOnSession.update(topic: "fixture.hello", payload: .string("hi")) }
        }
        handlers.onEnvironmentChange = { environment in
            AddOnSession.update(topic: "fixture.environment", payload: .string(environment.appearance))
        }
        handlers.on("echo") { (params: [String: String]) in params }
        handlers.on("ask") { (params: [String: String]) -> [String: String] in
            // Asks Ledge for a stored value from inside a request, and reports the answer or the refusal.
            do {
                return ["got": try await LedgeHost.value(String.self, forKey: params["key"] ?? "") ?? "nothing"]
            } catch {
                return ["refused": String(describing: error)]
            }
        }
        handlers.on("slow") { (_: [String: String]) -> [String: String] in
            try await Task.sleep(nanoseconds: 60_000_000_000)
            return [:]
        }
        handlers.on("crash") { (_: [String: String]) -> [String: String] in exit(3) }
        handlers.on("logs") { (_: [String: String]) -> [String: String] in
            for index in 0..<500 { AddOnSession.log("line \(index)") }
            return [:]
        }
        handlers.on("child") { (_: [String: String]) -> [String: Int] in
            // Starts a long sleep in the background, in this add-on's process group, and reports its pid.
            let shell = Process()
            shell.executableURL = URL(fileURLWithPath: "/bin/sh")
            shell.arguments = ["-c", "sleep 300 >/dev/null 2>&1 & echo $!"]
            let output = Pipe()
            shell.standardOutput = output
            try shell.run()
            shell.waitUntilExit()
            let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            return ["pid": Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0]
        }
        handlers.on("diagnose") { (_: [String: String]) -> [String: String] in
            FileHandle.standardError.write(Data("fixture diagnostic\n".utf8))
            return [:]
        }
        let status = await AddOnSession.run(id: "fixture", handlers: handlers)
        if mode == "linger" {
            // Ignores the end of the session and SIGTERM, so stopping it has to escalate to SIGKILL.
            signal(SIGTERM, SIG_IGN)
            while true { sleep(60) }
        }
        exit(status)
    }
}
