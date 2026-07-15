# Detach Runtime

Local runtime for the Detach macOS app.

This replaces the legacy Lazzy AI Gateway server with a small process-backed Detach agent host:

- no billing credits
- no provider registry
- no Polar
- no Supabase plan logic
- no hosted model keys

The runtime supports first-class local agent adapters for:

- Codex via `codex exec --json`
- Claude via `claude -p --output-format stream-json`
- Grok via `grok -p --output-format streaming-json`

The Gemini CLI adapter was removed after the CLI deprecation; future non-first-party model support should go through a bridge adapter such as OpenCode.

Chat history, quick actions, and MCP server configs are stored locally in SQLite at:

```text
~/Library/Application Support/Detach/chats.sqlite
```

Set `DETACH_DATABASE_PATH` or `DETACH_DATA_DIR` to override the location for tests or development.

## Commands

```bash
bun run dev
bun run build
```

The runtime listens on `PORT` or `3847`.

Enabled MCP servers are stored once in Detach. `MCPServerConfig` is the agent-neutral source of truth for transport, credentials, enabled state, exposed tool names, and approval policy. Each adapter only translates that shared model into its native protocol:

- Codex uses per-run `mcp_servers.*` config overrides.
- Claude gets a temporary `--mcp-config` file plus targeted `--allowedTools` entries for pre-approved servers.
- Grok runs over Agent Client Protocol (ACP), so Detach injects MCP servers in `session/new` without editing `~/.grok/config.toml`.
- Future ACP agents such as OpenCode can reuse `ACPAgentProcess` and only need to supply their executable/arguments and output identity.

Built-in Detach tools may opt into `approvalPolicy: "auto-approve"`. User-configured MCP servers default to prompting. ACP permission requests that are not covered by a pre-approved policy are forwarded to the existing macOS approval window.

## Built-in automation bridges

The browser and desktop bridges use the same agent-neutral MCP pipeline:

```text
native capability -> local runtime bridge -> built-in MCP server -> agent adapter mapper
```

`detach_browser_*` works through the Chrome extension/native host. `detach_macos_*` works through the connected Detach app so Accessibility, Screen Recording, and input synthesis remain in the signed macOS process instead of an agent CLI.

The macOS v1 tools cover permission status, running apps and windows, app launch/activation, accessibility snapshots, display screenshots, semantic or coordinate clicks, text input, shortcuts, and scrolling. Snapshot refs expire on the next snapshot. Secure text fields are blocked, and the bridge intentionally exposes no arbitrary AppleScript or shell command.

Both built-in servers are represented as ordinary `MCPServerConfig` values. Codex, Claude, Grok/ACP, and future ACP adapters therefore receive the same tools and policy without desktop-specific code in an adapter.

Composio is managed as a first-class MCP session, not as a pasted URL. Set `COMPOSIO_API_KEY` in the runtime environment; Detach creates or reuses a Composio session per stable Detach user id, stores the returned session MCP endpoint in SQLite, and passes that endpoint to Codex, Claude, Grok/ACP, and future agents like any other MCP server. Custom HTTP/SSE/stdio MCP servers still belong in Settings > MCP > Custom.
