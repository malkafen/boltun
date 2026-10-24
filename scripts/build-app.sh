#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Boltun"
EXEC=Boltun
BUNDLE_ID=io.github.malkafen.boltun
VERSION=${VERSION:-$(git describe --tags --always 2>/dev/null || echo 0.0.0)}
VERSION=${VERSION#v}
case "$VERSION" in [0-9]*) ;; *) VERSION=0.0.0-$VERSION ;; esac
SHORT_VERSION=${VERSION%%-*}
BUILD_NUMBER=${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}

swift build -c release --arch arm64 --product "$EXEC"
BIN=$(swift build -c release --arch arm64 --show-bin-path)

APP="build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/$EXEC" "$APP/Contents/MacOS/$EXEC"
SDK_VERSION=$(xcrun --show-sdk-version)
MIN_VERSION=$(otool -l "$APP/Contents/MacOS/$EXEC" | awk '/LC_BUILD_VERSION/{f=1} f&&/minos/{print $2; exit}')
xcrun vtool -set-build-version macos "${MIN_VERSION:-15.0}" "$SDK_VERSION" -replace \
  -output "$APP/Contents/MacOS/$EXEC.tmp" "$APP/Contents/MacOS/$EXEC"
mv "$APP/Contents/MacOS/$EXEC.tmp" "$APP/Contents/MacOS/$EXEC"
for b in "$BIN"/*.bundle; do [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/"; done

ICON_KEY=""
if [ -f Tools/make-icon.swift ]; then
  if [ ! -f build/AppIcon.icns ] || [ Tools/make-icon.swift -nt build/AppIcon.icns ]; then
    rm -rf build/AppIcon.iconset
    swift Tools/make-icon.swift build/AppIcon.iconset
    iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
  fi
  cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
  ICON_KEY="<key>CFBundleIconFile</key><string>AppIcon</string>"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleExecutable</key><string>$EXEC</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$SHORT_VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>BoltunFullVersion</key><string>$VERSION</string>
  $ICON_KEY
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.social-networking</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSSupportsAutomaticTermination</key><false/>
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsArbitraryLoads</key><true/>
  </dict>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key><string>Mattermost deep link</string>
      <key>CFBundleURLSchemes</key><array><string>mattermost</string><string>boltun</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST

codesign --force --sign - --timestamp=none "$APP"
echo "Built: $APP"

if [ "${1:-}" = "--install" ]; then
  pkill -x "$EXEC" 2>/dev/null && sleep 1 || true
  DEST="/Applications/$APP_NAME.app"
  rm -rf "$DEST" && ditto "$APP" "$DEST"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST" || true
  echo "Installed: $DEST"
fi
