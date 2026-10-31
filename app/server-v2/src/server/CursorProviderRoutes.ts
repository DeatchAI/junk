import { cursorProviderCredentials } from "../runtime/providers/CursorProviderCredentials";
import { findExecutable } from "../runtime/CapabilityDetector";
import { processEnv } from "../runtime/ProcessRunner";
import { jsonResponse } from "./RuntimeHelpers";

export async function cursorProviderCredentialResponse(request: Request) {
  if (request.method === "DELETE") {
    cursorProviderCredentials.setApiKey(undefined);
    return jsonResponse({ ok: true, hasApiKey: false });
  }
  if (request.method !== "PUT") {
    return jsonResponse({ ok: false, error: "Method not allowed" }, 405);
  }

  try {
    const body = await request.json() as { apiKey?: unknown };
    cursorProviderCredentials.setApiKey(body.apiKey);
    return jsonResponse({ ok: true, hasApiKey: Boolean(cursorProviderCredentials.apiKey) });
  } catch (error) {
    return jsonResponse({ ok: false, error: error instanceof Error ? error.message : "Invalid request" }, 400);
  }
}

export async function cursorProviderLoginResponse(request: Request) {
  if (request.method !== "POST") return jsonResponse({ ok: false, error: "Method not allowed" }, 405);
  const executable = await findExecutable("cursor");
  if (!executable) return jsonResponse({ ok: false, error: "Install Cursor CLI before signing in." }, 404);

  try {
    const env = processEnv();
    delete env.CURSOR_API_KEY;
    const child = Bun.spawn([executable, "login"], {
      stdin: "ignore",
      stdout: "ignore",
      stderr: "ignore",
      env,
    });
    child.unref();
    return jsonResponse({ ok: true });
  } catch {
    return jsonResponse({ ok: false, error: "Could not start Cursor CLI sign-in." }, 500);
  }
}
