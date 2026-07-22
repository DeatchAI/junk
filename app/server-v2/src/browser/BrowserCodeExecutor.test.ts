import { describe, expect, test } from "bun:test";

import { BrowserCodeExecutor } from "./BrowserCodeExecutor";

describe("browser code executor", () => {
  test("batches Playwright-shaped actions over private browser primitives", async () => {
    const commands: string[] = [];
    const executor = new BrowserCodeExecutor(async (command) => {
      commands.push(command);
      if (command === "browser.snapshot") {
        return {
          url: "https://example.com",
          title: "Example",
          elements: [{ ref: "e1", role: "button", name: "Save", depth: 1 }],
          delta: { changed: [] },
        };
      }
      if (command === "browser.screenshot") return { format: "png", data: "aW1hZ2U=" };
      if (command === "browser.events") return { events: [{ type: "navigation", url: "https://example.com" }] };
      return { ok: true };
    });

    const result = await executor.execute(`
      await page.goto("https://example.com");
      await page.getByRole("button", { name: "Save", exact: true }).click();
      await page.screenshot();
      return await page.snapshot();
    `);

    expect(commands).toEqual([
      "browser.navigate",
      "browser.snapshot",
      "browser.click",
      "browser.screenshot",
      "browser.snapshot",
      "browser.events",
    ]);
    expect(result.result).toMatchObject({ title: "Example", tree: expect.stringContaining("button \"Save\"") });
    expect(result.images).toEqual([{ data: "aW1hZ2U=", mimeType: "image/png" }]);
    expect(result.events).toEqual([{ type: "navigation", url: "https://example.com" }]);
  });

  test("supports safe local data transforms without exposing runtime globals", async () => {
    const executor = new BrowserCodeExecutor(async (command) => command === "browser.events" ? { events: [] } : {});
    const result = await executor.execute("return [1, 2, 3, 4].filter((value) => value > 2).map((value) => value * 10);");
    expect(result.result).toEqual([30, 40]);
    await expect(executor.execute("return process.env;")).rejects.toThrow("unknown identifier: process");
  });

  test("rejects the Hugging Face search-box ambiguity and exposes exact login refs", async () => {
    const elements = [
      { ref: "search-ref", role: "textbox", accessibleName: "Search models, datasets, users...", placeholder: "Search models, datasets, users...", type: "text" },
      { ref: "username-ref", role: "textbox", accessibleName: "Username or Email address", name: "username", type: "text", autocomplete: "username" },
      { ref: "password-ref", role: "textbox", accessibleName: "Password Forgot your password?", name: "password", placeholder: "Password", type: "password", autocomplete: "current-password", value: "[password]" },
    ];
    const runner = async (command: string, payload: Record<string, unknown>) => {
      if (command === "browser.snapshot") return { url: "https://huggingface.co/login", elements };
      if (command === "browser.query" && payload.kind === "element") {
        return { element: elements.find((element) => element.ref === payload.ref), matched: true };
      }
      if (command === "browser.events") return { events: [] };
      return { verified: true };
    };

    const ambiguous = new BrowserCodeExecutor(runner);
    await expect(ambiguous.execute('await page.getByRole("textbox").click();')).rejects.toThrow(
      "Locator matched 3 elements"
    );

    const reliable = new BrowserCodeExecutor(runner);
    const result = await reliable.execute(`
      const username = await page.getByLabel("Username or Email address", { exact: true }).describe();
      const password = await page.getByPlaceholder("Password", { exact: true }).describe();
      return { usernameRef: username.ref, passwordRef: password.ref, usernameAutocomplete: username.autocomplete };
    `);
    expect(result.result).toEqual({
      usernameRef: "username-ref",
      passwordRef: "password-ref",
      usernameAutocomplete: "username",
    });
  });

  test("can fall back to an HTML name when a role has a localized accessible name", async () => {
    const calls: Array<{ command: string; payload: Record<string, unknown> }> = [];
    const executor = new BrowserCodeExecutor(async (command, payload) => {
      calls.push({ command, payload });
      if (command === "browser.snapshot") {
        return { elements: [{ ref: "country-ref", role: "combobox", name: "البلد *", htmlName: "country" }] };
      }
      if (command === "browser.query") return { value: "مصر", matched: true };
      if (command === "browser.events") return { events: [] };
      return { verified: true };
    });

    const result = await executor.execute(`
      const country = page.getByRole("combobox", { name: "country" });
      await country.selectOption("مصر");
      return await country.inputValue();
    `);

    expect(result.result).toBe("مصر");
    expect(calls).toContainEqual({
      command: "browser.select",
      payload: { ref: "country-ref", value: "مصر" },
    });
    expect(calls).toContainEqual({
      command: "browser.query",
      payload: { ref: "country-ref", kind: "inputValue" },
    });
  });

  test("uses live DOM queries for locator reads and safe page.evaluate", async () => {
    const calls: Array<{ command: string; payload: Record<string, unknown> }> = [];
    const executor = new BrowserCodeExecutor(async (command, payload) => {
      calls.push({ command, payload });
      if (command === "browser.get_active_tab") return { url: "https://example.com/data", title: "Live page" };
      if (command === "browser.query") {
        if (payload.kind === "count") return { count: payload.selector === "input" ? 2 : 3 };
        if (payload.kind === "all") {
          return {
            count: 2,
            elements: [
              { tagName: "a", textContent: "First", href: "https://example.com/1" },
              { tagName: "a", textContent: "Second", href: "https://example.com/2" },
            ],
          };
        }
        if (payload.kind === "inputValue") return { value: "nonlatin@example.com", matched: true };
        return { value: '{"items":["alpha","beta"]}', matched: true };
      }
      if (command === "browser.wait") return { matched: true, ...payload };
      if (command === "browser.events") return { events: [] };
      return {};
    });

    const result = await executor.execute(`
      const currentUrl = page.url ? await page.url() : "";
      const title = await page.title();
      const body = await page.locator("body").textContent();
      const parsed = JSON.parse(body);
      const values = [];
      values.push(parsed.items[0]);
      values.push(parsed.items[1]);
      const email = await page.ref("email").inputValue();
      const inputCount = await page.locator("input").count();
      const evaluatedText = await page.evaluate(() => document.body.innerText);
      const evaluatedCount = await page.evaluate(() => document.querySelectorAll("input").length);
      const shadowedDocumentCount = await page.evaluate((document) => document.querySelectorAll("input").length);
      const links = await page.evaluate(() => Array.from(document.querySelectorAll("a")).map((link) => link.textContent));
      await page.waitFor(25);
      await page.waitFor("body", { timeout: 750 });
      return { currentUrl, title, values, firstIndex: values.indexOf("alpha"), email, inputCount, evaluatedText, evaluatedCount, shadowedDocumentCount, links };
    `);

    expect(result.result).toEqual({
      currentUrl: "https://example.com/data",
      title: "Live page",
      values: ["alpha", "beta"],
      firstIndex: 0,
      email: "nonlatin@example.com",
      inputCount: 2,
      evaluatedText: '{"items":["alpha","beta"]}',
      evaluatedCount: 2,
      shadowedDocumentCount: 2,
      links: ["First", "Second"],
    });
    expect(calls).toContainEqual({ command: "browser.query", payload: { ref: "email", kind: "inputValue" } });
    expect(calls).toContainEqual({ command: "browser.wait", payload: { delayMs: 25 } });
    expect(calls).toContainEqual({ command: "browser.wait", payload: { selector: "body", timeoutMs: 750 } });
  });

  test("waits for URL changes without inspecting a credential-locked document", async () => {
    let reads = 0;
    const executor = new BrowserCodeExecutor(async (command) => {
      if (command === "browser.get_active_tab") {
        reads += 1;
        return reads < 2
          ? { url: "https://example.com/login", title: "Login", status: "complete" }
          : { url: "https://example.com/dashboard", title: "Dashboard", status: "complete" };
      }
      if (command === "browser.events") return { events: [] };
      throw new Error(`Unexpected command: ${command}`);
    });

    const result = await executor.execute('return await page.waitForURL("**/dashboard", { timeout: 1000 });');
    expect(result.result).toEqual({
      matched: true,
      url: "https://example.com/dashboard",
      title: "Dashboard",
      status: "complete",
    });
  });

  test("does not turn unmatched or empty live reads into invented values", async () => {
    const executor = new BrowserCodeExecutor(async (command, payload) => {
      if (command === "browser.query" && payload.kind === "count") return { count: 0 };
      if (command === "browser.query" && payload.kind === "textContent") return { value: null, matched: false };
      if (command === "browser.events") return { events: [] };
      throw new Error("No page element matched the live inputValue query");
    });
    const result = await executor.execute(`
      return {
        count: await page.locator(".missing").count(),
        text: await page.locator(".missing").textContent()
      };
    `);
    expect(result.result).toEqual({ count: 0, text: null });
    await expect(executor.execute('return await page.locator(".missing").inputValue();')).rejects.toThrow(
      "No page element matched the live inputValue query"
    );
  });

  test("supports live form validation, selector iteration, select options, and uploaded file metadata", async () => {
    const email = {
      tagName: "input",
      value: "مستخدم@مثال.مصر",
      id: "email",
      name: "email",
      type: "email",
      checked: false,
      required: true,
      validity: { valid: true, typeMismatch: false },
      files: [],
      options: [],
      attributes: { id: "email", name: "email", type: "email", required: "" },
    };
    const country = {
      tagName: "select",
      value: "مصر",
      id: "country",
      name: "country",
      required: true,
      validity: { valid: true },
      files: [],
      options: [
        { value: "", label: "اختر...", text: "اختر...", textContent: "اختر...", selected: false },
        { value: "مصر", label: "مصر", text: "مصر", textContent: "مصر", selected: true },
      ],
      attributes: { id: "country", name: "country", required: "" },
    };
    const upload = {
      tagName: "input",
      value: "وثيقة-اختبار.txt",
      id: "document",
      name: "document",
      type: "file",
      required: true,
      validity: { valid: true },
      files: [{ name: "وثيقة-اختبار.txt", type: "text/plain", size: 42 }],
      options: [],
      attributes: { id: "document", name: "document", type: "file", required: "" },
    };
    const form = { tagName: "form", validity: { valid: true }, files: [], options: [], attributes: { id: "non-latin-form" } };
    const bySelector: Record<string, Record<string, unknown>> = {
      "#email": email,
      "#country": country,
      "#document": upload,
      form,
    };
    const executor = new BrowserCodeExecutor(async (command, payload) => {
      if (command === "browser.query") {
        if (payload.kind === "all") return { count: 3, elements: [email, country, upload] };
        if (payload.kind === "element") return { element: bySelector[String(payload.selector)] };
        if (payload.kind === "checkValidity") return { valid: true, validity: { valid: true }, matched: true };
      }
      if (command === "browser.events") return { events: [] };
      return {};
    });

    const result = await executor.execute(`
      return await page.evaluate(() => {
        const fields = [];
        for (const el of document.querySelectorAll('input, select, textarea, button')) {
          fields.push({
            tag: el.tagName,
            name: el.getAttribute('name'),
            required: el.hasAttribute('required'),
            options: el.tagName === 'SELECT' ? Array.from(el.options).map((option) => option.textContent) : []
          });
        }
        const file = document.querySelector('#document').files[0];
        return {
          fields,
          emailValid: document.querySelector('#email').checkValidity(),
          formValid: document.querySelector('form').checkValidity(),
          countryOptions: Array.from(document.querySelector('#country').options).map((option) => option.value),
          checked: document.querySelector('#email').checked,
          fileName: file.name,
          fileCount: document.querySelector('#document').files.length
        };
      });
    `);

    expect(result.result).toMatchObject({
      emailValid: true,
      formValid: true,
      countryOptions: ["", "مصر"],
      checked: false,
      fileName: "وثيقة-اختبار.txt",
      fileCount: 1,
    });
    expect((result.result as { fields: unknown[] }).fields).toHaveLength(3);
  });

  test("includes queued failure and dialog events when a program aborts", async () => {
    const executor = new BrowserCodeExecutor(async (command) => {
      if (command === "browser.click") throw new Error("Target is covered");
      if (command === "browser.events") return { events: [{ type: "failure", error: "Target is covered" }] };
      return {};
    });

    await expect(executor.execute('await page.locator("#submit").click();')).rejects.toThrow(
      'Browser events: [{"type":"failure","error":"Target is covered"}]'
    );
  });
});
