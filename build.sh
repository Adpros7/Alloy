#!/usr/bin/env bash
# Build the Alloy editor: Rust engine first (static lib), then the Swift app.
#
#   ./build.sh          # debug build
#   ./build.sh release  # release build
#
# To build *and run* in one step, use ./run.sh instead.
set -euo pipefail
cd "$(dirname "$0")"

# cargo / homebrew tools are often not on a non-interactive PATH.
export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:$PATH"

CONFIG="${1:-debug}"   # debug | release

if [ "$CONFIG" = "release" ]; then
    echo "==> Building Rust engine (release static lib)…"
    ( cd alloy-engine && cargo build -p alloy-text --release )
    echo "==> Building Swift app (release)…"
    swift build -c release
else
    echo "==> Building Rust engine (debug static lib)…"
    ( cd alloy-engine && cargo build -p alloy-text )
    echo "==> Building Swift app (debug)…"
    swift build
fi

echo
echo "Build complete. Launch with:"
echo "    ./run.sh                 # build + run (easiest)"
echo "    ./run.sh path/to/file    # open a file or folder"
echo "    ./bundle.sh              # make a double-clickable Alloy.app"
