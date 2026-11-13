import Foundation
import LedgeKit

// `ledgekit update`: moves an add-on to this ledgekit's LedgeKit. Package.swift's pin moves and Package.resolved with it;
// kit.minAPI stays, so the add-on keeps running in every Ledge it ran in, until it uses something new and
// `--raise` moves that too. `ledgekit check` says when it does.

private let pinPattern = #"(\.package\(\s*url:\s*"https://github\.com/Ammyy9908/LedgeKit\.git"\s*,\s*exact:\s*")([0-9]+\.[0-9]+\.[0-9]+)(")"#
private let minAPIPattern = #"("minAPI"\s*:\s*")([0-9]+\.[0-9]+\.[0-9]+)(")"#

/// The LedgeKit release an add-on's Package.swift pins, or nil when it doesn't pin one by URL.
func pinnedKit(in folder: URL) -> String? {
    guard let text = try? String(contentsOf: folder.appendingPathComponent("Package.swift"), encoding: .utf8) else { return nil }
    return firstMatch(pinPattern, in: text)?.value
}

func update(_ given: [String]) throws {
    var arguments = given
    let raise = flag("--raise", in: &arguments)
    let folder = packageFolder(arguments)
    let manifest = try readManifest(in: folder)
    let release = SessionProtocol.release

    // Package.swift: the pin.
    let packageFile = folder.appendingPathComponent("Package.swift")
    guard var package = try? String(contentsOf: packageFile, encoding: .utf8) else {
        throw CLIError("No Package.swift in \(folder.path).")
    }
    guard let pin = firstMatch(pinPattern, in: package) else {
        if package.contains(".package(path:") {
            throw CLIError("Package.swift uses a local LedgeKit. Pin the published one instead: .package(url: \"\(kitURL)\", exact: \"\(release)\")")
        }
        throw CLIError("Package.swift doesn't pin LedgeKit as .package(url: \"\(kitURL)\", exact: \"…\"), so there's nothing to move.")
    }
    switch AddOnManifest.compare(pin.value, release) {
    case .orderedDescending:
        throw CLIError("Package.swift pins LedgeKit \(pin.value), newer than this ledgekit (\(release)). Update ledgekit first: git pull in LedgeKit, then swift build -c release.")
    case .orderedSame:
        print("Package.swift already pins LedgeKit \(release).")
    case .orderedAscending:
        package.replaceSubrange(pin.range, with: release)
        try package.write(to: packageFile, atomically: true, encoding: .utf8)
        print("Package.swift: LedgeKit \(pin.value) → \(release)")
        print("Resolving…")
        try run("swift", ["package", "resolve"], in: folder)
        print("Package.resolved: LedgeKit \(release)")
    }

    // addon.json: kit.minAPI, only when asked.
    let apiLevel = SessionProtocol.apiLevel
    let minAPI = manifest.kit?.minAPI
    if raise {
        let manifestFile = folder.appendingPathComponent("addon.json")
        var text = try String(contentsOf: manifestFile, encoding: .utf8)
        guard let declared = firstMatch(minAPIPattern, in: text) else {
            throw CLIError("addon.json has no kit.minAPI to raise. Add \"kit\": { \"minAPI\": \"\(apiLevel)\" }.")
        }
        if declared.value == apiLevel {
            print("addon.json: kit.minAPI is \(apiLevel) already.")
        } else {
            text.replaceSubrange(declared.range, with: apiLevel)
            try text.write(to: manifestFile, atomically: true, encoding: .utf8)
            print("addon.json: kit.minAPI \(declared.value) → \(apiLevel). Ledge older than LedgeKit \(apiLevel) will say \(manifest.name) needs an update.")
        }
    } else if let minAPI, AddOnManifest.compare(minAPI, apiLevel) == .orderedAscending {
        print("""
        kit.minAPI stays \(minAPI), so \(manifest.name) still runs in every Ledge with LedgeKit \(minAPI) or later.
        When it uses something newer, ledgekit update --raise moves it to \(apiLevel); ledgekit check says when.
        """)
    }
    print("Next: swift test, then ledgekit check. AGENTS.md is yours; ledgekit agent --force writes this release's brief over it.")
}

/// The first match of a three-group pattern: the middle group's text and range.
private func firstMatch(_ pattern: String, in text: String) -> (value: String, range: Range<String.Index>)? {
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          let range = Range(match.range(at: 2), in: text) else { return nil }
    return (String(text[range]), range)
}
