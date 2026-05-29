#!/usr/bin/env bash
# Alloy — build everything and launch, in one command.
#
#   ./run.sh                 # build (debug) + launch, opening the current folder
#   ./run.sh path/to/file    # build + launch, opening a file
#   ./run.sh path/to/folder  # build + launch, opening a folder
#   ./run.sh --release        # build + launch the optimized release binary
#
# This is the easy way to run during development: it builds the Rust engine
# (static lib) and the Swift app, then runs the resulting binary directly — no
# Xcode required.
set -euo pipefail
cd "$(dirname "$0")"

# cargo / homebrew tools are often not on a non-interactive PATH.
export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:$PATH"

CONFIG="debug"
ARGS=()
for a in "$@"; do
    case "$a" in
        --release) CONFIG="release" ;;
        --debug)   CONFIG="debug" ;;
        *)         ARGS+=("$a") ;;
    esac
done

echo "==> Building Rust engine ($CONFIG)…"
if [ "$CONFIG" = "release" ]; then
    ( cd alloy-engine && cargo build -p alloy-text --release )
else
    ( cd alloy-engine && cargo build -p alloy-text )
fi

echo "==> Building Alloy ($CONFIG)…"
if [ "$CONFIG" = "release" ]; then
    swift build -c release
    BIN=".build/release/Alloy"
else
    swift build
    BIN=".build/debug/Alloy"
fi

echo "==> Launching Alloy"
# Expand ARGS safely even when empty (macOS bash 3.2 + `set -u`).
exec "$BIN" ${ARGS[@]+"${ARGS[@]}"}
