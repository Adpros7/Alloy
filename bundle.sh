#!/usr/bin/env bash
# Assemble a double-clickable Alloy.app from a release build.
#
#   ./bundle.sh            # build release + create ./Alloy.app, then `open` it
#   ./bundle.sh --no-open  # just build the bundle
#
# The Rust engine is statically linked into the binary, so the app is
# self-contained — it only needs the executable, the SwiftPM resource bundle
# (keybindings) and an Info.plist. This is a dev/local bundle (unsigned); proper
# Developer ID signing + Sparkle come in the Distribution phase.
set -euo pipefail
cd "$(dirname "$0")"
export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:$PATH"

OPEN=1
[ "${1:-}" = "--no-open" ] && OPEN=0

echo "==> Building release…"
( cd alloy-engine && cargo build -p alloy-text --release )
swift build -c release

APP="Alloy.app"
echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp ".build/release/Alloy" "$APP/Contents/MacOS/Alloy"

# Bundle.module looks for Alloy_Alloy.bundle next to Bundle.main.bundleURL,
# which for an .app is the .app directory itself.
RES_BUNDLE=".build/release/Alloy_Alloy.bundle"
if [ -d "$RES_BUNDLE" ]; then
    cp -R "$RES_BUNDLE" "$APP/Alloy_Alloy.bundle"
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>Alloy</string>
    <key>CFBundleDisplayName</key>     <string>Alloy</string>
    <key>CFBundleExecutable</key>      <string>Alloy</string>
    <key>CFBundleIdentifier</key>      <string>com.alloy.editor</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>0.2.0</string>
    <key>CFBundleVersion</key>         <string>0.2.0</string>
    <key>LSMinimumSystemVersion</key>  <string>14.0</string>
    <key>NSHighResolutionCapable</key> <true/>
    <key>NSPrincipalClass</key>        <string>NSApplication</string>
</dict>
</plist>
PLIST

# Ad-hoc sign so macOS is happy launching it locally.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "==> Built $(pwd)/$APP"
[ "$OPEN" = "1" ] && open "$APP"
exit 0
