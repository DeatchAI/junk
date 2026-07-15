# Deprecated Lazzy v1 Surfaces

The active macOS app path now targets `server-v2` / `detach-runtime`.

Old Lazzy v1 code is intentionally left in place for reference until the project
can be fully compiled and pruned in Xcode:

- hosted provider model registry
- BYOK provider-key settings
- Supabase account and usage billing
- Polar credit tracking
- Composio integration management
- Stagehand/server-v1 browser settings
- MCP management UI designed for the old bundled server

Do not wire new Detach product work through those surfaces. New work should use
`server-v2` and the local agent adapter boundary.
