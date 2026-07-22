---
name: detach-browser
description: Fast, reliable web automation in the user's active Signed-in Chrome window or Power Browser.
---

# Detach Browser

Use `detach_browser_execute` for webpage work. Never use macOS typing or clicks inside Chrome; native typing can hit the address bar instead of the page.

## Fast path

1. Inspect the active tab and take one compact snapshot.
2. Choose a unique locator. Prefer `getByLabel`, then `getByRole` with a name, then `getByPlaceholder`, then an exact CSS selector.
3. Batch the actions and live verification in one program.
4. Take another snapshot only after a meaningful page change or when the exact error says the locator is stale.

Do not use an unnamed `getByRole("textbox")` on pages with multiple textboxes. Detach enforces strict semantic locators and returns candidates when a locator is ambiguous. Use `first()`, `last()`, or `nth(index)` only when position is genuinely the intended selector.

`locator.describe()` returns the live element metadata and stable `ref`. Live reads include `inputValue`, `textContent`, `innerText`, `count`, `allTextContents`, and `checkValidity`. Actions include `click`, `fill`, `type`, `press`, `selectOption`, `setInputFiles`, and `scrollIntoView`.

Use `page.open(url)` to open a new tab in the user's current Chrome window. Use `page.goto(url)` only when replacing the current tab is intended. Never create or switch to a separate browser process.

## Login forms and saved credentials

1. Navigate to the login page and inspect it once.
2. Resolve the username, password, and submit control with labels, roles, autocomplete attributes, or exact selectors. Call `describe()` on all three and retain their refs plus the active tab ID and exact origin.
3. Call `detach_secrets_search_credential`, then call `detach_secrets_use_credential` once with the origin, tab ID, username ref, password ref, and submit ref. Detach fills and submits atomically after Touch ID.
4. Use the structured result to distinguish `submitted`, `navigation.changed`, and `inspection`. If needed, call `page.waitForURL(...)`; URL, title, and browser navigation events remain available while DOM inspection is locked.
5. Snapshot only after navigation unlocks the new document. If submission did not navigate, report that the site stayed on the login page; do not guess whether the credential or Browser MCP failed.

The secure-fill result is authoritative. Do not retype credentials, inspect password values, or retry with macOS automation.

## Learning successful site navigation

When the task has direct completion evidence, make the final browser program return `{ taskComplete: true, evidence: ... }`. Detach will automatically learn stable semantic locators and operation order for that domain and attach the generated site skill on later runs. Never mark a task complete merely because a click was dispatched.

Learned site skills are generated from successful traces. Do not invent or hardcode site-specific steps in the generic browser skill.

## Recovery budget

On failure, use the exact tool error. Make one targeted locator fallback (label to autocomplete/exact CSS) and retry once. Do not spend turns rediscovering the same form or probing unsupported APIs.
