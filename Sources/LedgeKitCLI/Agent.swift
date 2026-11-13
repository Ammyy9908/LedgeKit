import Foundation
import LedgeKit

// ledgekit agent: the files a coding agent reads before working on an add-on, and the MCP wiring that gives it the
// whole loop as tools. They're for this Mac only: the scaffold's .gitignore keeps them out of the repository, and
// LedgeAddOns refuses them, so they never reach a submission.

/// Files `agent` writes, by path; AGENTS.md is the brief, the others point at it or at `ledgekit mcp`.
func agentFiles(for folder: URL) -> [(String, String)] {
    let tool = ledgekitPath()
    let server: [String: Any] = ["mcpServers": ["ledgekit": ["command": tool, "args": ["mcp", "--package", folder.path]]]]
    let json = (try? JSONSerialization.data(withJSONObject: server, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]))
        .map { String(decoding: $0, as: UTF8.self) + "\n" } ?? "{}\n"
    return [
        ("AGENTS.md", brief),
        ("CLAUDE.md", "@AGENTS.md\n"),
        (".cursor/rules/ledgekit.mdc", "---\ndescription: Building a Ledge add-on with LedgeKit\nalwaysApply: true\n---\n\n" + brief),
        (".mcp.json", json),
        (".cursor/mcp.json", json),
    ]
}

/// Names kept out of git and out of a submission: agent files and the tools' own output.
let localOnly = ["AGENTS.md", "CLAUDE.md", ".cursor", ".mcp.json", "shots", "check"]
private let ignoreLines = ["AGENTS.md", "CLAUDE.md", ".cursor/", ".mcp.json", "shots/", "check/"]

func agent(_ given: [String]) throws {
    var arguments = given
    let force = flag("--force", in: &arguments)
    let folder = packageFolder(arguments)
    _ = try readManifest(in: folder)
    for (path, text) in agentFiles(for: folder) {
        let file = folder.appendingPathComponent(path)
        // The brief is the developer's to edit once written; only --force writes it again. The wiring is always fresh.
        if ["AGENTS.md", "CLAUDE.md", ".cursor/rules/ledgekit.mdc"].contains(path), FileManager.default.fileExists(atPath: file.path), !force {
            print("  kept \(path)")
            continue
        }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
        print("  wrote \(path)")
    }
    try ignoreLocalFiles(in: folder)
    print("""

    Claude Code reads CLAUDE.md and asks to use the ledgekit server in .mcp.json; Cursor reads .cursor/. For Codex,
    once:  codex mcp add ledgekit -- \(ledgekitPath()) mcp
    Run ledgekit agent again after moving this folder or LedgeKit: the wiring holds absolute paths.
    """)
}

/// Adds the local-only names to .gitignore, so they're never committed or submitted.
func ignoreLocalFiles(in folder: URL) throws {
    let file = folder.appendingPathComponent(".gitignore")
    var lines = (try? String(contentsOf: file, encoding: .utf8))?.split(separator: "\n").map(String.init) ?? []
    var changed = false
    for name in ignoreLines where !lines.contains(name) {
        lines.append(name)
        changed = true
    }
    if changed { try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8) }
}

/// This ledgekit's absolute path, for wiring that has to find it from any shell.
func ledgekitPath() -> String {
    let given = CommandLine.arguments[0]
    let url = given.contains("/")
        ? URL(fileURLWithPath: given, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        : (try? output("which", [given])).map { URL(fileURLWithPath: $0) } ?? URL(fileURLWithPath: given)
    return url.standardizedFileURL.resolvingSymlinksInPath().path
}

let brief = """
# Building a Ledge add-on

This folder is an add-on for Ledge, a macOS app that lives in the notch. It's written with LedgeKit \(SessionProtocol.release).
Read this before changing anything, and keep to it.

## What an add-on is

- A separate program Ledge runs and talks to in JSON. It never draws on screen: it **describes** what to show, and
  Ledge draws it in its own style, after checking it against its limits.
- `Sources/<Name>Core` holds what the add-on knows and **builds every surface** (settings page, widget, notch page,
  activities). `Sources/<Name>/main.swift` only runs the session and sends what Core builds. Keep logic in Core, so the
  tests can check it without Ledge.
- `addon.json` names the add-on, the **surfaces** it shows and the **capabilities** it asks for. They must match what
  the code does: Ledge refuses a surface that isn't declared, and a call whose capability isn't listed.

## What Ledge gives each surface

- **Widget**: the Widgets page shows one widget at a time, under a title strip. Its `size` sets the room, at the
  default notch width (60 points narrower at Compact, 80 wider at Large): `.small` (the default) **348 × 78 points**,
  two or three short lines; `.medium` **348 × 138**; `.large` **348 × 198**. Pick the smallest that fits; anything
  taller is cut off at the bottom. Medium and large need `kit.minAPI` 0.15.0. A row with a `spacer` in it spans the full width, so the spacer pushes what follows to the right edge.
- **Notch page**: 348 points wide by default, and 122, 202 or 282 points tall for `small`, `medium` and `large`.
  On a display with a camera notch, its header sits either side of the camera: about 39 points a side at Compact,
  69 at Regular. Keep titles short; Ledge truncates them rather than put them under the camera.
- **Live activity**: a symbol and a short text. Beside a camera notch the text gets about 64 points; as a pill on a
  display without one, the capsule's width; in the card below the notch, about 125. Write it to fit 64.
- **Settings page**: rows in Ledge's Settings window. A `button` row's button reads the row's `title`; its `detail`
  is the label beside it.
- **Categories** (`category` in addon.json and listing.json): AI, Productivity, Media, Capture, Files or System.
- **Capabilities** this LedgeKit knows: `clipboard-write` (`LedgeHost.copy`), `hud` (`LedgeHost.notify`),
  `notch-control` (`showPage`, `openSettings`, `holdOpen`), and the account ones Ledge brokers: `spotify-library`,
  `apple-music-queue`, `apple-music-controls`, `notification-banners`. Settings, the environment and `dataFolder`
  need none.

## What the program may do

An add-on is an ordinary Mac program running as the user, not sandboxed: it can read files, run tools like
`/usr/sbin/system_profiler` or `pmset`, and use IOKit or other system frameworks. Ledge's review reads all of it, so:
give every process and request a deadline (a few seconds) so a hang never leaves a surface stuck, do it off the
session's actor, read only what the add-on shows, and say in the README what it reads.

## The loop: after every change

Use the `ledgekit` MCP tools when you have them; otherwise the same commands in a shell.

1. `swift test` (tool `ledgekit_test`). Core's tests include every surface checked against Ledge's limits.
2. `ledgekit build` (`ledgekit_build`).
3. `ledgekit check --report check/report.json` (`ledgekit_check`). It runs the add-on with no Ledge and says what
   Ledge would refuse. **You're not done while it reports problems.** Read the warnings too.
4. `ledgekit shots --out shots` (`ledgekit_shots`) when the user's Ledge has Developer Mode on: Ledge draws each
   surface into a PNG, in every shape people meet it in: each notch width, beside a camera and as a pill.
   **Look at them, the narrowest first** (`@notch-compact`); a surface that passes check can still look wrong.
5. `ledgekit validate` (`ledgekit_validate`) before saying it's ready, and `ledgekit validate --submit` before a pull
   request to LedgeAddOns.

A green build isn't the end. Check, then look.

## Rules that aren't negotiable

- Surfaces in `addon.json` and what the code sends agree. Capabilities: list what you use, nothing more.
- Never pin LedgeKit to a local path. `Package.swift` depends on https://github.com/Ammyy9908/LedgeKit.git at an exact
  release, and `kit.minAPI` in `addon.json` is at least the LedgeKit whose features you use (check flags it).
- Raise `version` in `addon.json` for every release and add a `## <version>` entry at the top of `CHANGELOG.md`.
- Work only while something is seen: use `onVisibilityChange` instead of polling surfaces nobody has open.
- Files go in `LedgeHost.dataFolder()`. Secrets go in the Keychain, never `LedgeHost.set`, which is plain JSON on disk.
- Anything that costs battery, takes something over or sends something about the user is **off until the user turns it on**.
- Destructive settings buttons ask first (`confirm:`). Prefer the Trash to deleting.
- `.attention` importance only while something needs acting on now. Take activities down when they have nothing to say.
- Words: English, sentence case ("Show seconds", never "Show Seconds"), short titles, whole sentences. No other
  company's logo or icon anywhere, including `Assets/Icon.png`.
- Never log what the add-on reads (notes, songs, accounts): log that something failed, not its contents.
- Don't add files at the top of the folder beyond what LedgeAddOns takes: addon.json, listing.json, Package.swift,
  Package.resolved, README.md, CHANGELOG.md, LICENSE, NOTICE.md, .gitignore, Sources, Tests, Assets, Store.

## Before it's ready to submit

Replace every placeholder `ledgekit new` left: summary and description in `addon.json`, `listing.json`'s description,
`README.md`, the first `CHANGELOG.md` entry, `Assets/Icon.png` (the developer's own, 1024 px, no one else's marks),
and at least one screenshot in `Store/` named in `listing.json` (`ledgekit shots` makes good ones). Then
`ledgekit validate --submit` must pass.

## These agent files

`AGENTS.md`, `CLAUDE.md`, `.cursor/` and `.mcp.json` are listed in `.gitignore` on purpose: they hold paths on this
Mac and are for the developer's tools, so LedgeAddOns refuses them. Edit AGENTS.md freely; don't commit it.

## Docs

https://www.tryledge.app/docs/ledgekit: the surfaces, Asking Ledge, Good add-ons, limits. `ledgekit help` for the
tool. LedgeKit's own sources are in this package's checkout under `.build/checkouts/LedgeKit` after a build.
"""
