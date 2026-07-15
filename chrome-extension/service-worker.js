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

chrome.runtime.onInstalled.addListener(() => {
  chrome.storage.local.set({
    lazzyBrowserAgent: {
      nativeHost: NATIVE_HOST,
      installedAt: Date.now()
    }
  });
});

chrome.runtime.onStartup.addListener(connectBridge);

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
    const result = await runBrowserCommand(command, payload || {});
    sendBridge({ type: "result", id, ok: true, result });
  } catch (error) {
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
    case "browser.status":
      return buildStatus();
    case "browser.list_tabs":
      return listTabs();
    case "browser.get_active_tab":
      return getActiveTabSummary();
    case "browser.open_tab":
      return openTab(payload);
    case "browser.navigate":
      return navigate(payload);
    case "browser.snapshot":
      return sendContentCommand(await resolveTabId(payload), "snapshot", payload);
    case "browser.extract_text":
      return sendContentCommand(await resolveTabId(payload), "extractText", payload);
    case "browser.get_selection":
      return sendContentCommand(await resolveTabId(payload), "getSelection", payload);
    case "browser.click":
      return sendContentCommand(await resolveTabId(payload), "click", payload);
    case "browser.type":
      return sendContentCommand(await resolveTabId(payload), "type", payload);
    case "browser.prepare_secret_fill":
      return sendContentCommand(await resolveTabId(payload), "prepareSecretFill", payload);
    case "browser.lock_sensitive_document":
      {
        const tabId = await resolveTabId(payload);
        sensitiveTabIds.add(tabId);
        return sendContentCommand(tabId, "lockSensitiveDocument", payload);
      }
    case "browser.select":
      return sendContentCommand(await resolveTabId(payload), "select", payload);
    case "browser.scroll":
      return sendContentCommand(await resolveTabId(payload), "scroll", payload);
    case "browser.screenshot":
      {
        const tabId = await resolveTabId(payload);
        if (sensitiveTabIds.has(tabId)) throw new Error("Screenshots are locked after a secure credential fill. Navigate before capturing this page.");
        return captureVisibleTab({ ...payload, tabId });
      }
    case "browser.request_all_sites_access":
      return requestAllSitesAccess();
    default:
      throw new Error(`Unsupported Detach browser command: ${command}`);
  }
}

async function buildStatus() {
  const activeTab = await getActiveTabSummary().catch(() => undefined);
  const hasAllSites = await containsPermission({ origins: ["<all_urls>"] });

  return {
    extensionConnected: true,
    nativeConnected,
    runtimeConnected,
    transport: isRuntimeSocketOpen() ? "websocket" : nativeConnected ? "native" : "none",
    nativeHost: NATIVE_HOST,
    nativeError: lastNativeError,
    hasAllSitesAccess: hasAllSites,
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

async function listTabs() {
  const tabs = await tabsQuery({});
  return tabs.map(summarizeTab);
}

async function getActiveTabSummary() {
  return summarizeTab(await getActiveTab());
}

async function getActiveTab() {
  const [tab] = await tabsQuery({ active: true, currentWindow: true });
  if (!tab?.id) {
    throw new Error("No active Chrome tab found");
  }
  return tab;
}

async function resolveTabId(payload = {}) {
  if (Number.isInteger(payload.tabId)) return payload.tabId;
  return (await getActiveTab()).id;
}

async function navigate(payload = {}) {
  const tabId = await resolveTabId(payload);
  const url = requireWebUrl(payload.url);
  const tab = await tabsUpdate(tabId, { url });
  return summarizeTab(tab);
}

async function openTab(payload = {}) {
  const url = requireWebUrl(payload.url);
  const tab = await tabsCreate({
    url,
    active: payload.active !== false
  });
  return summarizeTab(tab);
}

async function captureVisibleTab(payload = {}) {
  const tab = Number.isInteger(payload.tabId) ? await tabsGet(payload.tabId) : await getActiveTab();
  const format = payload.format === "jpeg" ? "jpeg" : "png";
  const quality = typeof payload.quality === "number" ? payload.quality : undefined;
  const dataUrl = await tabsCaptureVisibleTab(tab.windowId, { format, quality });

  return {
    tab: summarizeTab(tab),
    format,
    dataUrl
  };
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

function tabsCaptureVisibleTab(windowId, options) {
  return new Promise((resolve, reject) => {
    chrome.tabs.captureVisibleTab(windowId, options, withLastError(resolve, reject));
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
