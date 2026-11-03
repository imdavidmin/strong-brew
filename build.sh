#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Strong Brew.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Universal binary so it runs on Apple Silicon and Intel Macs.
for arch in arm64 x86_64; do
  swiftc -O -target $arch-apple-macos13 -o build/StrongBrew-$arch main.swift Icons.swift -framework AppKit -framework IOKit
done
lipo -create build/StrongBrew-arm64 build/StrongBrew-x86_64 -output "$APP/Contents/MacOS/StrongBrew"

# App icon, used by Finder and by the app's dialogs.
swiftc -O -o build/make-icon icon/main.swift Icons.swift -framework AppKit
rm -rf build/AppIcon.iconset
build/make-icon build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Strong Brew</string>
  <key>CFBundleDisplayName</key><string>Strong Brew</string>
  <key>CFBundleIdentifier</key><string>local.strongbrew</string>
  <key>CFBundleExecutable</key><string>StrongBrew</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
EOF

# SIGN_ID="Developer ID Application: …" signs for distribution; default is ad-hoc (this Mac only).
if [[ -n "${SIGN_ID:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
else
  codesign --force --sign - "$APP"
fi
echo "Built $APP"
