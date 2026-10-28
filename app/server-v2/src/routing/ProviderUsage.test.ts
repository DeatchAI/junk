import { expect, test } from "bun:test";
import { codexUsageWindows, ProviderUsageService, providerUsageResponse } from "./ProviderUsage";

test("Codex quotas prefer multiple buckets, preserve unknown scope, and reject malformed values", () => {
  const windows = codexUsageWindows({ rateLimits: { primary: { usedPercent: 99 } }, rateLimitsByLimitId: {
    codex: { primary: { usedPercent: 25, resetsAt: 1_900_000_000 }, secondary: { usedPercent: 90 } },
    specialist: { primary: { usedPercent: 100 }, secondary: { usedPercent: "40" } },
    invalid: { primary: { usedPercent: -1 } },
  } });
  expect(windows).toHaveLength(3);
  expect(windows[0]).toEqual({ agent: "codex", bucket: "codex:primary", modelIDs: null, usedPercent: 25, resetsAt: 1_900_000_000 });
  expect(windows[2]?.modelIDs).toEqual([]);
  expect(codexUsageWindows({})).toEqual([]);
  expect(codexUsageWindows({ rateLimits: { primary: { usedPercent: 0 } } })[0]?.usedPercent).toBe(0);
});

test("usage discovery only reads quota, closes the client and coalesces refreshes", async () => {
  const calls: string[] = [];
  let closed = 0;
  const service = new ProviderUsageService(async () => ({
    async initialize() { calls.push("initialize"); },
    async request(method, params) { calls.push(method); expect(params).toEqual({}); return { rateLimits: { primary: { usedPercent: 75 } } }; },
    close() { closed++; },
  }));
  const [first, second] = await Promise.all([service.get(), service.get()]);
  expect(first).toBe(second);
  expect(calls).toEqual(["initialize", "account/rateLimits/read"]);
  expect(closed).toBe(1);
  expect(first.windows[0]?.usedPercent).toBe(75);
  expect(await service.get()).toBe(first);
});

test("unavailable usage stays unknown and errors never echo account data", async () => {
  let closed = false;
  const service = new ProviderUsageService(async () => ({
    async initialize() { throw new Error("private-account-information"); },
    async request() { throw new Error("must not run"); }, close() { closed = true; },
  }));
  const result = await service.get();
  expect(result.windows).toEqual([]);
  expect(JSON.stringify(result)).not.toContain("private-account-information");
  expect(closed).toBe(true);
  expect((await new ProviderUsageService(async () => undefined).get()).windows).toEqual([]);
});

test("usage endpoint rejects browser origins and writes without probing the provider", async () => {
  let reads = 0;
  const service = { async get() { reads++; return { checkedAt: 1, windows: [], notices: [] }; } };
  expect((await providerUsageResponse(new Request("http://127.0.0.1/api/agent-usage", { headers: { Origin: "https://example.com" } }), service)).status).toBe(403);
  expect((await providerUsageResponse(new Request("http://127.0.0.1/api/agent-usage", { method: "POST" }), service)).status).toBe(405);
  expect(reads).toBe(0);
  const response = await providerUsageResponse(new Request("http://127.0.0.1/api/agent-usage"), service);
  expect(response.headers.get("cache-control")).toBe("no-store");
  expect(reads).toBe(1);
});
