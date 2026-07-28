import * as ts from "typescript";

import { compactBrowserSnapshot, type CompactSnapshotOptions } from "./BrowserSnapshot";

export type BrowserPrimitiveRunner = (command: string, payload: Record<string, unknown>) => Promise<unknown>;

export interface BrowserCodeExecution {
  result: unknown;
  operations: BrowserCodeOperation[];
  events: unknown[];
  images: Array<{ data: string; mimeType: string }>;
}

export interface BrowserCodeOperation {
  operation: string;
  durationMs: number;
  ok: boolean;
  error?: string;
}

interface LocatorSpec {
  kind: "selector" | "text" | "role" | "label" | "placeholder" | "ref";
  value: string;
  name?: string;
  exact?: boolean;
  many?: boolean;
  index?: number;
  frameSelector?: string;
  frameId?: number;
  documentId?: string;
}

interface SafeFunction {
  kind: "safe_function";
  node: ts.ArrowFunction | ts.FunctionExpression;
  environment: Environment;
}

interface ReturnSignal {
  kind: "return";
  value: unknown;
}

class Environment {
  private readonly values = new Map<string, unknown>();

  constructor(private readonly parent?: Environment) {}

  declare(name: string, value: unknown) {
    this.values.set(name, value);
  }

  get(name: string): unknown {
    if (this.values.has(name)) return this.values.get(name);
    if (this.parent) return this.parent.get(name);
    throw new Error(`Browser code uses an unknown identifier: ${name}`);
  }

  assign(name: string, value: unknown): unknown {
    if (this.values.has(name)) {
      this.values.set(name, value);
      return value;
    }
    if (this.parent) return this.parent.assign(name, value);
    throw new Error(`Browser code cannot assign undeclared identifier: ${name}`);
  }
}

class PageHandle {
  readonly keyboard = new KeyboardHandle(this);
  readonly media = new MediaHandle(this);

  constructor(readonly executor: BrowserCodeExecutor) {}
}

class MediaHandle {
  constructor(readonly page: PageHandle) {}
}

class FrameLocatorHandle {
  frameId?: number;
  documentId?: string;

  constructor(readonly page: PageHandle, readonly selector: string) {}
}

class KeyboardHandle {
  constructor(readonly page: PageHandle) {}
}

class LocatorHandle {
  resolvedTarget?: Record<string, unknown>;

  constructor(readonly page: PageHandle, readonly spec: LocatorSpec) {}
}

class DocumentHandle {
  constructor(readonly page: PageHandle) {}
}

class WindowHandle {
  constructor(readonly page: PageHandle) {}
}

class LocationHandle {
  constructor(readonly page: PageHandle) {}
}

class DOMElementHandle {
  constructor(readonly data: Record<string, unknown>) {}
}

class ConsoleHandle {}

class BuiltinHandle {
  constructor(readonly name: "JSON" | "Math" | "String" | "Number" | "Boolean" | "Object" | "Array") {}
}

const BLOCKED_PROPERTIES = new Set(["__proto__", "prototype", "constructor", "caller", "callee"]);
const PAGE_METHODS = new Set([
  "status", "goto", "open", "snapshot", "text", "tabs", "activeTab", "activateTab", "closeTab",
  "back", "forward", "reload", "waitFor", "waitForURL", "waitForEvent", "events", "screenshot", "acceptDialog", "dismissDialog",
  "frames", "frameLocator", "table", "artifact", "artifacts",
  "getByRole", "getByText", "getByLabel", "getByPlaceholder", "locator", "ref", "url", "title", "evaluate",
]);
const MAX_CODE_LENGTH = 20_000;
const MAX_LOOP_ITERATIONS = 1_000;

/**
 * A deliberately small JavaScript interpreter for Playwright-shaped browser
 * programs. It parses normal JS/TS syntax but never executes model code through
 * eval/Function, so filesystem, process, Bun, imports, and network globals are
 * not reachable from the model-facing tool.
 */
export class BrowserCodeExecutor {
  private readonly operations: BrowserCodeOperation[] = [];
  private readonly images: Array<{ data: string; mimeType: string }> = [];
  private readonly consoleOutput: unknown[] = [];
  private deadline = 0;
  private executionStartedAt = 0;

  constructor(private readonly runPrimitive: BrowserPrimitiveRunner) {}

  async execute(code: string, timeoutMs = 60_000): Promise<BrowserCodeExecution> {
    const source = code.trim();
    if (!source) throw new Error("Browser code is required");
    if (source.length > MAX_CODE_LENGTH) throw new Error(`Browser code is limited to ${MAX_CODE_LENGTH} characters`);

    const parsed = ts.createSourceFile("browser-task.ts", source, ts.ScriptTarget.ES2022, true, ts.ScriptKind.TS);
    const diagnostics = (parsed as ts.SourceFile & { parseDiagnostics?: readonly ts.Diagnostic[] }).parseDiagnostics ?? [];
    if (diagnostics.length > 0) {
      throw new Error(`Browser code syntax error: ${ts.flattenDiagnosticMessageText(diagnostics[0]!.messageText, " ")}`);
    }

    this.executionStartedAt = Date.now();
    this.deadline = this.executionStartedAt + clampNumber(timeoutMs, 1_000, 300_000, 60_000);
    const environment = new Environment();
    const page = new PageHandle(this);
    environment.declare("page", page);
    environment.declare("console", new ConsoleHandle());
    for (const name of ["JSON", "Math", "String", "Number", "Boolean", "Object", "Array"] as const) {
      environment.declare(name, new BuiltinHandle(name));
    }
    environment.declare("undefined", undefined);

    let result: unknown;
    let executionError: unknown;
    try {
      result = await this.evaluateStatements(parsed.statements, environment);
    } catch (signal) {
      if (isReturnSignal(signal)) result = signal.value;
      else executionError = signal;
    }

    const eventsResult = await this.primitive("browser.events", { drain: true }, false).catch(() => ({ events: [] }));
    const eventsRecord = asRecord(eventsResult);
    const events = Array.isArray(eventsRecord.events) ? eventsRecord.events : [];
    if (executionError) {
      const message = executionError instanceof Error ? executionError.message : String(executionError);
      throw new Error(`${message}\nBrowser operations: ${JSON.stringify(this.operations)}\nBrowser events: ${JSON.stringify(events)}`);
    }
    const finalResult = result === undefined && this.consoleOutput.length > 0 ? this.consoleOutput : result;
    return {
      result: sanitizeResult(finalResult),
      operations: this.operations,
      events,
      images: this.images,
    };
  }

  private async evaluateStatements(statements: readonly ts.Statement[], environment: Environment) {
    let result: unknown;
    for (const statement of statements) {
      this.assertWithinDeadline();
      result = await this.evaluateStatement(statement, environment);
    }
    return result;
  }

  private async evaluateStatement(statement: ts.Statement, environment: Environment): Promise<unknown> {
    if (ts.isVariableStatement(statement)) {
      let value: unknown;
      for (const declaration of statement.declarationList.declarations) {
        if (!ts.isIdentifier(declaration.name)) throw new Error("Browser code supports only simple variable names");
        value = declaration.initializer ? await this.evaluateExpression(declaration.initializer, environment) : undefined;
        environment.declare(declaration.name.text, value);
      }
      return value;
    }
    if (ts.isExpressionStatement(statement)) return await this.evaluateExpression(statement.expression, environment);
    if (ts.isReturnStatement(statement)) {
      throw { kind: "return", value: statement.expression ? await this.evaluateExpression(statement.expression, environment) : undefined } satisfies ReturnSignal;
    }
    if (ts.isBlock(statement)) return await this.evaluateStatements(statement.statements, new Environment(environment));
    if (ts.isIfStatement(statement)) {
      const condition = await this.evaluateExpression(statement.expression, environment);
      if (condition) return await this.evaluateStatement(statement.thenStatement, new Environment(environment));
      if (statement.elseStatement) return await this.evaluateStatement(statement.elseStatement, new Environment(environment));
      return undefined;
    }
    if (ts.isForOfStatement(statement)) {
      let values = await this.evaluateExpression(statement.expression, environment);
      if (values instanceof LocatorHandle) values = await this.allLocatorElements(values);
      if (!Array.isArray(values) && typeof values !== "string") throw new Error("Browser code for...of requires an array or string");
      const declaration = statement.initializer;
      if (!ts.isVariableDeclarationList(declaration) || declaration.declarations.length !== 1 || !ts.isIdentifier(declaration.declarations[0]!.name)) {
        throw new Error("Browser code for...of requires one simple loop variable");
      }
      const name = declaration.declarations[0]!.name.text;
      let result: unknown;
      let iterations = 0;
      for (const value of values) {
        if (++iterations > MAX_LOOP_ITERATIONS) throw new Error("Browser code loop exceeded its iteration limit");
        const child = new Environment(environment);
        child.declare(name, value);
        result = await this.evaluateStatement(statement.statement, child);
      }
      return result;
    }
    if (ts.isEmptyStatement(statement)) return undefined;
    throw new Error(`Unsupported browser code statement: ${ts.SyntaxKind[statement.kind]}`);
  }

  private async evaluateExpression(expression: ts.Expression, environment: Environment): Promise<unknown> {
    this.assertWithinDeadline();
    if (ts.isParenthesizedExpression(expression)) return await this.evaluateExpression(expression.expression, environment);
    if (ts.isAwaitExpression(expression)) return await this.evaluateExpression(expression.expression, environment);
    if (ts.isAsExpression(expression) || ts.isTypeAssertionExpression(expression) || ts.isNonNullExpression(expression)) {
      return await this.evaluateExpression(expression.expression, environment);
    }
    if (ts.isStringLiteralLike(expression)) return expression.text;
    if (ts.isNumericLiteral(expression)) return Number(expression.text);
    if (expression.kind === ts.SyntaxKind.TrueKeyword) return true;
    if (expression.kind === ts.SyntaxKind.FalseKeyword) return false;
    if (expression.kind === ts.SyntaxKind.NullKeyword) return null;
    if (ts.isIdentifier(expression)) return environment.get(expression.text);
    if (ts.isArrayLiteralExpression(expression)) {
      const result: unknown[] = [];
      for (const element of expression.elements) {
        if (ts.isSpreadElement(element)) {
          const spread = await this.evaluateExpression(element.expression, environment);
          if (!Array.isArray(spread)) throw new Error("Browser code can spread only arrays into arrays");
          result.push(...spread);
        } else {
          result.push(await this.evaluateExpression(element, environment));
        }
      }
      return result;
    }
    if (ts.isObjectLiteralExpression(expression)) return await this.evaluateObject(expression, environment);
    if (ts.isTemplateExpression(expression)) {
      let value = expression.head.text;
      for (const span of expression.templateSpans) {
        value += String(await this.evaluateExpression(span.expression, environment) ?? "") + span.literal.text;
      }
      return value;
    }
    if (ts.isNoSubstitutionTemplateLiteral(expression)) return expression.text;
    if (ts.isArrowFunction(expression) || ts.isFunctionExpression(expression)) {
      return { kind: "safe_function", node: expression, environment } satisfies SafeFunction;
    }
    if (ts.isConditionalExpression(expression)) {
      return await this.evaluateExpression(await this.evaluateExpression(expression.condition, environment) ? expression.whenTrue : expression.whenFalse, environment);
    }
    if (ts.isPrefixUnaryExpression(expression)) {
      const value = await this.evaluateExpression(expression.operand, environment);
      if (expression.operator === ts.SyntaxKind.ExclamationToken) return !value;
      if (expression.operator === ts.SyntaxKind.MinusToken) return -Number(value);
      if (expression.operator === ts.SyntaxKind.PlusToken) return Number(value);
      throw new Error(`Unsupported browser code unary operator: ${ts.tokenToString(expression.operator)}`);
    }
    if (ts.isTypeOfExpression(expression)) return typeof await this.evaluateExpression(expression.expression, environment);
    if (ts.isBinaryExpression(expression)) return await this.evaluateBinary(expression, environment);
    if (ts.isCallExpression(expression)) return await this.evaluateCall(expression, environment);
    if (ts.isPropertyAccessExpression(expression)) {
      return await this.getProperty(await this.evaluateExpression(expression.expression, environment), expression.name.text);
    }
    if (ts.isElementAccessExpression(expression)) {
      const receiver = await this.evaluateExpression(expression.expression, environment);
      const key = expression.argumentExpression ? await this.evaluateExpression(expression.argumentExpression, environment) : undefined;
      return await this.getProperty(receiver, String(key));
    }
    throw new Error(`Unsupported browser code expression: ${ts.SyntaxKind[expression.kind]}`);
  }

  private async evaluateObject(expression: ts.ObjectLiteralExpression, environment: Environment) {
    const value: Record<string, unknown> = {};
    for (const property of expression.properties) {
      if (ts.isPropertyAssignment(property)) {
        value[propertyName(property.name)] = await this.evaluateExpression(property.initializer, environment);
      } else if (ts.isShorthandPropertyAssignment(property)) {
        value[property.name.text] = environment.get(property.name.text);
      } else if (ts.isSpreadAssignment(property)) {
        const spread = await this.evaluateExpression(property.expression, environment);
        if (!isPlainRecord(spread)) throw new Error("Browser code can spread only plain objects into objects");
        Object.assign(value, spread);
      } else {
        throw new Error("Browser code object methods and accessors are not supported");
      }
    }
    return value;
  }

  private async evaluateBinary(expression: ts.BinaryExpression, environment: Environment) {
    const operator = expression.operatorToken.kind;
    if (operator === ts.SyntaxKind.EqualsToken) {
      const value = await this.evaluateExpression(expression.right, environment);
      if (ts.isIdentifier(expression.left)) return environment.assign(expression.left.text, value);
      throw new Error("Browser code assignment supports variables only");
    }
    if (operator === ts.SyntaxKind.AmpersandAmpersandToken) {
      const left = await this.evaluateExpression(expression.left, environment);
      return left ? await this.evaluateExpression(expression.right, environment) : left;
    }
    if (operator === ts.SyntaxKind.BarBarToken) {
      const left = await this.evaluateExpression(expression.left, environment);
      return left ? left : await this.evaluateExpression(expression.right, environment);
    }
    if (operator === ts.SyntaxKind.QuestionQuestionToken) {
      const left = await this.evaluateExpression(expression.left, environment);
      return left === null || left === undefined ? await this.evaluateExpression(expression.right, environment) : left;
    }
    const left = await this.evaluateExpression(expression.left, environment);
    const right = await this.evaluateExpression(expression.right, environment);
    switch (operator) {
      case ts.SyntaxKind.PlusToken: return typeof left === "string" || typeof right === "string" ? `${left ?? ""}${right ?? ""}` : Number(left) + Number(right);
      case ts.SyntaxKind.MinusToken: return Number(left) - Number(right);
      case ts.SyntaxKind.AsteriskToken: return Number(left) * Number(right);
      case ts.SyntaxKind.SlashToken: return Number(left) / Number(right);
      case ts.SyntaxKind.PercentToken: return Number(left) % Number(right);
      case ts.SyntaxKind.EqualsEqualsToken: return left == right;
      case ts.SyntaxKind.EqualsEqualsEqualsToken: return left === right;
      case ts.SyntaxKind.ExclamationEqualsToken: return left != right;
      case ts.SyntaxKind.ExclamationEqualsEqualsToken: return left !== right;
      case ts.SyntaxKind.LessThanToken: return (left as any) < (right as any);
      case ts.SyntaxKind.LessThanEqualsToken: return (left as any) <= (right as any);
      case ts.SyntaxKind.GreaterThanToken: return (left as any) > (right as any);
      case ts.SyntaxKind.GreaterThanEqualsToken: return (left as any) >= (right as any);
      default: throw new Error(`Unsupported browser code operator: ${ts.tokenToString(operator)}`);
    }
  }

  private async evaluateCall(expression: ts.CallExpression, environment: Environment) {
    const args: unknown[] = [];
    for (const argument of expression.arguments) args.push(await this.evaluateExpression(argument, environment));

    if (ts.isPropertyAccessExpression(expression.expression)) {
      const receiver = await this.evaluateExpression(expression.expression.expression, environment);
      return await this.callMethod(receiver, expression.expression.name.text, args);
    }
    if (ts.isElementAccessExpression(expression.expression)) {
      const receiver = await this.evaluateExpression(expression.expression.expression, environment);
      const name = expression.expression.argumentExpression
        ? String(await this.evaluateExpression(expression.expression.argumentExpression, environment))
        : "";
      return await this.callMethod(receiver, name, args);
    }
    if (ts.isIdentifier(expression.expression)) {
      const callable = environment.get(expression.expression.text);
      if (callable instanceof BuiltinHandle) return this.callBuiltinFunction(callable, args);
    }
    throw new Error("Browser code may call only methods on page, locators, arrays, strings, JSON, Math, or console");
  }

  private async callMethod(receiver: unknown, method: string, args: unknown[]) {
    if (BLOCKED_PROPERTIES.has(method)) throw new Error(`Browser code property is blocked: ${method}`);
    if (receiver instanceof PageHandle) return await this.callPage(receiver, method, args);
    if (receiver instanceof LocatorHandle) return await this.callLocator(receiver, method, args);
    if (receiver instanceof FrameLocatorHandle) return await this.callFrameLocator(receiver, method, args);
    if (receiver instanceof MediaHandle) return await this.callMedia(receiver, method, args);
    if (receiver instanceof DocumentHandle) return this.callDocument(receiver, method, args);
    if (receiver instanceof DOMElementHandle) return this.callDOMElement(receiver, method, args);
    if (receiver instanceof KeyboardHandle && method === "press") {
      return await receiver.page.executor.primitive("browser.key", { key: requireString(args[0], "key") });
    }
    if (receiver instanceof ConsoleHandle && ["log", "info", "warn", "error"].includes(method)) {
      this.consoleOutput.push(args.length <= 1 ? args[0] : args);
      return args.at(-1);
    }
    if (receiver instanceof BuiltinHandle) return await this.callBuiltin(receiver, method, args);
    if (Array.isArray(receiver)) return await this.callArray(receiver, method, args);
    if (typeof receiver === "string") return this.callString(receiver, method, args);
    if (isPlainRecord(receiver) && method === "hasOwnProperty") return Object.hasOwn(receiver, String(args[0]));
    throw new Error(`Unsupported browser code method: ${method}`);
  }

  private async callPage(page: PageHandle, method: string, args: unknown[]) {
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

  private async callFrameLocator(frame: FrameLocatorHandle, method: string, args: unknown[]) {
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

  private async callMedia(media: MediaHandle, method: string, args: unknown[]) {
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

  private async captureArtifact(input: unknown) {
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

  private async callLocator(locator: LocatorHandle, method: string, args: unknown[]) {
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

  private async callDocument(document: DocumentHandle, method: string, args: unknown[]) {
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

  private async verifiedType(target: Record<string, unknown>, inputText: string, append: boolean) {
    const result = asRecord(await this.primitive("browser.type", { ...target, inputText, append }));
    if (result.verified === false) {
      throw new Error(`Browser ${append ? "type" : "fill"} did not retain the requested value`);
    }
    return result;
  }

  private callDOMElement(element: DOMElementHandle, method: string, args: unknown[]) {
    if (method === "getAttribute") return stringValue(asRecord(element.data.attributes)[String(args[0] ?? "")]) ?? null;
    if (method === "hasAttribute") return Object.hasOwn(asRecord(element.data.attributes), String(args[0] ?? ""));
    if (method === "checkValidity") {
      return typeof element.data.valid === "boolean" ? element.data.valid : Boolean(asRecord(element.data.validity).valid);
    }
    throw new Error(`Unsupported safe DOM element method: ${method}`);
  }

  private async waitFor(args: unknown[]) {
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

  private async waitForURL(args: unknown[]) {
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

  private async waitForEvent(args: unknown[]) {
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

  private locatorPayload(locator: LocatorHandle) {
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

  private async liveLocatorPayload(locator: LocatorHandle) {
    await this.resolveLocatorFrame(locator);
    if (locator.resolvedTarget || locator.spec.kind === "selector" || locator.spec.kind === "ref" || locator.spec.kind === "text") {
      return this.locatorPayload(locator);
    }
    return (await this.resolveLocator(locator)).target;
  }

  private async readLocator(locator: LocatorHandle, kind: "textContent" | "innerText" | "inputValue") {
    const result = asRecord(await this.primitive("browser.query", { ...await this.liveLocatorPayload(locator), kind }));
    if (!("value" in result)) throw new Error(`Browser ${kind} query returned no value`);
    return result.value;
  }

  private async countLocator(locator: LocatorHandle) {
    const result = asRecord(await this.primitive("browser.query", { ...await this.liveLocatorPayload(locator), kind: "count" }));
    if (typeof result.count !== "number") throw new Error("Browser count query returned no count");
    return result.count;
  }

  private async readLocatorElement(locator: LocatorHandle) {
    const result = asRecord(await this.primitive("browser.query", { ...await this.liveLocatorPayload(locator), kind: "element" }));
    if (!isPlainRecord(result.element)) throw new Error("Browser element query returned no element");
    return new DOMElementHandle(result.element);
  }

  private async allLocatorElements(locator: LocatorHandle) {
    const result = asRecord(await this.primitive("browser.query", { ...await this.liveLocatorPayload(locator), kind: "all" }));
    return Array.isArray(result.elements) ? result.elements.map((element) => new DOMElementHandle(asRecord(element))) : [];
  }

  private async resolveLocator(locator: LocatorHandle) {
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

  private async resolveLocatorFrame(locator: LocatorHandle) {
    if (!locator.spec.frameSelector || locator.spec.frameId !== undefined) return;
    const frame = asRecord(await this.primitive("browser.resolve_frame", { selector: locator.spec.frameSelector }));
    if (!Number.isInteger(frame.frameId)) throw new Error(`Frame selector did not resolve: ${locator.spec.frameSelector}`);
    locator.spec.frameId = frame.frameId;
    locator.spec.documentId = stringValue(frame.documentId);
  }

  private async captureScreenshot(options: Record<string, unknown>) {
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
    const operation: BrowserCodeOperation = { operation: command.replace(/^browser\./, ""), durationMs: 0, ok: false };
    try {
      const result = await this.runPrimitive(command, payload);
      operation.ok = true;
      return result;
    } catch (error) {
      operation.error = error instanceof Error ? error.message : String(error);
      throw error;
    } finally {
      operation.durationMs = Date.now() - startedAt;
      if (record) this.operations.push(operation);
    }
  }

  private async callArray(receiver: unknown[], method: string, args: unknown[]) {
    const callback = isSafeFunction(args[0]) ? args[0] : undefined;
    switch (method) {
      case "map": return callback ? await Promise.all(receiver.map((value, index) => this.invoke(callback, [value, index, receiver]))) : receiver;
      case "filter": {
        if (!callback) throw new Error("Array.filter needs a callback");
        const keep = await Promise.all(receiver.map((value, index) => this.invoke(callback, [value, index, receiver])));
        return receiver.filter((_, index) => Boolean(keep[index]));
      }
      case "find": {
        if (!callback) throw new Error("Array.find needs a callback");
        for (let index = 0; index < receiver.length; index += 1) if (await this.invoke(callback, [receiver[index], index, receiver])) return receiver[index];
        return undefined;
      }
      case "some": {
        if (!callback) throw new Error("Array.some needs a callback");
        for (let index = 0; index < receiver.length; index += 1) if (await this.invoke(callback, [receiver[index], index, receiver])) return true;
        return false;
      }
      case "every": {
        if (!callback) throw new Error("Array.every needs a callback");
        for (let index = 0; index < receiver.length; index += 1) if (!await this.invoke(callback, [receiver[index], index, receiver])) return false;
        return true;
      }
      case "flatMap": return callback ? (await Promise.all(receiver.map((value, index) => this.invoke(callback, [value, index, receiver])))).flat() : receiver.flat();
      case "push": return receiver.push(...args);
      case "pop": return receiver.pop();
      case "shift": return receiver.shift();
      case "unshift": return receiver.unshift(...args);
      case "includes": return receiver.includes(args[0]);
      case "indexOf": return receiver.indexOf(args[0]);
      case "slice": return receiver.slice(numberOr(args[0], 0), args[1] === undefined ? undefined : numberOr(args[1], receiver.length));
      case "join": return receiver.join(stringValue(args[0]) ?? ",");
      case "at": return receiver.at(numberOr(args[0], 0));
      case "concat": return receiver.concat(...args);
      case "reverse": return [...receiver].reverse();
      case "sort": {
        const sorted = [...receiver];
        if (!callback) return sorted.sort();
        for (let left = 1; left < sorted.length; left += 1) {
          let right = left;
          while (right > 0 && Number(await this.invoke(callback, [sorted[right - 1], sorted[right]])) > 0) {
            [sorted[right - 1], sorted[right]] = [sorted[right], sorted[right - 1]];
            right -= 1;
          }
        }
        return sorted;
      }
      default: throw new Error(`Unsupported safe array method: ${method}`);
    }
  }

  private callString(receiver: string, method: string, args: unknown[]) {
    switch (method) {
      case "includes": return receiver.includes(String(args[0] ?? ""));
      case "indexOf": return receiver.indexOf(String(args[0] ?? ""), numberOr(args[1], 0));
      case "lastIndexOf": return receiver.lastIndexOf(String(args[0] ?? ""), args[1] === undefined ? undefined : numberOr(args[1], receiver.length));
      case "startsWith": return receiver.startsWith(String(args[0] ?? ""));
      case "endsWith": return receiver.endsWith(String(args[0] ?? ""));
      case "toLowerCase": return receiver.toLowerCase();
      case "toUpperCase": return receiver.toUpperCase();
      case "trim": return receiver.trim();
      case "slice": return receiver.slice(numberOr(args[0], 0), args[1] === undefined ? undefined : numberOr(args[1], receiver.length));
      case "substring": return receiver.substring(numberOr(args[0], 0), args[1] === undefined ? undefined : numberOr(args[1], receiver.length));
      case "at": return receiver.at(numberOr(args[0], 0));
      case "charAt": return receiver.charAt(numberOr(args[0], 0));
      case "split": return receiver.split(String(args[0] ?? ""), args[1] === undefined ? undefined : numberOr(args[1], 0));
      case "replace": return receiver.replace(String(args[0] ?? ""), String(args[1] ?? ""));
      default: throw new Error(`Unsupported safe string method: ${method}`);
    }
  }

  private async callBuiltin(receiver: BuiltinHandle, method: string, args: unknown[]) {
    if (receiver.name === "JSON") {
      if (method === "stringify") return JSON.stringify(args[0], null, numberOr(args[1], 0));
      if (method === "parse") return JSON.parse(requireString(args[0], "JSON string"));
    }
    if (receiver.name === "Math" && ["min", "max", "round", "floor", "ceil", "abs"].includes(method)) {
      const fn = Math[method as "min"] as (...values: number[]) => number;
      return fn(...args.map(Number));
    }
    if (receiver.name === "Object") {
      if (method === "keys") return Object.keys(asRecord(args[0]));
      if (method === "values") return Object.values(asRecord(args[0]));
      if (method === "entries") return Object.entries(asRecord(args[0]));
    }
    if (receiver.name === "Array" && method === "isArray") return Array.isArray(args[0]);
    if (receiver.name === "Array" && method === "from") {
      if (args[0] instanceof LocatorHandle) {
        return await this.allLocatorElements(args[0]);
      }
      if (Array.isArray(args[0]) || typeof args[0] === "string") return Array.from(args[0]);
      throw new Error("Array.from supports browser locator collections, arrays, or strings");
    }
    throw new Error(`Unsupported safe builtin method: ${receiver.name}.${method}`);
  }

  private callBuiltinFunction(receiver: BuiltinHandle, args: unknown[]) {
    if (receiver.name === "String") return String(args[0] ?? "");
    if (receiver.name === "Number") return Number(args[0]);
    if (receiver.name === "Boolean") return Boolean(args[0]);
    if (receiver.name === "Array") return args.length === 0 ? [] : [args[0]];
    throw new Error(`Safe builtin is not directly callable: ${receiver.name}`);
  }

  private async invoke(callback: SafeFunction, args: unknown[], bindings: Record<string, unknown> = {}) {
    const environment = new Environment(callback.environment);
    for (const [name, value] of Object.entries(bindings)) environment.declare(name, value);
    callback.node.parameters.forEach((parameter, index) => {
      if (!ts.isIdentifier(parameter.name)) throw new Error("Browser code callbacks support only simple parameters");
      const name = parameter.name.text;
      if (args[index] === undefined && Object.hasOwn(bindings, name)) return;
      environment.declare(name, args[index]);
    });
    if (ts.isBlock(callback.node.body)) {
      try {
        return await this.evaluateStatements(callback.node.body.statements, environment);
      } catch (signal) {
        if (isReturnSignal(signal)) return signal.value;
        throw signal;
      }
    }
    return await this.evaluateExpression(callback.node.body, environment);
  }

  private async getProperty(receiver: unknown, property: string): Promise<unknown> {
    if (BLOCKED_PROPERTIES.has(property)) throw new Error(`Browser code property is blocked: ${property}`);
    if (receiver instanceof PageHandle && property === "keyboard") return receiver.keyboard;
    if (receiver instanceof PageHandle && property === "media") return receiver.media;
    if (receiver instanceof PageHandle && PAGE_METHODS.has(property)) return true;
    if (receiver instanceof DocumentHandle) {
      if (property === "body") return new LocatorHandle(receiver.page, { kind: "selector", value: "body" });
      if (property === "documentElement") return new LocatorHandle(receiver.page, { kind: "selector", value: "html" });
      if (property === "title") return await this.callPage(receiver.page, "title", []);
      if (property === "URL" || property === "url") return await this.callPage(receiver.page, "url", []);
    }
    if (receiver instanceof WindowHandle) {
      if (property === "document") return new DocumentHandle(receiver.page);
      if (property === "location") return new LocationHandle(receiver.page);
    }
    if (receiver instanceof LocationHandle) {
      if (property === "href") return await this.callPage(receiver.page, "url", []);
    }
    if (receiver instanceof LocatorHandle) {
      if (property === "length") return await this.countLocator(receiver);
      if (property === "textContent") return await this.readLocator(receiver, "textContent");
      if (property === "innerText") return await this.readLocator(receiver, "innerText");
      if (property === "value") return await this.readLocator(receiver, "inputValue");
      if ([
        "ref", "href", "tagName", "id", "name", "type", "accept", "placeholder", "autocomplete", "checked", "selected",
        "disabled", "required", "multiple", "files", "options", "validity", "rect", "frameId", "documentId", "frameUrl", "src",
      ].includes(property)) {
        const element = await this.readLocatorElement(receiver);
        return await this.getProperty(element, property);
      }
    }
    if (receiver instanceof DOMElementHandle) {
      if (property === "textContent") return receiver.data.textContent ?? "";
      if (property === "innerText") return receiver.data.innerText ?? receiver.data.textContent ?? "";
      if (property === "value") return receiver.data.value ?? "";
      if (property === "href") return receiver.data.href ?? "";
      if (property === "src") return receiver.data.src ?? "";
      if (property === "tagName") return String(receiver.data.tagName ?? "").toUpperCase();
      if ([
        "ref", "id", "name", "type", "accept", "placeholder", "autocomplete", "checked", "selected", "disabled", "required",
        "multiple", "files", "options", "validity", "rect", "frameId", "documentId", "frameUrl",
      ].includes(property)) return receiver.data[property];
    }
    if (Array.isArray(receiver) && property === "length") return receiver.length;
    if (Array.isArray(receiver) && /^\d+$/.test(property)) return receiver[Number(property)];
    if (typeof receiver === "string" && property === "length") return receiver.length;
    if (typeof receiver === "string" && /^\d+$/.test(property)) return receiver[Number(property)];
    if (isPlainRecord(receiver)) return receiver[property];
    if (receiver === null || receiver === undefined) return undefined;
    throw new Error(`Unsupported browser code property access: ${property}`);
  }

  private assertWithinDeadline() {
    if (Date.now() > this.deadline) throw new Error("Browser code execution timed out");
  }
}

function sanitizeResult(value: unknown, depth = 0): unknown {
  if (depth > 12) return "[max depth]";
  if (value instanceof LocatorHandle) return { locator: value.spec };
  if (value instanceof PageHandle) return { page: true };
  if (value instanceof KeyboardHandle) return { keyboard: true };
  if (value instanceof MediaHandle) return { media: true };
  if (value instanceof FrameLocatorHandle) return { frameLocator: value.selector };
  if (value instanceof DOMElementHandle) return sanitizeResult(value.data, depth + 1);
  if (
    value instanceof DocumentHandle
    || value instanceof WindowHandle
    || value instanceof LocationHandle
    || value instanceof BuiltinHandle
    || value instanceof ConsoleHandle
    || isSafeFunction(value)
  ) return undefined;
  if (Array.isArray(value)) return value.slice(0, 1_000).map((item) => sanitizeResult(item, depth + 1));
  if (isPlainRecord(value)) {
    return Object.fromEntries(Object.entries(value).filter(([key]) => key !== "data" && key !== "dataUrl")
      .map(([key, item]) => [key, sanitizeResult(item, depth + 1)]));
  }
  return value;
}

function propertyName(name: ts.PropertyName) {
  if (ts.isIdentifier(name) || ts.isStringLiteralLike(name) || ts.isNumericLiteral(name)) return name.text;
  throw new Error("Browser code object keys must be identifiers, strings, or numbers");
}

function isSafeFunction(value: unknown): value is SafeFunction {
  return Boolean(value && typeof value === "object" && (value as SafeFunction).kind === "safe_function");
}

function isReturnSignal(value: unknown): value is ReturnSignal {
  return Boolean(value && typeof value === "object" && (value as ReturnSignal).kind === "return");
}

function isPlainRecord(value: unknown): value is Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const prototype = Object.getPrototypeOf(value);
  return prototype === Object.prototype || prototype === null;
}

function asRecord(value: unknown): Record<string, any> {
  return isPlainRecord(value) ? value as Record<string, any> : {};
}

function normalize(value: unknown) {
  return typeof value === "string" ? value.replace(/\s+/g, " ").trim().toLocaleLowerCase() : "";
}

function requireString(value: unknown, name: string) {
  if (typeof value !== "string" || !value.trim()) throw new Error(`Browser code needs ${name}`);
  return value;
}

function requireStringOrNumber(value: unknown, name: string) {
  if (typeof value === "string" && value.trim()) return value;
  if (typeof value === "number" && Number.isFinite(value)) return value;
  throw new Error(`Browser code needs ${name}`);
}

function stringValue(value: unknown) {
  return typeof value === "string" ? value : undefined;
}

function urlMatches(actual: string, expected: string) {
  if (!expected.includes("*")) return actual === expected || actual.includes(expected);
  const source = expected.split("*").map((part) => part.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join(".*");
  return new RegExp(`^${source}$`).test(actual);
}

function numberOr(value: unknown, fallback: number) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function clampNumber(value: unknown, min: number, max: number, fallback: number) {
  return Math.min(max, Math.max(min, numberOr(value, fallback)));
}

function waitTimeout(value: Record<string, unknown>) {
  return clampNumber(value.timeoutMs ?? value.timeout, 100, 60_000, 10_000);
}

function cssEscape(value: string) {
  return value.replace(/[^a-zA-Z0-9_-]/g, (character) => `\\${character.codePointAt(0)!.toString(16)} `);
}

function cssAttributeEscape(value: string) {
  return value.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
}
