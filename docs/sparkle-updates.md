# Sparkle Updates

PlexBar uses Sparkle to update Developer ID builds distributed outside the Mac App Store.

The appcast is hosted on GitHub Pages:

```text
https://austin-smith.github.io/PlexBar/appcast.xml
```

Release DMGs are hosted on GitHub Releases. The appcast points to those versioned release assets.

## GitHub Configuration

Set these repository variables:

```text
SPARKLE_APPCAST_URL=https://austin-smith.github.io/PlexBar/appcast.xml
SPARKLE_PUBLIC_KEY=<Sparkle public EdDSA key>
```

Set this repository secret:

```text
SPARKLE_PRIVATE_KEY_BASE64=<base64-encoded Sparkle private EdDSA key>
```

The public key is embedded into the generated app bundle as `SUPublicEDKey`. The private key is used only in GitHub Actions to sign generated appcast entries.

## Local Configuration

`script/build_and_run.sh` loads `.env.local` from the repo root when the file exists.

Use it for local build-time Sparkle metadata:

```bash
SPARKLE_APPCAST_URL=https://austin-smith.github.io/PlexBar/appcast.xml
SPARKLE_PUBLIC_KEY=<Sparkle public EdDSA key>
```

Do not rely on setting these values only when launching an already-built app. They must be present when the app bundle is generated because they are written into `Info.plist`.

## Keys

Print the existing public key:

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys
```

Sparkle may report that a pre-existing signing key was found. That is expected if a Sparkle key already exists in the local Keychain.

Export the matching private key to a temporary file:

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys -x /tmp/sparkle-private-key
```

Base64-encode it for GitHub Actions:

```bash
base64 -i /tmp/sparkle-private-key
```

Store that output in `SPARKLE_PRIVATE_KEY_BASE64`, then delete the temporary file:

```bash
rm /tmp/sparkle-private-key
```

## Release Flow

Stable tags use this form:

```text
vX.Y.Z
```

Stable releases:

- build, sign, notarize, and staple the DMG
- upload the DMG to the GitHub Release
- generate a signed Sparkle appcast
- publish `appcast.xml` to GitHub Pages

Prerelease tags use a suffix:

```text
vX.Y.Z-beta.1
```

Prereleases create GitHub prereleases but do not update the stable Sparkle appcast.

## Build-Time Plist Values

`script/build_and_run.sh` generates the app bundle `Info.plist`.

When `SPARKLE_APPCAST_URL` and `SPARKLE_PUBLIC_KEY` are set, the script writes:

```text
CFBundleShortVersionString
CFBundleVersion
SUFeedURL
SUPublicEDKey
SUVerifyUpdateBeforeExtraction
SUEnableAutomaticChecks
```

`SUEnableAutomaticChecks` is set so Sparkle does not show its stock automatic-update permission prompt.
