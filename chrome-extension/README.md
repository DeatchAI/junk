# Detach Browser Agent

Chrome extension for Detach browser automation. It works inside the user's real logged-in Chrome profile and reuses the already-focused Chrome window.

This extension is intentionally dependency-free. Load it directly with Chrome's "Load unpacked" button.

The extension reads `runtime-config.json` and connects directly to the authenticated Detach runtime on the random loopback port selected for that app launch. Native messaging remains available as a fallback.

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

After pulling an extension update, click **Reload** for Detach Browser Agent on `chrome://extensions`.

Release builds bundle this directory inside Detach. Onboarding copies it to Application Support and opens that stable folder so it can be selected with **Load unpacked** until the Chrome Web Store listing is live. To keep native messaging available as a fallback during source development, optionally run:

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

## Runtime commands

These commands are the private engine contract used by Detach itself. Agents no longer receive them as separate tools. They receive one `detach_browser_execute` MCP tool and write a Playwright-shaped program; the runtime translates that program into the commands below.

- `browser.status`
- `browser.list_tabs`
- `browser.get_active_tab`
- `browser.open_tab`
- `browser.activate_tab`
- `browser.close_tab`
- `browser.navigate`
- `browser.back`
- `browser.forward`
- `browser.refresh`
- `browser.frames`
- `browser.resolve_frame`
- `browser.snapshot`
- `browser.extract_text`
- `browser.get_selection`
- `browser.click`
- `browser.hover`
- `browser.drag`
- `browser.type`
- `browser.key`
- `browser.dropdown_options`
- `browser.select`
- `browser.upload_file`
- `browser.scroll`
- `browser.wait`
- `browser.screenshot`
- `browser.media`
- `browser.artifact_fetch`
- `browser.events`
- `browser.dialog`
- `browser.begin_task` and `browser.end_task` (runtime-managed task scope)
- `browser.request_all_sites_access`

Targets can use `tabId`, `ref`, `selector`, or visible `targetText` depending on the command. Snapshots aggregate accessible child frames and bind each ref to its tab, frame, and document. Collision-free refs such as `lz-a1b2c3d4-7` remain bound to the same DOM element until it is removed or its document navigates.

The code tool returns pruned semantic trees and automatically drains popup, new-tab, download, navigation, dialog, and failure events. It can also crop a target element from a screenshot, drag elements, inspect/seek media, and import authenticated page resources into task-owned artifacts.

`browser.request_all_sites_access` is listed for protocol completeness, but Chrome normally requires permission prompts to start from a user gesture. In practice the popup button is the reliable way to grant all-sites access during development.

## Safety Notes

The extension never exposes saved password values to the agent. After Touch ID, the credential is bound directly to the previously verified DOM refs; when a validated submit ref is supplied, fill and submit happen atomically and Detach returns structured navigation state. URL/title navigation checks remain available while DOM inspection and screenshots are locked. Detach does not use global keyboard events that could reach Chrome's address bar, and existing Chrome windows are never closed.

After a browser program returns explicit verified completion evidence, the runtime can learn domain-scoped semantic locators into the app's local `browser-skills` directory. These generated skills are attached on later visits and never record credentials, typed values, or per-run user content.
