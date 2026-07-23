# Releasing AgentMeter

AgentMeter is distributed as a signed, notarized `.app` zipped and attached to a
GitHub Release. This is a one-time setup; after that, pushing a `vX.Y.Z` tag
builds and publishes automatically.

## One-time setup

### 1. Developer ID certificate

You need an Apple Developer Program membership ($99/yr).

1. In Xcode → Settings → Accounts, or on the Apple Developer site, create a
   **Developer ID Application** certificate.
2. Export it from Keychain Access as a `.p12` (right-click the certificate →
   Export), setting a password.
3. Find your identity string:
   ```bash
   security find-identity -v -p codesigning
   # e.g. "Developer ID Application: Your Name (TEAMID)"
   ```

### 2. App Store Connect API key (for notarization)

1. App Store Connect → Users and Access → Integrations → App Store Connect API.
2. Create a key with the **Developer** role. Download the `.p8` (once only).
3. Note the **Key ID** and **Issuer ID**.

### 3. GitHub repository secrets

Add these under Settings → Secrets and variables → Actions:

| Secret | Value |
|--------|-------|
| `MACOS_CERT_P12` | base64 of your `.p12`: `base64 -i cert.p12 \| pbcopy` |
| `MACOS_CERT_PASSWORD` | the `.p12` export password |
| `KEYCHAIN_PASSWORD` | any random string (temp CI keychain) |
| `APPLE_API_KEY` | base64 of your `.p8`: `base64 -i AuthKey_XXX.p8 \| pbcopy` |
| `APPLE_API_KEY_ID` | the Key ID |
| `APPLE_API_ISSUER` | the Issuer ID |

## Sparkle auto-updates

Releases from v1.4.0 onward include a Sparkle appcast:

- `scripts/release.sh` runs `generate_appcast` (from the SPM Sparkle artifact),
  which signs the zip with the **EdDSA private key stored in the login
  Keychain** (item: "Private key for signing Sparkle updates"). The matching
  public key is embedded in Info.plist (`SUPublicEDKey` in `scripts/bundle.sh`).
- Upload **both** `AgentMeter.zip` and `appcast.xml` as release assets. The
  app's feed URL is `releases/latest/download/appcast.xml`, so the newest
  release's appcast is always the one served.
- **Back up the private key** (`generate_keys -x backup-file` from
  `.build/artifacts/sparkle/Sparkle/bin/`). If it is lost, shipped apps can
  never auto-update again (the public key baked into them won't match) and
  users would need one manual reinstall. Store the backup somewhere safe
  (e.g. 1Password), never in the repo.

## Homebrew cask

After publishing a release, bump the cask in
[fdtorres1/homebrew-tap](https://github.com/fdtorres1/homebrew-tap):
update `version` and `sha256` (`curl -sL <zip url> | shasum -a 256`) in
`Casks/agentmeter.rb` and push. Existing installs auto-update via Sparkle
regardless (`auto_updates true`), so the cask matters mainly for new installs.

## Cutting a release (local — the actual flow)

Releases are cut locally, not via CI (`.github/workflows/release.yml` is
manual-dispatch only and its secrets are not configured). The signing identity
lives in the login keychain; notarization credentials are fetched from
1Password by `release.sh` automatically (via `op-sa`, vault Sage-Openclaw, item
"AgentMeter Notarization (App Store Connect API)").

1. Update `CHANGELOG.md` with the new version.
2. Commit and push `main`.
3. Build + sign + notarize + appcast:
   ```bash
   export SIGN_IDENTITY="Developer ID Application: Felix Torres (77Z6XS8JU8)"
   export AGENTMETER_VERSION=X.Y.Z
   scripts/release.sh   # notarization creds pulled from op-sa
   ```
   (Approve the Sparkle Keychain prompt with "Always Allow" if it appears.)
   To override op-sa, set `APPLE_API_KEY`/`APPLE_API_KEY_ID`/`APPLE_API_ISSUER`
   or `NOTARY_PROFILE` and the script uses those instead.
4. Tag and publish with BOTH assets:
   ```bash
   git tag vX.Y.Z && git push origin vX.Y.Z
   gh release create vX.Y.Z AgentMeter.zip appcast.xml \
     --title "AgentMeter X.Y.Z" --notes "..."
   ```
5. Bump the Homebrew cask (see below).
6. Install locally to verify; tick the roadmap and close the milestone.

## Before first publish (historical — already done)

- Buy Me a Coffee slug is set (`buymeacoffee.com/fdtorres`).
