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
version="$(grep -o 'apiLevel = "[0-9.]*"' Sources/LedgeKit/SessionProtocol.swift | grep -o '[0-9.]*')"

swift package dump-symbol-graph >/dev/null
graphs="$(mktemp -d)"
trap 'rm -rf "$graphs"' EXIT
# Only the library add-ons are written with: not the CLI, the host or the test fixture.
cp "$(swift build --show-bin-path)/../symbolgraph/LedgeKit.symbols.json" "$graphs/" 2>/dev/null \
  || cp .build/*/symbolgraph/LedgeKit.symbols.json "$graphs/"

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
