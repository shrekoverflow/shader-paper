#!/bin/bash
set -euo pipefail
AERIAL_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$AERIAL_DIR/../.." && pwd)"
OUTPUT_DIR="$REPO_DIR/build/aerial"
mkdir -p "$OUTPUT_DIR"
xcrun swiftc -O -module-cache-path "$REPO_DIR/build/module-cache" \
    "$AERIAL_DIR/RenderAerial.swift" -o "$OUTPUT_DIR/render" \
    -framework Metal -framework AVFoundation -framework AppKit -framework VideoToolbox
if [ ! -f "$OUTPUT_DIR/Almost a Shape.mov" ]; then
    "$OUTPUT_DIR/render" "$REPO_DIR/Resources/shaders/GPT6-Astra-II.shader" "$OUTPUT_DIR"
fi
xcrun swiftc -O -module-cache-path "$REPO_DIR/build/module-cache" \
    "$AERIAL_DIR/TemporalEncode.swift" -o "$OUTPUT_DIR/temporal-encode"
xcrun swiftc -O -parse-as-library -module-cache-path "$REPO_DIR/build/module-cache" \
    "$AERIAL_DIR/ValidateAerial.swift" -o "$OUTPUT_DIR/validate-aerial"
if [ ! -f "$OUTPUT_DIR/Almost a Shape — Native.mov" ]; then
    "$OUTPUT_DIR/temporal-encode" "$OUTPUT_DIR/Almost a Shape.mov" \
        "$OUTPUT_DIR/Almost a Shape — Native.mov" 3 18
fi
"$OUTPUT_DIR/validate-aerial" "$OUTPUT_DIR/Almost a Shape — Native.mov"
