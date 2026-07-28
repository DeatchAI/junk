chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.target !== "lazzy-offscreen" || message.command !== "crop") return false;
  cropImage(message.dataUrl, message.crop)
    .then((dataUrl) => sendResponse({ ok: true, dataUrl }))
    .catch((error) => sendResponse({ ok: false, error: error instanceof Error ? error.message : String(error) }));
  return true;
});

async function cropImage(dataUrl, crop = {}) {
  const response = await fetch(dataUrl);
  const bitmap = await createImageBitmap(await response.blob());
  const scale = Math.max(0.1, Number(crop.devicePixelRatio) || 1);
  const sourceX = clamp(Math.round((Number(crop.x) || 0) * scale), 0, bitmap.width - 1);
  const sourceY = clamp(Math.round((Number(crop.y) || 0) * scale), 0, bitmap.height - 1);
  const sourceWidth = clamp(Math.round((Number(crop.width) || 1) * scale), 1, bitmap.width - sourceX);
  const sourceHeight = clamp(Math.round((Number(crop.height) || 1) * scale), 1, bitmap.height - sourceY);
  const canvas = new OffscreenCanvas(sourceWidth, sourceHeight);
  const context = canvas.getContext("2d");
  if (!context) throw new Error("Browser image canvas is unavailable");
  context.drawImage(bitmap, sourceX, sourceY, sourceWidth, sourceHeight, 0, 0, sourceWidth, sourceHeight);
  bitmap.close();
  const blob = await canvas.convertToBlob({ type: "image/png" });
  return await blobToDataUrl(blob);
}

function blobToDataUrl(blob) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onerror = () => reject(reader.error || new Error("Could not encode cropped screenshot"));
    reader.onload = () => resolve(String(reader.result || ""));
    reader.readAsDataURL(blob);
  });
}

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}
