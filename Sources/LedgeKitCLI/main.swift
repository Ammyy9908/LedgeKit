import Foundation
import LedgeKit

// ledgekit: the add-on developer's tool. Each command is a function in its own file; this one only chooses.

let usage = """
ledgekit \(SessionProtocol.apiLevel): build Ledge add-ons

  ledgekit new <id> [--name "Name"] [--page] [--widget] [--activity] [--into <folder>]
      Writes a working add-on in a new folder: package, tests, manifest, listing, README, changelog, icon.
  ledgekit build [<folder>]
      Builds a .ledgeaddon you can load in Ledge (Settings, Add-on Store, Load Add-on…), ad-hoc signed.
  ledgekit validate [<folder> | <addon.json>]
      Checks an add-on folder the way LedgeAddOns does, or just a manifest.
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
