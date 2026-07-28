# Composio setup

Detach supports two separate ways to use Composio. Pick one; do not put a key
in the app source code, a Git commit, or an issue.

| What you want | Use this | Who pays for Composio |
| --- | --- | --- |
| Build Detach from source and use your own Composio project | Your own local `COMPOSIO_API_KEY` | You |
| Use Detach's hosted Composio service | The Detach-hosted app distribution | Detach, included in the hosted product |

## Option 1: Use your own Composio key (available now)

Create a Composio project and project API key in your Composio dashboard. Keep
that key private. In Xcode, select the **lazzy** scheme, open **Edit Scheme →
Run → Arguments**, and add an environment variable:

```text
COMPOSIO_API_KEY=your_own_key_here
```

Run the app from that scheme. Detach passes the environment only to its local
runtime, which uses it to create Composio sessions for the signed-in Detach
user. The key is not stored in the repository or sent to Detach's hosted API.

For a locally built `.app`, start its executable from a terminal with the same
environment variable instead of adding it to source code:

```bash
COMPOSIO_API_KEY=your_own_key_here /Applications/Detach.app/Contents/MacOS/Detach
```

Replace the app path with the location and executable name of your build. Do
not paste the key into a shell history you share, screenshots, or a tracked
`.env` file.

If the runtime says that Composio is not configured, the environment variable
did not reach the app process. Quit Detach fully, set it in the Xcode scheme
or launch command, then start the app again.

## Option 2: Detach-hosted Composio

The commercial Detach build has a `hosted` distribution mode and a configured
HTTPS control-plane URL. It passes the signed-in user's Supabase access token
to its localhost runtime, which calls the private Next.js endpoint for
integrations, account connections, and user-scoped MCP sessions. The
Detach-owned Composio key remains on the server.

The decision is now:

```text
Own COMPOSIO_API_KEY available locally?
    Yes → use the user's own Composio project directly.
    No  → hosted build calls Detach's hosted endpoint.
            The endpoint creates a user-scoped session.
    Self-hosted build → never calls Detach's endpoint; it receives HTTP 402 if
            it tries to call it anyway.
```

The app must never contain the Detach-owned project key. Returned session
headers are credentials and must never be written to source code, logs, or
analytics. The current runtime still persists MCP session headers in its local
runtime database; moving that material to the macOS Keychain is required before
shipping hosted Composio broadly.

### Building the hosted distribution

The open-source project defaults to `self_hosted`. The official release build
sets these Xcode build settings, without changing the public source checkout:

```text
DETACH_DISTRIBUTION_MODE=hosted
DETACH_HOSTED_CONTROL_PLANE_URL=https://your-private-web-domain.example
```

That URL must be HTTPS. A self-hosted build should leave the defaults alone and
use its own `COMPOSIO_API_KEY`.

The current `402` check identifies the intended distribution path; it is not a
tamper-proof licensing system because a modified client can imitate an HTTP
header. Before hosted Composio becomes a paid entitlement, add server-issued
installation registration or attestation and enforce it at the web API.

## For people hosting their own copy of Detach

If you run your own website/control plane, configure its server-only
`COMPOSIO_API_KEY` and an explicit `COMPOSIO_ALLOWED_TOOLKITS` allowlist. Do
not expose either through a `NEXT_PUBLIC_*` environment variable. Your
deployment is then responsible for its own account connections, subscription
rules, rate limits, support, and Composio bill.

## Hosted models

Hosted models use the same principle, but they are not available yet. The
private hosted-model endpoint intentionally returns `501` until credit
reservation, provider routing, streaming, rate limits, redacted usage records,
and refunds are implemented. Open-source users should continue using their own
model accounts and credentials until that work is complete.
