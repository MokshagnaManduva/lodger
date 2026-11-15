# Product and release workflow

Local builds use an ad-hoc signature. Distribution still requires a Developer ID Application
certificate, a stored Apple notarytool profile, and a hosted release. These credentials and
services have not been configured or verified here.

The scripts below are implemented tooling, not evidence of a completed public release.
Product/import completion, desktop acceptance, energy certification and runtime turnaround
art also remain open in [the current checklist](../left.md).

## Build and checks

Install Python dependencies in your development environment:

```sh
python3 -m pip install -r Tools/packtool/requirements.txt -r Scripts/requirements-release.txt
make test
make engine-test
make release-test
make release-check
```

The macOS CI workflow runs pack, engine, separation, and release regression checks. CI has
been configured locally; a successful hosted run has not yet been observed.

The app version comes from the root `VERSION` file, independently of character-pack versions.
The bundler includes the icon, root license/credits, and each bundled pack's license/credits.
`release-check` builds a fresh development bundle: run it **before** distribution signing.

## Distribution sequence

1. Set `VERSION` and build: `make app`. To enable the manual update check, pass
   `SPARKLE_FEED_URL=https://your-host/lodger/appcast.xml`.
2. Sign: `make sign IDENTITY='Developer ID Application: …'`.
3. Notarize: `make notarize NOTARY_PROFILE=your-stored-profile`.
4. Sign the final `build/Lodger.zip` with your Ed25519 update key using Sparkle's
   `sign_update` tool. Keep the private key outside this repository.
5. Generate the feed using the matching public key and signature:

```sh
make appcast APPCAST_URL=https://your-host/lodger/Lodger.zip \
  APPCAST_PUBLIC_KEY='base64-public-key' \
  APPCAST_SIGNATURE='base64-signature-from-sign_update'
```

`notarize` verifies Developer ID signing, hardened runtime, and timestamp; archives the app;
submits it with the stored keychain profile; requires an Accepted response; staples and validates
the ticket; performs Gatekeeper assessment; and creates a new ZIP containing the stapled app.
The response is retained in `build/notarization.json`.

`make archive` is available separately for an already Developer ID-signed app. It rejects
ad-hoc bundles and replaces an existing archive only after successful packaging.
`make appcast` consumes the existing archive **without rebuilding or repacking it**, verifies
the supplied Ed25519 signature over those exact bytes, then writes `build/appcast.xml`.
Any archive change requires a new signature. Failed verification preserves the previous feed.

Publish that exact ZIP and feed over HTTPS. A successful Apple submission and a full
download/install/relaunch test remain required before distribution. Apple's
[notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
and Sparkle's [publishing guide](https://sparkle-project.org/documentation/publishing/) describe
the ticket and archive-signature steps.

## What the app currently does

**Check for Updates…** fetches the configured HTTPS feed, selects the newest compatible
numeric version, and opens its archive URL in the browser after confirmation. Without a feed
it reports that updates are unconfigured. It performs no scheduled background checks.

This is a manual download flow. It does not download and authenticate an archive itself,
verify its Ed25519 signature, or install updates. Automatic authenticated updates remain open.
The public key passed to the release tool verifies the feed's archive signature at build time;
it is not an in-app verification mechanism.

## Branding, licensing, and art

The icon source is `Assets/Branding/lodger-icon.png`; the standard About panel is implemented.
Final visual approval, support metadata, and license/provenance review remain open. Root
`LICENSE` currently contains MIT terms; Klien's pack notice reflects the CC-BY-NC-4.0 identifier
already present in its manifest.

The engine license choice still needs explicit owner confirmation. Existing license files
and attribution statements alone do not establish that every reference asset's rights have
been reviewed.

The turnaround and perch images are concept references. Full runtime turnaround artwork is
unfinished. Window perching remains a [future idea](future-ideas.md).
