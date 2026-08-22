# Architecture and trust boundaries

Detach is composed of a signed macOS application, a local Bun runtime, and an optional Chrome extension.

```text
User approval
    │
    ▼
Detach macOS app ── local WebSocket ── Detach runtime ── agent CLI / MCP server
    │                                      │
    ├── Finder, Accessibility, Screen      └── optional Chrome extension
    ├── Recording, Apple Events                    on localhost only
    └── Keychain-backed local secrets
```

## Rules

- The runtime never gains macOS privileges by itself; desktop operations are performed by the connected, signed app.
- User-configured MCP servers require explicit approval unless a trusted built-in capability has a documented policy.
- Secrets remain in local secure storage. Runtime activity and learned browser skills must not record credential values.
- Signed-in Chrome is opt-in. The extension limits its bridge to localhost and asks the user before requesting broad site access.

The website is intentionally outside this Git repository's deployment boundary. It remains in a separate private repository connected to its own Vercel project and is not a submodule or part of app CI.
