#!/bin/zsh
# Builds, signs (Developer ID), notarizes, staples, and zips AgentMeter.app.
#
# Prerequisites (see docs/RELEASING.md):
#   - A "Developer ID Application" certificate in your login keychain
#   - An App Store Connect API key for notarytool
#
# Required environment:
#   SIGN_IDENTITY        e.g. "Developer ID Application: Your Name (TEAMID)"
#   AGENTMETER_VERSION   e.g. 1.0.1 (defaults to 1.0)
# Notarization (either a stored keychain profile OR API key fields):
#   NOTARY_PROFILE       name of a `notarytool store-credentials` profile
#   -- or --
#   APPLE_API_KEY_ID, APPLE_API_ISSUER, APPLE_API_KEY (path to .p8)
set -euo pipefail

cd "$(dirname "$0")/.."

: "${SIGN_IDENTITY:?Set SIGN_IDENTITY to your Developer ID Application identity}"

APP="AgentMeter.app"
ZIP="AgentMeter.zip"

# 1. Build + sign with hardened runtime.
SIGN_IDENTITY="$SIGN_IDENTITY" scripts/bundle.sh

# 2. Zip for notarization (ditto preserves the bundle + signature).
rm -f "$ZIP"
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"

# 3. Notarize and wait.
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
else
    : "${APPLE_API_KEY_ID:?Set NOTARY_PROFILE or APPLE_API_KEY_ID/ISSUER/KEY}"
    : "${APPLE_API_ISSUER:?Set APPLE_API_ISSUER}"
    : "${APPLE_API_KEY:?Set APPLE_API_KEY (path to .p8)}"
    xcrun notarytool submit "$ZIP" \
        --key "$APPLE_API_KEY" \
        --key-id "$APPLE_API_KEY_ID" \
        --issuer "$APPLE_API_ISSUER" \
        --wait
fi

# 4. Staple the ticket to the app, then re-zip the stapled bundle.
xcrun stapler staple "$APP"
rm -f "$ZIP"
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"

# 5. Generate the Sparkle appcast, signed with the EdDSA key in the Keychain.
#    The enclosure URL must point at the versioned release asset.
VERSION="${AGENTMETER_VERSION:-1.0}"
GENERATE_APPCAST=$(find .build/artifacts/sparkle -name generate_appcast -type f | head -1)
if [[ -n "$GENERATE_APPCAST" ]]; then
    APPCAST_DIR=$(mktemp -d)
    cp "$ZIP" "$APPCAST_DIR/"
    "$GENERATE_APPCAST" \
        --download-url-prefix "https://github.com/fdtorres1/AgentMeter/releases/download/v${VERSION}/" \
        --maximum-versions 1 \
        "$APPCAST_DIR"
    cp "$APPCAST_DIR/appcast.xml" appcast.xml
    echo "Appcast written to $PWD/appcast.xml"
else
    echo "warning: generate_appcast not found; skipping appcast" >&2
fi

echo "Release artifact ready: $PWD/$ZIP"
xcrun stapler validate "$APP"
