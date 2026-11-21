import Foundation
import LedgeKit
import LedgeKitHost

// ledgekit check: runs an add-on with no Ledge, the way Ledge would, and says what Ledge would make of it.
//
// It starts the built program with LedgeKitHost's runtime, the one Ledge uses, reads every surface it sends with
// SurfaceUpdate, the reader Ledge uses, and answers its calls to Ledge the way Ledge does, refusing what its
// capabilities don't allow. A script of steps can press its controls, type in its editor and open its surfaces.
// Everything goes into a report: printed for a person, and as JSON with --report for a script or a coding agent.

func check(_ given: [String]) async throws -> Bool {
    var arguments = given
    let scriptPath = option("--script", in: &arguments)
    let reportPath = option("--report", in: &arguments)
    let skipBuild = flag("--no-build", in: &arguments)
    let deny = option("--deny", in: &arguments)
    let path = arguments.first.map { URL(fileURLWithPath: $0).standardizedFileURL } ?? packageFolder([])

    // The package to run: a .ledgeaddon as given, or the folder's, built first.
    var bundle = path
    if path.pathExtension != "ledgeaddon" {
        let manifest = try readManifest(in: path)
        if !skipBuild { try build([path.path]) }
        bundle = path.appendingPathComponent(".build/addons/\(manifest.executable).ledgeaddon")
    }
    let package: AddOnPackage
    do { package = try AddOnPackage(contentsOf: bundle) } catch {
        throw CLIError("Ledge would refuse \(bundle.path): \(describe(error)). Run ledgekit build first, or check addon.json, the program and the icon.")
    }
    let steps = try scriptPath.map(readScript) ?? defaultSteps(for: package.manifest)

    let report = CheckReport(manifest: package.manifest)
    let denied = try deniedCapabilities(deny, manifest: package.manifest, report: report)
    let host = SimulatedHost(manifest: package.manifest, report: report, denied: denied)
    defer { host.cleanUp() }
    let runtime = AddOnRuntime(addOnID: package.manifest.id, executable: package.executableURL,
                               onEvent: { event in report.received(event) },
                               services: { method, params in try host.answer(method, params) })
    print("Checking \(package.manifest.name) \(package.manifest.version)…")
    do {
        try await runtime.start()
        report.started = true
        // A terminal starts at the size Ledge's first sends, as when its page first shows.
        if (package.manifest.surfaces ?? []).contains(Surface.terminal) {
            try await runtime.terminalResize(TerminalSize(columns: 80, rows: 24))
            report.note("terminal: 80 × 24")
        }
        for step in steps { try await play(step, on: runtime, host: host, report: report) }
        try await Task.sleep(nanoseconds: 300_000_000)   // the last updates
    } catch {
        report.problem("It didn't run: \(describe(error))")
    }
    await runtime.stop()
    report.finish()

    report.printSummary()
    if let reportPath {
        let url = URL(fileURLWithPath: reportPath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try report.json().write(to: url)
        print("Report: \(url.path)")
    }
    return report.passed
}

// MARK: Scripts

/// One step of a check. In JSON: {"wait": 1}, {"visible": ["notch-page"]},
/// {"press": "add", "on": "notch-page", "screen": "list", "item": "n1"}, {"edit": "body", "text": "…", "on": "notch-page"},
/// {"end": "body", "text": "…"}, {"toggle": "id", "on": "settings-page", "to": true}, {"pick": "id", "value": "x"},
/// {"change": "id", "value": 0.5}, {"tool": "add_note", "arguments": {"text": "…"}},
/// {"type": "ls\n"} (into the terminal; a newline is Return), {"picked": "heart", "section": "smileys"} (from the picker),
/// {"share": ["/path/a.png"], "destination": "pixel"} (from the shelf's share menu, or dropped on a list row).
private struct Step: Decodable {
    var share: [String]?
    var destination: String?
    var wait: Double?
    var type: String?
    var picked: String?
    var section: String?
    var visible: [String]?
    var tool: String?
    var arguments: JSONValue?
    var press, edit, end, toggle, pick, change: String?
    var on: String?
    var screen, item, widget, text: String?
    var to: Bool?
    var value: JSONValue?
}

private func readScript(_ path: String) throws -> [Step] {
    guard let data = FileManager.default.contents(atPath: path) else { throw CLIError("No script at \(path).") }
    do { return try JSONDecoder().decode([Step].self, from: data) } catch {
        throw CLIError("The script isn't a list of steps: \(error)")
    }
}

/// Without a script: start, let it settle, then open everything it declares that can be seen, and close it again.
private func defaultSteps(for manifest: AddOnManifest) -> [Step] {
    let seeable = Set(manifest.surfaces ?? []).intersection([Surface.notchPage, Surface.widget, Surface.settingsPage, Surface.menuBarTile])
    var steps = [Step(wait: 1.5)]
    if !seeable.isEmpty { steps += [Step(visible: seeable.sorted()), Step(wait: 1), Step(visible: []), Step(wait: 0.5)] }
    return steps
}

private func play(_ step: Step, on runtime: AddOnRuntime, host: SimulatedHost, report: CheckReport) async throws {
    if let wait = step.wait {
        try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        return
    }
    if let visible = step.visible {
        report.note("visible: \(visible.isEmpty ? "nothing" : visible.joined(separator: ", "))")
        try? await runtime.visibilityChanged(SurfaceVisibility(visible: Set(visible)))
        return
    }
    if let text = step.type {
        // Return is a carriage return on a terminal; a newline in a script means Return.
        try await runtime.terminalInput(Data(text.replacingOccurrences(of: "\n", with: "\r").utf8))
        report.note("terminal: typed \(text.count) characters")
        return
    }
    if let id = step.picked {
        // As Ledge will: only an item the picker holds.
        guard let picker = report.lastPicker(),
              let section = picker.sections.first(where: { step.section == nil ? $0.items.contains { $0.id == id } : $0.id == step.section }),
              section.items.contains(where: { $0.id == id }) else {
            report.problem("The script picks \(id), which isn't in the picker the add-on sent.")
            return
        }
        try await runtime.picked(PickedItem(section: section.id, id: id))
        report.note("picker: picked \(section.id)/\(id)")
        return
    }
    if let files = step.share {
        // As Ledge will: only a destination the add-on offered, in its share target or a list row that takes files.
        let destination = step.destination ?? ""
        guard report.shareDestinations().contains(destination) else {
            report.problem("The script shares with \(destination), which isn't a destination or a row that takes files.")
            return
        }
        try await runtime.shared(SharedFiles(destination: destination, files: files))
        report.note("shared \(files.count) file\(files.count == 1 ? "" : "s") with \(destination)")
        return
    }
    if let name = step.tool {
        // As Ledge will: the tool must be one the add-on offered, and the arguments must fit it.
        guard let tool = report.lastTools().first(where: { $0.name == name }) else {
            report.problem("The script calls \(name), which isn't among the tools the add-on sent.")
            return
        }
        let given = step.arguments ?? .null
        do {
            let arguments = try tool.check(given)
            let result = try await runtime.runTool(ToolCall(tool: name, arguments: arguments, app: "ledgekit check"))
            report.tool(name, arguments: given, result: result)
        } catch let error as AddOnError {
            report.tool(name, arguments: given, refused: error.message)
        } catch AddOnRuntimeError.addOnError(let message) {
            report.tool(name, arguments: given, refused: message)
        } catch {
            report.tool(name, arguments: given, refused: "\(error)")
        }
        return
    }
    let action: SurfaceEvent.Action
    let control: String
    if let id = step.press { control = id; action = .pressed }
    else if let id = step.edit { control = id; action = .edited(step.text ?? "") }
    else if let id = step.end { control = id; action = .ended(step.text ?? "") }
    else if let id = step.toggle { control = id; action = .toggled(step.to ?? true) }
    else if let id = step.pick, case .string(let value)? = step.value { control = id; action = .picked(value) }
    else if let id = step.change, case .number(let value)? = step.value { control = id; action = .changed(value) }
    else { throw CLIError("A script step does nothing: give it wait, visible, press, edit, end, toggle, pick, change, tool, type or picked.") }
    let surface = step.on ?? Surface.notchPage
    let event = SurfaceEvent(surface: surface, widget: step.widget, control: control, action: action, screen: step.screen, item: step.item)
    host.userActed()
    report.note("\(surface): \(control) \(action)")
    _ = try await runtime.sendEvent(try JSONValue(encoding: event))
}

// MARK: Ledge, simulated

/// Answers an add-on's calls to Ledge (`LedgeHost`) the way Ledge does, and notes each one.
/// The capabilities `--deny` turns off: a comma-separated list, or "all" for every one the add-on asks for. As a person
/// would by switching them off in Ledge, so the check shows what the add-on does without them.
private func deniedCapabilities(_ given: String?, manifest: AddOnManifest, report: CheckReport) throws -> Set<String> {
    guard let given else { return [] }
    let asked = Set(manifest.capabilities)
    let names = given == "all" ? asked : Set(given.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
    for name in names.sorted() where !asked.contains(name) {
        throw CLIError("--deny \(name): addon.json doesn't ask for it, so it's off already. It asks for: \(asked.isEmpty ? "nothing" : asked.sorted().joined(separator: ", ")).")
    }
    report.deny(names)
    return names
}

private final class SimulatedHost: @unchecked Sendable {
    private let manifest: AddOnManifest
    private let report: CheckReport
    private let lock = NSLock()
    private var settings: [String: JSONValue] = [:]
    private var lastAction = Date.distantPast
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ledgekit-check-\(UUID().uuidString)")
    /// What Ledge would grant: the capabilities it knows, of those the manifest asks for.
    private let granted: Set<String>
    /// What the person turned off (`--deny`): refused as Ledge refuses them, but expected, so not a problem.
    private let denied: Set<String>

    init(manifest: AddOnManifest, report: CheckReport, denied: Set<String> = []) {
        self.manifest = manifest
        self.report = report
        self.denied = denied
        granted = Set(manifest.capabilities).intersection(AddOnCapability.known).subtracting(denied)
        for capability in manifest.capabilities where !AddOnCapability.known.contains(capability) {
            report.warning("\(capability) isn't a capability this LedgeKit knows, so Ledge won't grant it.")
        }
    }

    func userActed() { lock.withLock { lastAction = Date() } }
    func cleanUp() { try? FileManager.default.removeItem(at: folder) }

    func answer(_ method: String, _ params: JSONValue) throws -> JSONValue {
        let object: [String: JSONValue] = { if case .object(let value) = params { return value }; return [:] }()
        func string(_ key: String) -> String? { if case .string(let value)? = object[key] { return value }; return nil }
        func require(_ capability: String) throws {
            if denied.contains(capability) {
                report.call(method, denied: capability)
                throw CLIError("\(manifest.name) isn't allowed \(capability).")
            }
            guard granted.contains(capability) else {
                report.call(method, refused: "needs the \(capability) capability in addon.json")
                throw CLIError("\(manifest.name) isn't allowed \(capability).")
            }
        }
        func needs(_ version: String, _ what: String) {
            if let minAPI = manifest.kit?.minAPI, AddOnManifest.compare(minAPI, version) == .orderedAscending {
                report.problem("\(what) needs LedgeKit \(version), but kit.minAPI is \(minAPI). An older Ledge would refuse it; raise kit.minAPI.")
            }
        }
        let recent = lock.withLock { Date().timeIntervalSince(lastAction) < 2 }

        switch method {
        case LedgeHost.Method.configureTranslation, LedgeHost.Method.translateSelection:
            needs("0.24.0", "Selection translation")
            try require(SelectionTranslation.capability)
            if method == LedgeHost.Method.configureTranslation {
                if let value = object["options"], value != .null { try value.decode(SelectionTranslation.self).validate() }
            } else if !recent {
                throw CLIError("Translate only just after the user uses the add-on.")
            }
            report.call(method, detail: "Ledge owns the selection and on-device translation card; no text is read in a check")
            return .bool(true)
        case LedgeHost.Method.settingsGet:
            report.call(method)
            return lock.withLock { string("key").flatMap { settings[$0] } ?? .null }
        case LedgeHost.Method.settingsSet:
            report.call(method)
            if let key = string("key") { lock.withLock { settings[key] = object["value"] ?? .null } }
            return .bool(true)
        case LedgeHost.Method.settingsRemove:
            report.call(method)
            if let key = string("key") { _ = lock.withLock { settings.removeValue(forKey: key) } }
            return .bool(true)
        case LedgeHost.Method.environment:
            report.call(method)
            return try JSONValue(encoding: HostEnvironment(ledgeVersion: "check", apiLevel: SessionProtocol.apiLevel,
                                                           appearance: "dark", accentColor: "#0A84FF", hasNotch: true))
        case LedgeHost.Method.open:
            let link = string("url").flatMap(URL.init(string:))
            guard let scheme = link?.scheme?.lowercased(), ["https", "http", "mailto"].contains(scheme) else {
                report.call(method, refused: "only https, http and mailto links open")
                throw CLIError("Ledge only opens web and mail links.")
            }
            report.call(method, detail: link?.absoluteString)
            return .bool(true)
        case LedgeHost.Method.copy:
            try require("clipboard-write")
            report.call(method)
            return .bool(true)
        case LedgeHost.Method.notify:
            try require("hud")
            report.call(method, detail: string("title"))
            return .bool(true)
        case LedgeHost.Method.account:
            report.call(method, detail: "\(string("provider") ?? "?"): not connected in a check")
            return try JSONValue(encoding: HostAccount(connected: false, name: nil))
        case LedgeHost.Method.http:
            report.call(method, refused: "ledgekit check doesn't reach accounts' APIs; Ledge would make this call")
            throw CLIError("Not in a check.")
        case LedgeHost.Method.dataFolder:
            needs("0.13.0", "LedgeHost.dataFolder()")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            report.call(method)
            return .string(folder.path)
        case LedgeHost.Method.showPage:
            needs("0.13.0", "LedgeHost.showPage()")
            try require("notch-control")
            guard (manifest.surfaces ?? []).contains(Surface.notchPage), report.hasPage else {
                report.call(method, refused: "there's no page in the notch to show")
                throw CLIError("No page.")
            }
            guard recent || report.hasAttentionActivity else {
                report.call(method, refused: "a page opens only just after the user uses the add-on, or for an attention activity")
                throw CLIError("Not now.")
            }
            report.call(method)
            return .bool(true)
        case LedgeHost.Method.openSettings:
            needs("0.13.0", "LedgeHost.openSettings()")
            guard recent else {
                report.call(method, refused: "Settings opens only just after the user uses one of the add-on's controls")
                throw CLIError("Not now.")
            }
            report.call(method)
            return .bool(true)
        case LedgeHost.Method.addToShelf:
            needs("0.20.0", "LedgeHost.addToShelf(_:)")
            try require(Surface.shelfAddCapability)
            guard case .array(let files)? = object["files"], (1...Surface.maximumSharedFiles).contains(files.count) else {
                report.call(method, refused: "give 1 to \(Surface.maximumSharedFiles) files")
                throw CLIError("No files.")
            }
            report.call(method, detail: "\(files.count) file\(files.count == 1 ? "" : "s")")
            return .bool(true)
        case LedgeHost.Method.ask:
            needs("0.20.0", "LedgeHost.ask(_:)")
            try require(Surface.questionsCapability)
            guard let question = try? object["question"]?.decode(HostQuestion.self), (try? question.validate()) != nil else {
                report.call(method, refused: "the question isn't valid")
                throw CLIError("Invalid question.")
            }
            // A check answers yes, so the add-on's next steps run.
            report.call(method, detail: "\(question.title) → \(question.accept)")
            return .bool(true)
        case LedgeHost.Method.holdOpen:
            needs("0.13.0", "LedgeHost.holdOpen(_:)")
            try require("notch-control")
            report.call(method, detail: object["on"] == .bool(true) ? "on" : "off")
            return .bool(true)
        default:
            report.call(method, refused: "Ledge has no such call")
            throw CLIError("Unknown call \(method).")
        }
    }
}

// MARK: The report

private final class CheckReport: @unchecked Sendable {
    private let manifest: AddOnManifest
    private let lock = NSLock()
    var started = false
    private(set) var problems: [String] = []
    private(set) var warnings: [String] = []
    private var timeline: [String] = []
    private var logs: [String] = []
    private var calls: [[String: String]] = []
    /// Per surface: how many sends, how many Ledge took, and why it refused the others.
    private var sent: [String: (sent: Int, accepted: Int, refusals: [String])] = [:]
    /// The last version of each surface Ledge took, as the add-on sent it: what a person would see when the check ends.
    private var last: [String: JSONValue] = [:]
    private(set) var hasPage = false
    /// Everything the terminal's program wrote, up to 256 KB.
    private var terminalOutput = Data()
    private(set) var hasAttentionActivity = false

    init(manifest: AddOnManifest) { self.manifest = manifest }

    func problem(_ text: String) { lock.withLock { if !problems.contains(text) { problems.append(text) } } }
    func warning(_ text: String) { lock.withLock { if !warnings.contains(text) { warnings.append(text) } } }
    func note(_ text: String) { lock.withLock { timeline.append(text) } }

    /// Capabilities the check turned off, as a person can in Ledge.
    private var denied: [String] = []

    func deny(_ names: Set<String>) { lock.withLock { denied = names.sorted() } }

    /// Tool calls the script made, and what came back.
    private var tools: [[String: Any]] = []

    /// The picker the add-on last sent.
    func lastPicker() -> Picker? {
        lock.withLock { try? last[Surface.picker]?.decode(Picker.self) }
    }

    /// Where files can be shared: the share target's destinations and the notch page's rows that take files.
    func shareDestinations() -> Set<String> {
        lock.withLock {
            var ids = Set(((try? last[Surface.shareTarget]?.decode(ShareTarget.self))?.destinations ?? []).map(\.id))
            if let page = try? last[Surface.notchPage]?.decode(NotchPage.self) {
                ids.formUnion(page.screen.content.listRows.filter { $0.acceptsFiles == true }.map(\.id))
            }
            return ids
        }
    }

    /// The tools the add-on last offered.
    func lastTools() -> [AddOnTool] {
        lock.withLock { (try? last[Surface.aiTool]?.decode([AddOnTool].self)) ?? [] }
    }

    func tool(_ name: String, arguments: JSONValue, result: ToolResult) {
        let object = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(result), options: [.fragmentsAllowed])) ?? NSNull()
        lock.withLock {
            tools.append(["tool": name, "result": object])
            timeline.append("tool \(name): answered")
        }
    }

    func tool(_ name: String, arguments: JSONValue, refused reason: String) {
        lock.withLock {
            tools.append(["tool": name, "refused": reason])
            timeline.append("tool \(name): refused, \(reason)")
        }
    }

    /// A call refused because its capability was turned off: what Ledge does, and what the add-on has to handle.
    func call(_ method: String, denied capability: String) {
        lock.withLock {
            calls.append(["method": method, "result": "denied", "reason": "\(capability) is turned off"])
            timeline.append("call \(method): refused, \(capability) is turned off")
        }
    }

    func call(_ method: String, refused reason: String? = nil, detail: String? = nil) {
        lock.withLock {
            var entry = ["method": method, "result": reason == nil ? "allowed" : "refused"]
            if let reason { entry["reason"] = reason }
            if let detail { entry["detail"] = detail }
            calls.append(entry)
            timeline.append("call \(method)\(reason.map { ": refused, \($0)" } ?? "")")
        }
        if let reason { problem("\(method) was refused: \(reason).") }
    }

    func received(_ event: AddOnRuntime.Event) {
        switch event {
        case let .log(level, message):
            lock.withLock { logs.append("[\(level.rawValue)] \(message)") }
            if level == .error { warning("It logged an error: \(message)") }
        case let .update(topic, payload):
            surface(topic, payload)
        case let .exited(status, restarting):
            problem("It exited with status \(status)\(restarting ? " and Ledge would restart it" : "").")
        case let .failed(reason):
            problem("Ledge would stop it: \(reason)")
        }
    }

    private func surface(_ topic: String, _ payload: JSONValue) {
        guard let name = SurfaceUpdate.surface(forTopic: topic) else {
            warning("It sent \(topic), which Ledge doesn't know and ignores.")
            return
        }
        do {
            let update = try SurfaceUpdate.read(topic: topic, payload: payload, declared: Set(manifest.surfaces ?? []))
            // A terminal's output is a stream, kept whole rather than as its last piece.
            if case .terminalOutput(let data)? = update {
                lock.withLock {
                    sent[name, default: (0, 0, [])].sent += 1
                    sent[name, default: (0, 0, [])].accepted += 1
                    if terminalOutput.count < 262_144 { terminalOutput.append(data) }
                }
                newerThanMinAPI(update)
                return
            }
            lock.withLock {
                sent[name, default: (0, 0, [])].sent += 1
                sent[name, default: (0, 0, [])].accepted += 1
                last[name] = payload
                timeline.append("sent \(name)")
                switch update {
                case .notchPage(let page)?:
                    hasPage = page != nil
                case .activities(let list)?:
                    hasAttentionActivity = list.contains { $0.importance == .attention }
                default: break
                }
            }
            newerThanMinAPI(update)
        } catch {
            let reason = describe(error)
            lock.withLock {
                sent[name, default: (0, 0, [])].sent += 1
                sent[name, default: (0, 0, [])].refusals.append(reason)
                timeline.append("sent \(name): refused, \(reason)")
            }
            problem("Ledge refused its \(name): \(reason)")
        }
    }

    /// Things in a surface an older Ledge can't read, against kit.minAPI.
    private func newerThanMinAPI(_ update: SurfaceUpdate?) {
        guard let minAPI = manifest.kit?.minAPI else { return }
        func needs(_ version: String, _ what: String) {
            if AddOnManifest.compare(minAPI, version) == .orderedAscending {
                problem("\(what) needs LedgeKit \(version), but kit.minAPI is \(minAPI). Raise kit.minAPI.")
            }
        }
        switch update {
        case .notchPage(let page)?:
            needs("0.12.0", "A notch page")
            if page?.screen.content.listRows.contains(where: { $0.acceptsFiles == true }) == true { needs("0.20.0", "A list row that takes files") }
            if page?.screen.content.hasImage == true { needs("0.21.0", "An image on a page") }
            if page?.screen.content.hasSlider == true { needs("0.22.0", "A slider on a page") }
            if page?.screen.content.hasNativeControls == true || page?.preferredWidth != nil { needs("0.23.0", "Native page controls or preferred width") }
        case .activities(let list)?:
            if list.contains(where: { $0.kind != nil || $0.accessibilityValue != nil || $0.importance == .attention }) {
                needs("0.13.0", "An activity's kind, accessibilityValue or .attention")
            }
        case .settingsPage(let page)?:
            if page.keywords != nil || page.sections.contains(where: { $0.rows.contains { $0.confirm != nil } }) {
                needs("0.13.0", "A settings page's keywords or confirmed buttons")
            }
        case .lockScreenRow?, .menuBarTiles?: needs("0.11.0", "Lock screen rows and menu bar tiles")
        case .widgets(let list)?:
            if list.contains(where: { $0.size != .small }) { needs("0.15.0", "A medium or large widget") }
            if list.contains(where: { $0.compactContent != nil }) { needs("0.17.0", "A widget's compactContent") }
            if list.contains(where: { $0.content.needsSliderOrImage || $0.compactContent?.needsSliderOrImage == true }) {
                needs("0.22.0", "A slider or image in a widget")
            }
        case .tools?: needs("0.16.0", "Tools for AI apps")
        case .terminalOutput?, .terminalState?: needs("0.18.0", "A terminal")
        case .picker?: needs("0.19.0", "A picker")
        case .shareTarget?: needs("0.20.0", "A share target")
        case .shortcuts?: needs("0.22.0", "Shortcuts")
        default: break
        }
    }

    /// After the run: what was declared and never sent.
    func finish() {
        let declared = Set(manifest.surfaces ?? [])
        for surface in declared.sorted() where sent[surface] == nil {
            // Player buttons and menus are sent when there's a song, which a check doesn't play.
            if [Surface.playerAction, Surface.player].contains(surface) { continue }
            warning("addon.json declares \(surface), but it never sent one. Send it, or take it out of surfaces.")
        }
        if !started && problems.isEmpty { problem("It never started.") }
    }

    var passed: Bool { started && problems.isEmpty }

    func printSummary() {
        lock.withLock {
            print("")
            for (surface, counts) in sent.sorted(by: { $0.key < $1.key }) {
                let mark = counts.refusals.isEmpty ? "✓" : "✗"
                print("\(mark) \(surface): sent \(counts.sent), Ledge took \(counts.accepted)")
            }
            if !calls.isEmpty {
                let allowed = calls.filter { $0["result"] == "allowed" }.count
                print("• calls to Ledge: \(calls.count), \(allowed) allowed")
            }
            if !denied.isEmpty {
                let refused = calls.filter { $0["result"] == "denied" }.count
                print("⊘ turned off: \(denied.joined(separator: ", ")). Ledge refused \(refused) call\(refused == 1 ? "" : "s"); look at what the add-on showed instead.")
            }
            for line in problems { print("✗ \(line)") }
            for line in warnings { print("! \(line)") }
            print(passed ? "✓ Ledge would run it as it is." : "\(problems.count) problem\(problems.count == 1 ? "" : "s").")
        }
    }

    /// A terminal's output as a person reads it: colors, cursor moves and titles taken out, Returns kept.
    static func plainText(_ data: Data) -> String {
        var text = String(decoding: data, as: UTF8.self)
        for pattern in ["\u{1B}\\][^\u{07}\u{1B}]*(\u{07}|\u{1B}\\\\)", "\u{1B}\\[[0-9;?]*[ -/]*[@-~]", "\u{1B}[()][0-9A-Za-z]", "\u{1B}[=>78]"] {
            text = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "")
    }

    func json() throws -> Data {
        try lock.withLock {
            let object: [String: Any] = [
                "addOn": ["id": manifest.id, "version": manifest.version, "minAPI": manifest.kit?.minAPI ?? NSNull()],
                "checkedWith": SessionProtocol.release,
                "passed": passed,
                "started": started,
                "surfaces": sent.sorted { $0.key < $1.key }.map { name, counts in
                    var entry: [String: Any] = ["surface": name, "declared": (manifest.surfaces ?? []).contains(name), "sent": counts.sent,
                                                "accepted": counts.accepted, "refusals": counts.refusals]
                    if let payload = last[name], let data = try? JSONEncoder().encode(payload),
                       let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
                        entry["last"] = object
                    }
                    return entry
                } + Set(manifest.surfaces ?? []).subtracting(sent.keys).sorted().map {
                    ["surface": $0, "declared": true, "sent": 0, "accepted": 0, "refusals": [String]()] as [String: Any]
                },
                "calls": calls,
                "terminal": terminalOutput.isEmpty ? NSNull() : ["output": Self.plainText(terminalOutput)] as Any,
                "denied": denied,
                "tools": tools,
                "problems": problems,
                "warnings": warnings,
                "timeline": timeline,
                "logs": logs,
            ]
            return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        }
    }
}
