# LedgeKit developer preview

LedgeKit is the Swift package for authoring Ledge add-ons. It currently supports
the version-1, one-request executable transport used by Spotify Likes.
Requires Swift 6 and macOS 14 or later.

## Add the library

During development, place your add-on beside a LedgeKit checkout and declare:
    
```swift
dependencies: [.package(path: "../LedgeKit")],
targets: [
    .executableTarget(name: "MyAddOn", dependencies: ["LedgeKit"])
]
```

A private remote dependency requires GitHub access for every developer and CI
runner. Use an immutable release tag once the standalone repository is published.
The SDK currently ships the library product LedgeKit and executable ledgekit.

## Implement a worker

```swift
import LedgeKit

@main
struct Example {
    static func main() async {
        await AddOnWorker.run { request in
            // Validate your operation and inputs before performing an action.
            return AddOnResponse(value: request.liked ?? false)
        }
    }
}
```

This example demonstrates the transport. Ledge currently installs only the Spotify
Likes adapter. A different package cannot yet register player controls or settings.

The host writes one JSON request and closes stdin. The SDK reads at most 64 KiB
plus one byte to detect overflow, rejects malformed or incompatible requests,
invokes the handler and writes one JSON response. stdout is reserved for this
response. Use stderr for diagnostics and never log tokens or full requests.

The SDK returns a generic error for thrown handler errors to avoid disclosing
credentials. Provider-specific input validation remains the handler's responsibility.
The host owns deadlines and process termination. A blocked input or handler has
no independent worker timeout. Host output limits and lifecycle messages are pending.

## Package metadata

Use AddOnManifest's public initializer, call validate(), then JSONEncoder to
produce addon.json. Existing version-1 JSON without an icon remains compatible.

Required keys: id, version, protocolVersion, name, summary, description, author,
capabilities, executable. Optional icon points to Assets/<filename>.png.
The version format is three nonnegative decimal integers. Protocol version is 1.
The only currently supported capability is spotify-library. Empty capabilities
are valid metadata but do not add host functionality.

Validation throws ManifestValidationError with an invalid field, unsupported
protocol, or unsupported capability. New strict checks reject previously accepted
malformed versions, duplicate capabilities and blank author/name values.

## Validate and build

From the LedgeKit repository root:

```sh
swift run ledgekit validate /path/to/your/addon.json
swift build
swift test
```

CLI exit codes: 0 valid, 1 invalid/unreadable, 2 incorrect usage. The CLI checks
metadata only. The host additionally validates executable and image files.
It does not certify trust, signatures, compatibility with arbitrary capabilities,
or successful installation.

## Support and roadmap

Implemented: manifest authoring/validation, metadata validation CLI, bounded
version-1 input, worker dispatch, example Spotify integration.

Pending: generic package registry and contributions, persistent lifecycle,
capability-scoped host services, credential broker, sandbox enforcement,
CLI scaffolding/build/install, Playground and community publishing.

Version 1 supplies an access token to trusted native code. A subprocess is not a
sandbox. Keep this developer preview restricted to trusted code until sandboxing,
capability enforcement, lifecycle isolation and reviewed distribution are verified.
