#!/bin/zsh
# Builds AgentMeter.app (menu-bar-only bundle) into the repo root.
#
# Usage:
#   scripts/bundle.sh [--install]
#     --install   also copy the app to /Applications
#
# Optional environment for signing (used by scripts/release.sh and CI):
#   SIGN_IDENTITY   Developer ID Application identity; defaults to ad-hoc "-"
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="AgentMeter"
BUNDLE_ID="com.felixtorres.agentmeter"
VERSION="${AGENTMETER_VERSION:-1.0}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

swift build -c release

APP="${APP_NAME}.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp ".build/release/${APP_NAME}" "$APP/Contents/MacOS/${APP_NAME}"
if [[ -f Resources/AppIcon.icns ]]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>${APP_NAME}</string>
	<key>CFBundleIdentifier</key>
	<string>${BUNDLE_ID}</string>
	<key>CFBundleName</key>
	<string>${APP_NAME}</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>${VERSION}</string>
	<key>CFBundleVersion</key>
	<string>${VERSION}</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>CFBundleURLTypes</key>
	<array>
		<dict>
			<key>CFBundleURLName</key>
			<string>${BUNDLE_ID}.oauth</string>
			<key>CFBundleURLSchemes</key>
			<array>
				<string>agentmeter</string>
			</array>
		</dict>
	</array>
</dict>
</plist>
PLIST

# Sign. Ad-hoc ("-") for local dev; Developer ID for distribution.
# --options runtime enables the hardened runtime required for notarization.
if [[ "$SIGN_IDENTITY" == "-" ]]; then
    codesign --force --sign - "$APP"
else
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi

echo "Built $PWD/$APP (version ${VERSION}, identity: ${SIGN_IDENTITY})"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf "/Applications/$APP"
    cp -R "$APP" /Applications/
    echo "Installed to /Applications/$APP"
fi
