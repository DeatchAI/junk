# Detach

Detach is a macOS-native agent workspace for working with selected text and files, local agent CLIs, browser automation, and user-approved desktop capabilities.

> Detach is under active development. The first public release will be published from this repository with signed and notarized macOS artifacts.

## What is in this repository?

| Area | Location | Purpose |
| --- | --- | --- |
| macOS app | `app/lazzy` | SwiftUI app, permissions, Finder integration, updates, and local secret handling. |
| Local runtime | `app/server-v2` | Bun runtime for agent adapters and local MCP bridges. |
| Chrome extension | `chrome-extension` | Optional Signed-in Chrome integration. |
| Website | `web` | Maintained in a separate private repository and intentionally excluded from this public app repository. |

## Requirements

- macOS 14 or later
- Xcode with the macOS SDK
- [Bun](https://bun.sh/)

## Get started from source

Clone the app repository:

```bash
git clone https://github.com/DeatchAI/junk.git detach
cd detach
```

Run the local checks:

```bash
bash scripts/verify.sh
```

Or run one component at a time:

```bash
# Runtime
cd app/server-v2
bun install --frozen-lockfile
bun run check

# macOS app (unsigned development build)
cd ..
xcodebuild -project detach.xcodeproj -scheme lazzy \
  -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

The website remains in its separate private repository and is not included in
this checkout or in the app CI workflows.

## Security and permissions

Detach can use Accessibility, Screen Recording, Apple Events, Finder integration, browser access, and the macOS Keychain only after explicit user actions. Read [SECURITY.md](SECURITY.md) before reporting a vulnerability, and see [docs/architecture.md](docs/architecture.md) for the local capability boundary.

Detach-owned Composio and hosted-model credentials belong only in the private
hosted control plane—not in the app, local runtime, or CI.

For the available bring-your-own-key setup and the planned hosted-service
fallback, read [Composio setup](docs/composio-setup.md).

The Chrome extension is optional. It uses page access only when the user grants it, and it connects to the local runtime on `127.0.0.1`.

## Contributing

Please read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request. Bugs and feature proposals use the repository issue forms. General questions belong in GitHub Discussions once enabled.

Maintainers should follow the one-time [GitHub repository setup](docs/repository-settings.md) before opening the project publicly.

## Releases

Published macOS releases are signed, notarized, and delivered through GitHub Releases and Sparkle. See [RELEASING.md](RELEASING.md) for the maintainer process.

## License

Licensed under the [Apache License 2.0](LICENSE).
