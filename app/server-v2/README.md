# Detach Runtime

Local runtime for the Detach macOS app.

This replaces the legacy Lazzy AI Gateway server with a small process-backed Detach agent host:

- no billing credits
- no provider registry
- no Polar
- no Supabase plan logic
- no Detach Cloud model keys in the Mac app or local runtime

The runtime supports first-class local agent adapters for:

- Codex via `codex exec --json`
- Claude via `claude -p --output-format stream-json`
- Grok via `grok -p --output-format streaming-json`
- OpenCode through the user's own OpenCode login and provider configuration
- Detach Cloud via a separate bundled OpenCode ACP harness and the Detach Cloud control plane

The Gemini CLI adapter was removed after the CLI deprecation. Provider-neutral
Detach Cloud models run through a separate OpenCode configuration. The local runtime exchanges the signed-in
user session for a short-lived model-only token, then points OpenCode at the
Detach proxy. The user's Supabase token and Detach's provider credentials are
never inherited by the agent process.

Kie.ai is the primary Detach Cloud provider behind Detach's own `/api/v1/responses`
endpoint. The control plane owns Kie's provider-specific routes and transactional
credit accounting. The earlier Vercel AI Gateway adapter remains available but
is not the default Detach Cloud route.

Detach Cloud image and video generation uses the same scoped session but a separate
asynchronous media contract. The runtime uploads user-selected references,
streams durable `media_job` state to SwiftUI, and stores typed media parts in
SQLite. Provider URLs are replaced by signed Detach storage URLs before they
enter conversation history.

Standalone OpenCode inherits the user's normal OpenCode configuration, login,
providers, and model choice. Detach Cloud runs a separate OpenCode process in
ACP `--pure` mode with isolated state under
`~/Library/Application Support/Detach/OpenCode`, and injects an inline provider
configuration for each run. Both routes retain Detach's native tool approval UI.

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

`detach_browser_execute` is the single model-facing browser tool. It runs a safe Playwright-shaped JavaScript subset and translates each local program into the signed-in Chrome extension contract. Live locator reads query every accessible frame, snapshots are pruned before they reach the model, and popup, download, tab, navigation, and failure events are queued with each run. The same tool supports element screenshots, drag/range/media interactions, and task-owned document artifacts. `detach_macos_*` works through the connected Detach app so Accessibility, Screen Recording, and input synthesis remain in the signed macOS process instead of an agent CLI.

The macOS v1 tools cover permission status, running apps and windows, app launch/activation, accessibility snapshots, display screenshots, semantic or coordinate clicks, text input, shortcuts, and scrolling. Snapshot refs expire on the next snapshot. Secure text fields are blocked, and the bridge intentionally exposes no arbitrary AppleScript or shell command.

Both built-in servers are represented as ordinary `MCPServerConfig` values. Codex, Claude, Grok/ACP, and future ACP adapters therefore receive the same tools and policy without desktop-specific code in an adapter.

Composio is managed as a first-class MCP session, not as a pasted URL. The
bundled runtime authenticates to the Detach control plane with the signed-in
user's token, receives a paid-user Composio session, and connects directly to
Composio's MCP endpoint. The Detach-owned project key never reaches this
runtime or the macOS app. Custom HTTP/SSE/stdio MCP servers still belong in
Settings > MCP > Custom.

For a source build using its own Composio project, see
[`../../docs/composio-setup.md`](../../docs/composio-setup.md).
