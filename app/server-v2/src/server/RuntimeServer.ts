import { PORT, RUNTIME_TOKEN, agentQuestions, capabilityBroker, browserAutomation, desktopBridge, composio, BROWSER_EXTENSION_ORIGIN, browserBridge, appClients, secretBridge, activeRuns, nativeHistory, gitReview } from "./RuntimeContext";
import { isAuthorizedRuntimeRequest, isAllowedRuntimeSocketOrigin } from "../runtime/RuntimeAuth";
import { jsonResponse, capabilities, isBrowserNativeSocket, log } from "./RuntimeHelpers";
import { resolvePermissionsForSocket } from "./RuntimeApprovals";
import { handleMessage } from "./RuntimeMessages";
import { closeHistoryProcesses } from "../imports/ReadOnlyProcess";
import { historyCatalogResponse, historyConversationResponse } from "./HistoryHTTPRoute";
import { historyCacheResponse } from "./HistoryCacheRoute";
import { ProviderUsageService, providerUsageResponse } from "../routing/ProviderUsage";
import { gitResponse } from "./GitRoutes";
import { cursorProviderCredentialResponse, cursorProviderLoginResponse } from "./CursorProviderRoutes";

const providerUsage = new ProviderUsageService();


export const server = Bun.serve<{ kind: "app" | "browser-native" }>({
  port: PORT,
  hostname: "127.0.0.1",
  async fetch(req, server) {
    const url = new URL(req.url);

    if (!isAuthorizedRuntimeRequest(req, url, RUNTIME_TOKEN)) {
      return jsonResponse({ error: "Unauthorized local runtime request" }, 401);
    }

    if (url.pathname === "/api/providers/cursor/api-key") {
      return cursorProviderCredentialResponse(req);
    }
    if (url.pathname === "/api/providers/cursor/login") {
      return cursorProviderLoginResponse(req);
    }

    if (url.pathname === "/api/agent-usage") {
      return providerUsageResponse(req, providerUsage);
    }

    if (url.pathname.startsWith("/api/git/")) {
      server.timeout(req, 120);
      return gitResponse(req, gitReview);
    }

    if (url.pathname === "/api/history/cache") {
      return historyCacheResponse(req, nativeHistory);
    }

    if (url.pathname === "/api/history/conversation") {
      server.timeout(req, 120);
      return historyConversationResponse(req, url, nativeHistory);
    }

    if (url.pathname === "/api/history/conversations") {
      return historyCatalogResponse(req, url, nativeHistory);
    }

    if (url.pathname === "/api/capabilities") {
      return jsonResponse(await capabilities());
    }

    if (url.pathname === "/api/agent/questions" && req.method === "POST") {
      server.timeout(req, 0);
      try {
        const body = await req.json() as { runId?: string; questions?: unknown };
        const answers = await agentQuestions.ask(body.runId ?? "", body);
        return jsonResponse({ ok: true, result: { answers, cancelled: answers === null } });
      } catch (error) {
        return jsonResponse({ ok: false, error: error instanceof Error ? error.message : String(error) }, 400);
      }
    }

    if (url.pathname === "/api/agent/capabilities" && req.method === "GET") {
      try {
        return jsonResponse({
          ok: true,
          capabilities: await capabilityBroker.list(url.searchParams.get("query") ?? undefined),
        });
      } catch (error) {
        return jsonResponse({ ok: false, error: error instanceof Error ? error.message : String(error) }, 400);
      }
    }

    if (url.pathname === "/api/agent/capabilities/describe" && req.method === "POST") {
      try {
        const body = await req.json() as { capabilityId?: string };
        return jsonResponse({ ok: true, result: await capabilityBroker.describe(body.capabilityId ?? "") });
      } catch (error) {
        return jsonResponse({ ok: false, error: error instanceof Error ? error.message : String(error) }, 400);
      }
    }

    if (url.pathname === "/api/agent/capabilities/invoke" && req.method === "POST") {
      try {
        const body = await req.json() as {
          capabilityId?: string;
          toolName?: string;
          arguments?: Record<string, unknown>;
          runId?: string;
        };
        return jsonResponse({
          ok: true,
          result: await capabilityBroker.invoke({
            capabilityId: body.capabilityId ?? "",
            toolName: body.toolName ?? "",
            arguments: body.arguments,
            runId: body.runId,
          }),
        });
      } catch (error) {
        return jsonResponse({ ok: false, error: error instanceof Error ? error.message : String(error) }, 400);
      }
    }

    if (url.pathname === "/api/browser/status" && req.method === "GET") {
      return jsonResponse(await browserAutomation.getStatus());
    }

    if (url.pathname === "/api/browser/artifacts" && req.method === "GET") {
      const runId = url.searchParams.get("runId")?.trim();
      if (!runId) return jsonResponse({ ok: false, error: "runId is required" }, 400);
      return jsonResponse({ ok: true, ...browserAutomation.getArtifacts(runId) });
    }

    if (url.pathname === "/api/browser/command" && req.method === "POST") {
      try {
        const body = await req.json() as { command?: string; payload?: Record<string, unknown>; runId?: string };
        const result = await browserAutomation.execute({
          command: body.command ?? "",
          payload: body.payload ?? {},
        }, body.runId);
        return jsonResponse({ ok: true, result });
      } catch (error) {
        return jsonResponse({ ok: false, error: error instanceof Error ? error.message : String(error) }, 400);
      }
    }

    if (url.pathname === "/api/desktop/status" && req.method === "GET") {
      return jsonResponse(desktopBridge.getStatus());
    }

    if (url.pathname === "/api/desktop/command" && req.method === "POST") {
      try {
        const body = await req.json() as { command?: string; payload?: Record<string, unknown>; runId?: string };
        const result = await desktopBridge.execute({
          command: body.command ?? "",
          payload: body.payload ?? {},
          runId: body.runId,
        });
        return jsonResponse({ ok: true, result });
      } catch (error) {
        return jsonResponse({ ok: false, error: error instanceof Error ? error.message : String(error) }, 400);
      }
    }

    if (url.pathname === "/api/secrets/command" && req.method === "POST") {
      try {
        const body = await req.json() as { command?: "search" | "use"; payload?: Record<string, unknown> };
        const result = await capabilityBroker.executeSecretCommand(body.command ?? "", body.payload ?? {});
        return jsonResponse({ ok: true, result });
      } catch (error) {
        return jsonResponse({ ok: false, error: error instanceof Error ? error.message : String(error) }, 400);
      }
    }

    if (url.pathname === "/api/sync-profile" && req.method === "POST") {
      const body = await req.json().catch(() => undefined) as { accessToken?: unknown } | undefined;
      const hostedControlPlane = {
        endpoint: Bun.env.DETACH_HOSTED_CONTROL_PLANE_URL,
        accessToken: typeof body?.accessToken === "string" ? body.accessToken : undefined,
      };
      // Optional Composio integrations use the signed-in profile sync.
      // The Composio project key stays on the hosted control plane; this local
      // runtime receives only the user's bearer token and MCP session details.
      composio.configureHostedControlPlane(hostedControlPlane);
      const composioAvailable = await composio.refreshAccess({ force: true });
      return jsonResponse({ success: true, composioAvailable });
    }

    if (url.pathname === "/api/usage" && req.method === "GET") {
      const nextReset = new Date();
      nextReset.setMonth(nextReset.getMonth() + 1);

      return jsonResponse({
        creditsUsed: 0,
        creditLimit: 1_000_000,
        isUnlimited: true,
        planType: "local",
        nextResetDate: nextReset.toISOString(),
        hasBYOKAccess: false,
        requiresBYOK: false,
        hasAllModels: true,
        allowedModels: ["Codex", "Claude", "Grok"],
      });
    }

    if (url.pathname === "/api/browser/native") {
      const origin = req.headers.get("origin");
      if (!isAllowedRuntimeSocketOrigin(url.pathname, origin, BROWSER_EXTENSION_ORIGIN)) {
        return jsonResponse({ error: "Browser bridge origin is not allowed" }, 403);
      }
      if (server.upgrade(req, { data: { kind: "browser-native" } })) {
        return;
      }
    }

    // URLSession does not send an Origin header. Browsers do, so reject any
    // browser-originated attempt to attach as the privileged app socket.
    if (!isAllowedRuntimeSocketOrigin(url.pathname, req.headers.get("origin"), BROWSER_EXTENSION_ORIGIN)) {
      return jsonResponse({ error: "App WebSocket origin is not allowed" }, 403);
    }
    if (server.upgrade(req, { data: { kind: "app" } })) {
      return;
    }

    return jsonResponse({
      name: "Detach Runtime",
      version: "0.1.0",
      port: PORT,
    });
  },
  websocket: {
    open(ws) {
      if (isBrowserNativeSocket(ws)) {
        browserBridge.attachNativeSocket(ws);
        return;
      }
      desktopBridge.attachAppSocket(ws);
      appClients.add(ws);
      secretBridge.attachAppSocket(ws);
      if (autoSyncHistory) void nativeHistory.refresh();
      log("client connected");
    },
    close(ws) {
      if (browserBridge.isNativeSocket(ws)) {
        browserBridge.detachNativeSocket(ws);
        return;
      }
      desktopBridge.detachAppSocket(ws);
      appClients.delete(ws);
      secretBridge.detachAppSocket(ws);
      activeRuns.get(ws)?.cancel();
      activeRuns.delete(ws);
      resolvePermissionsForSocket(ws, false);
      agentQuestions.endSocket(ws);
      log("client disconnected");
    },
    async message(ws, raw) {
      if (browserBridge.isNativeSocket(ws)) {
        browserBridge.handleNativeMessage(raw.toString());
        return;
      }
      const desktopStop = (() => { try { return JSON.parse(raw.toString()) as { type?: string; runId?: string }; } catch { return undefined; } })();
      if (desktopStop?.type === "desktop_stop_requested" && desktopBridge.isAppSocket(ws)) {
        if (typeof desktopStop.runId === "string") desktopBridge.stopRun(desktopStop.runId);
        return;
      }
      await handleMessage(ws, raw.toString());
    },
  },
});

// Discovery never sends prompts. Tests opt in against isolated provider fixtures.
const autoSyncHistory = Bun.env.NODE_ENV !== "test" || Bun.env.DETACH_NATIVE_HISTORY_AUTO_SYNC === "1";
const historyPoll = setInterval(() => {
  if (autoSyncHistory && appClients.size) void nativeHistory.refresh();
}, 30_000);
historyPoll.unref();

log(`Detach runtime listening on ${PORT}`);


process.on("SIGINT", () => shutdown("SIGINT"));

process.on("SIGTERM", () => shutdown("SIGTERM"));


export let isShuttingDown = false;


export function shutdown(signal: string) {
  if (isShuttingDown) return;
  isShuttingDown = true;
  clearInterval(historyPoll);
  nativeHistory.stop();
  closeHistoryProcesses();
  log(`shutting down (${signal})`);
  void (async () => {
    await browserAutomation.stop();
    await server.stop(true);
    process.exit(0);
  })();
}
