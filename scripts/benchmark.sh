#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo"
mkdir -p build/native build/module-cache
xcrun swiftc -O -swift-version 5 -parse-as-library -module-cache-path build/module-cache \
  Sources/Shared/*.swift Tests/BenchmarkRenderer.swift -o build/native/benchmark-renderer \
  -framework AppKit -framework Metal -framework AVFoundation
build/native/benchmark-renderer Resources build/native/render-benchmark.json
