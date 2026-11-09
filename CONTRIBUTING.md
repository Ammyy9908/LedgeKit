# Contributing to LedgeKit

LedgeKit contains public serializable contracts, manifest validation, and worker
transport helpers. Application windows, installation UI, credentials, and provider
business logic belong in host or add-on projects.

Document public APIs and compatibility changes. Preserve decoding of existing
version-1 packages. Add behavior tests for malformed input, unsupported versions,
limits and error redaction. Never log credentials or complete requests.

Run from this repository:
```sh
swift build
swift test
```

The SDK is a developer preview. Changes to wire behavior require testing against
the Ledge host and Spotify Likes example before creating an immutable release tag.
Do not claim process separation is sandboxing. Do not commit generated binaries,
build caches, tokens or signing credentials.
