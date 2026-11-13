import AppKit
import Foundation
import LedgeKit

// ledgekit validate: an add-on folder checked the way LedgeAddOns checks a pull request, so nothing CI refuses is a
// surprise. What a fresh scaffold leaves for you to write is a warning, so it validates from the start; --submit
// makes those warnings errors, as a submission should.

private let allowedTop: Set<String> = ["addon.json", "listing.json", "Package.swift", "Package.resolved", "README.md",
                                       "CHANGELOG.md", "LICENSE", "NOTICE.md", ".gitignore", "Sources", "Tests", "Assets", "Store"]
private let required = ["addon.json", "Package.swift", "README.md", "CHANGELOG.md", "Assets/Icon.png"]
private let kitURL = "https://github.com/Ammyy9908/LedgeKit.git"

/// Returns whether it passed.
func validate(_ given: [String]) throws -> Bool {
    var arguments = given
    let submit = flag("--submit", in: &arguments)
    // `ledgekit validate addon.json`, as before: the manifest alone.
    if let path = arguments.first, path.hasSuffix(".json") {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let manifest = try JSONDecoder().decode(AddOnManifest.self, from: data)
        do { try manifest.validate() } catch { throw CLIError(describe(error)) }
        print("Valid manifest: \(manifest.id) \(manifest.version) (protocol \(manifest.protocolVersion))")
        return true
    }

    let folder = packageFolder(arguments)
    var report = Report()
    check(folder, into: &report)
    if submit {
        report.errors += report.warnings
        report.warnings = []
    }
    for line in report.errors { print("✗ \(line)") }
    for line in report.warnings { print("! \(line)") }
    if report.errors.isEmpty {
        print(report.warnings.isEmpty ? "✓ Ready for LedgeAddOns." : "✓ Valid, with \(report.warnings.count) thing\(report.warnings.count == 1 ? "" : "s") to do before you submit.")
    } else {
        print("\(report.errors.count) problem\(report.errors.count == 1 ? "" : "s") LedgeAddOns would refuse.")
    }
    return report.errors.isEmpty
}

private struct Report {
    var errors: [String] = []
    var warnings: [String] = []
}

private func check(_ folder: URL, into report: inout Report) {
    let manager = FileManager.default
    func exists(_ path: String) -> Bool { manager.fileExists(atPath: folder.appendingPathComponent(path).path) }
    func text(_ path: String) -> String? {
        manager.contents(atPath: folder.appendingPathComponent(path).path).map { String(decoding: $0, as: UTF8.self) }
    }

    // The folder holds only what the Store takes.
    for name in (try? manager.contentsOfDirectory(atPath: folder.path)) ?? [] {
        if name == ".build" || name == ".swiftpm" || name == ".git" || name == ".DS_Store" { continue }
        // Agent files and the tools' output stay on this Mac: .gitignore keeps them out, and so does LedgeAddOns.
        if localOnly.contains(name) {
            let ignored = (try? String(contentsOf: folder.appendingPathComponent(".gitignore"), encoding: .utf8))?
                .split(separator: "\n").contains { $0.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")) == name } ?? false
            if !ignored { report.errors.append("\(name) is for this Mac only. Add it to .gitignore (ledgekit agent does), so it's never committed.") }
            continue
        }
        if !allowedTop.contains(name) {
            report.errors.append("\(name) can't be at the top of an add-on folder. Allowed: \(allowedTop.sorted().joined(separator: ", ")).")
        }
    }
    for path in required where !exists(path) { report.errors.append("\(path) is missing.") }
    let tests = (try? manager.subpathsOfDirectory(atPath: folder.appendingPathComponent("Tests").path)) ?? []
    if !tests.contains(where: { $0.hasSuffix(".swift") }) { report.errors.append("Tests/ has no tests. Every add-on ships with tests.") }

    // The manifest.
    guard let manifest = try? readManifest(in: folder) else {
        report.errors.append("addon.json isn't a manifest LedgeKit can read.")
        return
    }
    do { try manifest.validate() } catch { report.errors.append("addon.json: \(describe(error))") }
    if folder.lastPathComponent != manifest.id && folder.lastPathComponent != ".", folder.deletingLastPathComponent().lastPathComponent == "add-ons" {
        report.errors.append("The folder is \(folder.lastPathComponent), but addon.json's id is \(manifest.id). In LedgeAddOns they match.")
    }
    if manifest.protocolVersion != SessionProtocol.version {
        report.warnings.append("protocolVersion is \(manifest.protocolVersion); add-ons written today use \(SessionProtocol.version), a session.")
    }
    if manifest.icon != "Assets/Icon.png" { report.errors.append("addon.json's icon must be Assets/Icon.png.") }
    if let minAPI = manifest.kit?.minAPI {
        if AddOnManifest.compare(minAPI, SessionProtocol.apiLevel) == .orderedDescending {
            report.errors.append("kit.minAPI is \(minAPI), newer than this LedgeKit (\(SessionProtocol.apiLevel)).")
        }
    } else {
        report.warnings.append("addon.json has no kit.minAPI. Set it to the LedgeKit you build with, so an older Ledge says it needs an update.")
    }
    if manifest.summary.hasPrefix("One line about") { report.warnings.append("addon.json: write the summary.") }
    if manifest.description.contains("Replace this") { report.warnings.append("addon.json: write the description.") }
    if manifest.author == "Your name" { report.warnings.append("addon.json: put your name in author.") }
    if let category = manifest.category, !AddOnManifest.categories.contains(category) {
        report.errors.append("addon.json: category must be one of \(AddOnManifest.categories.joined(separator: ", ")); it's \"\(category)\".")
    }

    // LedgeKit by its published URL, so CI and everyone else build the same thing.
    if let package = text("Package.swift") {
        if !package.contains(kitURL) {
            report.errors.append("Package.swift must depend on LedgeKit by its URL, \(kitURL), pinned to a release.")
        }
        if package.contains(".package(path:") {
            report.errors.append("Package.swift depends on a local path. Pin LedgeKit's published release instead.")
        }
    }

    // A changelog entry for this version.
    if let changelog = text("CHANGELOG.md") {
        if !changelog.contains("## \(manifest.version)") {
            report.errors.append("CHANGELOG.md has no \"## \(manifest.version)\" entry for this version.")
        } else if changelog.contains("not only \"First release\"") {
            report.warnings.append("CHANGELOG.md: write the \(manifest.version) entry.")
        }
    }
    if text("README.md")?.contains("Replace this") == true { report.warnings.append("README.md: write what the add-on does.") }

    // The icon: a square PNG Ledge can draw.
    let iconFile = folder.appendingPathComponent("Assets/Icon.png")
    if exists("Assets/Icon.png") {
        if let image = NSImage(contentsOf: iconFile), let rep = image.representations.first {
            if rep.pixelsWide != rep.pixelsHigh { report.errors.append("Assets/Icon.png must be square; it's \(rep.pixelsWide)×\(rep.pixelsHigh).") }
            if rep.pixelsWide < 256 { report.warnings.append("Assets/Icon.png is \(rep.pixelsWide) pixels; use at least 256, ideally 1024.") }
            if rep.pixelsWide > 2048 { report.errors.append("Assets/Icon.png is \(rep.pixelsWide) pixels; Ledge takes at most 2048. Use 1024.") }
            if isPlaceholderIcon(rep) { report.warnings.append("Assets/Icon.png is still the placeholder ledgekit drew. Draw the add-on's own.") }
        } else {
            report.errors.append("Assets/Icon.png isn't a PNG Ledge can read.")
        }
    }

    // Size limits, as CI applies them.
    for path in (try? manager.subpathsOfDirectory(atPath: folder.path)) ?? [] {
        if path.hasPrefix(".build") || path.hasPrefix(".swiftpm") || path.hasPrefix(".git") { continue }
        let file = folder.appendingPathComponent(path)
        guard let size = (try? manager.attributesOfItem(atPath: file.path))?[.size] as? Int else { continue }
        let limit = path.lowercased().hasSuffix(".mp4") ? 32 : path.lowercased().hasSuffix(".png") ? 8 : 4
        if size > limit * 1024 * 1024 { report.errors.append("\(path) is over \(limit) MB.") }
    }

    checkListing(folder, into: &report)
}

/// listing.json, as LISTING.md describes it and the catalog build reads it.
private func checkListing(_ folder: URL, into report: inout Report) {
    guard let data = FileManager.default.contents(atPath: folder.appendingPathComponent("listing.json").path) else {
        report.errors.append("listing.json is missing: the Store page's developer, category, description and screenshots.")
        return
    }
    guard let listing = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        report.errors.append("listing.json isn't a JSON object.")
        return
    }
    for (field, limit) in [("developer", 120), ("category", 60), ("availability", 120), ("description", 10000)] {
        guard let value = listing[field] as? String, !value.isEmpty, value.count <= limit else {
            report.errors.append("listing.json: \(field) must be text of up to \(limit) characters.")
            continue
        }
        if field == "description", value.hasPrefix("Describe what") { report.warnings.append("listing.json: write the description.") }
        if field == "developer", value == "Your name" { report.warnings.append("listing.json: put your name in developer.") }
        if field == "category", !AddOnManifest.categories.contains(value) {
            report.errors.append("listing.json: category must be one of \(AddOnManifest.categories.joined(separator: ", ")).")
        }
    }
    let feedback = (listing["feedbackURL"] as? String).flatMap(URL.init(string:))
    if feedback?.scheme != "https" || feedback?.host == nil {
        report.errors.append("listing.json: feedbackURL must be an https link.")
    }
    if listing["installs"] != nil { report.errors.append("listing.json: installs is counted by the Store, never supplied.") }
    let screenshots = listing["screenshots"] as? [String] ?? []
    if screenshots.isEmpty {
        report.warnings.append("listing.json: add 1 to 8 screenshots (PNG, in Store/). The Store needs at least one to publish.")
    } else if screenshots.count > 8 {
        report.errors.append("listing.json: at most 8 screenshots.")
    }
    for path in screenshots { checkMedia(path, ".png", folder, into: &report) }
    if let demo = listing["motionDemo"] as? String { checkMedia(demo, ".mp4", folder, into: &report) }
}

private func checkMedia(_ path: String, _ suffix: String, _ folder: URL, into report: inout Report) {
    let file = folder.appendingPathComponent(path).standardizedFileURL
    guard file.path.hasPrefix(folder.path + "/"), path.lowercased().hasSuffix(suffix) else {
        report.errors.append("listing.json: \(path) must be a \(suffix) file inside the add-on's folder.")
        return
    }
    if !FileManager.default.fileExists(atPath: file.path) { report.errors.append("listing.json names \(path), which isn't there.") }
}
