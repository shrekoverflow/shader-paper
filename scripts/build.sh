#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
out="$repo/build/native"
app="$out/Shader Paper.app"
ext="$app/Contents/Extensions/MeditationExtension.appex"
mkdir -p "$out" "$repo/build/module-cache" "$app/Contents/MacOS" "$app/Contents/Resources" "$ext/Contents/MacOS" "$ext/Contents/Resources"
common=(-O -swift-version 5 -target arm64-apple-macos26.0 -module-cache-path "$repo/build/module-cache")
code_sign_identity="${CODE_SIGN_IDENTITY:--}"
signing=(--force --sign "$code_sign_identity" --options runtime)
if [[ "$code_sign_identity" != - ]]; then
  # Developer ID distribution requires a secure timestamp; local ad-hoc
  # builds keep their existing offline signing behavior.
  signing+=(--timestamp)
fi
# Bundle only the curated collection declared in Resources/Shaders.txt.
# Clear generated resources so rebuilding an older bundle also removes choices
# that are no longer featured.
for bundle in "$app" "$ext"; do
  rm -rf "$bundle/Contents/Resources/shaders" "$bundle/Contents/Resources/Previews"
  mkdir -p "$bundle/Contents/Resources/shaders" "$bundle/Contents/Resources/Previews"
  while IFS= read -r shader || [[ -n "$shader" ]]; do
    [[ -n "$shader" ]] || continue
    cp "$repo/Resources/shaders/$shader.shader" "$bundle/Contents/Resources/shaders/"
  done < "$repo/Resources/Shaders.txt"
done
# Match Xcode's ExtensionKit target entry point. AppExtension.main() registers
# the implementation; _NSExtensionMain supplies the host's blocking XPC runloop.
xcrun swiftc "${common[@]}" -parse-as-library -application-extension -Xlinker -e -Xlinker _NSExtensionMain \
  -import-objc-header "$repo/Sources/Extension/WallpaperBridge.h" \
  "$repo"/Sources/Shared/*.swift "$repo"/Sources/Extension/*.swift \
  -o "$ext/Contents/MacOS/MeditationExtension" \
  -framework AppKit -framework Metal -framework AVFoundation -framework IOSurface -framework QuartzCore -framework ExtensionFoundation -framework Security
xcrun swiftc "${common[@]}" -parse-as-library "$repo/Sources/Shared/ShaderLibrary.swift" \
  "$repo"/Sources/App/*.swift -o "$app/Contents/MacOS/VisualMeditation" -framework SwiftUI -framework AppKit
if [[ "${1:-}" != "--reuse-previews" ]]; then
  xcrun swiftc "${common[@]}" -parse-as-library "$repo"/Sources/Shared/*.swift \
    "$repo/Tests/RenderLibrary.swift" -o "$out/render-library" -framework AppKit -framework Metal -framework AVFoundation
  "$out/render-library" "$app/Contents/Resources" "$out/Previews"
fi
for bundle in "$app" "$ext"; do
  while IFS= read -r shader || [[ -n "$shader" ]]; do
    [[ -n "$shader" ]] || continue
    cp "$out/Previews/$shader.png" "$bundle/Contents/Resources/Previews/"
  done < "$repo/Resources/Shaders.txt"
  cp "$repo/LICENSE.phosphene" "$bundle/Contents/Resources/LICENSE.phosphene"
done
cp "$repo/Sources/App/Info.plist" "$app/Contents/Info.plist"
cp "$repo/Sources/Extension/Info.plist" "$ext/Contents/Info.plist"
codesign "${signing[@]}" --entitlements "$repo/Sources/Extension/Entitlements.plist" "$ext"
codesign "${signing[@]}" "$app"
codesign --verify --deep --strict "$app"
printf 'Built %s\n' "$app"
