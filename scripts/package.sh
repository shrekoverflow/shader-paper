#!/bin/bash
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
app="$repo/build/native/Shader Paper.app"
ext="$app/Contents/Extensions/MeditationExtension.appex"
out="$repo/build/distribution"
skip_build=false

usage() {
  printf 'Usage: bash scripts/package.sh [--skip-build]\n'
  printf 'Build and package Shader Paper for another Apple Silicon Mac running macOS 26+.\n'
  printf 'Use --skip-build only after building the app you intend to transfer.\n'
  printf 'Set CODE_SIGN_IDENTITY to sign a new build with a certificate; default is ad-hoc.\n'
  printf 'Packaging reports the existing signature and stapled ticket; it does not notarize.\n'
}

if [[ $# -gt 1 ]]; then
  usage >&2
  exit 2
fi
case "${1:-}" in
  '') ;;
  --skip-build) skip_build=true ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

fail() {
  printf 'Packaging failed: %s\n' "$1" >&2
  exit 1
}

if [[ "$skip_build" == true ]]; then
  [[ -d "$app" ]] || fail "No built app at $app. Run without --skip-build first."
else
  bash "$repo/scripts/build.sh"
fi

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist"
}

[[ -x "$app/Contents/MacOS/VisualMeditation" ]] || fail 'The app executable is missing.'
[[ -x "$ext/Contents/MacOS/MeditationExtension" ]] || fail 'The wallpaper extension executable is missing.'
[[ "$(plist_value "$app" CFBundleIdentifier)" == com.avisualmeditation.wallpaper ]] || fail 'Unexpected app identity.'
[[ "$(plist_value "$ext" CFBundleIdentifier)" == com.avisualmeditation.wallpaper.shader-extension ]] || fail 'Unexpected wallpaper provider identity.'
version="$(plist_value "$app" CFBundleShortVersionString)"
build="$(plist_value "$app" CFBundleVersion)"
[[ "$version" =~ ^[A-Za-z0-9._-]+$ && "$build" =~ ^[A-Za-z0-9._-]+$ ]] || fail 'Invalid bundle version.'
[[ "$(plist_value "$ext" CFBundleShortVersionString)" == "$version" ]] || fail 'App and extension versions differ.'
[[ "$(plist_value "$ext" CFBundleVersion)" == "$build" ]] || fail 'App and extension build numbers differ.'
cmp -s "$repo/Sources/App/Info.plist" "$app/Contents/Info.plist" || fail 'The app metadata is stale. Rebuild before packaging.'
cmp -s "$repo/Sources/Extension/Info.plist" "$ext/Contents/Info.plist" || fail 'The extension metadata is stale. Rebuild before packaging.'

for bundle in "$app" "$ext"; do
  [[ "$(plist_value "$bundle" LSMinimumSystemVersion)" == 26.0 ]] || fail 'Unexpected minimum macOS version; update the transfer documentation before packaging.'
  [[ -s "$bundle/Contents/Resources/LICENSE.phosphene" ]] || fail 'The bundled license is missing.'
  cmp -s "$repo/LICENSE.phosphene" "$bundle/Contents/Resources/LICENSE.phosphene" || fail 'The bundled license is stale. Rebuild before packaging.'
  while IFS= read -r shader || [[ -n "$shader" ]]; do
    [[ -n "$shader" ]] || continue
    [[ -s "$bundle/Contents/Resources/shaders/$shader.shader" ]] || fail "Missing bundled shader: $shader"
    cmp -s "$repo/Resources/shaders/$shader.shader" "$bundle/Contents/Resources/shaders/$shader.shader" || fail "The bundled $shader shader is stale. Rebuild before packaging."
    [[ -s "$bundle/Contents/Resources/Previews/$shader.png" ]] || fail "Missing bundled preview: $shader"
  done < "$repo/Resources/Shaders.txt"
done
/usr/bin/lipo -verify_arch arm64 "$app/Contents/MacOS/VisualMeditation"
/usr/bin/lipo -verify_arch arm64 "$ext/Contents/MacOS/MeditationExtension"
/usr/bin/codesign --verify --strict "$ext"
/usr/bin/codesign --verify --deep --strict "$app"

revision=local
if git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  revision="$(git -C "$repo" rev-parse --short=12 HEAD)"
  if [[ -n "$(git -C "$repo" status --porcelain --untracked-files=normal)" ]]; then
    revision="$revision-dirty"
  fi
fi
name="Shader-Paper-$version-$build-$revision"
mkdir -p "$out"
staging="$(mktemp -d "$out/.package.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
release="$staging/$name"
mkdir -p "$release/docs"
/usr/bin/ditto "$app" "$release/Shader Paper.app"
cp "$repo/docs/transfer.md" "$release/docs/transfer.md"
cp "$repo/docs/migration.md" "$release/docs/migration.md"
cp "$repo/LICENSE.phosphene" "$repo/NOTICE.md" "$release/"
/usr/bin/codesign --verify --deep --strict "$release/Shader Paper.app"
signature_info="$(/usr/bin/codesign --display --verbose=4 "$release/Shader Paper.app" 2>&1)"
signing_identity="$(printf '%s\n' "$signature_info" | /usr/bin/awk '/^Authority=/ { sub(/^Authority=/, ""); print; exit }')"
signing_team="$(printf '%s\n' "$signature_info" | /usr/bin/awk '/^TeamIdentifier=/ { sub(/^TeamIdentifier=/, ""); print; exit }')"
if [[ "$signature_info" == *"Signature=adhoc"* ]]; then
  signing_status='Ad-hoc (local signing; no Apple Developer identity)'
  signing_identity='None (ad-hoc)'
elif [[ "$signing_identity" == 'Developer ID Application: '* ]]; then
  signing_status='Developer ID signed'
else
  signing_status='Certificate signed (not Developer ID Application)'
fi
signing_team="${signing_team:-Not available}"
ticket_status='Not verified (stapler validate did not succeed); notarization status is unknown.'
if /usr/bin/xcrun stapler validate "$release/Shader Paper.app" > "$staging/stapler.log" 2>&1; then
  ticket_status='Verified (stapler validate succeeded).'
fi
{
  printf 'Shader Paper %s (%s)\n\n' "$version" "$build"
  printf 'Signing: %s\nIdentity: %s\nTeam: %s\n' "$signing_status" "${signing_identity:-Not available}" "$signing_team"
  printf 'Stapled notarization ticket: %s\n\n' "$ticket_status"
  printf 'This report describes the enclosed app at packaging time.\n'
  printf 'Developer ID signing alone does not mean Apple notarized the app.\n'
  printf 'See docs/transfer.md for compatibility, installation, and signing instructions.\n'
} > "$release/SIGNING.txt"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$release" "$staging/$name.zip"
(
  cd "$staging"
  /usr/bin/shasum -a 256 "$name.zip" > "$name.zip.sha256"
)
mv "$staging/$name.zip" "$out/$name.zip"
mv "$staging/$name.zip.sha256" "$out/$name.zip.sha256"
printf 'Package: %s\nChecksum: %s\n' "$out/$name.zip" "$out/$name.zip.sha256"
printf 'Signing: %s\nStapled notarization ticket: %s\n' "$signing_status" "$ticket_status"
printf 'The archive includes SIGNING.txt with the app signing identity and ticket verification result.\n'
