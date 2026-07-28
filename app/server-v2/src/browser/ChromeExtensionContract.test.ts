import { describe, expect, test } from "bun:test";

const serviceWorkerPath = new URL("../../../../chrome-extension/service-worker.js", import.meta.url);
const contentScriptPath = new URL("../../../../chrome-extension/content-script.js", import.meta.url);
const secretVaultPath = new URL("../../../lazzy/Core/Secrets/SecretVault.swift", import.meta.url);

describe("Signed-in Chrome product contracts", () => {
  test("always reuses the focused signed-in Chrome window", async () => {
    const source = await Bun.file(serviceWorkerPath).text();
    expect(source).toContain('tabsQuery({ active: true, lastFocusedWindow: true })');
    expect(source).not.toContain("windowsCreate(");
    expect(source).not.toContain("windowsRemove(");
  });

  test("routes semantic refs to their owning frame and document", async () => {
    const source = await Bun.file(serviceWorkerPath).text();
    expect(source).toContain("snapshotAllFrames(payload)");
    expect(source).toContain("targetFrameForPayload(tabId, payload)");
    expect(source).toContain("documentId");
    expect(source).toContain("webNavigation.getAllFrames");
  });

  test("supports element crops, drag, media, and task artifacts without debugger access", async () => {
    const source = await Bun.file(serviceWorkerPath).text();
    expect(source).toContain("cropImageDataUrl");
    expect(source).toContain("dragAndVerify(payload)");
    expect(source).toContain("browser.media");
    expect(source).toContain("browser.artifact_fetch");
    expect(source).not.toContain("chrome.debugger");
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
