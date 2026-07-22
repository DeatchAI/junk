import { describe, expect, test } from "bun:test";

const serviceWorkerPath = new URL("../../../chrome-extension/service-worker.js", import.meta.url);
const contentScriptPath = new URL("../../../chrome-extension/content-script.js", import.meta.url);
const secretVaultPath = new URL("../../../lazzy/Core/Secrets/SecretVault.swift", import.meta.url);

describe("Signed-in Chrome product contracts", () => {
  test("reuses the focused Chrome window unless isolation is explicit", async () => {
    const source = await Bun.file(serviceWorkerPath).text();
    expect(source).toContain('if (payload.isolated !== true)');
    expect(source).toContain('tabsQuery({ active: true, lastFocusedWindow: true })');
    expect(source).toContain('if (ownsWindow && Number.isInteger(windowId)) await windowsRemove(windowId)');
  });

  test("fills verified DOM refs after Touch ID without global keystrokes", async () => {
    const contentScript = await Bun.file(contentScriptPath).text();
    const secretVault = await Bun.file(secretVaultPath).text();
    expect(contentScript).toContain('case "secureFill"');
    expect(contentScript).toContain('setNativeValue(username, usernameValue)');
    expect(contentScript).toContain('setNativeValue(password, passwordValue)');
    expect(contentScript).toContain('submit.click()');
    expect(contentScript).toContain('secretDocumentLocked = true');
    expect(secretVault).toContain('authorizeBrowserCredential');
    expect(secretVault).not.toContain('CGEvent(');
    expect(secretVault).not.toContain('postUnicodeText');
  });

  test("returns structured navigation state from atomic secure fill and submit", async () => {
    const serviceWorker = await Bun.file(serviceWorkerPath).text();
    expect(serviceWorker).toContain("secureFillAndVerify(payload)");
    expect(serviceWorker).toContain('inspection: navigationChanged ? "unlocked_after_navigation" : "locked_until_navigation"');
    expect(serviceWorker).toContain('next: navigationChanged ? "verify_new_document"');
  });
});
