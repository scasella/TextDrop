#!/bin/bash
set -euo pipefail

APP_NAME="TextDrop"

echo "Compiling ${APP_NAME}..."
swiftc -parse-as-library -O -o "${APP_NAME}" "${APP_NAME}.swift"

echo "Creating ${APP_NAME}.app bundle..."
rm -rf "${APP_NAME}.app"
mkdir -p "${APP_NAME}.app/Contents/MacOS"
mv "${APP_NAME}" "${APP_NAME}.app/Contents/MacOS/"

cat > "${APP_NAME}.app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>TextDrop</string>
    <key>CFBundleIdentifier</key><string>com.scasella.textdrop</string>
    <key>CFBundleName</key><string>TextDrop</string>
    <key>CFBundleVersion</key><string>0.1.0</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>LSUIElement</key><true/>
</dict></plist>
EOF

echo "Built ${APP_NAME}.app ($(wc -l < "${APP_NAME}.swift" | tr -d ' ') lines)"
