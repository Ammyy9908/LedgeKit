import Foundation
import LedgeKit

// ledgekit submit: the add-on as a pull request to LedgeAddOns.
//
// It checks first, the way review will (validate --submit, the tests, and check), then copies only what the Store
// takes into add-ons/<id>/ on a fresh branch of your LedgeAddOns checkout or fork, runs the repository's own
// validate.py, commits, pushes and opens the pull request with the template filled in. --print does the checks and
// shows the rest without doing it.

private let upstream = "Ammyy9908/LedgeAddOns"

func submit(_ given: [String]) async throws {
    var arguments = given
    let printOnly = flag("--print", in: &arguments)
    let repoPath = option("--repo", in: &arguments)
    let folder = packageFolder(arguments)
    let manifest = try readManifest(in: folder)

    // 1. What review checks first.
    print("Checking \(manifest.name) \(manifest.version) the way review will…")
    guard try validate([folder.path, "--submit"]) else { throw CLIError("Fix what validate --submit reports, then submit again.") }
    guard try lint([folder.path]) else { throw CLIError("ledgekit lint found errors review would send back. Fix them, then submit again.") }
    do { try run("swift", ["test", "--package-path", folder.path]) } catch { throw CLIError("The tests fail. Fix them, then submit again.") }
    let reportFile = FileManager.default.temporaryDirectory.appendingPathComponent("ledgekit-submit-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: reportFile) }
    guard try await check([folder.path, "--report", reportFile.path]) else {
        throw CLIError("ledgekit check found problems Ledge would refuse. Fix them, then submit again.")
    }
    let report = (try? JSONSerialization.jsonObject(with: Data(contentsOf: reportFile))) as? [String: Any] ?? [:]

    let branch = "add-\(manifest.id)-\(manifest.version)"
    let files = submittedFiles(in: folder)
    let body = pullRequestBody(manifest, report: report)
    let gh = (try? output("which", ["gh"])).flatMap { $0.isEmpty ? nil : $0 }

    if printOnly {
        // Whether this is an update: known from the checkout when there is one.
        let existing = repoPath.map { FileManager.default.fileExists(atPath: URL(fileURLWithPath: $0).appendingPathComponent("add-ons/\(manifest.id)/addon.json").path) }
        let titleLine = existing.map { title(manifest, existing: $0) }
            ?? "\(title(manifest, existing: false)), or \(title(manifest, existing: true)) if LedgeAddOns has it already"
        print("""

        Would copy into add-ons/\(manifest.id)/ on a branch \(branch) of \(repoPath ?? "your fork of \(upstream)"):
        \(files.map { "  \($0)" }.joined(separator: "\n"))
        then run scripts/validate.py there, commit, push, and open a pull request against \(upstream):main.
        \(gh == nil ? "\nThe GitHub CLI isn't installed (brew install gh, then gh auth login), so you'd open the pull request yourself from the link it prints.\n" : "")
        Title: \(titleLine)

        \(body)
        """)
        return
    }

    // 2. A checkout to work in: the one given, or a fresh clone of your fork.
    let checkout: URL
    if let repoPath {
        checkout = URL(fileURLWithPath: repoPath, isDirectory: true).standardizedFileURL
        guard FileManager.default.fileExists(atPath: checkout.appendingPathComponent("scripts/validate.py").path) else {
            throw CLIError("\(checkout.path) isn't a LedgeAddOns checkout.")
        }
    } else {
        guard gh != nil else {
            throw CLIError("Submitting needs the GitHub CLI (brew install gh, then gh auth login), or --repo <your LedgeAddOns checkout>.")
        }
        checkout = FileManager.default.temporaryDirectory.appendingPathComponent("LedgeAddOns-\(UUID().uuidString)")
        try run("gh", ["repo", "fork", upstream, "--clone=false"])
        let user = try output("gh", ["api", "user", "--jq", ".login"])
        try run("gh", ["repo", "clone", "\(user)/LedgeAddOns", checkout.path, "--", "--quiet"])
    }
    let status = try output("git", ["-C", checkout.path, "status", "--porcelain"])
    guard status.isEmpty else { throw CLIError("\(checkout.path) has uncommitted changes. Commit or stash them first.") }

    // 3. A branch from LedgeAddOns' main, with the add-on's folder in it.
    let upstreamURL = "https://github.com/\(upstream).git"
    try run("git", ["-C", checkout.path, "fetch", "--quiet", upstreamURL, "main"])
    try run("git", ["-C", checkout.path, "switch", "--quiet", "-C", branch, "FETCH_HEAD"])
    let target = checkout.appendingPathComponent("add-ons/\(manifest.id)", isDirectory: true)
    let existing = FileManager.default.fileExists(atPath: target.path)
    // An update has to move the version forward, or the Store keeps what it has.
    if existing, let published = try? readManifest(in: target),
       AddOnManifest.compare(manifest.version, published.version) != .orderedDescending {
        try? run("git", ["-C", checkout.path, "switch", "--quiet", "-"])
        throw CLIError("LedgeAddOns already has \(manifest.name) \(published.version). Raise version in addon.json and add a CHANGELOG.md entry for it.")
    }
    try? FileManager.default.removeItem(at: target)
    for path in files {
        let destination = target.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: folder.appendingPathComponent(path), to: destination)
    }

    // 4. The repository's own checks, then the commit.
    do { try run("python3", ["scripts/validate.py"], in: checkout) } catch {
        throw CLIError("LedgeAddOns' validate.py refused it, in \(checkout.path) on \(branch). Fix the add-on and submit again.")
    }
    let pullTitle = title(manifest, existing: existing)
    try run("git", ["-C", checkout.path, "add", "add-ons/\(manifest.id)"])
    guard try !output("git", ["-C", checkout.path, "diff", "--cached", "--name-only"]).isEmpty else {
        throw CLIError("Nothing changed from what LedgeAddOns has, so there's nothing to submit.")
    }
    try run("git", ["-C", checkout.path, "commit", "--quiet", "-m", pullTitle + "\n\nOpened with ledgekit submit."])

    // 5. Push, and open the pull request.
    try run("git", ["-C", checkout.path, "push", "--quiet", "--force-with-lease", "-u", "origin", branch])
    let origin = try output("git", ["-C", checkout.path, "remote", "get-url", "origin"])
    let owner = origin.replacingOccurrences(of: ".git", with: "").split(whereSeparator: { $0 == "/" || $0 == ":" }).dropLast().last.map(String.init) ?? ""
    if gh != nil {
        let bodyFile = FileManager.default.temporaryDirectory.appendingPathComponent("ledgekit-pr-\(UUID().uuidString).md")
        try body.write(to: bodyFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: bodyFile) }
        try run("gh", ["pr", "create", "--repo", upstream, "--base", "main", "--head", "\(owner):\(branch)",
                       "--title", pullTitle, "--body-file", bodyFile.path])
    } else {
        let bodyFile = checkout.appendingPathComponent(".git/ledgekit-pull-request.md")
        try body.write(to: bodyFile, atomically: true, encoding: .utf8)
        print("""

        Pushed \(branch). Open the pull request here, and paste the description from \(bodyFile.path):
        https://github.com/\(upstream)/compare/main...\(owner):\(branch)?expand=1
        """)
    }
}

private func title(_ manifest: AddOnManifest, existing: Bool) -> String {
    existing ? "Update \(manifest.name) to \(manifest.version)" : "Add \(manifest.name) \(manifest.version): \(manifest.summary)"
}

/// What the Store takes, by path: the allowed top-level items, without local-only files or build products.
private func submittedFiles(in folder: URL) -> [String] {
    let allowed: Set<String> = ["addon.json", "listing.json", "Package.swift", "Package.resolved", "README.md", "CHANGELOG.md",
                                "LICENSE", "NOTICE.md", ".gitignore", "Sources", "Tests", "Assets", "Store"]
    let manager = FileManager.default
    var files: [String] = []
    for top in ((try? manager.contentsOfDirectory(atPath: folder.path)) ?? []).sorted() where allowed.contains(top) {
        var isFolder: ObjCBool = false
        manager.fileExists(atPath: folder.appendingPathComponent(top).path, isDirectory: &isFolder)
        if !isFolder.boolValue { files.append(top); continue }
        for path in ((try? manager.subpathsOfDirectory(atPath: folder.appendingPathComponent(top).path)) ?? []).sorted() {
            let full = folder.appendingPathComponent(top).appendingPathComponent(path)
            var inner: ObjCBool = false
            manager.fileExists(atPath: full.path, isDirectory: &inner)
            if inner.boolValue || path.hasSuffix(".DS_Store") { continue }
            files.append("\(top)/\(path)")
        }
    }
    return files
}

/// The repository's pull request template, filled in from the manifest and the check.
private func pullRequestBody(_ manifest: AddOnManifest, report: [String: Any]) -> String {
    let surfaces = (manifest.surfaces ?? []).joined(separator: ", ")
    let capabilities = manifest.capabilities.isEmpty ? "none" : manifest.capabilities.map { "`\($0)`" }.joined(separator: ", ")
    let accepted = (report["surfaces"] as? [[String: Any]] ?? []).compactMap { entry -> String? in
        guard let name = entry["surface"] as? String, let count = entry["accepted"] as? Int, count > 0 else { return nil }
        return "\(name) (\(count) accepted)"
    }
    let calls = Set((report["calls"] as? [[String: String]] ?? []).compactMap { $0["method"] }).sorted()
    let warnings = report["warnings"] as? [String] ?? []
    return """
    ## Add-on
    \(manifest.name) (`\(manifest.id)`) \(manifest.version). \(manifest.summary). Needs LedgeKit \(manifest.kit?.minAPI ?? "?").

    \(manifest.description)

    ## Capabilities and data
    - Capabilities: \(capabilities). Surfaces: \(surfaces).
    - Calls to Ledge seen in `ledgekit check`: \(calls.isEmpty ? "none" : calls.joined(separator: ", ")).
    - Network destinations, credentials and what it stores: (describe them here)

    ## Checklist
    - [x] `python3 scripts/validate.py` passes
    - [x] Tests pass (`swift test --package-path add-ons/\(manifest.id)`)
    - [ ] Loaded and tried in Ledge (`ledgekit run`, or `python3 scripts/package.py \(manifest.id)` then Load Add-on…)
    - [x] `version` raised in `addon.json` and a matching `CHANGELOG.md` entry added
    - [x] LedgeKit pinned to a published release
    - [ ] No credentials, build products or private content in the folder or Store media
    - [ ] I have the rights to the icon, screenshots and demo
    - [ ] Failure and removal behaviour checked

    ## What was tested
    - `ledgekit validate --submit` and `ledgekit check` (LedgeKit \(report["checkedWith"] as? String ?? SessionProtocol.apiLevel)) pass. Ledge accepted: \(accepted.isEmpty ? "nothing" : accepted.joined(separator: ", ")).\(warnings.isEmpty ? "" : "\n- Check's warnings: " + warnings.joined(separator: " "))
    - (What you tried by hand in Ledge, and what you couldn't test.)

    Opened with `ledgekit submit`. Unticked items are the author's to confirm.
    """
}
