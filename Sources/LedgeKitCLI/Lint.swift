import Foundation

// `ledgekit lint`: what review would send back, read from the add-on's sources with no build. Each finding names the
// file and line, says what goes wrong, and what to do instead. A finding that's wrong for a line can be waived with
// `// ledgekit:allow <rule>` on that line or the one above; say why next to it, since review reads it too.

struct LintFinding {
    enum Severity: String { case error, warning }
    let rule: String
    let severity: Severity
    let file: String
    let line: Int
    let message: String
}

private struct LintRule {
    let id: String
    let severity: LintFinding.Severity
    let pattern: NSRegularExpression
    let message: String
    /// The rule only applies when this returns true for the whole package's source.
    var applies: (String) -> Bool = { _ in true }
    /// The rule only applies to a file when this returns true for its source.
    var appliesToFile: (String) -> Bool = { _ in true }

    init(_ id: String, _ severity: LintFinding.Severity, _ pattern: String, _ message: String,
         package: @escaping (String) -> Bool = { _ in true }, file: @escaping (String) -> Bool = { _ in true }) {
        self.id = id
        self.severity = severity
        self.pattern = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        self.message = message
        applies = package
        appliesToFile = file
    }
}

private func lintRules() -> [LintRule] { [
    LintRule("print", .error, #"(^|[^\w.])print\s*\("#,
             "print writes to standard output, which is the add-on's line to Ledge: it breaks the session. Use AddOnSession.log(_:)."),
    LintRule("refusal-ignored", .warning, #"try\?\s*(await\s+)?LedgeHost\.(copy|notify|showPage|openSettings|holdOpen|request)\b"#,
             "try? drops a refusal, so the person sees nothing happen when a capability is off. Catch LedgeHostError and show what the add-on can't do; ledgekit check --deny shows it."),
    LintRule("process-deadline", .warning, #"\bProcess\s*\(\s*\)"#,
             "The add-on waits for this program with no deadline, so a hang hangs the add-on. Terminate it after a few seconds.",
             file: { text in
                 let waits = ["waitUntilExit()", "readDataToEndOfFile()", "readToEnd()"].contains { text.contains($0) }
                 return waits && !text.contains(".terminate()") && !text.contains(".interrupt()")
             }),
    LintRule("unseen-polling", .warning, #"\bTimer\.(scheduledTimer|publish)\b|\bTask\.sleep\s*\("#,
             "Repeating work, and the add-on never handles onVisibilityChange: it works while nobody can see it. Start and stop it from onVisibilityChange.",
             package: { !$0.contains("onVisibilityChange") }),
    LintRule("secret-in-settings", .warning, #"LedgeHost\.set\s*\(.*(token|password|secret|api[_-]?key)"#,
             "LedgeHost.set stores plain JSON on disk. Keep secrets in the Keychain."),
    LintRule("logs-content", .warning, #"AddOnSession\.log\s*\(.*\\\(\s*[\w.]*\b(text|body|content|note|title|song|track|artist|email|token|password)\b"#,
             "This logs what the add-on read. Log that something failed, not its contents."),
    LintRule("home-path", .warning, #""/Users/[^"]*""#,
             "A path in someone's home folder won't exist on another Mac. Use LedgeHost.dataFolder() or FileManager."),
] }

/// The add-on's own sources: Sources/, Swift files only.
private func sourceFiles(in folder: URL) -> [URL] {
    let sources = folder.appendingPathComponent("Sources")
    guard let walker = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil) else { return [] }
    return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }.sorted { $0.path < $1.path }
}

func lintFindings(in folder: URL) -> [LintFinding] {
    let files = sourceFiles(in: folder).compactMap { url in (try? String(contentsOf: url, encoding: .utf8)).map { (url, $0) } }
    let everything = files.map(\.1).joined(separator: "\n")
    var findings: [LintFinding] = []
    let root = folder.resolvingSymlinksInPath().path
    for (url, text) in files {
        let path = url.resolvingSymlinksInPath().path
        let relative = path.hasPrefix(root + "/") ? String(path.dropFirst(root.count + 1)) : url.lastPathComponent
        let lines = text.components(separatedBy: "\n")
        for rule in lintRules() where rule.applies(everything) && rule.appliesToFile(text) {
            for (index, line) in lines.enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                if code.hasPrefix("//") || code.hasPrefix("///") || code.hasPrefix("*") { continue }
                guard rule.pattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil else { continue }
                let waiver = "ledgekit:allow \(rule.id)"
                if line.contains(waiver) || (index > 0 && lines[index - 1].contains(waiver)) { continue }
                findings.append(LintFinding(rule: rule.id, severity: rule.severity, file: relative, line: index + 1, message: rule.message))
            }
        }
    }
    return findings.sorted { ($0.file, $0.line) < ($1.file, $1.line) }
}

/// Prints the findings, or writes them as JSON. True when nothing is an error.
func lint(_ given: [String]) throws -> Bool {
    var arguments = given
    let json = flag("--json", in: &arguments)
    let folder = packageFolder(arguments)
    _ = try readManifest(in: folder)
    let findings = lintFindings(in: folder)
    let errors = findings.filter { $0.severity == .error }.count
    if json {
        let list = findings.map { ["rule": $0.rule, "severity": $0.severity.rawValue, "file": $0.file, "line": $0.line, "message": $0.message] as [String: Any] }
        let data = try JSONSerialization.data(withJSONObject: ["findings": list, "errors": errors, "warnings": findings.count - errors],
                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        print(String(decoding: data, as: UTF8.self))
    } else {
        for finding in findings {
            print("\(finding.severity == .error ? "✗" : "!") \(finding.file):\(finding.line): \(finding.rule): \(finding.message)")
        }
        print(findings.isEmpty ? "✓ Nothing for review to send back." : "\(errors) error\(errors == 1 ? "" : "s"), \(findings.count - errors) warning\(findings.count - errors == 1 ? "" : "s").")
    }
    return errors == 0
}
