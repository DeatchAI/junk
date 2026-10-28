import { findExecutable } from "../runtime/CapabilityDetector";
import { CodexHistoryRPC } from "../imports/ReadOnlyProcess";
import { withTimeout } from "../agents/CliAdapterUtils";

interface UsageWindow {
  agent: "codex";
  bucket: string;
  modelIDs: string[] | null;
  usedPercent: number;
  resetsAt: number | null;
}
export interface UsageSnapshot { checkedAt: number; windows: UsageWindow[]; notices: string[] }
interface UsageRPC { initialize(): Promise<unknown>; request(method: string, params: unknown): Promise<unknown>; close(): void }
const object = (value: unknown): Record<string, unknown> => value && typeof value === "object" && !Array.isArray(value)
  ? value as Record<string, unknown> : {};

export function codexUsageWindows(value: unknown): UsageWindow[] {
  const response = object(value);
  const byID = object(response.rateLimitsByLimitId);
  const buckets = Object.keys(byID).length ? Object.entries(byID) : [["codex", response.rateLimits] as const];
  const windows: UsageWindow[] = [];
  for (const [key, value] of buckets) {
    const bucket = object(value);
    const bucketID = typeof bucket.limitId === "string" ? bucket.limitId : key;
    for (const name of ["primary", "secondary"]) {
      const window = object(bucket[name]);
      if (typeof window.usedPercent !== "number" || !Number.isFinite(window.usedPercent) || window.usedPercent < 0 || window.usedPercent > 100) continue;
      windows.push({ agent: "codex", bucket: `${bucketID}:${name}`,
        // Named buckets have no reliable model mapping in this interface.
        modelIDs: bucketID === "codex" ? null : [], usedPercent: window.usedPercent,
        resetsAt: typeof window.resetsAt === "number" && Number.isFinite(window.resetsAt) ? window.resetsAt : null });
    }
  }
  return windows;
}

export class ProviderUsageService {
  private cached?: UsageSnapshot;
  private pending?: Promise<UsageSnapshot>;
  constructor(private readonly connect: () => Promise<UsageRPC | undefined> = async () => {
    const executable = await findExecutable("codex");
    return executable ? new CodexHistoryRPC(executable) : undefined;
  }) {}

  get(): Promise<UsageSnapshot> {
    if (this.cached && Date.now() / 1000 - this.cached.checkedAt < 60) return Promise.resolve(this.cached);
    if (this.pending) return this.pending;
    this.pending = this.read().then(snapshot => { this.cached = snapshot; return snapshot; })
      .finally(() => { this.pending = undefined; });
    return this.pending;
  }

  private async read(): Promise<UsageSnapshot> {
    let rpc: UsageRPC | undefined;
    let windows: UsageWindow[] = [];
    const notices = ["Usage limits for providers without a supported read interface are unknown."];
    try {
      rpc = await this.connect();
      if (rpc) {
        const connection = rpc;
        const result = await withTimeout((async () => {
          await connection.initialize();
          return connection.request("account/rateLimits/read", {});
        })(), 2500, () => connection.close());
        windows = codexUsageWindows(result);
      }
      if (!windows.length) notices.push("Codex usage limits are unavailable for this account or CLI version.");
    } catch { notices.push("Codex usage limits could not be refreshed."); }
    finally { rpc?.close(); }
    return { checkedAt: Date.now() / 1000, windows, notices };
  }
}

/** RuntimeServer validates the per-launch bearer token before dispatch. */
export async function providerUsageResponse(request: Request, service: Pick<ProviderUsageService, "get">) {
  const headers = { "Cache-Control": "no-store" };
  if (request.headers.has("origin")) return Response.json({ error: "Browser usage access is not allowed." }, { status: 403, headers });
  if (request.method !== "GET") return Response.json({ error: "Use GET to read provider limits." }, { status: 405, headers });
  return Response.json(await service.get(), { headers });
}
