# Releasing Detach

Releases are created from protected, reviewed commits on `main`.

1. Confirm pull-request CI is green and update `CHANGELOG.md`.
2. Choose the next semantic version and an increasing numeric build number.
3. Create and push an annotated tag such as `v1.0.0`.
4. The macOS release workflow builds the runtime, signs, notarizes, packages, publishes the Sparkle feed, and creates the GitHub Release.
5. Download the release artifact and verify installation and update behavior from the previous released version.

The release workflow needs the protected repository secrets documented in [app/SPARKLE_RELEASE.md](app/SPARKLE_RELEASE.md). Configure them in a GitHub Environment named `release` and require maintainer approval before production publishing.

Never attach unnotarized builds, private keys, or local benchmark data to a release.
