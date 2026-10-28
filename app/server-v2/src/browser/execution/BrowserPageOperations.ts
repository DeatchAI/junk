import { compactBrowserSnapshot, type CompactSnapshotOptions } from "../BrowserSnapshot";
import { Environment, PageHandle, MediaHandle, FrameLocatorHandle, KeyboardHandle, LocatorHandle,
  DocumentHandle, WindowHandle, LocationHandle, DOMElementHandle, ConsoleHandle, BuiltinHandle,
  BLOCKED_PROPERTIES, PAGE_METHODS, MAX_CODE_LENGTH, MAX_LOOP_ITERATIONS, sanitizeResult,
  propertyName, isSafeFunction, isReturnSignal, isPlainRecord, asRecord, normalize, requireString,
  requireStringOrNumber, stringValue, urlMatches, numberOr, clampNumber, waitTimeout, cssEscape,
  cssAttributeEscape, type SafeFunction, type LocatorSpec, type BrowserPrimitiveRunner,
  type BrowserPrimitiveObserver, type BrowserCodeExecution, type BrowserCodeOperation } from "./BrowserCodeValues";

export abstract class BrowserPageOperations {
  protected readonly operations: BrowserCodeOperation[] = [];
  protected readonly images: Array<{ data: string; mimeType: string }> = [];
  protected deadline = 0;
  protected executionStartedAt = 0;

  constructor(
    private readonly runPrimitive: BrowserPrimitiveRunner,
    private readonly observePrimitive?: BrowserPrimitiveObserver,
  ) {}

  protected abstract invoke(callback: SafeFunction, args: unknown[], bindings?: Record<string, unknown>): Promise<unknown>;

  protected async callPage(page: PageHandle, method: string, args: unknown[]) {
    const options = asRecord(args[1] ?? args[0]);
    switch (method) {
      case "status": return await this.primitive("browser.status", {});
      case "goto": return await this.primitive("browser.navigate", { ...asRecord(args[1]), url: requireString(args[0], "url") });
      case "open": return await this.primitive("browser.open_tab", { ...asRecord(args[1]), url: requireString(args[0], "url") });
      case "snapshot": {
        const snapshotOptions = asRecord(args[0]);
        const raw = await this.primitive("browser.snapshot", {
          maxElements: snapshotOptions.maxLines ?? 180,
          maxTextLength: snapshotOptions.maxTextLength ?? 12_000,
        });
        return compactBrowserSnapshot(raw, snapshotOptions as CompactSnapshotOptions);
      }
      case "text": return await this.primitive("browser.extract_text", {
        maxLength: isPlainRecord(args[0]) ? numberOr(args[0].maxLength, 20_000) : numberOr(args[0], 20_000),
      });
      case "tabs": return await this.primitive("browser.list_tabs", {});
      case "activeTab": return await this.primitive("browser.get_active_tab", {});
      case "activateTab": return await this.primitive("browser.activate_tab", { tabId: requireStringOrNumber(args[0], "tabId") });
      case "closeTab": return await this.primitive("browser.close_tab", args[0] === undefined ? {} : { tabId: requireStringOrNumber(args[0], "tabId") });
      case "back": return await this.primitive("browser.back", asRecord(args[0]));
      case "forward": return await this.primitive("browser.forward", asRecord(args[0]));
      case "reload": return await this.primitive("browser.refresh", asRecord(args[0]));
      case "waitFor": return await this.waitFor(args);
      case "waitForURL": return await this.waitForURL(args);
      case "waitForEvent": return await this.waitForEvent(args);
      case "events": return await this.primitive("browser.events", { drain: asRecord(args[0]).drain !== false }, false);
      case "screenshot": return await this.captureScreenshot(asRecord(args[0]));
      case "acceptDialog": return await this.primitive("browser.dialog", { action: "accept", promptText: stringValue(args[0]) });
      case "dismissDialog": return await this.primitive("browser.dialog", { action: "dismiss" });
      case "frames": return await this.primitive("browser.frames", {});
      case "frameLocator": return new FrameLocatorHandle(page, requireString(args[0], "frame selector"));
      case "table": {
        const snapshot = asRecord(await this.primitive("browser.snapshot", {
          maxElements: 40,
          maxTextLength: 1_000,
        }));
        const tables = Array.isArray(snapshot.tables) ? snapshot.tables : [];
        if (typeof args[0] === "number") return tables[args[0]];
        return tables;
      }
      case "artifact": return await this.captureArtifact(args[0]);
      case "artifacts": return await this.primitive("browser.artifacts", isPlainRecord(args[0]) ? args[0] : (
        typeof args[0] === "string" ? { artifactId: args[0] } : {}
      ));
      case "url": return stringValue(asRecord(await this.primitive("browser.get_active_tab", {})).url) ?? "";
      case "title": return stringValue(asRecord(await this.primitive("browser.get_active_tab", {})).title) ?? "";
      case "evaluate": {
        const callback = args[0];
        if (!isSafeFunction(callback)) throw new Error("page.evaluate requires an arrow function or function expression");
        return await this.invoke(callback, args.slice(1), {
          document: new DocumentHandle(page),
          window: new WindowHandle(page),
          location: new LocationHandle(page),
        });
      }
      case "getByRole": return new LocatorHandle(page, {
        kind: "role",
        value: requireString(args[0], "role"),
        name: stringValue(options.name),
        exact: Boolean(options.exact),
      });
      case "getByText": return new LocatorHandle(page, { kind: "text", value: requireString(args[0], "text"), exact: Boolean(asRecord(args[1]).exact) });
      case "getByLabel": return new LocatorHandle(page, { kind: "label", value: requireString(args[0], "label"), exact: Boolean(asRecord(args[1]).exact) });
      case "getByPlaceholder": return new LocatorHandle(page, { kind: "placeholder", value: requireString(args[0], "placeholder"), exact: Boolean(asRecord(args[1]).exact) });
      case "locator": return new LocatorHandle(page, { kind: "selector", value: requireString(args[0], "selector") });
      case "ref": return new LocatorHandle(page, { kind: "ref", value: requireString(args[0], "ref") });
      default: throw new Error(`Unsupported page method: ${method}`);
    }
  }

  protected async callFrameLocator(frame: FrameLocatorHandle, method: string, args: unknown[]) {
    const options = asRecord(args[1]);
    const base = { frameSelector: frame.selector, frameId: frame.frameId, documentId: frame.documentId };
    if (method === "getByRole") return new LocatorHandle(frame.page, {
      ...base,
      kind: "role",
      value: requireString(args[0], "role"),
      name: stringValue(options.name),
      exact: Boolean(options.exact),
    });
    if (method === "getByText") return new LocatorHandle(frame.page, {
      ...base,
      kind: "text",
      value: requireString(args[0], "text"),
      exact: Boolean(options.exact),
    });
    if (method === "getByLabel") return new LocatorHandle(frame.page, {
      ...base,
      kind: "label",
      value: requireString(args[0], "label"),
      exact: Boolean(options.exact),
    });
    if (method === "getByPlaceholder") return new LocatorHandle(frame.page, {
      ...base,
      kind: "placeholder",
      value: requireString(args[0], "placeholder"),
      exact: Boolean(options.exact),
    });
    if (method === "locator") return new LocatorHandle(frame.page, {
      ...base,
      kind: "selector",
      value: requireString(args[0], "selector"),
    });
    if (method === "ref") return new LocatorHandle(frame.page, {
      ...base,
      kind: "ref",
      value: requireString(args[0], "ref"),
    });
    throw new Error(`Unsupported frameLocator method: ${method}`);
  }

  protected async callMedia(media: MediaHandle, method: string, args: unknown[]) {
    const options = asRecord(args[1] ?? args[0]);
    const selector = stringValue(options.selector) || "video,audio";
    if (method === "inspect" || method === "captions") {
      const result = asRecord(await this.primitive("browser.media", { action: "inspect", selector }));
      return method === "captions" ? result.captions || "" : result;
    }
    if (method === "seek") {
      return await this.primitive("browser.media", {
        action: "seek",
        selector,
        seconds: numberOr(args[0], 0),
      });
    }
    if (method === "frame") {
      const seconds = numberOr(args[0], 0);
      await this.primitive("browser.media", { action: "frame", selector, seconds });
      return await this.captureScreenshot({ selector });
    }
    throw new Error(`Unsupported page.media method: ${method}`);
  }

  protected async captureArtifact(input: unknown) {
    let payload: Record<string, unknown>;
    if (input instanceof LocatorHandle) payload = await this.liveLocatorPayload(input);
    else if (typeof input === "string") payload = { url: input };
    else payload = asRecord(input);
    const result = asRecord(await this.primitive("browser.artifact", payload));
    const image = asRecord(result.image);
    if (typeof image.data === "string" && typeof image.mimeType === "string") {
      this.images.push({ data: image.data, mimeType: image.mimeType });
    }
    return result;
  }

  protected async callLocator(locator: LocatorHandle, method: string, args: unknown[]) {
    if (method === "first") return new LocatorHandle(locator.page, { ...locator.spec, index: 0 });
    if (method === "last") return new LocatorHandle(locator.page, { ...locator.spec, index: -1 });
    if (method === "nth") {
      const index = Number(args[0]);
      if (!Number.isInteger(index)) throw new Error("locator.nth requires an integer index");
      return new LocatorHandle(locator.page, { ...locator.spec, index });
    }
    if (method === "textContent") return await this.readLocator(locator, "textContent");
    if (method === "innerText") return await this.readLocator(locator, "innerText");
    if (method === "inputValue") return await this.readLocator(locator, "inputValue");
    if (method === "describe") return await this.readLocatorElement(locator);
    if (method === "boundingBox") {
      const element = await this.readLocatorElement(locator);
      return element.data.rect ?? null;
    }
    if (method === "screenshot") {
      return await this.captureScreenshot({ ...await this.liveLocatorPayload(locator), ...asRecord(args[0]) });
    }
    if (method === "checkValidity") {
      const result = asRecord(await this.primitive("browser.query", { ...await this.liveLocatorPayload(locator), kind: "checkValidity" }));
      if (typeof result.valid !== "boolean") throw new Error("Browser validity query returned no result");
      return result.valid;
    }
    if (method === "count") return await this.countLocator(locator);
    if (method === "allTextContents") {
      return (await this.allLocatorElements(locator)).map((element) => stringValue(element.data.textContent) ?? "");
    }
    const resolved = await this.resolveLocator(locator);
    const target = resolved.target;
    switch (method) {
      case "click": return await this.primitive("browser.click", { ...target, ...asRecord(args[0]) });
      case "dblclick": return await this.primitive("browser.click", { ...target, ...asRecord(args[0]), clickCount: 2 });
      case "tap": return await this.primitive("browser.click", { ...target, ...asRecord(args[0]) });
      case "hover": return await this.primitive("browser.hover", target);
      case "focus": return await this.primitive("browser.focus", target);
      case "check": return await this.primitive("browser.check", { ...target, checked: true });
      case "uncheck": return await this.primitive("browser.check", { ...target, checked: false });
      case "clear": return await this.verifiedType(target, "", false);
      case "fill": return await this.verifiedType(target, stringValue(args[0]) ?? "", false);
      case "type": return await this.verifiedType(target, stringValue(args[0]) ?? "", true);
      case "press": {
        await this.primitive("browser.click", target);
        return await this.primitive("browser.key", { ...target, key: requireString(args[0], "key") });
      }
      case "dragTo": {
        const destination = args[0];
        if (destination instanceof LocatorHandle) {
          const resolvedDestination = await this.resolveLocator(destination);
          if (
            Number.isInteger(target.frameId)
            && Number.isInteger(resolvedDestination.target.frameId)
            && target.frameId !== resolvedDestination.target.frameId
          ) {
            throw new Error("Dragging across browser frames is not supported");
          }
          return await this.primitive("browser.drag", { ...target, target: resolvedDestination.target });
        }
        const options = asRecord(destination);
        return await this.primitive("browser.drag", { ...target, ...options });
      }
      case "setRange": return await this.primitive("browser.drag", { ...target, value: Number(args[0]) });
      case "selectOption": {
        const choice = isPlainRecord(args[0]) ? args[0] : { value: requireString(args[0], "option") };
        return await this.primitive("browser.select", { ...target, ...choice });
      }
      case "options": return await this.primitive("browser.dropdown_options", target);
      case "setInputFiles": {
        const input = args[0];
        if (typeof input === "string") return await this.primitive("browser.upload_file", { ...target, path: input });
        if (Array.isArray(input)) return await this.primitive("browser.upload_file", { ...target, paths: input });
        return await this.primitive("browser.upload_file", { ...target, ...asRecord(input) });
      }
      case "scrollIntoView": return await this.primitive("browser.scroll", target);
      default: throw new Error(`Unsupported locator method: ${method}`);
    }
  }

  protected async callDocument(document: DocumentHandle, method: string, args: unknown[]) {
    if (method === "querySelector") {
      return new LocatorHandle(document.page, { kind: "selector", value: requireString(args[0], "selector") });
    }
    if (method === "querySelectorAll") {
      return new LocatorHandle(document.page, { kind: "selector", value: requireString(args[0], "selector"), many: true });
    }
    if (method === "getElementById") {
      return new LocatorHandle(document.page, { kind: "selector", value: `#${cssEscape(requireString(args[0], "id"))}` });
    }
    throw new Error(`Unsupported safe document method: ${method}`);
  }

  protected async verifiedType(target: Record<string, unknown>, inputText: string, append: boolean) {
    const result = asRecord(await this.primitive("browser.type", { ...target, inputText, append }));
    if (result.verified === false) {
      throw new Error(`Browser ${append ? "type" : "fill"} did not retain the requested value`);
    }
    return result;
  }

  protected callDOMElement(element: DOMElementHandle, method: string, args: unknown[]) {
    if (method === "getAttribute") return stringValue(asRecord(element.data.attributes)[String(args[0] ?? "")]) ?? null;
    if (method === "hasAttribute") return Object.hasOwn(asRecord(element.data.attributes), String(args[0] ?? ""));
    if (method === "checkValidity") {
      return typeof element.data.valid === "boolean" ? element.data.valid : Boolean(asRecord(element.data.validity).valid);
    }
    throw new Error(`Unsupported safe DOM element method: ${method}`);
  }

  protected async waitFor(args: unknown[]) {
    const condition = args[0];
    const options = asRecord(args[1]);
    if (typeof condition === "number") {
      return await this.primitive("browser.wait", { delayMs: clampNumber(condition, 0, 60_000, 0) });
    }
    if (typeof condition === "string") {
      return await this.primitive("browser.wait", {
        selector: condition,
        timeoutMs: waitTimeout(options),
      });
    }
    const payload = { ...asRecord(condition) };
    const configuredTimeout = waitTimeout(payload);
    delete payload.timeout;
    return await this.primitive("browser.wait", { ...payload, timeoutMs: configuredTimeout });
  }

  protected async waitForURL(args: unknown[]) {
    const expected = requireString(args[0], "URL or URL pattern");
    const timeoutMs = waitTimeout(asRecord(args[1]));
    const deadline = Date.now() + timeoutMs;
    let lastUrl = "";
    while (Date.now() < deadline) {
      const tab = asRecord(await this.primitive("browser.get_active_tab", {}, false));
      lastUrl = stringValue(tab.url) ?? "";
      if (urlMatches(lastUrl, expected)) {
        return { matched: true, url: lastUrl, title: stringValue(tab.title) ?? "", status: stringValue(tab.status) ?? "unknown" };
      }
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
    throw new Error(`NAVIGATION_TIMEOUT: URL did not match ${JSON.stringify(expected)} within ${timeoutMs}ms. Last URL: ${lastUrl || "unknown"}`);
  }

  protected async waitForEvent(args: unknown[]) {
    const expected = requireString(args[0], "event type");
    const timeoutMs = waitTimeout(asRecord(args[1]));
    const deadline = Date.now() + timeoutMs;
    let observed: unknown[] = [];
    while (Date.now() < deadline) {
      const result = asRecord(await this.primitive("browser.events", { drain: false }, false));
      observed = Array.isArray(result.events) ? result.events : [];
      const match = [...observed].reverse().find((event) => {
        const record = asRecord(event);
        const timestamp = Number(record.timestamp);
        return String(record.type || "") === expected
          && (!Number.isFinite(timestamp) || timestamp >= this.executionStartedAt);
      });
      if (match) return match;
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
    throw new Error(`EVENT_TIMEOUT: Browser event ${JSON.stringify(expected)} did not occur within ${timeoutMs}ms. Recent events: ${JSON.stringify(observed.slice(-10))}`);
  }

  protected locatorPayload(locator: LocatorHandle) {
    if (locator.resolvedTarget) return locator.resolvedTarget;
    const spec = locator.spec;
    const frame = spec.frameId === undefined ? {} : { frameId: spec.frameId, documentId: spec.documentId };
    if (spec.kind === "selector") return { ...frame, selector: spec.value };
    if (spec.kind === "ref") return { ...frame, ref: spec.value };
    if (spec.kind === "text") return { ...frame, targetText: spec.value, exact: Boolean(spec.exact) };
    if (spec.kind === "role") return { ...frame, role: spec.value, name: spec.name, exact: Boolean(spec.exact) };
    if (spec.kind === "placeholder") return { ...frame, selector: `[placeholder="${cssAttributeEscape(spec.value)}"]` };
    return { ...frame, label: spec.value, exact: Boolean(spec.exact) };
  }

  protected async liveLocatorPayload(locator: LocatorHandle) {
    await this.resolveLocatorFrame(locator);
    if (locator.resolvedTarget || locator.spec.kind === "selector" || locator.spec.kind === "ref" || locator.spec.kind === "text") {
      return this.locatorPayload(locator);
    }
    return (await this.resolveLocator(locator)).target;
  }

  protected async readLocator(locator: LocatorHandle, kind: "textContent" | "innerText" | "inputValue") {
    const result = asRecord(await this.primitive("browser.query", { ...await this.liveLocatorPayload(locator), kind }));
    if (!("value" in result)) throw new Error(`Browser ${kind} query returned no value`);
    return result.value;
  }

  protected async countLocator(locator: LocatorHandle) {
    const result = asRecord(await this.primitive("browser.query", { ...await this.liveLocatorPayload(locator), kind: "count" }));
    if (typeof result.count !== "number") throw new Error("Browser count query returned no count");
    return result.count;
  }

  protected async readLocatorElement(locator: LocatorHandle) {
    const result = asRecord(await this.primitive("browser.query", { ...await this.liveLocatorPayload(locator), kind: "element" }));
    if (!isPlainRecord(result.element)) throw new Error("Browser element query returned no element");
    return new DOMElementHandle(result.element);
  }

  protected async allLocatorElements(locator: LocatorHandle) {
    const result = asRecord(await this.primitive("browser.query", { ...await this.liveLocatorPayload(locator), kind: "all" }));
    return Array.isArray(result.elements) ? result.elements.map((element) => new DOMElementHandle(asRecord(element))) : [];
  }

  protected async resolveLocator(locator: LocatorHandle) {
    await this.resolveLocatorFrame(locator);
    if (locator.resolvedTarget) return { target: locator.resolvedTarget, element: undefined };
    const spec = locator.spec;
    if (spec.kind === "selector") {
      locator.resolvedTarget = this.locatorPayload(locator);
      return { target: locator.resolvedTarget, element: undefined };
    }
    if (spec.kind === "ref") {
      locator.resolvedTarget = this.locatorPayload(locator);
      return { target: locator.resolvedTarget, element: undefined };
    }
    if (spec.kind === "text") {
      locator.resolvedTarget = this.locatorPayload(locator);
      return { target: locator.resolvedTarget, element: { name: spec.value } };
    }

    const snapshot = asRecord(await this.primitive("browser.snapshot", { maxElements: 240, maxTextLength: 2_000 }));
    const elements = Array.isArray(snapshot.elements) ? snapshot.elements.map(asRecord) : [];
    const wantedRole = spec.kind === "role" ? normalize(spec.value) : undefined;
    const wantedName = spec.kind === "role" ? normalize(spec.name) : normalize(spec.value);
    const matches = elements.filter((element) => {
      if (spec.frameId !== undefined && Number(element.frameId) !== spec.frameId) return false;
      const roleMatches = !wantedRole || normalize(element.role || element.tag) === wantedRole;
      const candidateNames = spec.kind === "placeholder"
        ? [element.placeholder]
        : [element.accessibleName, element.ariaLabel, element.name, element.htmlName, element.id, element.text, element.placeholder];
      const normalizedNames = candidateNames
        .map(normalize).filter(Boolean);
      const nameMatches = !wantedName || normalizedNames.some((candidate) => spec.exact ? candidate === wantedName : candidate.includes(wantedName));
      return roleMatches && nameMatches;
    });
    if (matches.length === 0) {
      const nearby = elements.filter((element) => !wantedRole || normalize(element.role || element.tag) === wantedRole)
        .slice(0, 12).map((element) => ({ ref: element.ref, role: element.role, name: element.name || element.text }));
      throw new Error(`LOCATOR_NOT_FOUND: No element matched ${spec.kind} ${JSON.stringify(spec.name ?? spec.value)}. Candidates: ${JSON.stringify(nearby)}`);
    }
    if (spec.index === undefined && matches.length > 1) {
      const candidates = matches.slice(0, 12).map((element) => ({
        ref: element.ref,
        role: element.role,
        name: element.accessibleName || element.ariaLabel || element.name || element.placeholder || element.text,
        type: element.type,
        autocomplete: element.autocomplete,
      }));
      throw new Error(`LOCATOR_AMBIGUOUS: Locator matched ${matches.length} elements. Use a name, label, exact selector, first(), last(), or nth(). Candidates: ${JSON.stringify(candidates)}`);
    }
    const selectedIndex = spec.index === undefined ? 0 : spec.index < 0 ? matches.length + spec.index : spec.index;
    const element = matches[selectedIndex];
    if (!element) throw new Error(`Locator index ${spec.index} is outside ${matches.length} matched elements`);
    if (typeof element.ref !== "string" || !element.ref) throw new Error("Matched semantic node is not actionable");
    locator.resolvedTarget = {
      ref: element.ref,
      ...(Number.isInteger(element.frameId) ? { frameId: element.frameId } : {}),
      ...(typeof element.documentId === "string" ? { documentId: element.documentId } : {}),
    };
    return { target: locator.resolvedTarget, element };
  }

  protected async resolveLocatorFrame(locator: LocatorHandle) {
    if (!locator.spec.frameSelector || locator.spec.frameId !== undefined) return;
    const frame = asRecord(await this.primitive("browser.resolve_frame", { selector: locator.spec.frameSelector }));
    if (!Number.isInteger(frame.frameId)) throw new Error(`Frame selector did not resolve: ${locator.spec.frameSelector}`);
    locator.spec.frameId = frame.frameId;
    locator.spec.documentId = stringValue(frame.documentId);
  }

  protected async captureScreenshot(options: Record<string, unknown>) {
    const result = asRecord(await this.primitive("browser.screenshot", options));
    const data = typeof result.data === "string"
      ? result.data
      : typeof result.dataUrl === "string" ? result.dataUrl.match(/^data:image\/[^;]+;base64,(.+)$/s)?.[1] : undefined;
    if (!data) throw new Error("Browser screenshot did not return image data");
    const format = result.format === "jpeg" ? "jpeg" : "png";
    this.images.push({ data, mimeType: `image/${format}` });
    return { screenshot: true, format, tab: result.tab };
  }

  async primitive(command: string, payload: Record<string, unknown>, record = true) {
    this.assertWithinDeadline();
    const startedAt = Date.now();
    const activityId = `browser_activity_${crypto.randomUUID()}`;
    const operation: BrowserCodeOperation = { operation: command.replace(/^browser\./, ""), durationMs: 0, ok: false };
    if (record) {
      this.observePrimitive?.({ id: activityId, command, payload, phase: "started" });
    }
    try {
      const result = await this.runPrimitive(command, payload);
      operation.ok = true;
      if (record) {
        this.observePrimitive?.({ id: activityId, command, payload, phase: "completed" });
      }
      return result;
    } catch (error) {
      operation.error = error instanceof Error ? error.message : String(error);
      if (record) {
        this.observePrimitive?.({
          id: activityId,
          command,
          payload,
          phase: "failed",
          error: operation.error,
        });
      }
      throw error;
    } finally {
      operation.durationMs = Date.now() - startedAt;
      if (record) this.operations.push(operation);
    }
  }

  protected assertWithinDeadline() {
    if (Date.now() > this.deadline) throw new Error("Browser code execution timed out");
  }
}
