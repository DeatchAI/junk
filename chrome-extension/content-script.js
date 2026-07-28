(() => {
  if (window.__lazzyBrowserAgentLoaded) return;
  window.__lazzyBrowserAgentLoaded = true;

  const MAX_TEXT_LENGTH = 12_000;
  const MAX_ELEMENTS = 160;
  const REF_ATTR = "data-lazzy-ref";
  const pageSession = crypto.randomUUID().slice(0, 8);
  const elementRefs = new WeakMap();
  const refElements = new Map();
  let nextElementRef = 1;
  let snapshotVersion = 0;
  let previousElementSignatures = new Map();
  let secretDocumentLocked = false;

  window.addEventListener("message", (event) => {
    if (event.source !== window || event.data?.source !== "detach-dialog-bridge") return;
    chrome.runtime.sendMessage({
      target: "lazzy-dialog-event",
      dialogType: event.data.dialogType,
      message: event.data.message,
      defaultValue: event.data.defaultValue,
      action: event.data.action
    }).catch(() => undefined);
  });

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
      case "query":
        return queryPage(payload);
      case "getSelection":
        return getSelectionInfo();
      case "click":
        return clickTarget(payload);
      case "focus":
        return focusTarget(payload);
      case "check":
        return checkTarget(payload);
      case "hover":
        return hoverTarget(payload);
      case "drag":
        return dragTarget(payload);
      case "type":
        return typeIntoTarget(payload);
      case "prepareSecretFill":
        return prepareSecretFill(payload);
      case "secureFill":
        return secureFill(payload);
      case "lockSensitiveDocument":
        return lockSensitiveDocument();
      case "unlockSensitiveDocument":
        secretDocumentLocked = false;
        return { protected: false };
      case "select":
        return selectTarget(payload);
      case "dropdownOptions":
        return dropdownOptions(payload);
      case "uploadFile":
        return uploadFile(payload);
      case "key":
        return pressKey(payload);
      case "scroll":
        return scrollPage(payload);
      case "wait":
        return waitForPage(payload);
      case "media":
        return mediaCommand(payload);
      case "fetchArtifact":
        return fetchArtifact(payload);
      default:
        throw new Error(`Unsupported page command: ${command}`);
    }
  }

  function snapshotPage(payload = {}) {
    if (secretDocumentLocked) throw new Error("INSPECTION_LOCKED: Navigate before taking another snapshot after secure credential fill.");
    assignElementRefs();
    const elements = collectInteractiveElements(payload.maxElements || MAX_ELEMENTS);
    const nextSignatures = new Map(elements.map((element) => [
      element.ref,
      JSON.stringify([element.role, element.text, element.value, element.disabled, element.rect])
    ]));
    const changed = elements.filter((element) => previousElementSignatures.get(element.ref) !== nextSignatures.get(element.ref));
    const removedRefs = Array.from(previousElementSignatures.keys()).filter((ref) => !nextSignatures.has(ref));
    previousElementSignatures = nextSignatures;
    snapshotVersion += 1;

    return {
      engine: "extension",
      snapshotVersion,
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
      elements,
      tables: collectTables(),
      delta: {
        changed,
        removedRefs,
        unchangedCount: Math.max(0, elements.length - changed.length)
      }
    };
  }

  function extractText(payload = {}) {
    if (secretDocumentLocked) throw new Error("INSPECTION_LOCKED: Navigate before extracting page text after secure credential fill.");
    const maxLength = clampNumber(payload.maxLength, 1_000, 80_000, MAX_TEXT_LENGTH);
    const text = normalizeWhitespace(document.body?.innerText || "");

    return {
      text: truncate(text, maxLength),
      truncated: text.length > maxLength
    };
  }

  function queryPage(payload = {}) {
    if (secretDocumentLocked) throw new Error("INSPECTION_LOCKED: Navigate before querying the DOM after secure credential fill.");
    const kind = String(payload.kind || "all");
    const elements = findQueryElements(payload);
    if (kind === "count") return { count: elements.length };
    if (kind === "all") {
      const maxResults = clampNumber(payload.maxResults, 1, 1_000, 250);
      return { count: elements.length, elements: elements.slice(0, maxResults).map(serializeQueryElement) };
    }

    const element = elements[0];
    if (!element) {
      if (kind === "textContent" || kind === "innerText") return { value: null, matched: false };
      throw new Error(`No page element matched the live ${kind} query`);
    }
    if (kind === "textContent") {
      const value = String(element.textContent ?? "");
      const maxLength = clampNumber(payload.maxLength, 1_000, 1_000_000, 1_000_000);
      return { value: truncate(value, maxLength), truncated: value.length > maxLength, matched: true };
    }
    if (kind === "innerText") {
      const value = String(element.innerText ?? element.textContent ?? "");
      const maxLength = clampNumber(payload.maxLength, 1_000, 1_000_000, 1_000_000);
      return { value: truncate(value, maxLength), truncated: value.length > maxLength, matched: true };
    }
    if (kind === "inputValue") {
      return { value: liveElementValue(element), matched: true };
    }
    if (kind === "element") {
      return { element: serializeQueryElement(element), matched: true };
    }
    if (kind === "checkValidity") {
      return {
        valid: typeof element.checkValidity === "function" ? element.checkValidity() : true,
        validity: serializeElementValidity(element),
        matched: true
      };
    }
    throw new Error(`Unsupported live DOM query kind: ${kind}`);
  }

  function findQueryElements(payload = {}) {
    if (payload.ref) {
      const element = refElements.get(String(payload.ref));
      return element?.isConnected ? [element] : [];
    }

    const roots = collectQueryRoots();
    if (payload.selector) {
      const selector = String(payload.selector);
      const matches = [];
      for (const root of roots) {
        try { matches.push(...root.querySelectorAll(selector)); } catch (error) { throw new Error(`Invalid browser selector ${selector}: ${normalizeError(error)}`); }
      }
      return uniqueElements(matches);
    }

    const exact = Boolean(payload.exact);
    const role = normalizeWhitespace(payload.role || "").toLocaleLowerCase();
    const name = normalizeWhitespace(payload.name || "").toLocaleLowerCase();
    const label = normalizeWhitespace(payload.label || "").toLocaleLowerCase();
    const targetText = normalizeWhitespace(payload.targetText || "").toLocaleLowerCase();
    const candidates = uniqueElements(roots.flatMap((root) => Array.from(root.querySelectorAll("*"))));
    return candidates.filter((element) => {
      if (role && normalizeWhitespace(element.getAttribute("role") || implicitRole(element)).toLocaleLowerCase() !== role) return false;
      const accessibleName = queryAccessibleName(element).toLocaleLowerCase();
      if (name && !(exact ? accessibleName === name : accessibleName.includes(name))) return false;
      if (label && !(exact ? accessibleName === label : accessibleName.includes(label))) return false;
      if (targetText) {
        const text = normalizeWhitespace(element.innerText || element.textContent || element.getAttribute("aria-label") || "").toLocaleLowerCase();
        if (!(exact ? text === targetText : text.includes(targetText))) return false;
      }
      return Boolean(role || name || label || targetText);
    });
  }

  function collectQueryRoots() {
    const roots = [];
    const visit = (root) => {
      if (!root || roots.includes(root)) return;
      roots.push(root);
      for (const element of root.querySelectorAll?.("*") || []) {
        if (element.shadowRoot) visit(element.shadowRoot);
      }
    };
    visit(document);
    return roots;
  }

  function uniqueElements(elements) {
    return Array.from(new Set(elements)).filter((element) => element?.nodeType === 1);
  }

  function queryAccessibleName(element) {
    const labelledBy = element.getAttribute("aria-labelledby");
    const labelledText = labelledBy
      ? labelledBy.split(/\s+/).map((id) => element.ownerDocument.getElementById(id)?.textContent || "").join(" ")
      : "";
    const labelText = "labels" in element && element.labels
      ? Array.from(element.labels).map((item) => item.textContent || "").join(" ")
      : "";
    return normalizeWhitespace(
      element.getAttribute("aria-label")
      || labelledText
      || labelText
      || element.getAttribute("alt")
      || element.getAttribute("placeholder")
      || element.innerText
      || element.textContent
      || ""
    );
  }

  function serializeQueryElement(element) {
    const isPassword = element.tagName?.toLowerCase() === "input" && String(element.type || "").toLowerCase() === "password";
    const options = element instanceof HTMLSelectElement
      ? serializeOptions(element).slice(0, 500).map((option) => ({ ...option, textContent: option.text }))
      : [];
    const files = element instanceof HTMLInputElement && element.type.toLowerCase() === "file"
      ? Array.from(element.files || []).slice(0, 100).map((file) => ({ name: file.name, type: file.type, size: file.size }))
      : [];
    const rect = element.getBoundingClientRect();
    return {
      ref: refForElement(element),
      tagName: element.tagName.toLowerCase(),
      role: element.getAttribute("role") || implicitRole(element),
      textContent: truncate(String(element.textContent ?? ""), 20_000),
      innerText: truncate(String(element.innerText ?? element.textContent ?? ""), 20_000),
      value: isPassword ? "[password]" : liveElementValue(element),
      href: element.href || element.getAttribute("href") || "",
      src: element.src || element.getAttribute("src") || "",
      id: element.id || "",
      name: String(element.name || ""),
      type: String(element.type || ""),
      accept: String(element.accept || ""),
      placeholder: String(element.placeholder || ""),
      autocomplete: String(element.autocomplete || element.getAttribute("autocomplete") || ""),
      accessibleName: queryAccessibleName(element),
      checked: Boolean(element.checked),
      selected: Boolean(element.selected),
      disabled: Boolean(element.disabled || element.getAttribute("aria-disabled") === "true"),
      required: Boolean(element.required || element.hasAttribute("required")),
      multiple: Boolean(element.multiple),
      files,
      options,
      valid: typeof element.checkValidity === "function" ? element.checkValidity() : true,
      validity: serializeElementValidity(element),
      rect: {
        x: Math.round(rect.x),
        y: Math.round(rect.y),
        width: Math.round(rect.width),
        height: Math.round(rect.height)
      },
      devicePixelRatio: window.devicePixelRatio,
      attributes: Object.fromEntries(Array.from(element.attributes || [])
        .filter((attribute) => attribute.name !== "value" && attribute.name !== REF_ATTR)
        .slice(0, 40)
        .map((attribute) => [attribute.name, truncate(attribute.value, 1_000)])),
    };
  }

  function serializeElementValidity(element) {
    const validity = element.validity;
    if (!validity) return { valid: true };
    return {
      valid: Boolean(validity.valid),
      valueMissing: Boolean(validity.valueMissing),
      typeMismatch: Boolean(validity.typeMismatch),
      patternMismatch: Boolean(validity.patternMismatch),
      tooLong: Boolean(validity.tooLong),
      tooShort: Boolean(validity.tooShort),
      rangeUnderflow: Boolean(validity.rangeUnderflow),
      rangeOverflow: Boolean(validity.rangeOverflow),
      stepMismatch: Boolean(validity.stepMismatch),
      badInput: Boolean(validity.badInput),
      customError: Boolean(validity.customError)
    };
  }

  function liveElementValue(element) {
    const tag = element.tagName?.toLowerCase();
    const type = String(element.type || "").toLowerCase();
    if (tag === "input" && type === "password") return "[password]";
    if (tag === "input" && type === "file") {
      return Array.from(element.files || []).map((file) => file.name).join(", ");
    }
    if ("value" in element) return String(element.value ?? "");
    if (element.isContentEditable) return String(element.textContent ?? "");
    throw new Error("Matched page element does not expose an input value");
  }

  function getSelectionInfo() {
    if (secretDocumentLocked) throw new Error("INSPECTION_LOCKED: Navigate before inspecting selection after secure credential fill.");
    const selection = window.getSelection();
    const text = selection ? String(selection).trim() : "";

    return {
      text,
      hasSelection: text.length > 0
    };
  }

  async function clickTarget(payload = {}) {
    const element = resolveElement(payload);
    scrollIntoView(element);
    const before = pageState();
    assertUnoccluded(element);
    const clickCount = clampNumber(payload.clickCount, 1, 3, 1);
    const rect = element.getBoundingClientRect();
    const position = payload.position && typeof payload.position === "object"
      ? {
          x: rect.left + clampNumber(payload.position.x, 0, rect.width, rect.width / 2),
          y: rect.top + clampNumber(payload.position.y, 0, rect.height, rect.height / 2),
        }
      : undefined;
    simulatePointer(element, position, clickCount);
    if (position || clickCount > 1) {
      for (let count = 1; count <= clickCount; count += 1) {
        element.dispatchEvent(new MouseEvent("click", pointerEventInit(element, position, count)));
      }
      if (clickCount === 2) element.dispatchEvent(new MouseEvent("dblclick", pointerEventInit(element, position, 2)));
    } else {
      element.click();
    }
    await afterPaint();

    return {
      clicked: describeElement(element),
      trusted: false,
      before,
      after: pageState()
    };
  }

  async function focusTarget(payload = {}) {
    const element = resolveElement(payload);
    scrollIntoView(element);
    element.focus({ preventScroll: true });
    await afterPaint();
    const verified = document.activeElement === element || element.contains(document.activeElement);
    if (!verified) throw new Error("The target did not retain browser focus");
    return { focused: describeElement(element), verified: true };
  }

  async function checkTarget(payload = {}) {
    const element = resolveElement(payload);
    if (!(element instanceof HTMLInputElement) || !["checkbox", "radio"].includes(element.type.toLowerCase())) {
      throw new Error("Target is not a checkbox or radio input");
    }
    const checked = payload.checked !== false;
    if (!checked && element.type.toLowerCase() === "radio") throw new Error("Radio inputs cannot be unchecked directly");
    if (element.checked !== checked) {
      const descriptor = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "checked");
      if (descriptor?.set) descriptor.set.call(element, checked);
      else element.checked = checked;
      element.dispatchEvent(new InputEvent("input", { bubbles: true }));
      element.dispatchEvent(new Event("change", { bubbles: true }));
    }
    await afterPaint();
    if (element.checked !== checked) throw new Error(`Target did not become ${checked ? "checked" : "unchecked"}`);
    return { target: describeElement(element), checked: element.checked, verified: true };
  }

  async function hoverTarget(payload = {}) {
    const element = resolveElement(payload);
    scrollIntoView(element);
    assertUnoccluded(element);
    const rect = element.getBoundingClientRect();
    const eventInit = {
      bubbles: true,
      cancelable: true,
      view: window,
      clientX: rect.left + rect.width / 2,
      clientY: rect.top + rect.height / 2
    };
    element.dispatchEvent(new PointerEvent("pointerover", eventInit));
    element.dispatchEvent(new MouseEvent("mouseover", eventInit));
    element.dispatchEvent(new MouseEvent("mousemove", eventInit));
    await afterPaint();
    return { hovered: describeElement(element), trusted: false };
  }

  async function dragTarget(payload = {}) {
    const source = resolveElement(payload);
    scrollIntoView(source);
    if (source instanceof HTMLInputElement && source.type.toLowerCase() === "range") {
      const min = Number.isFinite(Number(source.min)) ? Number(source.min) : 0;
      const max = Number.isFinite(Number(source.max)) ? Number(source.max) : 100;
      const requested = Number(payload.value ?? payload.toValue ?? max);
      const value = Math.min(max, Math.max(min, Number.isFinite(requested) ? requested : max));
      setNativeValue(source, String(value));
      dispatchInputEvents(source);
      await afterPaint();
      return { dragged: describeElement(source), mode: "range", value: source.value, verified: Number(source.value) === value };
    }

    const targetPayload = payload.target && typeof payload.target === "object"
      ? payload.target
      : {
          ref: payload.targetRef,
          selector: payload.targetSelector,
          targetText: payload.targetText
        };
    const target = resolveElement(targetPayload);
    scrollIntoView(target);
    const sourceRect = source.getBoundingClientRect();
    const targetRect = target.getBoundingClientRect();
    const transfer = new DataTransfer();
    const event = (type, element, rect) => element.dispatchEvent(new DragEvent(type, {
      bubbles: true,
      cancelable: true,
      dataTransfer: transfer,
      clientX: rect.left + rect.width / 2,
      clientY: rect.top + rect.height / 2
    }));
    event("dragstart", source, sourceRect);
    event("dragenter", target, targetRect);
    event("dragover", target, targetRect);
    event("drop", target, targetRect);
    event("dragend", source, targetRect);
    await afterPaint();
    return {
      dragged: describeElement(source),
      target: describeElement(target),
      mode: "html5",
      trusted: false,
      verified: true
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
      const typed = describeElement(element);
      return { typed, verified: normalizeWhitespace(element.textContent || "").endsWith(normalizeWhitespace(text)) };
    }

    if (!("value" in element)) {
      throw new Error("Target is not text-editable");
    }

    const nextValue = append ? `${element.value || ""}${text}` : text;
    setNativeValue(element, nextValue);
    dispatchInputEvents(element);

    const typed = describeElement(element);
    return { typed, verified: filledValueMatches(element, nextValue) };
  }

  function filledValueMatches(element, expected) {
    const actual = String(element.value || "");
    if (actual === expected) return true;
    if (!(element instanceof HTMLInputElement) || element.type.toLowerCase() !== "email" || !element.validity.valid) return false;
    const at = expected.lastIndexOf("@");
    if (at <= 0 || at === expected.length - 1) return false;
    try {
      const normalizedDomain = new URL(`http://${expected.slice(at + 1)}`).hostname;
      return actual === `${expected.slice(0, at)}@${normalizedDomain}`;
    } catch {
      return false;
    }
  }

  function prepareSecretFill(payload = {}) {
    const expectedOrigin = requireString(payload.origin, "origin");
    if (location.origin !== expectedOrigin) throw new Error("Credential destination changed; refusing secure fill.");
    const username = resolveElement({ ref: requireString(payload.usernameRef, "usernameRef") });
    const password = resolveElement({ ref: requireString(payload.passwordRef, "passwordRef") });
    if (!(username instanceof HTMLInputElement) || !(password instanceof HTMLInputElement) || password.type.toLowerCase() !== "password") {
      throw new Error("Secure credential fill requires a username input and a password input.");
    }
    const submit = payload.submitRef ? resolveElement({ ref: requireString(payload.submitRef, "submitRef") }) : undefined;
    if (submit && !isSubmitControl(submit)) {
      throw new Error("SUBMIT_FAILED: submitRef must point to a button or submit input.");
    }
    return {
      origin: location.origin,
      ready: true,
      usernameRef: username.getAttribute(REF_ATTR),
      passwordRef: password.getAttribute(REF_ATTR),
      submitRef: submit?.getAttribute(REF_ATTR)
    };
  }

  async function secureFill(payload = {}) {
    const expectedOrigin = requireString(payload.origin, "origin");
    if (location.origin !== expectedOrigin) throw new Error("Credential destination changed; refusing secure fill.");
    const username = resolveElement({ ref: requireString(payload.usernameRef, "usernameRef") });
    const password = resolveElement({ ref: requireString(payload.passwordRef, "passwordRef") });
    const usernameValue = requireString(payload.username, "username");
    const passwordValue = requireString(payload.password, "password");
    if (!(username instanceof HTMLInputElement) || !(password instanceof HTMLInputElement) || password.type.toLowerCase() !== "password") {
      throw new Error("Secure credential fill requires the previously inspected username and password inputs.");
    }
    const submit = payload.submitRef ? resolveElement({ ref: requireString(payload.submitRef, "submitRef") }) : undefined;
    if (submit && !isSubmitControl(submit)) {
      throw new Error("SUBMIT_FAILED: the retained submit ref is no longer a button or submit input.");
    }

    setNativeValue(username, usernameValue);
    dispatchInputEvents(username);
    setNativeValue(password, passwordValue);
    dispatchInputEvents(password);
    password.focus();

    if (!filledValueMatches(username, usernameValue) || String(password.value || "") !== passwordValue) {
      throw new Error("The verified login fields did not retain the secure credential.");
    }
    secretDocumentLocked = true;
    if (submit) {
      scrollIntoView(submit);
      submit.click();
      await afterPaint();
    }
    return {
      filled: true,
      submitted: Boolean(submit),
      origin: location.origin,
      usernameRef: username.getAttribute(REF_ATTR),
      passwordRef: password.getAttribute(REF_ATTR),
      submitRef: submit?.getAttribute(REF_ATTR)
    };
  }

  function isSubmitControl(element) {
    if (element instanceof HTMLButtonElement) return true;
    return element instanceof HTMLInputElement && ["submit", "button", "image"].includes(element.type.toLowerCase());
  }

  function lockSensitiveDocument() {
    secretDocumentLocked = true;
    return { protected: true, message: "Further page inspection is locked until navigation." };
  }

  function selectTarget(payload = {}) {
    const element = resolveElement(payload);
    const wanted = requireString(payload.value ?? payload.label, "value or label");

    if (!(element instanceof HTMLSelectElement)) {
      throw new Error("Target is not a select menu");
    }

    scrollIntoView(element);
    element.focus();
    const normalized = normalizeWhitespace(wanted).toLocaleLowerCase();
    const option = Array.from(element.options).find((candidate) => candidate.value === wanted)
      || Array.from(element.options).find((candidate) => {
        return normalizeWhitespace(candidate.label).toLocaleLowerCase() === normalized
          || normalizeWhitespace(candidate.text).toLocaleLowerCase() === normalized;
      });
    if (!option) {
      throw new Error(`No dropdown option matched "${wanted}". Available options: ${JSON.stringify(serializeOptions(element))}`);
    }
    element.value = option.value;
    dispatchInputEvents(element);

    if (element.value !== option.value) throw new Error(`Dropdown did not retain the selected value "${option.value}"`);
    return {
      selected: describeElement(element),
      option: { label: option.label, text: option.text, value: option.value },
      verified: true
    };
  }

  function dropdownOptions(payload = {}) {
    const element = resolveElement(payload);
    if (!(element instanceof HTMLSelectElement)) throw new Error("Target is not a select menu");
    return { options: serializeOptions(element) };
  }

  function serializeOptions(element) {
    return Array.from(element.options).map((option, index) => ({
      index,
      label: option.label,
      text: option.text,
      value: option.value,
      selected: option.selected,
      disabled: option.disabled
    }));
  }

  function uploadFile(payload = {}) {
    const element = resolveElement(payload);
    if (!(element instanceof HTMLInputElement) || element.type.toLowerCase() !== "file") {
      throw new Error("Target is not a file input");
    }

    const supplied = Array.isArray(payload.files) ? payload.files : [];
    const files = supplied.length > 0
      ? supplied.map(fileFromPayload)
      : [new File(
          [typeof payload.content === "string" ? payload.content : "Created by Detach for this browser task.\n"],
          safeFilename(payload.fileName || "detach-upload.txt"),
          { type: payload.mimeType || "text/plain", lastModified: Date.now() }
        )];
    const transfer = new DataTransfer();
    for (const file of files) transfer.items.add(file);
    element.files = transfer.files;
    dispatchInputEvents(element);
    if (element.files?.length !== files.length) throw new Error("The page rejected the selected upload files");
    return {
      uploaded: Array.from(element.files || []).map((file) => ({ name: file.name, type: file.type, size: file.size })),
      target: describeElement(element),
      verified: true
    };
  }

  function fileFromPayload(value) {
    const data = value?.dataBase64 ? base64Bytes(String(value.dataBase64)) : String(value?.content || "");
    return new File([data], safeFilename(value?.name || "detach-upload.txt"), {
      type: value?.type || "application/octet-stream",
      lastModified: Date.now()
    });
  }

  async function pressKey(payload = {}) {
    const shortcut = requireString(payload.key ?? payload.shortcut, "key");
    const parsed = parseShortcut(shortcut);
    const target = document.activeElement instanceof HTMLElement ? document.activeElement : document.body;
    const init = {
      key: parsed.key,
      code: parsed.code,
      keyCode: parsed.keyCode,
      which: parsed.keyCode,
      metaKey: parsed.metaKey,
      ctrlKey: parsed.ctrlKey,
      altKey: parsed.altKey,
      shiftKey: parsed.shiftKey,
      bubbles: true,
      cancelable: true
    };
    target.dispatchEvent(new KeyboardEvent("keydown", init));
    applyKeyDefault(target, parsed);
    target.dispatchEvent(new KeyboardEvent("keyup", init));
    await afterPaint();
    return { pressed: shortcut, trusted: false, page: pageState() };
  }

  async function waitForPage(payload = {}) {
    if (Number.isFinite(payload.delayMs)) {
      const delayMs = clampNumber(payload.delayMs, 0, 60_000, 0);
      await new Promise((resolve) => setTimeout(resolve, delayMs));
      return { matched: true, delayMs, ...pageState() };
    }
    const timeoutMs = clampNumber(payload.timeoutMs, 100, 60_000, 10_000);
    const deadline = Date.now() + timeoutMs;
    const wantedText = typeof payload.text === "string" ? payload.text : "";
    const selector = typeof payload.selector === "string" ? payload.selector : "";
    const urlIncludes = typeof payload.urlIncludes === "string" ? payload.urlIncludes : "";
    let previousSignature = "";
    let stableSamples = 0;

    while (Date.now() < deadline) {
      const signature = `${document.readyState}:${document.body?.childElementCount || 0}:${document.body?.innerText?.length || 0}`;
      stableSamples = signature === previousSignature ? stableSamples + 1 : 0;
      previousSignature = signature;
      const matched = document.readyState !== "loading"
        && stableSamples >= 1
        && (!wantedText || (document.body?.innerText || "").includes(wantedText))
        && (!selector || Boolean(document.querySelector(selector)))
        && (!urlIncludes || location.href.includes(urlIncludes));
      if (matched) return { matched: true, ...pageState() };
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
    throw new Error(`WAIT_TIMEOUT: Browser wait timed out after ${timeoutMs}ms`);
  }

  async function mediaCommand(payload = {}) {
    const action = String(payload.action || "inspect");
    const selector = typeof payload.selector === "string" ? payload.selector : "video,audio";
    const media = findQueryElements({ selector })[0];
    if (!(media instanceof HTMLMediaElement)) throw new Error(`No media element matched: ${selector}`);
    if (action === "seek" || action === "frame") {
      const seconds = Number(payload.seconds ?? payload.time ?? 0);
      if (!Number.isFinite(seconds) || seconds < 0) throw new Error("Media seek needs a non-negative time in seconds");
      if (Number.isFinite(media.duration) && seconds > media.duration) {
        throw new Error(`Media time ${seconds} exceeds duration ${media.duration}`);
      }
      await new Promise((resolve, reject) => {
        const timeout = setTimeout(() => reject(new Error("Media seek timed out")), 10_000);
        const done = () => {
          clearTimeout(timeout);
          media.removeEventListener("seeked", done);
          resolve();
        };
        media.addEventListener("seeked", done, { once: true });
        media.currentTime = seconds;
        if (Math.abs(media.currentTime - seconds) < 0.05 && media.readyState >= 2) done();
      });
    }
    const textTracks = Array.from(media.textTracks || []).map((track) => ({
      kind: track.kind,
      label: track.label,
      language: track.language,
      mode: track.mode,
      cues: Array.from(track.cues || []).slice(0, 5_000).map((cue) => ({
        startTime: cue.startTime,
        endTime: cue.endTime,
        text: String(cue.text || "")
      }))
    }));
    const captions = textTracks.flatMap((track) => track.cues).map((cue) => cue.text).filter(Boolean).join("\n");
    return {
      action,
      media: describeElement(media),
      currentTime: media.currentTime,
      duration: Number.isFinite(media.duration) ? media.duration : undefined,
      paused: media.paused,
      readyState: media.readyState,
      textTracks,
      captions: truncate(captions, 200_000)
    };
  }

  async function fetchArtifact(payload = {}) {
    let url = typeof payload.url === "string" ? payload.url : "";
    if (!url && (payload.ref || payload.selector || payload.targetText)) {
      const element = resolveElement(payload);
      url = element.href || element.src || element.getAttribute("href") || element.getAttribute("src") || "";
    }
    if (!url) url = location.href;
    const absoluteUrl = new URL(url, location.href).href;
    const response = await fetch(absoluteUrl, { credentials: "include" });
    if (!response.ok) throw new Error(`Document fetch failed with HTTP ${response.status}`);
    const bytes = new Uint8Array(await response.arrayBuffer());
    if (bytes.byteLength > 25 * 1024 * 1024) throw new Error("Document is larger than 25 MB");
    return {
      url: response.url || absoluteUrl,
      mimeType: response.headers.get("content-type") || "application/octet-stream",
      fileName: artifactFileName(response, absoluteUrl),
      dataBase64: base64FromBytes(bytes)
    };
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
    for (const [ref, element] of refElements) {
      if (!element.isConnected) refElements.delete(ref);
    }
    for (const root of collectQueryRoots()) {
      for (const element of root.querySelectorAll(interactiveSelector())) {
        if (!isVisible(element)) continue;
        refForElement(element);
      }
    }
  }

  function refForElement(element) {
    let ref = elementRefs.get(element);
    if (!ref) {
      ref = `lz-${pageSession}-${nextElementRef++}`;
      elementRefs.set(element, ref);
      refElements.set(ref, element);
      element.setAttribute(REF_ATTR, ref);
    }
    return ref;
  }

  function collectInteractiveElements(maxElements) {
    const elements = [];

    for (const root of collectQueryRoots()) {
      for (const element of root.querySelectorAll(interactiveSelector())) {
        if (!isVisible(element)) continue;
        elements.push(describeElement(element));
        if (elements.length >= maxElements) return elements;
      }
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

  function collectTables() {
    return Array.from(document.querySelectorAll("table"))
      .filter(isVisible)
      .slice(0, 12)
      .map((table) => ({
        caption: normalizeWhitespace(table.caption?.innerText || ""),
        rows: Array.from(table.rows || []).slice(0, 40).map((row) => {
          return Array.from(row.cells || []).slice(0, 20).map((cell) => normalizeWhitespace(cell.innerText || cell.textContent || ""));
        })
      }));
  }

  function resolveElement(payload = {}) {
    if (payload.ref) {
      const ref = String(payload.ref);
      const element = refElements.get(ref);
      if (element?.isConnected) return element;
      refElements.delete(ref);
      throw new Error(`STALE_REF: Browser ref is no longer attached: ${ref}. Take a new snapshot.`);
    }

    if (payload.selector) {
      const element = findQueryElements({ selector: String(payload.selector) })[0];
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

    for (const root of collectQueryRoots()) {
      for (const element of root.querySelectorAll(interactiveSelector())) {
        if (!isVisible(element)) continue;
        const haystack = normalizeWhitespace(element.innerText || element.textContent || element.getAttribute("aria-label") || "").toLowerCase();
        if (haystack.includes(needle)) return element;
      }
    }

    return undefined;
  }

  function describeElement(element) {
    const rect = element.getBoundingClientRect();
    const tag = element.tagName.toLowerCase();
    const type = element.getAttribute("type") || "";
    const isPassword = tag === "input" && type.toLowerCase() === "password";

    return {
      ref: refForElement(element),
      tag,
      type,
      role: element.getAttribute("role") || implicitRole(element),
      text: truncate(normalizeWhitespace(element.innerText || element.textContent || ""), 240),
      ariaLabel: element.getAttribute("aria-label") || "",
      accessibleName: queryAccessibleName(element),
      name: element.getAttribute("name") || "",
      placeholder: element.getAttribute("placeholder") || "",
      autocomplete: element.getAttribute("autocomplete") || "",
      value: isPassword ? "[password]" : truncate(String(element.value || ""), 240),
      href: element.href || element.getAttribute("href") || "",
      disabled: Boolean(element.disabled || element.getAttribute("aria-disabled") === "true"),
      inViewport: rect.bottom > 0 && rect.right > 0 && rect.top < window.innerHeight && rect.left < window.innerWidth,
      rect: {
        x: Math.round(rect.x),
        y: Math.round(rect.y),
        width: Math.round(rect.width),
        height: Math.round(rect.height)
      },
      devicePixelRatio: window.devicePixelRatio
    };
  }

  function implicitRole(element) {
    const tag = element.tagName.toLowerCase();
    if (tag === "a") return "link";
    if (tag === "button") return "button";
    if (tag === "select") return "combobox";
    if (tag === "textarea") return "textbox";
    if (tag === "canvas") return "canvas";
    if (tag === "svg") return "img";
    if (tag === "video" || tag === "audio") return "media";
    if (tag === "iframe" || tag === "frame") return "iframe";
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
      "canvas",
      "svg",
      "video",
      "audio",
      "iframe",
      "frame",
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

  function simulatePointer(element, position, clickCount = 1) {
    const eventInit = pointerEventInit(element, position, clickCount);
    for (const type of ["pointerdown", "mousedown", "pointerup", "mouseup"]) {
      element.dispatchEvent(new MouseEvent(type, eventInit));
    }
  }

  function pointerEventInit(element, position, clickCount = 1) {
    const rect = element.getBoundingClientRect();
    return {
      bubbles: true,
      cancelable: true,
      view: window,
      clientX: position?.x ?? rect.left + rect.width / 2,
      clientY: position?.y ?? rect.top + rect.height / 2,
      detail: clickCount,
    };
  }

  function assertUnoccluded(element) {
    const rect = element.getBoundingClientRect();
    const x = Math.min(window.innerWidth - 1, Math.max(0, rect.left + rect.width / 2));
    const y = Math.min(window.innerHeight - 1, Math.max(0, rect.top + rect.height / 2));
    const top = document.elementFromPoint(x, y);
    if (top && top !== element && !element.contains(top) && !composedContains(top, element)) {
      throw new Error(`Target is covered by ${describeElement(top).tag || "another element"}; take a new snapshot or scroll before clicking.`);
    }
  }

  function composedContains(container, element) {
    let current = element;
    while (current) {
      if (current === container || container.contains?.(current)) return true;
      const root = current.getRootNode?.();
      current = root instanceof ShadowRoot ? root.host : current.parentElement;
    }
    return false;
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

  function pageState() {
    return { url: location.href, title: document.title, readyState: document.readyState };
  }

  function afterPaint() {
    return new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
  }

  function parseShortcut(shortcut) {
    const parts = shortcut.toUpperCase().replace(/CMD|COMMAND/g, "META").replace(/OPTION/g, "ALT").split("+").map((part) => part.trim()).filter(Boolean);
    const raw = parts.find((part) => !["META", "CTRL", "CONTROL", "ALT", "SHIFT"].includes(part)) || "ENTER";
    const keys = {
      ENTER: ["Enter", "Enter", 13], TAB: ["Tab", "Tab", 9], ESC: ["Escape", "Escape", 27], ESCAPE: ["Escape", "Escape", 27],
      BACKSPACE: ["Backspace", "Backspace", 8], DELETE: ["Delete", "Delete", 46], SPACE: [" ", "Space", 32],
      ARROWUP: ["ArrowUp", "ArrowUp", 38], ARROWDOWN: ["ArrowDown", "ArrowDown", 40], ARROWLEFT: ["ArrowLeft", "ArrowLeft", 37], ARROWRIGHT: ["ArrowRight", "ArrowRight", 39]
    };
    const mapped = keys[raw] || [raw.length === 1 ? raw.toLowerCase() : raw, raw.length === 1 ? `Key${raw}` : raw, raw.length === 1 ? raw.charCodeAt(0) : 0];
    return {
      key: mapped[0], code: mapped[1], keyCode: mapped[2],
      metaKey: parts.includes("META"), ctrlKey: parts.includes("CTRL") || parts.includes("CONTROL"),
      altKey: parts.includes("ALT"), shiftKey: parts.includes("SHIFT")
    };
  }

  function applyKeyDefault(target, key) {
    if (key.metaKey && key.key.toLowerCase() === "a" && ("selectionStart" in target)) {
      target.setSelectionRange?.(0, String(target.value || "").length);
      return;
    }
    if (key.key === "Backspace" && "value" in target) {
      const start = Number(target.selectionStart ?? String(target.value || "").length);
      const end = Number(target.selectionEnd ?? start);
      const value = String(target.value || "");
      const nextStart = start === end ? Math.max(0, start - 1) : start;
      setNativeValue(target, `${value.slice(0, nextStart)}${value.slice(end)}`);
      target.setSelectionRange?.(nextStart, nextStart);
      dispatchInputEvents(target);
      return;
    }
    if (key.key === "Tab") {
      const focusable = Array.from(document.querySelectorAll(interactiveSelector())).filter(isVisible);
      const index = focusable.indexOf(target);
      const offset = key.shiftKey ? -1 : 1;
      focusable[(index + offset + focusable.length) % focusable.length]?.focus();
      return;
    }
    if (key.key === "Enter") {
      if (target instanceof HTMLButtonElement || target instanceof HTMLAnchorElement) target.click();
      else target.form?.requestSubmit?.();
    }
  }

  function base64Bytes(value) {
    const binary = atob(value);
    const bytes = new Uint8Array(binary.length);
    for (let index = 0; index < binary.length; index += 1) bytes[index] = binary.charCodeAt(index);
    return bytes;
  }

  function base64FromBytes(bytes) {
    let binary = "";
    const chunkSize = 0x8000;
    for (let offset = 0; offset < bytes.length; offset += chunkSize) {
      binary += String.fromCharCode(...bytes.subarray(offset, Math.min(bytes.length, offset + chunkSize)));
    }
    return btoa(binary);
  }

  function artifactFileName(response, fallbackUrl) {
    const disposition = response.headers.get("content-disposition") || "";
    const encoded = disposition.match(/filename\*=UTF-8''([^;]+)/i)?.[1];
    const plain = disposition.match(/filename="?([^";]+)"?/i)?.[1];
    if (encoded) {
      try { return safeFilename(decodeURIComponent(encoded)); } catch {}
    }
    if (plain) return safeFilename(plain);
    try {
      return safeFilename(decodeURIComponent(new URL(response.url || fallbackUrl).pathname.split("/").pop() || "document"));
    } catch {
      return "document";
    }
  }

  function safeFilename(value) {
    const cleaned = Array.from(String(value || "").normalize("NFC")
      .replace(/[\\/:\u0000-\u001F\u007F]/g, "_")
      .replace(/^\.+/, "")
      .trim()).slice(0, 180).join("");
    return cleaned && cleaned !== "." && cleaned !== ".." ? cleaned : "detach-upload.txt";
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
