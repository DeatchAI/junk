import * as ts from "typescript";
import { Environment, PageHandle, MediaHandle, FrameLocatorHandle, KeyboardHandle, LocatorHandle,
  DocumentHandle, WindowHandle, LocationHandle, DOMElementHandle, ConsoleHandle, BuiltinHandle,
  BLOCKED_PROPERTIES, PAGE_METHODS, MAX_CODE_LENGTH, MAX_LOOP_ITERATIONS, sanitizeResult,
  propertyName, isSafeFunction, isReturnSignal, isPlainRecord, asRecord, normalize, requireString,
  requireStringOrNumber, stringValue, urlMatches, numberOr, clampNumber, waitTimeout, cssEscape,
  cssAttributeEscape, type SafeFunction, type ReturnSignal, type LocatorSpec, type BrowserPrimitiveRunner,
  type BrowserPrimitiveObserver, type BrowserCodeExecution, type BrowserCodeOperation } from "./execution/BrowserCodeValues";
import { BrowserPageOperations } from "./execution/BrowserPageOperations";
export type { BrowserPrimitiveRunner, BrowserPrimitiveObserver, BrowserPrimitiveUpdate, BrowserCodeExecution, BrowserCodeOperation } from "./execution/BrowserCodeValues";

/** Restricted AST interpreter; browser primitives live in the execution directory. */
export class BrowserCodeExecutor extends BrowserPageOperations {
  private readonly consoleOutput: unknown[] = [];
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

  protected async invoke(callback: SafeFunction, args: unknown[], bindings: Record<string, unknown> = {}): Promise<unknown> {
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

}
