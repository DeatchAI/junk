# Detach Browser Agent

Chrome extension for letting Detach agents work inside the user's real logged-in Chrome profile.

This extension is intentionally dependency-free. Load it directly with Chrome's "Load unpacked" button.

The extension connects directly to the local Detach runtime over `ws://127.0.0.1:3847`. Native messaging remains available as a fallback, but it is not required for normal local testing.

The extension has a fixed development ID:

```text
gdobcabflbojkedmocahijccipghgoij
```

## Install for Development

1. Open `chrome://extensions`.
2. Enable Developer mode.
3. Choose Load unpacked.
4. Select this `chrome-extension/` folder.
5. Pin "Detach Browser Agent" and open the popup once.

The direct localhost bridge requires no additional installation. To keep native messaging available as a fallback, optionally run:

```bash
scripts/install-chrome-native-host.sh
```

The popup can request all-sites access. Without all-sites access, Chrome only grants page access after explicit user gestures such as clicking the extension action on the current tab.

## Optional Native Host Contract

The extension connects to a native messaging host named:

```text
com.lazzy.browser
```

The macOS native messaging manifest will live at:

```text
~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.lazzy.browser.json
```

For load-unpacked development, the manifest `allowed_origins` must contain this extension's generated ID from `chrome://extensions`.

Chrome native messaging sends length-prefixed JSON over stdio. The host should send commands to the extension like:

```json
{
  "type": "command",
  "id": "cmd_123",
  "command": "browser.snapshot",
  "payload": {}
}
```

The extension responds with:

```json
{
  "type": "result",
  "id": "cmd_123",
  "ok": true,
  "result": {}
}
```

Errors are returned as:

```json
{
  "type": "result",
  "id": "cmd_123",
  "ok": false,
  "error": "Message"
}
```

## Commands

- `browser.status`
- `browser.list_tabs`
- `browser.get_active_tab`
- `browser.open_tab`
- `browser.navigate`
- `browser.snapshot`
- `browser.extract_text`
- `browser.get_selection`
- `browser.click`
- `browser.type`
- `browser.select`
- `browser.scroll`
- `browser.screenshot`
- `browser.request_all_sites_access`

Targets can use `tabId`, `ref`, `selector`, or visible `targetText` depending on the command. `browser.snapshot` returns stable element refs such as `lz-1`, which later commands can use.

`browser.request_all_sites_access` is listed for protocol completeness, but Chrome normally requires permission prompts to start from a user gesture. In practice the popup button is the reliable way to grant all-sites access during development.

## Safety Notes

This first extension build does not approve sensitive browser actions by itself. The next server-v2 step should add policy gates before allowing actions such as submit, purchase, delete, send, publish, or irreversible navigation.
