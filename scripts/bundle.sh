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

# Compile Spanish strings from the catalog; en.lproj is checked in separately.
xcrun xcstringstool compile Sources/AgentMeter/Resources/Localizable.xcstrings \
    --output-directory Sources/AgentMeter/Resources

swift build -c release

APP="${APP_NAME}.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

cp ".build/release/${APP_NAME}" "$APP/Contents/MacOS/${APP_NAME}"
if [[ -d ".build/release/AgentMeter_AgentMeter.bundle" ]]; then
    cp -R ".build/release/AgentMeter_AgentMeter.bundle" "$APP/Contents/Resources/"
fi
if [[ -f Resources/AppIcon.icns ]]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

# Embed Sparkle.framework (SwiftPM links it via @rpath but does not bundle it).
SPARKLE_FRAMEWORK=$(find .build/artifacts/sparkle -type d -name "Sparkle.framework" -path "*macos*" | head -1)
if [[ -z "$SPARKLE_FRAMEWORK" ]]; then
    echo "error: Sparkle.framework not found in .build/artifacts (run swift build first)" >&2
    exit 1
fi
cp -R "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/${APP_NAME}" 2>/dev/null || true

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
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleLocalizations</key>
	<array>
		<string>en</string>
		<string>es</string>
	</array>
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
	<key>SUFeedURL</key>
	<string>https://github.com/fdtorres1/AgentMeter/releases/latest/download/appcast.xml</string>
	<key>SUPublicEDKey</key>
	<string>pwHih7xHwBmiGn3ky45I4HSoDDJEYPxB3ltBcptRnwE=</string>
	<key>SUEnableAutomaticChecks</key>
	<true/>
</dict>
</plist>
PLIST

# Sign. Ad-hoc ("-") for local dev; Developer ID for distribution.
# --options runtime enables the hardened runtime required for notarization.
# Sparkle.framework (including its XPC services) must be signed before the app;
# --deep is discouraged, so sign inside-out.
if [[ "$SIGN_IDENTITY" == "-" ]]; then
    codesign --force --sign - "$APP/Contents/Frameworks/Sparkle.framework"
    codesign --force --sign - "$APP"
else
    for xpc in "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/"*.xpc; do
        codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$xpc"
    done
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" \
        "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate" \
        "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app" \
        "$APP/Contents/Frameworks/Sparkle.framework"
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi

echo "Built $PWD/$APP (version ${VERSION}, identity: ${SIGN_IDENTITY})"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf "/Applications/$APP"
    cp -R "$APP" /Applications/
    echo "Installed to /Applications/$APP"
fi
