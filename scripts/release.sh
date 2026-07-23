#!/bin/zsh
# Builds, signs (Developer ID), notarizes, staples, and zips AgentMeter.app.
#
# Prerequisites (see docs/RELEASING.md):
#   - A "Developer ID Application" certificate in your login keychain
#   - App Store Connect API key for notarytool
#
# Required environment:
#   SIGN_IDENTITY        e.g. "Developer ID Application: Your Name (TEAMID)"
#   AGENTMETER_VERSION   e.g. 1.0.1 (defaults to 1.0)
#
# Notarization credentials are fetched automatically from 1Password via op-sa
# (item "AgentMeter Notarization (App Store Connect API)" in vault
# Sage-Openclaw). Override by setting NOTARY_PROFILE, or all of
# APPLE_API_KEY_ID / APPLE_API_ISSUER / APPLE_API_KEY (path to .p8).
set -euo pipefail

cd "$(dirname "$0")/.."

: "${SIGN_IDENTITY:?Set SIGN_IDENTITY to your Developer ID Application identity}"

APP="AgentMeter.app"
ZIP="AgentMeter.zip"

OP_SA="$HOME/.local/bin/op-sa"
OP_VAULT="Sage-Openclaw"
OP_ITEM="AgentMeter Notarization (App Store Connect API)"
NOTARY_KEY_TMP=""

cleanup() { [[ -n "$NOTARY_KEY_TMP" && -f "$NOTARY_KEY_TMP" ]] && rm -P "$NOTARY_KEY_TMP"; }
trap cleanup EXIT

# Fetch notarization credentials from 1Password unless already provided.
if [[ -z "${NOTARY_PROFILE:-}" && -z "${APPLE_API_KEY:-}" ]]; then
    if [[ -x "$OP_SA" ]]; then
        echo "Fetching notarization credentials from 1Password (op-sa)…"
        NOTARY_KEY_TMP="$(mktemp -d)/AuthKey.p8"
        "$OP_SA" item get "$OP_ITEM" --vault "$OP_VAULT" --fields "private key b64" --reveal \
            | base64 -d > "$NOTARY_KEY_TMP"
        export APPLE_API_KEY="$NOTARY_KEY_TMP"
        export APPLE_API_KEY_ID="$("$OP_SA" item get "$OP_ITEM" --vault "$OP_VAULT" --fields "key id")"
        export APPLE_API_ISSUER="$("$OP_SA" item get "$OP_ITEM" --vault "$OP_VAULT" --fields "issuer id")"
    fi
fi

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
