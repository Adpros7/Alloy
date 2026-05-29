#!/usr/bin/env bash
# Build the Alloy editor: Rust engine first (static lib), then the Swift app.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-debug}"   # debug | release

echo "==> Building Rust engine (release static lib)…"
( cd alloy-engine && cargo build --release )

echo "==> Building Swift app ($CONFIG)…"
if [ "$CONFIG" = "release" ]; then
    swift build -c release
else
    swift build
fi

echo
echo "Build complete. Launch with:"
echo "    swift run Alloy        # debug"
echo "    .build/release/Alloy   # if you built release"
