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
