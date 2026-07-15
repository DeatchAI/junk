const port = chrome.runtime.connect({ name: "popup" });

const nativeState = document.getElementById("nativeState");
const statusText = document.getElementById("statusText");
const activeTab = document.getElementById("activeTab");
const refreshButton = document.getElementById("refreshButton");
const connectButton = document.getElementById("connectButton");
const siteAccessButton = document.getElementById("siteAccessButton");
const snapshotButton = document.getElementById("snapshotButton");
const snapshotOutput = document.getElementById("snapshotOutput");

const pending = new Map();

port.onMessage.addListener((message) => {
  const request = pending.get(message.requestId);
  if (!request) return;
  pending.delete(message.requestId);
  request.resolve(message);
});

port.onDisconnect.addListener(() => {
  setStatus({
    nativeConnected: false,
    nativeError: chrome.runtime.lastError?.message || "Popup disconnected"
  });
});

refreshButton.addEventListener("click", refresh);
connectButton.addEventListener("click", connect);
siteAccessButton.addEventListener("click", requestAllSites);
snapshotButton.addEventListener("click", getSnapshot);

refresh();

async function refresh() {
  await withButton(refreshButton, async () => {
    const response = await send("status");
    if (!response.ok) throw new Error(response.error);
    setStatus(response.result);
  });
}

async function connect() {
  await withButton(connectButton, async () => {
    const response = await send("connect");
    if (!response.ok) throw new Error(response.error);
    setStatus(response.result);
  });
}

async function requestAllSites() {
  await withButton(siteAccessButton, async () => {
    await requestAllSitesAccess();
    await refresh();
  }, { restore: false });
}

async function getSnapshot() {
  await withButton(snapshotButton, async () => {
    const response = await send("getActiveSnapshot");
    if (!response.ok) throw new Error(response.error);

    const snapshot = response.result;
    snapshotOutput.textContent = JSON.stringify({
      title: snapshot.title,
      url: snapshot.url,
      elements: snapshot.elements?.slice(0, 8),
      textPreview: snapshot.text?.slice(0, 500)
    }, null, 2);
  });
}

function send(command, payload = {}) {
  const requestId = crypto.randomUUID();

  return new Promise((resolve, reject) => {
    pending.set(requestId, { resolve, reject });
    port.postMessage({
      target: "lazzy-service-worker",
      requestId,
      command,
      payload
    });

    setTimeout(() => {
      if (!pending.has(requestId)) return;
      pending.delete(requestId);
      reject(new Error(`Timed out: ${command}`));
    }, 8_000);
  });
}

function setStatus(status = {}) {
  nativeState.textContent = status.runtimeConnected ? "Connected" : "Not connected";
  nativeState.classList.toggle("connected", Boolean(status.runtimeConnected));
  nativeState.classList.toggle("disconnected", !status.runtimeConnected);

  if (status.runtimeConnected) {
    statusText.textContent = "Ready for Detach browser commands.";
  } else if (status.nativeError) {
    statusText.textContent = status.nativeError;
  } else {
    statusText.textContent = "Detach runtime is not connected yet.";
  }

  if (status.activeTab) {
    activeTab.textContent = status.activeTab.title || status.activeTab.url || "Active tab detected";
  } else {
    activeTab.textContent = "No active tab detected.";
  }

  siteAccessButton.textContent = status.hasAllSitesAccess
    ? "All-sites automation access granted"
    : "Allow automation on all sites";
  siteAccessButton.disabled = Boolean(status.hasAllSitesAccess);
}

async function requestAllSitesAccess() {
  return new Promise((resolve, reject) => {
    chrome.permissions.request({ origins: ["<all_urls>"] }, (granted) => {
      const error = chrome.runtime.lastError?.message;
      if (error) {
        reject(new Error(error));
        return;
      }
      resolve(granted);
    });
  });
}

async function withButton(button, action, options = {}) {
  const previousText = button.textContent;
  button.disabled = true;
  button.textContent = "Working...";

  try {
    await action();
  } catch (error) {
    statusText.textContent = error instanceof Error ? error.message : String(error);
  } finally {
    if (options.restore !== false) {
      button.disabled = false;
      button.textContent = previousText;
    }
  }
}
