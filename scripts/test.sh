#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo"
mkdir -p build/native build/module-cache
common=(-O -swift-version 5 -parse-as-library -module-cache-path build/module-cache)
xcrun swiftc "${common[@]}" Sources/Shared/MotionClock.swift Tests/MotionTests.swift \
  -o build/native/test-motion
build/native/test-motion
xcrun swiftc "${common[@]}" Sources/Shared/ShaderLibrary.swift Sources/App/WallpaperSelection.swift \
  Tests/SelectionTests.swift -o build/native/test-selection -framework AppKit
build/native/test-selection
xcrun swiftc "${common[@]}" Sources/Shared/*.swift Tests/RendererLifecycleTests.swift \
  -o build/native/test-lifecycle -framework AppKit -framework Metal -framework AVFoundation
build/native/test-lifecycle Resources
xcrun swiftc "${common[@]}" Sources/Shared/*.swift Tests/DaylightTests.swift \
  -o build/native/test-daylight -framework AppKit -framework Metal -framework AVFoundation
build/native/test-daylight Resources
