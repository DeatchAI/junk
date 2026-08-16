import { describe, expect, test } from "bun:test";
import { isAllowedRuntimeSocketOrigin, isAuthorizedRuntimeRequest } from "./RuntimeAuth";

const token = "launch-secret-token";

describe("local runtime authentication", () => {
  test("accepts the app bearer token and extension query token", () => {
    const headerRequest = new Request("http://127.0.0.1:3847/api/capabilities", {
      headers: { Authorization: `Bearer ${token}` },
    });
    expect(isAuthorizedRuntimeRequest(headerRequest, new URL(headerRequest.url), token)).toBe(true);

    const socketURL = new URL("ws://127.0.0.1:3847/api/browser/native");
    socketURL.searchParams.set("token", token);
    expect(isAuthorizedRuntimeRequest(new Request(socketURL.toString()), socketURL, token)).toBe(true);
  });

  test("rejects unrelated local processes and browser pages", () => {
    const request = new Request("http://127.0.0.1:3847/api/desktop/command");
    expect(isAuthorizedRuntimeRequest(request, new URL(request.url), token)).toBe(false);
    expect(isAuthorizedRuntimeRequest(request, new URL(`${request.url}?token=wrong`), token)).toBe(false);
    expect(isAllowedRuntimeSocketOrigin("/", "https://malicious.example", "chrome-extension://trusted")).toBe(false);
    expect(isAllowedRuntimeSocketOrigin("/api/browser/native", "chrome-extension://other", "chrome-extension://trusted")).toBe(false);
  });

  test("accepts only the trusted extension origin or a non-browser native client", () => {
    expect(isAllowedRuntimeSocketOrigin("/api/browser/native", "chrome-extension://trusted", "chrome-extension://trusted")).toBe(true);
    expect(isAllowedRuntimeSocketOrigin("/api/browser/native", null, "chrome-extension://trusted")).toBe(true);
    expect(isAllowedRuntimeSocketOrigin("/", null, "chrome-extension://trusted")).toBe(true);
  });
});
