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

## Cutting a release

```bash
# bump the version in the tag; the workflow derives CFBundleShortVersionString from it
git tag v1.0.1
git push origin v1.0.1
```

The Release workflow builds, signs with your Developer ID, notarizes via
`notarytool`, staples, zips, and uploads `AgentMeter.zip` to the release.

## Releasing locally (optional)

```bash
export SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export AGENTMETER_VERSION=1.0.1
# Either a stored notarytool profile:
xcrun notarytool store-credentials agentmeter-notary \
  --key AuthKey_XXX.p8 --key-id KEYID --issuer ISSUERID
export NOTARY_PROFILE=agentmeter-notary
scripts/release.sh
```

## Before first publish

- Replace the Buy Me a Coffee slug in `MenuContent.swift` and the README.
