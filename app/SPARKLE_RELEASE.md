# Releasing Detach updates with Sparkle

Sparkle is already configured in the macOS app. It checks this appcast on launch
and from the menu-bar **Check for Updates…** command:

`https://github.com/DeatchAI/App/releases/latest/download/appcast.xml`

The appcast must be available over HTTPS and every update archive must be
signed with the private half of the EdDSA key that corresponds to
`SUPublicEDKey` in `lazzy/Info.plist`. Keep the private key out of the repo.

## One-command local release

After setting up a local notarytool profile, release with:

```bash
bash scripts/release.sh --version 2.0 --build 9 \
  --notary-profile notary-lazzy \
  --publish
```

By default Sparkle reads its private key from your login Keychain. If you keep
the key elsewhere, add `--sparkle-key-file /secure/path/private-key` instead.

The command rebuilds and hash-checks `server-v2/detach-runtime`, archives and
exports the app, notarizes and staples it, creates a versioned DMG, generates a
Sparkle-signed appcast, and publishes `Detach.dmg` plus `appcast.xml` to the
GitHub Release `v2.0`. Release artifacts remain under `dist/`. It refuses to
publish when notarization is skipped.

## GitHub Actions release

Pushing a tag such as `v1.3.4` runs
`.github/workflows/release-macos.yml`. The workflow creates a Developer ID
signed and notarized release, then publishes `Detach.dmg` and `appcast.xml` to
the matching GitHub Release.

Add these repository secrets before triggering it:

- `APPLE_DEVELOPER_ID_CERTIFICATE_BASE64` — Base64 of the exported Developer
  ID Application `.p12` certificate.
- `APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD` — password used to export that
  certificate.
- `KEYCHAIN_PASSWORD` — any fresh random password for the temporary CI
  keychain.
- `APPLE_NOTARY_KEY_ID`, `APPLE_NOTARY_ISSUER_ID`, and
  `APPLE_NOTARY_KEY_P8_BASE64` — App Store Connect API-key credentials for
  notarization.
- `SPARKLE_PRIVATE_KEY` — the EdDSA private key contents, not its public key.

The workflow uses its built-in GitHub Actions token for release uploads; no
Supabase Storage credential is needed. The repository must be public for
unauthenticated website downloads and Sparkle updates.

The workflow runs on GitHub's Apple-silicon `macos-15` runner, matching the
current arm64 Detach runtime. Use a tag for normal releases; the manual trigger
is useful only when you deliberately provide the version and want the workflow
to create the tag/release from the selected commit.

## One-time setup or key rotation

Generate an EdDSA key pair with Sparkle's `generate_keys` tool. Put only the
public key in `SUPublicEDKey` in `lazzy/Info.plist`; store the private key in a
secure release secret manager. Changing the public key means every installed
copy must already trust the new key, so avoid rotating it without a migration
plan.

The next release must use a build number greater than the highest build already
published to the appcast.
