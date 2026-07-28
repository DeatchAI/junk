# Hosted models

Detach keeps the coding harness, customer authentication, provider routing, and
provider credentials in separate layers:

```text
Detach macOS UI
  -> local Detach runtime
  -> OpenCode ACP harness
  -> Detach hosted-model proxy
  -> provider adapter
  -> Vercel AI Gateway (today)
  -> Kie or another provider (future)
```

## Security boundary

- The Vercel AI Gateway key exists only in the web control plane.
- The macOS app sends its Supabase access token only to the local runtime over
  loopback.
- The local runtime exchanges that login token for a short-lived token that can
  call only the hosted-model proxy.
- Only the short-lived model token is inherited by OpenCode. Shell tools cannot
  recover the user's Supabase session or a provider credential.
- OpenCode runs in ACP `--pure` mode with isolated state under
  `~/Library/Application Support/Detach/OpenCode`.
- OpenCode tool permission requests use Detach's existing native approval
  window. Built-in Detach MCP servers retain their explicit auto-approval
  policy; user-added tools do not inherit it.

## Control-plane configuration

The web deployment requires:

```text
SUPABASE_URL
SUPABASE_PUBLISHABLE_KEY
VERCEL_AI_GATEWAY_API_KEY
HOSTED_MODEL_SESSION_SECRET
```

`HOSTED_MODEL_SESSION_SECRET` must be at least 32 characters. The optional
`DETACH_HOSTED_MODEL_CATALOG` JSON value controls the product model catalog
without a Mac app release. Each entry has this shape:

```json
{
  "id": "openai/gpt-5.6-terra",
  "displayName": "GPT-5.6 Terra",
  "provider": "vercel",
  "contextWindow": 1050000,
  "maxOutputTokens": 128000
}
```

The proxy accepts only the OpenAI-compatible `/v1/chat/completions` and
`/v1/responses` paths, validates the requested model against this catalog, and
streams the upstream response without logging prompts or generated content.

The in-memory request limiter protects against accidental loops. Before hosted
models leave beta, add the durable per-user reservation/reconciliation ledger
used by the subscription product; the Vercel project budget should remain the
aggregate hard stop.

## Adding Kie

Kie support should not add a new macOS agent or fork the OpenCode adapter:

1. Add a `HostedModelProvider` implementation in
   `web/lib/hosted-models/providers.ts`.
2. Give Kie-backed catalog entries a stable Detach model ID and
   `"provider": "kie"`.
3. Translate the stable ID into Kie's model-specific endpoint inside that
   provider.
4. Normalize Kie errors and streaming responses to the same OpenAI-compatible
   contract exposed by the Detach proxy.
5. Add provider-specific usage reconciliation behind the shared billing
   ledger.

This keeps provider changes out of the Mac protocol, agent picker, MCP mapping,
approval flow, and conversation history.
