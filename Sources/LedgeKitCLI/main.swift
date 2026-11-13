import Foundation
import LedgeKit

// ledgekit: the add-on developer's tool. Each command is a function in its own file; this one only chooses.

let usage = """
ledgekit \(SessionProtocol.apiLevel): build Ledge add-ons

  ledgekit new <id> [--name "Name"] [--page] [--widget] [--activity] [--into <folder>]
      Writes a working add-on in a new folder: package, tests, manifest, listing, README, changelog, icon.
  ledgekit build [<folder>]
      Builds a .ledgeaddon you can load in Ledge (Settings, Add-on Store, Load Add-on…), ad-hoc signed.
  ledgekit validate [<folder> | <addon.json>] [--submit]
      Checks an add-on folder the way LedgeAddOns does, or just a manifest.
  ledgekit check [<folder> | <Name.ledgeaddon>] [--script steps.json] [--report report.json] [--no-build]
      Runs the add-on with no Ledge, the way Ledge would: every surface it sends checked as Ledge checks it,
      its calls to Ledge answered or refused, and a report of what Ledge would make of it.
  ledgekit run [<folder> | <Name.ledgeaddon>] [--no-build]
      Installs it in your Ledge and says whether it started. Needs Ledge's Developer Mode (Add-on Store, ⋯).
  ledgekit shots [<folder> | <Name.ledgeaddon>] [--out shots] [--no-build] [--no-install]
      Installs it, then has Ledge draw each of its surfaces into PNGs, exactly as Ledge draws them.
  ledgekit submit [<folder>] [--print] [--repo <LedgeAddOns checkout>]
      Checks it the way review will, then opens a pull request adding it to LedgeAddOns. --print only shows what.
  ledgekit agent [<folder>] [--force]
      Writes AGENTS.md, CLAUDE.md, Cursor rules and the MCP wiring, so a coding agent knows the rules and the loop.
  ledgekit mcp [--package <folder>]
      A Model Context Protocol server on stdio: the loop above as tools for Claude Code, Codex or Cursor.
  ledgekit version
      The LedgeKit this tool belongs to.

"""

var arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else {
    print(usage, terminator: "")
    exit(0)
}
arguments.removeFirst()

do {
    switch command {
    case "new": try newAddOn(arguments)
    case "build": try build(arguments)
    case "validate": exit(try validate(arguments) ? 0 : 1)
    case "check": exit(try await check(arguments) ? 0 : 1)
    case "run": try runInLedge(arguments)
    case "shots": try shots(arguments)
    case "agent": try agent(arguments)
    case "submit": try await submit(arguments)
    case "mcp": mcp(arguments)
    case "version", "--version": print(SessionProtocol.apiLevel)
    case "help", "--help", "-h": print(usage, terminator: "")
    default:
        fail("Unknown command \(command).\n\n" + usage)
    }
} catch let error as CLIError {
    fail(error.message)
} catch {
    fail(String(describing: error))
}
