(() => {
  if (window.__lazzyBrowserAgentLoaded) return;
  window.__lazzyBrowserAgentLoaded = true;

  const MAX_TEXT_LENGTH = 20_000;
  const MAX_ELEMENTS = 160;
  const REF_ATTR = "data-lazzy-ref";
  let secretDocumentLocked = false;

  chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
    if (!message || message.target !== "lazzy-content") return false;

    handleCommand(message.command, message.payload || {})
      .then((result) => sendResponse({ ok: true, result }))
      .catch((error) => sendResponse({ ok: false, error: normalizeError(error) }));
    return true;
  });

  async function handleCommand(command, payload) {
    switch (command) {
      case "ping":
        return { ready: true };
      case "snapshot":
        return snapshotPage(payload);
      case "extractText":
        return extractText(payload);
      case "getSelection":
        return getSelectionInfo();
      case "click":
        return clickTarget(payload);
      case "type":
        return typeIntoTarget(payload);
      case "prepareSecretFill":
        return prepareSecretFill(payload);
      case "lockSensitiveDocument":
        return lockSensitiveDocument();
      case "select":
        return selectTarget(payload);
      case "scroll":
        return scrollPage(payload);
      default:
        throw new Error(`Unsupported page command: ${command}`);
    }
  }

  function snapshotPage(payload = {}) {
    if (secretDocumentLocked) throw new Error("Inspection is locked after a secure credential fill. Navigate before taking another snapshot.");
    assignElementRefs();

    return {
      url: location.href,
      title: document.title,
      viewport: {
        width: window.innerWidth,
        height: window.innerHeight,
        scrollX: window.scrollX,
        scrollY: window.scrollY,
        devicePixelRatio: window.devicePixelRatio
      },
      meta: collectMeta(),
      selection: getSelectionInfo(),
      text: extractText({ maxLength: payload.maxTextLength || MAX_TEXT_LENGTH }).text,
      elements: collectInteractiveElements(payload.maxElements || MAX_ELEMENTS)
    };
  }

  function extractText(payload = {}) {
    if (secretDocumentLocked) throw new Error("Text extraction is locked after a secure credential fill. Navigate before extracting page text.");
    const maxLength = clampNumber(payload.maxLength, 1_000, 80_000, MAX_TEXT_LENGTH);
    const text = normalizeWhitespace(document.body?.innerText || "");

    return {
      text: truncate(text, maxLength),
      truncated: text.length > maxLength
    };
  }

  function getSelectionInfo() {
    if (secretDocumentLocked) throw new Error("Selection inspection is locked after a secure credential fill. Navigate before inspecting this page.");
    const selection = window.getSelection();
    const text = selection ? String(selection).trim() : "";

    return {
      text,
      hasSelection: text.length > 0
    };
  }

  function clickTarget(payload = {}) {
    const element = resolveElement(payload);
    scrollIntoView(element);
    simulatePointer(element);
    element.click();

    return {
      clicked: describeElement(element)
    };
  }

  function typeIntoTarget(payload = {}) {
    const element = resolveElement(payload);
    const text = requireString(payload.inputText ?? payload.text, "inputText");
    const append = Boolean(payload.append);

    scrollIntoView(element);
    element.focus();

    if (element.isContentEditable) {
      if (append) {
        element.textContent = `${element.textContent || ""}${text}`;
      } else {
        element.textContent = text;
      }
      dispatchInputEvents(element);
      return { typed: describeElement(element) };
    }

    if (!("value" in element)) {
      throw new Error("Target is not text-editable");
    }

    const nextValue = append ? `${element.value || ""}${text}` : text;
    setNativeValue(element, nextValue);
    dispatchInputEvents(element);

    return { typed: describeElement(element) };
  }

  function prepareSecretFill(payload = {}) {
    const expectedOrigin = requireString(payload.origin, "origin");
    if (location.origin !== expectedOrigin) throw new Error("Credential destination changed; refusing secure fill.");
    const username = resolveElement({ ref: requireString(payload.usernameRef, "usernameRef") });
    const password = resolveElement({ ref: requireString(payload.passwordRef, "passwordRef") });
    if (!(username instanceof HTMLInputElement) || !(password instanceof HTMLInputElement) || password.type.toLowerCase() !== "password") {
      throw new Error("Secure credential fill requires a username input and a password input.");
    }
    username.focus();
    scrollIntoView(username);
    return { origin: location.origin, focused: true, usernameRef: username.getAttribute(REF_ATTR), passwordRef: password.getAttribute(REF_ATTR) };
  }

  function lockSensitiveDocument() {
    secretDocumentLocked = true;
    return { protected: true, message: "Further page inspection is locked until navigation." };
  }

  function selectTarget(payload = {}) {
    const element = resolveElement(payload);
    const value = requireString(payload.value, "value");

    if (!(element instanceof HTMLSelectElement)) {
      throw new Error("Target is not a select menu");
    }

    scrollIntoView(element);
    element.focus();
    element.value = value;
    dispatchInputEvents(element);

    return { selected: describeElement(element) };
  }

  function scrollPage(payload = {}) {
    const behavior = payload.smooth ? "smooth" : "auto";

    if (payload.ref || payload.selector || payload.text) {
      const element = resolveElement(payload);
      element.scrollIntoView({ behavior, block: payload.block || "center" });
    } else if (Number.isFinite(payload.x) || Number.isFinite(payload.y)) {
      window.scrollTo({
        left: Number.isFinite(payload.x) ? payload.x : window.scrollX,
        top: Number.isFinite(payload.y) ? payload.y : window.scrollY,
        behavior
      });
    } else {
      window.scrollBy({
        left: Number(payload.deltaX || 0),
        top: Number(payload.deltaY || window.innerHeight * 0.75),
        behavior
      });
    }

    return {
      scrollX: window.scrollX,
      scrollY: window.scrollY
    };
  }

  function assignElementRefs() {
    let index = 1;

    for (const element of document.querySelectorAll(interactiveSelector())) {
      if (!isVisible(element)) continue;
      if (!element.getAttribute(REF_ATTR)) {
        element.setAttribute(REF_ATTR, `lz-${index}`);
      }
      index += 1;
    }
  }

  function collectInteractiveElements(maxElements) {
    const elements = [];

    for (const element of document.querySelectorAll(interactiveSelector())) {
      if (!isVisible(element)) continue;
      elements.push(describeElement(element));
      if (elements.length >= maxElements) break;
    }

    return elements;
  }

  function collectMeta() {
    const description = document.querySelector('meta[name="description"]')?.content || "";

    return {
      description,
      language: document.documentElement.lang || "",
      headings: Array.from(document.querySelectorAll("h1, h2"))
        .filter(isVisible)
        .slice(0, 20)
        .map((heading) => ({
          level: heading.tagName.toLowerCase(),
          text: normalizeWhitespace(heading.innerText || heading.textContent || "")
        }))
    };
  }

  function resolveElement(payload = {}) {
    if (payload.ref) {
      const element = document.querySelector(`[${REF_ATTR}="${cssEscape(String(payload.ref))}"]`);
      if (element) return element;
      throw new Error(`No page element found for ref: ${payload.ref}`);
    }

    if (payload.selector) {
      const element = document.querySelector(String(payload.selector));
      if (element) return element;
      throw new Error(`No page element found for selector: ${payload.selector}`);
    }

    const targetText = payload.targetText ?? payload.text;
    if (targetText) {
      const element = findByText(String(targetText));
      if (element) return element;
      throw new Error(`No visible page element found for text: ${targetText}`);
    }

    throw new Error("Browser command needs ref, selector, or text");
  }

  function findByText(text) {
    const needle = normalizeWhitespace(text).toLowerCase();
    if (!needle) return undefined;

    for (const element of document.querySelectorAll(interactiveSelector())) {
      if (!isVisible(element)) continue;
      const haystack = normalizeWhitespace(element.innerText || element.textContent || element.getAttribute("aria-label") || "").toLowerCase();
      if (haystack.includes(needle)) return element;
    }

    return undefined;
  }

  function describeElement(element) {
    const rect = element.getBoundingClientRect();
    const tag = element.tagName.toLowerCase();
    const type = element.getAttribute("type") || "";
    const isPassword = tag === "input" && type.toLowerCase() === "password";

    return {
      ref: element.getAttribute(REF_ATTR) || "",
      tag,
      type,
      role: element.getAttribute("role") || implicitRole(element),
      text: truncate(normalizeWhitespace(element.innerText || element.textContent || ""), 240),
      ariaLabel: element.getAttribute("aria-label") || "",
      name: element.getAttribute("name") || "",
      placeholder: element.getAttribute("placeholder") || "",
      value: isPassword ? "[password]" : truncate(String(element.value || ""), 240),
      href: element.href || element.getAttribute("href") || "",
      disabled: Boolean(element.disabled || element.getAttribute("aria-disabled") === "true"),
      rect: {
        x: Math.round(rect.x),
        y: Math.round(rect.y),
        width: Math.round(rect.width),
        height: Math.round(rect.height)
      }
    };
  }

  function implicitRole(element) {
    const tag = element.tagName.toLowerCase();
    if (tag === "a") return "link";
    if (tag === "button") return "button";
    if (tag === "select") return "combobox";
    if (tag === "textarea") return "textbox";
    if (tag === "input") {
      const type = (element.getAttribute("type") || "text").toLowerCase();
      if (["button", "submit", "reset"].includes(type)) return "button";
      if (type === "checkbox") return "checkbox";
      if (type === "radio") return "radio";
      return "textbox";
    }
    return "";
  }

  function interactiveSelector() {
    return [
      "a[href]",
      "button",
      "input",
      "textarea",
      "select",
      "[contenteditable='true']",
      "[role='button']",
      "[role='link']",
      "[role='menuitem']",
      "[role='option']",
      "[role='checkbox']",
      "[role='radio']",
      "[tabindex]:not([tabindex='-1'])"
    ].join(",");
  }

  function isVisible(element) {
    if (!(element instanceof Element)) return false;
    const style = window.getComputedStyle(element);
    if (style.visibility === "hidden" || style.display === "none" || Number(style.opacity) === 0) return false;
    const rect = element.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0;
  }

  function scrollIntoView(element) {
    element.scrollIntoView({ behavior: "auto", block: "center", inline: "center" });
  }

  function simulatePointer(element) {
    for (const type of ["pointerdown", "mousedown", "pointerup", "mouseup"]) {
      element.dispatchEvent(new MouseEvent(type, { bubbles: true, cancelable: true, view: window }));
    }
  }

  function dispatchInputEvents(element) {
    element.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertText" }));
    element.dispatchEvent(new Event("change", { bubbles: true }));
  }

  function setNativeValue(element, value) {
    const prototype = Object.getPrototypeOf(element);
    const descriptor = Object.getOwnPropertyDescriptor(prototype, "value");

    if (descriptor?.set) {
      descriptor.set.call(element, value);
    } else {
      element.value = value;
    }
  }

  function requireString(value, name) {
    if (typeof value !== "string") {
      throw new Error(`Missing required page command field: ${name}`);
    }
    return value;
  }

  function normalizeWhitespace(text) {
    return String(text || "").replace(/\s+/g, " ").trim();
  }

  function truncate(text, maxLength) {
    if (text.length <= maxLength) return text;
    return `${text.slice(0, maxLength)}...`;
  }

  function clampNumber(value, min, max, fallback) {
    const number = Number(value);
    if (!Number.isFinite(number)) return fallback;
    return Math.min(max, Math.max(min, number));
  }

  function cssEscape(value) {
    if (window.CSS?.escape) return window.CSS.escape(value);
    return value.replace(/["\\]/g, "\\$&");
  }

  function normalizeError(error) {
    if (error instanceof Error) return error.message;
    return String(error || "Unknown error");
  }
})();
