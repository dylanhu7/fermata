#!/bin/bash
# Builds Fermata, signed with the team set in the project (DEVELOPMENT_TEAM).
#   ./build.sh           Release build into dist/, signed with Apple Development for this Mac
#   ./build.sh install   the same, then copy to /Applications and (re)launch it
#   ./build.sh release   Developer ID build, notarized and stapled, zipped into dist/ to share
#                        as Fermata-<version>.zip
set -euo pipefail
cd "$(dirname "$0")"

# Notarization credentials stored once with `xcrun notarytool store-credentials`.
NOTARY_PROFILE="${NOTARY_PROFILE:-fermata-notary}"

if [ "${1:-}" = "release" ]; then
  SETTINGS=$(xcodebuild -scheme Fermata -showBuildSettings 2>/dev/null)
  TEAM_ID=$(echo "$SETTINGS" | awk '$1 == "DEVELOPMENT_TEAM" { print $3 }')
  ZIP="dist/Fermata-$(echo "$SETTINGS" | awk '$1 == "MARKETING_VERSION" { print $3 }').zip"
  if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "No notarization credentials saved as \"$NOTARY_PROFILE\". Create an app-specific password at"
    echo "account.apple.com, then run:"
    echo "  xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <your Apple ID> --team-id $TEAM_ID"
    exit 1
  fi

  echo "Archiving Fermata..."
  rm -rf .build/Fermata.xcarchive .build/export
  xcodebuild archive -scheme Fermata -configuration Release \
    -archivePath .build/Fermata.xcarchive -allowProvisioningUpdates

  cat > .build/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
</dict>
</plist>
PLIST
  xcodebuild -exportArchive -archivePath .build/Fermata.xcarchive \
    -exportPath .build/export -exportOptionsPlist .build/ExportOptions.plist -allowProvisioningUpdates

  mkdir -p dist
  rm -rf dist/Fermata.app dist/Fermata*.zip
  cp -R .build/export/Fermata.app dist/
  ditto -c -k --keepParent dist/Fermata.app "$ZIP"

  echo "Notarizing (this usually takes a few minutes)..."
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple dist/Fermata.app
  # Re-zip so the download carries the stapled ticket.
  rm "$ZIP"
  ditto -c -k --keepParent dist/Fermata.app "$ZIP"
  spctl --assess --type execute --verbose dist/Fermata.app
  echo ""
  echo "Release ready: $ZIP"
  exit 0
fi

echo "Building Fermata..."
xcodebuild -scheme Fermata \
  -configuration Release \
  -derivedDataPath .build \
  -arch arm64 \
  -allowProvisioningUpdates \
  build

mkdir -p dist
rm -rf dist/Fermata.app
cp -R .build/Build/Products/Release/Fermata.app dist/

echo ""
echo "Build complete: dist/Fermata.app"

if [ "${1:-}" = "install" ]; then
  # Quit a running copy normally so it can unmute a microphone it muted. By path, because
  # the bundle identifier can resolve to the copy just built instead of the one running.
  osascript -e 'quit app "/Applications/Fermata.app"' 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -f "Fermata.app/Contents/MacOS/Fermata" >/dev/null || break
    sleep 0.5
  done
  rm -rf /Applications/Fermata.app
  cp -R dist/Fermata.app /Applications/
  open /Applications/Fermata.app
  echo "Installed and launched /Applications/Fermata.app"
fi
