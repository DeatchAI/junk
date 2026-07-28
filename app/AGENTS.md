# Detach app workspace

Detach is a macOS-native agent workspace. The app presents the signed user-facing UI; the local Bun runtime hosts agent adapters and MCP bridges.

## Layout

- `lazzy/` — SwiftUI macOS application.
- `FinderExtension/` — Finder Sync extension.
- `server-v2/` — Bun runtime and its tests.
- `scripts/` — local/release automation.
- `../chrome-extension/` — optional Signed-in Chrome integration.
- `../web/` — marketing site in a deliberately separate Git repository, included here as a submodule.

## Commands

```bash
# Runtime checks
cd app/server-v2 && bun install --frozen-lockfile && bun run check

# macOS compile check (no signing required)
cd app && xcodebuild -project detach.xcodeproj -scheme lazzy \
  -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build

# Release (requires configured signing and notarization credentials)
cd app && bash scripts/release.sh --version 1.2.3 --build 123
```

## Engineering rules

- Keep native app, runtime, and Chrome-extension contracts explicit and covered by tests.
- Treat Accessibility, screen capture, Apple Events, browser actions, and secret access as sensitive capabilities. Preserve approval and audit boundaries.
- Do not commit generated runtime binaries, release artifacts, user data, or secrets.
- Keep product documentation in the repository root; use this file only for implementation guidance.
