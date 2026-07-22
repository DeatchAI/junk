const NATIVE_HOST = "com.lazzy.browser";
const RUNTIME_WS_URL = "ws://127.0.0.1:3847/api/browser/native";
const CONTENT_TARGET = "lazzy-content";
const COMMAND_TIMEOUT_MS = 20_000;
const MAX_RECONNECT_DELAY_MS = 30_000;
const HEARTBEAT_INTERVAL_MS = 20_000;

let nativePort;
const sensitiveTabIds = new Set();
let nativeConnected = false;
let runtimeConnected = false;
let nativeReconnectTimer;
let nativeReconnectAttempt = 0;
let runtimeSocket;
let runtimeReconnectTimer;
let runtimeReconnectAttempt = 0;
let runtimeHeartbeat;
let nativeFallbackTimer;
let lastNativeError;
const pendingCommands = new Map();
const taskWindows = new Map();
const ownedTaskWindows = new Set();
const taskEvents = new Map();
const downloadTasks = new Map();
let recentInteraction;

chrome.runtime.onInstalled.addListener(() => {
  chrome.storage.local.set({
    lazzyBrowserAgent: {
      nativeHost: NATIVE_HOST,
      installedAt: Date.now()
    }
  });
});

chrome.runtime.onStartup.addListener(connectBridge);

chrome.tabs.onCreated.addListener((tab) => {
  const runId = runIdForWindow(tab.windowId);
  if (runId) {
    queueTabCreated(runId, tab);
    return;
  }
  if (Number.isInteger(tab.openerTabId)) {
    tabsGet(tab.openerTabId).then((opener) => {
      const openerRunId = runIdForWindow(opener.windowId);
      if (openerRunId) queueTabCreated(openerRunId, tab);
    }).catch(() => undefined);
  }
});

function queueTabCreated(runId, tab) {
  queueTaskEvent(runId, {
    type: Number.isInteger(tab.openerTabId) ? "popup" : "new_tab",
    tabId: tab.id,
    openerTabId: tab.openerTabId,
    url: tab.url || tab.pendingUrl || "",
    title: tab.title || ""
  });
}

chrome.tabs.onRemoved.addListener((tabId, removeInfo) => {
  sensitiveTabIds.delete(tabId);
  const runId = runIdForWindow(removeInfo.windowId);
  if (runId) queueTaskEvent(runId, { type: "tab_closed", tabId });
});

chrome.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  if (changeInfo.url) sensitiveTabIds.delete(tabId);
  const runId = runIdForWindow(tab.windowId);
  if (!runId || (!changeInfo.url && changeInfo.status !== "complete")) return;
  queueTaskEvent(runId, {
    type: "navigation",
    tabId,
    url: changeInfo.url || tab.url || "",
    status: changeInfo.status || tab.status || "unknown"
  });
});

chrome.webNavigation.onErrorOccurred.addListener((details) => {
  if (details.frameId !== 0) return;
  tabsGet(details.tabId).then((tab) => {
    const runId = runIdForWindow(tab.windowId);
    if (runId) queueTaskEvent(runId, { type: "failure", failureType: "navigation", tabId: details.tabId, url: details.url, error: details.error });
  }).catch(() => undefined);
});

chrome.downloads.onCreated.addListener((item) => {
  const taskIds = recentInteraction && Date.now() - recentInteraction.timestamp < 30_000 && taskWindows.has(recentInteraction.runId)
    ? [recentInteraction.runId]
    : taskWindows.size === 1 ? [...taskWindows.keys()] : [];
  for (const runId of taskIds) {
    downloadTasks.set(`${runId}:${item.id}`, runId);
    queueTaskEvent(runId, {
      type: "download",
      phase: "started",
      downloadId: item.id,
      url: item.finalUrl || item.url,
      filename: item.filename
    });
  }
});

chrome.downloads.onChanged.addListener((delta) => {
  for (const runId of taskWindows.keys()) {
    if (!downloadTasks.has(`${runId}:${delta.id}`)) continue;
    const phase = delta.state?.current || (delta.error?.current ? "interrupted" : "progress");
    queueTaskEvent(runId, {
      type: "download",
      phase,
      downloadId: delta.id,
      receivedBytes: delta.bytesReceived?.current,
      totalBytes: delta.totalBytes?.current,
      error: delta.error?.current
    });
    if (phase === "complete" || phase === "interrupted") downloadTasks.delete(`${runId}:${delta.id}`);
  }
});

chrome.runtime.onConnect.addListener((port) => {
  if (port.name !== "popup") return;

  port.onMessage.addListener(async (message) => {
    const response = await handlePopupMessage(message);
    try {
      port.postMessage({ requestId: message?.requestId, ...response });
    } catch {
      // Popup went away.
    }
  });
});

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (!message || message.target !== "lazzy-service-worker") return false;

  handlePopupMessage(message)
    .then(sendResponse)
    .catch((error) => sendResponse({ ok: false, error: normalizeError(error) }));
  return true;
});

connectBridge();

function connectBridge(force = false) {
  if (force) {
    disconnectRuntimeSocket();
    disconnectNativePort();
    clearReconnectTimers();
  }

  connectRuntimeSocket();

  if (!nativeFallbackTimer) {
    nativeFallbackTimer = setTimeout(() => {
      nativeFallbackTimer = undefined;
      if (!runtimeConnected) connectNative();
    }, 2_000);
  }
}

function connectRuntimeSocket() {
  if (runtimeSocket) return;

  const socket = new WebSocket(RUNTIME_WS_URL);
  runtimeSocket = socket;

  socket.addEventListener("open", () => {
    if (runtimeSocket !== socket) return;
    runtimeConnected = true;
    runtimeReconnectAttempt = 0;
    lastNativeError = undefined;

    if (nativeFallbackTimer) {
      clearTimeout(nativeFallbackTimer);
      nativeFallbackTimer = undefined;
    }

    disconnectNativePort();
    sendRuntime({
      type: "event",
      event: "extension.ready",
      payload: {
        transport: "websocket",
        version: chrome.runtime.getManifest().version
      }
    });
    startRuntimeHeartbeat();
  });

  socket.addEventListener("message", (event) => {
    if (runtimeSocket !== socket) return;
    try {
      handleNativeMessage(JSON.parse(String(event.data))).catch((error) => {
        sendBridge({ type: "event", event: "extension.error", error: normalizeError(error) });
      });
    } catch {
      lastNativeError = "Detach sent an invalid browser bridge message";
    }
  });

  socket.addEventListener("error", () => {
    if (runtimeSocket !== socket) return;
    lastNativeError = "Could not connect to the Detach runtime";
  });

  socket.addEventListener("close", () => {
    if (runtimeSocket !== socket) return;
    runtimeSocket = undefined;
    runtimeConnected = false;
    stopRuntimeHeartbeat();
    scheduleRuntimeReconnect();
  });
}

function scheduleRuntimeReconnect() {
  if (runtimeReconnectTimer) return;
  const delay = Math.min(1_000 * (2 ** runtimeReconnectAttempt), MAX_RECONNECT_DELAY_MS);
  runtimeReconnectAttempt += 1;
  runtimeReconnectTimer = setTimeout(() => {
    runtimeReconnectTimer = undefined;
    connectBridge();
  }, delay);
}

function startRuntimeHeartbeat() {
  stopRuntimeHeartbeat();
  runtimeHeartbeat = setInterval(() => {
    sendRuntime({ type: "event", event: "extension.heartbeat" });
  }, HEARTBEAT_INTERVAL_MS);
}

function stopRuntimeHeartbeat() {
  if (runtimeHeartbeat) clearInterval(runtimeHeartbeat);
  runtimeHeartbeat = undefined;
}

function disconnectRuntimeSocket() {
  const socket = runtimeSocket;
  runtimeSocket = undefined;
  runtimeConnected = false;
  stopRuntimeHeartbeat();
  try {
    socket?.close();
  } catch {
    // Socket was already closed.
  }
}

function connectNative() {
  if (nativePort) return;

  try {
    const port = chrome.runtime.connectNative(NATIVE_HOST);
    nativePort = port;
    nativeConnected = false;

    port.onMessage.addListener((message) => {
      if (nativePort !== port) return;
      nativeConnected = true;
      nativeReconnectAttempt = 0;
      lastNativeError = undefined;
      handleNativeMessage(message).catch((error) => {
        sendNative({
          type: "event",
          event: "extension.error",
          error: normalizeError(error)
        });
      });
    });

    port.onDisconnect.addListener(() => {
      if (nativePort !== port) return;
      nativeConnected = false;
      nativePort = undefined;
      if (!isRuntimeSocketOpen()) runtimeConnected = false;
      lastNativeError = chrome.runtime.lastError?.message || "Native host disconnected";
      scheduleNativeReconnect();
    });

    sendNative({
      type: "event",
      event: "extension.ready",
      payload: {
        host: NATIVE_HOST,
        version: chrome.runtime.getManifest().version
      }
    });
  } catch (error) {
    nativeConnected = false;
    nativePort = undefined;
    lastNativeError = normalizeError(error);
    scheduleNativeReconnect();
  }
}

function scheduleNativeReconnect() {
  if (nativeReconnectTimer || isRuntimeSocketOpen()) return;
  const delay = Math.min(1_000 * (2 ** nativeReconnectAttempt), MAX_RECONNECT_DELAY_MS);
  nativeReconnectAttempt += 1;
  nativeReconnectTimer = setTimeout(() => {
    nativeReconnectTimer = undefined;
    connectNative();
  }, delay);
}

function disconnectNativePort() {
  const port = nativePort;
  nativePort = undefined;
  nativeConnected = false;
  try {
    port?.disconnect();
  } catch {
    // Port was already disconnected.
  }
}

function clearReconnectTimers() {
  if (runtimeReconnectTimer) clearTimeout(runtimeReconnectTimer);
  if (nativeReconnectTimer) clearTimeout(nativeReconnectTimer);
  if (nativeFallbackTimer) clearTimeout(nativeFallbackTimer);
  runtimeReconnectTimer = undefined;
  nativeReconnectTimer = undefined;
  nativeFallbackTimer = undefined;
}

async function handleNativeMessage(message) {
  if (!message || typeof message !== "object") return;

  if (message.type === "event") {
    handleNativeEvent(message);
    return;
  }

  if (message.type !== "command") {
    return;
  }

  const { id, command, payload } = message;
  if (!id || typeof command !== "string") {
    sendBridge({
      type: "result",
      id,
      ok: false,
      error: "Invalid Detach browser command"
    });
    return;
  }

  try {
    if (typeof payload?.runId === "string" && [
      "browser.click", "browser.key", "browser.select", "browser.upload_file"
    ].includes(command)) {
      recentInteraction = { runId: payload.runId, timestamp: Date.now() };
    }
    const result = await runBrowserCommand(command, payload || {});
    sendBridge({ type: "result", id, ok: true, result });
  } catch (error) {
    if (typeof payload?.runId === "string") {
      queueTaskEvent(payload.runId, { type: "failure", command, error: normalizeError(error) });
    }
    sendBridge({ type: "result", id, ok: false, error: normalizeError(error) });
  }
}

async function handlePopupMessage(message) {
  if (!message || typeof message !== "object") {
    return { ok: false, error: "Invalid popup message" };
  }

  switch (message.command) {
    case "status":
      return { ok: true, result: await buildStatus() };
    case "connect":
      connectBridge(true);
      await waitForConnection(750);
      return { ok: true, result: await buildStatus() };
    case "getActiveSnapshot":
      return { ok: true, result: await runBrowserCommand("browser.snapshot", {}) };
    default:
      return { ok: false, error: `Unknown popup command: ${message.command}` };
  }
}

async function runBrowserCommand(command, payload) {
  switch (command) {
    case "browser.begin_task":
      return beginTask(payload);
    case "browser.end_task":
      return endTask(payload);
    case "browser.status":
      return buildStatus(payload);
    case "browser.list_tabs":
      return listTabs(payload);
    case "browser.get_active_tab":
      return getActiveTabSummary(payload);
    case "browser.open_tab":
      return openTab(payload);
    case "browser.activate_tab":
      return activateTab(payload);
    case "browser.close_tab":
      return closeTab(payload);
    case "browser.navigate":
      return navigate(payload);
    case "browser.back":
      return goHistory(payload, "back");
    case "browser.forward":
      return goHistory(payload, "forward");
    case "browser.refresh":
      return refresh(payload);
    case "browser.snapshot":
      return sendContentCommand(await resolveTabId(payload), "snapshot", payload);
    case "browser.extract_text":
      return sendContentCommand(await resolveTabId(payload), "extractText", payload);
    case "browser.query":
      return sendContentCommand(await resolveTabId(payload), "query", payload);
    case "browser.get_selection":
      return sendContentCommand(await resolveTabId(payload), "getSelection", payload);
    case "browser.click":
      return clickAndVerify(payload);
    case "browser.hover":
      return sendContentCommand(await resolveTabId(payload), "hover", payload);
    case "browser.type":
      return sendContentCommand(await resolveTabId(payload), "type", payload);
    case "browser.key":
      return keyAndVerify(payload);
    case "browser.prepare_secret_fill":
      return sendContentCommand(await resolveTabId(payload), "prepareSecretFill", payload);
    case "browser.secure_fill":
      return secureFillAndVerify(payload);
    case "browser.lock_sensitive_document":
      {
        const tabId = await resolveTabId(payload);
        sensitiveTabIds.add(tabId);
        return sendContentCommand(tabId, "lockSensitiveDocument", payload);
      }
    case "browser.select":
      return sendContentCommand(await resolveTabId(payload), "select", payload);
    case "browser.dropdown_options":
      return sendContentCommand(await resolveTabId(payload), "dropdownOptions", payload);
    case "browser.upload_file":
      return sendContentCommand(await resolveTabId(payload), "uploadFile", payload);
    case "browser.scroll":
      return sendContentCommand(await resolveTabId(payload), "scroll", payload);
    case "browser.wait":
      return sendContentCommand(await resolveTabId(payload), "wait", payload);
    case "browser.screenshot":
      {
        const tabId = await resolveTabId(payload);
        if (sensitiveTabIds.has(tabId)) throw new Error("INSPECTION_LOCKED: Navigate before capturing a screenshot after secure credential fill.");
        return captureVisibleTab({ ...payload, tabId });
      }
    case "browser.events":
      return readTaskEvents(payload);
    case "browser.dialog":
      throw new Error("JavaScript dialog control requires Power Browser mode");
    case "browser.request_all_sites_access":
      return requestAllSitesAccess();
    default:
      throw new Error(`Unsupported Detach browser command: ${command}`);
  }
}

async function buildStatus(payload = {}) {
  const activeTab = await getActiveTabSummary(payload).catch(() => undefined);
  const hasAllSites = await containsPermission({ origins: ["<all_urls>"] });

  return {
    extensionConnected: true,
    nativeConnected,
    runtimeConnected,
    transport: isRuntimeSocketOpen() ? "websocket" : nativeConnected ? "native" : "none",
    nativeHost: NATIVE_HOST,
    nativeError: lastNativeError,
    hasAllSitesAccess: hasAllSites,
    engine: "extension",
    taskIsolated: typeof payload.runId === "string" && ownedTaskWindows.has(payload.runId),
    activeTab
  };
}

function handleNativeEvent(message) {
  if (message.event === "runtime.connected") {
    runtimeConnected = true;
    lastNativeError = undefined;
  }

  if (message.event === "runtime.disconnected") {
    runtimeConnected = false;
    lastNativeError = "Detach runtime is not connected";
  }

  if (message.event === "runtime.error" || message.event === "native.error") {
    runtimeConnected = false;
    lastNativeError = message.error || "Browser bridge error";
  }
}

async function beginTask(payload = {}) {
  const runId = requireString(payload.runId, "runId");
  const existingWindowId = taskWindows.get(runId);
  if (Number.isInteger(existingWindowId)) {
    return { runId, windowId: existingWindowId, reused: true, isolated: ownedTaskWindows.has(runId) };
  }
  if (payload.isolated !== true) {
    const [activeTab] = await tabsQuery({ active: true, lastFocusedWindow: true });
    if (!Number.isInteger(activeTab?.windowId)) throw new Error("Chrome has no focused normal window to reuse");
    taskWindows.set(runId, activeTab.windowId);
    taskEvents.set(runId, []);
    return { runId, windowId: activeTab.windowId, tabId: activeTab.id, reused: true, isolated: false };
  }
  const window = await windowsCreate({ url: "about:blank", focused: true, type: "normal" });
  if (!Number.isInteger(window?.id)) throw new Error("Chrome did not create the task window");
  taskWindows.set(runId, window.id);
  ownedTaskWindows.add(runId);
  taskEvents.set(runId, []);
  return { runId, windowId: window.id, isolated: true };
}

async function endTask(payload = {}) {
  const runId = requireString(payload.runId, "runId");
  const windowId = taskWindows.get(runId);
  const ownsWindow = ownedTaskWindows.delete(runId);
  taskWindows.delete(runId);
  taskEvents.delete(runId);
  for (const key of downloadTasks.keys()) if (key.startsWith(`${runId}:`)) downloadTasks.delete(key);
  if (ownsWindow && Number.isInteger(windowId)) await windowsRemove(windowId).catch(() => undefined);
  return { runId, closed: ownsWindow && Number.isInteger(windowId), reusedWindow: !ownsWindow };
}

async function listTabs(payload = {}) {
  const windowId = resolveTaskWindowId(payload);
  const tabs = await tabsQuery(Number.isInteger(windowId) ? { windowId } : {});
  return tabs.map(summarizeTab);
}

async function getActiveTabSummary(payload = {}) {
  return summarizeTab(await getActiveTab(payload));
}

async function getActiveTab(payload = {}) {
  const windowId = resolveTaskWindowId(payload);
  const [tab] = await tabsQuery(Number.isInteger(windowId)
    ? { active: true, windowId }
    : { active: true, currentWindow: true });
  if (!tab?.id) {
    throw new Error("No active Chrome tab found");
  }
  return tab;
}

async function resolveTabId(payload = {}) {
  if (Number.isInteger(payload.tabId)) return payload.tabId;
  return (await getActiveTab(payload)).id;
}

async function navigate(payload = {}) {
  const tabId = await resolveTabId(payload);
  const url = requireWebUrl(payload.url);
  sensitiveTabIds.delete(tabId);
  await tabsUpdate(tabId, { url });
  return summarizeTab(await waitForTabReady(tabId, payload.timeoutMs));
}

async function openTab(payload = {}) {
  const url = requireWebUrl(payload.url);
  const windowId = resolveTaskWindowId(payload);
  if (Number.isInteger(windowId)) {
    const existingTabs = await tabsQuery({ windowId });
    const reusable = existingTabs.length === 1 && (existingTabs[0].url === "about:blank" || existingTabs[0].url === "chrome://newtab/")
      ? existingTabs[0]
      : undefined;
    if (reusable?.id) {
      await tabsUpdate(reusable.id, { url, active: payload.active !== false });
      return summarizeTab(await waitForTabReady(reusable.id, payload.timeoutMs));
    }
  }
  const tab = await tabsCreate({
    url,
    active: payload.active !== false,
    ...(Number.isInteger(windowId) ? { windowId } : {})
  });
  return summarizeTab(await waitForTabReady(tab.id, payload.timeoutMs));
}

async function activateTab(payload = {}) {
  const tabId = await resolveTabId(payload);
  const tab = await tabsUpdate(tabId, { active: true });
  await windowsUpdate(tab.windowId, { focused: true });
  return summarizeTab(tab);
}

async function closeTab(payload = {}) {
  const tabId = await resolveTabId(payload);
  const windowId = resolveTaskWindowId(payload);
  if (Number.isInteger(windowId)) {
    const tabs = await tabsQuery({ windowId });
    if (tabs.length <= 1) throw new Error("Cannot close the only tab in this browser task");
  }
  await tabsRemove(tabId);
  return { closed: tabId, activeTab: await getActiveTabSummary(payload).catch(() => undefined) };
}

async function goHistory(payload = {}, direction) {
  const tabId = await resolveTabId(payload);
  if (direction === "back") await tabsGoBack(tabId);
  else await tabsGoForward(tabId);
  return summarizeTab(await waitForTabReady(tabId, payload.timeoutMs));
}

async function refresh(payload = {}) {
  const tabId = await resolveTabId(payload);
  await tabsReload(tabId, { bypassCache: Boolean(payload.ignoreCache) });
  return summarizeTab(await waitForTabReady(tabId, payload.timeoutMs));
}

async function captureVisibleTab(payload = {}) {
  let tab = Number.isInteger(payload.tabId) ? await tabsGet(payload.tabId) : await getActiveTab(payload);
  if (!tab.active) {
    tab = await tabsUpdate(tab.id, { active: true });
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  const format = payload.format === "jpeg" ? "jpeg" : "png";
  const quality = typeof payload.quality === "number" ? payload.quality : undefined;
  const dataUrl = await tabsCaptureVisibleTab(tab.windowId, { format, quality });

  return {
    tab: summarizeTab(tab),
    format,
    dataUrl
  };
}

async function clickAndVerify(payload = {}) {
  return actionAndVerify(payload, "click");
}

async function keyAndVerify(payload = {}) {
  return actionAndVerify(payload, "key");
}

async function secureFillAndVerify(payload = {}) {
  const tabId = await resolveTabId(payload);
  const before = await tabsGet(tabId);
  sensitiveTabIds.add(tabId);
  let fillResult;
  try {
    fillResult = await sendContentCommand(tabId, "secureFill", payload);
  } catch (error) {
    const message = normalizeError(error);
    if (!payload.submitRef || !/message port closed|receiving end does not exist|context invalidated|frame was removed/i.test(message)) throw error;
    fillResult = { filled: true, submitted: true, navigationInterruptedResponse: true };
  }

  const submitted = fillResult?.submitted === true || Boolean(payload.submitRef);
  const after = submitted ? await settleAfterAction(tabId, before, payload.timeoutMs || 12_000) : await tabsGet(tabId);
  const navigationChanged = Boolean(after.url && after.url !== before.url);
  const documentReloaded = Boolean(after.detachSawNavigation);
  if (navigationChanged) {
    sensitiveTabIds.delete(tabId);
    await ensureContentScript(tabId).catch(() => undefined);
    await sendContentCommand(tabId, "unlockSensitiveDocument", {}).catch(() => undefined);
  } else if (documentReloaded) {
    await ensureContentScript(tabId).catch(() => undefined);
    await sendContentCommand(tabId, "lockSensitiveDocument", {}).catch(() => undefined);
  }

  return {
    filled: fillResult?.filled !== false,
    submitted,
    inspection: navigationChanged ? "unlocked_after_navigation" : "locked_until_navigation",
    navigation: {
      changed: navigationChanged,
      documentReloaded,
      beforeUrl: before.url || "",
      afterUrl: after.url || "",
      title: after.title || "",
      status: after.status || "unknown"
    },
    next: navigationChanged ? "verify_new_document" : submitted ? "site_remained_on_login_page" : "submit_required"
  };
}

async function actionAndVerify(payload, command) {
  const tabId = await resolveTabId(payload);
  const before = await tabsGet(tabId);
  let actionResult;
  try {
    actionResult = await sendContentCommand(tabId, command, payload);
  } catch (error) {
    const message = normalizeError(error);
    if (!/message port closed|receiving end does not exist|context invalidated|frame was removed/i.test(message)) throw error;
    actionResult = { dispatched: true, navigationInterruptedResponse: true };
  }
  const after = await settleAfterAction(tabId, before, payload.timeoutMs);
  return { ...actionResult, before: summarizeTab(before), after: summarizeTab(after), verified: true };
}

async function settleAfterAction(tabId, before, requestedTimeout) {
  const timeoutMs = Math.max(500, Math.min(15_000, Number(requestedTimeout) || 5_000));
  const startedAt = Date.now();
  let sawNavigation = false;
  let tab = before;
  while (Date.now() - startedAt < timeoutMs) {
    tab = await tabsGet(tabId);
    sawNavigation ||= tab.status === "loading" || tab.url !== before.url;
    if (sawNavigation && tab.status === "complete") {
      if (/^https?:\/\//.test(tab.url || "")) {
        await ensureContentScript(tabId).catch(() => undefined);
        await sendContentCommand(tabId, "wait", { timeoutMs: Math.min(4_000, timeoutMs) }).catch(() => undefined);
      }
      return { ...(await tabsGet(tabId)), detachSawNavigation: true };
    }
    if (!sawNavigation && Date.now() - startedAt >= 400) return { ...tab, detachSawNavigation: false };
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  return { ...tab, detachSawNavigation: sawNavigation };
}

async function waitForTabReady(tabId, requestedTimeout) {
  const timeoutMs = Math.max(500, Math.min(60_000, Number(requestedTimeout) || 15_000));
  const startedAt = Date.now();
  const deadline = Date.now() + timeoutMs;
  let lastTab;
  let lastSoftReadyAttempt = 0;
  while (Date.now() < deadline) {
    lastTab = await tabsGet(tabId);
    if (lastTab.status === "complete") {
      if (/^https?:\/\//.test(lastTab.url || "")) {
        await ensureContentScript(tabId).catch(() => undefined);
        await sendContentCommand(tabId, "wait", { timeoutMs: Math.min(5_000, timeoutMs) }).catch(() => undefined);
      }
      return await tabsGet(tabId);
    }
    if (
      /^https?:\/\//.test(lastTab.url || "")
      && Date.now() - startedAt >= 1_000
      && Date.now() - lastSoftReadyAttempt >= 750
    ) {
      lastSoftReadyAttempt = Date.now();
      try {
        await ensureContentScript(tabId);
        const state = await sendContentCommand(tabId, "wait", { timeoutMs: 700 });
        if (state?.matched) return { ...(await tabsGet(tabId)), detachSoftReady: true };
      } catch {
        // The document may still be replacing its execution context; keep polling.
      }
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  if (/^https?:\/\//.test(lastTab?.url || "")) {
    try {
      await ensureContentScript(tabId);
      const body = await sendContentCommand(tabId, "query", { selector: "body", kind: "count" });
      if (body?.count > 0) return { ...(await tabsGet(tabId)), detachSoftReady: true, detachLoadTimedOut: true };
    } catch {
      // A page with no inspectable document remains a real navigation failure.
    }
  }
  throw new Error(`NAVIGATION_TIMEOUT: Browser tab did not finish loading within ${timeoutMs}ms (${lastTab?.url || "unknown URL"})`);
}

function resolveTaskWindowId(payload = {}) {
  const runId = typeof payload.runId === "string" ? payload.runId : "";
  return runId ? taskWindows.get(runId) : undefined;
}

function readTaskEvents(payload = {}) {
  const runId = requireString(payload.runId, "runId");
  const events = (taskEvents.get(runId) || []).map((event) => ({ ...event }));
  if (payload.drain !== false) taskEvents.set(runId, []);
  return { events };
}

function runIdForWindow(windowId) {
  for (const [runId, taskWindowId] of taskWindows) {
    if (taskWindowId === windowId) return runId;
  }
  return undefined;
}

function queueTaskEvent(runId, event) {
  if (!taskEvents.has(runId)) taskEvents.set(runId, []);
  const events = taskEvents.get(runId);
  const queued = { ...event, timestamp: Date.now() };
  const previous = events.at(-1);
  const duplicateNavigation = queued.type === "navigation"
    && previous?.type === "navigation"
    && previous.tabId === queued.tabId
    && previous.url === queued.url
    && previous.status === queued.status;
  const replaceDownloadProgress = queued.type === "download"
    && queued.phase === "progress"
    && previous?.type === "download"
    && previous.phase === "progress"
    && previous.downloadId === queued.downloadId;
  if (replaceDownloadProgress) events[events.length - 1] = queued;
  else if (!duplicateNavigation) events.push(queued);
  if (events.length > 100) events.splice(0, events.length - 100);
}

async function requestAllSitesAccess() {
  const granted = await permissionsRequest({ origins: ["<all_urls>"] });
  return {
    granted,
    hasAllSitesAccess: await containsPermission({ origins: ["<all_urls>"] })
  };
}

async function sendContentCommand(tabId, command, payload) {
  await ensureSupportedTab(tabId);
  await ensureContentScript(tabId);

  return sendMessageToTab(tabId, {
    target: CONTENT_TARGET,
    command,
    payload
  });
}

async function ensureSupportedTab(tabId) {
  const tab = await tabsGet(tabId);
  const url = tab.url || "";

  if (!/^https?:\/\//.test(url)) {
    throw new Error(
      `The browser bridge is connected, but Chrome does not allow automation on its internal page "${tab.title || url}" (${url}). ` +
      "Use browser.open_tab with an http/https URL or choose a normal tab from browser.list_tabs. No approval prompt is required."
    );
  }
}

async function ensureContentScript(tabId) {
  try {
    await sendMessageToTab(tabId, {
      target: CONTENT_TARGET,
      command: "ping",
      payload: {}
    }, 1_000);
    return;
  } catch {
    await scriptingExecuteScript({
      target: { tabId },
      files: ["content-script.js"]
    });
  }
}

function sendMessageToTab(tabId, message, timeoutMs = COMMAND_TIMEOUT_MS) {
  const requestId = crypto.randomUUID();
  const payload = { ...message, requestId };

  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      pendingCommands.delete(requestId);
      reject(new Error(`Browser command timed out: ${message.command}`));
    }, timeoutMs);

    pendingCommands.set(requestId, { resolve, reject, timeout });

    chrome.tabs.sendMessage(tabId, payload, (response) => {
      const pending = pendingCommands.get(requestId);
      if (!pending) return;

      pendingCommands.delete(requestId);
      clearTimeout(pending.timeout);

      const runtimeError = chrome.runtime.lastError?.message;
      if (runtimeError) {
        pending.reject(new Error(runtimeError));
        return;
      }

      if (!response?.ok) {
        pending.reject(new Error(response?.error || "Browser command failed"));
        return;
      }

      pending.resolve(response.result);
    });
  });
}

function sendNative(message) {
  if (!nativePort) return false;

  try {
    nativePort.postMessage(message);
    return true;
  } catch (error) {
    nativeConnected = false;
    lastNativeError = normalizeError(error);
    return false;
  }
}

function sendRuntime(message) {
  if (!isRuntimeSocketOpen()) return false;

  try {
    runtimeSocket.send(JSON.stringify(message));
    return true;
  } catch (error) {
    runtimeConnected = false;
    lastNativeError = normalizeError(error);
    return false;
  }
}

function sendBridge(message) {
  return sendRuntime(message) || sendNative(message);
}

function isRuntimeSocketOpen() {
  return runtimeSocket?.readyState === WebSocket.OPEN;
}

function waitForConnection(timeoutMs) {
  if (runtimeConnected) return Promise.resolve();
  return new Promise((resolve) => setTimeout(resolve, timeoutMs));
}

function summarizeTab(tab) {
  if (!tab) return undefined;

  const url = tab.url || "";
  const automatable = /^https?:\/\//.test(url);

  return {
    id: tab.id,
    windowId: tab.windowId,
    active: Boolean(tab.active),
    title: tab.title || "",
    url,
    favIconUrl: tab.favIconUrl || "",
    status: tab.status || "unknown",
    softReady: Boolean(tab.detachSoftReady),
    loadTimedOut: Boolean(tab.detachLoadTimedOut),
    automatable,
    restrictionReason: automatable ? undefined : "Chrome internal pages cannot be automated by extensions"
  };
}

function requireString(value, name) {
  if (typeof value !== "string" || !value.trim()) {
    throw new Error(`Missing required browser command field: ${name}`);
  }
  return value.trim();
}

function requireWebUrl(value) {
  const url = requireString(value, "url");
  if (!/^https?:\/\//.test(url)) {
    throw new Error("Browser URLs must start with http:// or https://");
  }
  return url;
}

function normalizeError(error) {
  if (error instanceof Error) return error.message;
  return String(error || "Unknown error");
}

function tabsQuery(queryInfo) {
  return new Promise((resolve, reject) => {
    chrome.tabs.query(queryInfo, withLastError(resolve, reject));
  });
}

function tabsGet(tabId) {
  return new Promise((resolve, reject) => {
    chrome.tabs.get(tabId, withLastError(resolve, reject));
  });
}

function tabsUpdate(tabId, updateProperties) {
  return new Promise((resolve, reject) => {
    chrome.tabs.update(tabId, updateProperties, withLastError(resolve, reject));
  });
}

function tabsCreate(createProperties) {
  return new Promise((resolve, reject) => {
    chrome.tabs.create(createProperties, withLastError(resolve, reject));
  });
}

function tabsRemove(tabId) {
  return new Promise((resolve, reject) => {
    chrome.tabs.remove(tabId, withLastError(resolve, reject));
  });
}

function tabsGoBack(tabId) {
  return new Promise((resolve, reject) => {
    chrome.tabs.goBack(tabId, withLastError(resolve, reject));
  });
}

function tabsGoForward(tabId) {
  return new Promise((resolve, reject) => {
    chrome.tabs.goForward(tabId, withLastError(resolve, reject));
  });
}

function tabsReload(tabId, reloadProperties) {
  return new Promise((resolve, reject) => {
    chrome.tabs.reload(tabId, reloadProperties, withLastError(resolve, reject));
  });
}

function tabsCaptureVisibleTab(windowId, options) {
  return new Promise((resolve, reject) => {
    chrome.tabs.captureVisibleTab(windowId, options, withLastError(resolve, reject));
  });
}

function windowsCreate(createData) {
  return new Promise((resolve, reject) => {
    chrome.windows.create(createData, withLastError(resolve, reject));
  });
}

function windowsUpdate(windowId, updateInfo) {
  return new Promise((resolve, reject) => {
    chrome.windows.update(windowId, updateInfo, withLastError(resolve, reject));
  });
}

function windowsRemove(windowId) {
  return new Promise((resolve, reject) => {
    chrome.windows.remove(windowId, withLastError(resolve, reject));
  });
}

function scriptingExecuteScript(injection) {
  return new Promise((resolve, reject) => {
    chrome.scripting.executeScript(injection, withLastError(resolve, reject));
  });
}

function permissionsRequest(permissions) {
  return new Promise((resolve, reject) => {
    chrome.permissions.request(permissions, withLastError(resolve, reject));
  });
}

function containsPermission(permissions) {
  return new Promise((resolve, reject) => {
    chrome.permissions.contains(permissions, withLastError(resolve, reject));
  });
}

function withLastError(resolve, reject) {
  return (result) => {
    const error = chrome.runtime.lastError?.message;
    if (error) {
      reject(new Error(error));
      return;
    }
    resolve(result);
  };
}
