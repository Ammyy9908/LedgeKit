#!/bin/zsh
# Builds LedgeKit's API reference with DocC, from the library's doc comments, into a static site.
#
#   Scripts/docs.sh [output folder] [hosting base path]
#
# Defaults: .build/docs, hosted at /LedgeKit (GitHub Pages for Ammyy9908/LedgeKit). Needs Xcode's docc.
set -euo pipefail
cd "$(dirname "$0")/.."
out="${1:-.build/docs}"
base="${2:-LedgeKit}"
version="$(grep -o 'release = "[0-9.]*"' Sources/LedgeKit/SessionProtocol.swift | grep -o '[0-9.]*')"

graphs="$(mktemp -d)"
trap 'rm -rf "$graphs"' EXIT
# Only the library add-ons are written with: the compiler writes its symbol graph as it builds the one target, so
# the CLI, the host, the test fixture and the tests never come into it. (swift package dump-symbol-graph extracts
# every module, and fails on the tests with some toolchains.)
swift build --target LedgeKit -Xswiftc -emit-symbol-graph -Xswiftc -emit-symbol-graph-dir -Xswiftc "$graphs" >/dev/null
[[ -f "$graphs/LedgeKit.symbols.json" ]] || { echo "No symbol graph for LedgeKit." >&2; exit 1; }

rm -rf "$out"
xcrun docc convert \
  --additional-symbol-graph-dir "$graphs" \
  --fallback-display-name LedgeKit \
  --fallback-bundle-identifier app.ledge.LedgeKit \
  --fallback-bundle-version "$version" \
  --output-path "$out" \
  --transform-for-static-hosting \
  --hosting-base-path "$base"
echo "LedgeKit $version reference: $out (open $out/documentation/ledgekit/index.html through a web server at /$base)"
