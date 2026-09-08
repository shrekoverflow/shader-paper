#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/../.." && pwd)"
out="$repo/build/export"
mkdir -p "$out" "$repo/build/module-cache"
xcrun swiftc -O -parse-as-library -swift-version 5 \
  -module-cache-path "$repo/build/module-cache" \
  "$repo/tools/export/RenderShader.swift" \
  "$repo/Sources/Shared/ShaderRenderer.swift" "$repo/Sources/Shared/MotionClock.swift" \
  -o "$out/render-shader" \
  -framework AppKit -framework Metal -framework CoreVideo -framework AVFoundation \
  -framework IOSurface -framework QuartzCore -framework CoreImage
printf 'Built %s\n' "$out/render-shader"
