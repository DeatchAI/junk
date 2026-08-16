import type {
  MediaConfigOption,
  MediaAsset,
  MediaInputRequest,
  MediaJob,
  MediaModelCapability,
} from "../protocol/messages";
import { HostedModelSessionManager } from "./HostedModelSessionManager";

interface HostedMediaManagerOptions {
  pollIntervalMs?: number;
}

export class HostedMediaManager {
  private readonly pollIntervalMs: number;

  constructor(
    private readonly sessions: HostedModelSessionManager,
    options: HostedMediaManagerOptions = {},
  ) {
    this.pollIntervalMs = options.pollIntervalMs ?? 3_000;
  }

  async models(): Promise<MediaModelCapability[]> {
    const response = await this.sessions.authenticatedRequest("/media/models", {
      cache: "no-store",
    });
    const payload = await parseJSON(response);
    if (!response.ok) throw new Error(errorMessage(payload, "Unable to load media models."));
    return parseModels(objectValue(payload).models);
  }

  async quote(input: {
    model: string;
    prompt: string;
    config: Record<string, unknown>;
    inputs: Array<{ uploadId: string; role: string }>;
  }) {
    const response = await this.sessions.authenticatedRequest("/media/quote", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(input),
      cache: "no-store",
    });
    const payload = await parseJSON(response);
    if (!response.ok) throw new Error(errorMessage(payload, "Unable to quote this generation."));
    const quote = objectValue(objectValue(payload).quote);
    return {
      kieCredits: stringValue(quote.kieCredits),
      detachCredits: stringValue(quote.detachCredits),
      summary: stringValue(quote.summary),
    };
  }

  async create(input: {
    requestKey: string;
    model: string;
    prompt: string;
    config: Record<string, unknown>;
    inputs: MediaInputRequest[];
  }) {
    const uploaded = await Promise.all(input.inputs.map(async (mediaInput) => ({
      uploadId: await this.upload(mediaInput),
      role: mediaInput.role,
    })));
    const response = await this.sessions.authenticatedRequest("/media/jobs", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        requestKey: input.requestKey,
        model: input.model,
        prompt: input.prompt,
        config: input.config,
        inputs: uploaded,
      }),
      cache: "no-store",
    });
    const payload = await parseJSON(response);
    if (!response.ok) throw new Error(errorMessage(payload, "Unable to start media generation."));
    return parseJob(objectValue(payload).job);
  }

  async get(jobId: string) {
    const response = await this.sessions.authenticatedRequest(`/media/jobs/${jobId}`, {
      cache: "no-store",
    });
    const payload = await parseJSON(response);
    if (!response.ok) throw new Error(errorMessage(payload, "Unable to refresh generated media."));
    return parseJob(objectValue(payload).job);
  }

  async waitForCompletion(
    initial: MediaJob,
    onUpdate: (job: MediaJob) => void,
    signal?: AbortSignal,
  ) {
    let job = initial;
    onUpdate(job);
    while (!terminalState(job.state)) {
      await delay(this.pollIntervalMs, signal);
      job = await this.get(job.id);
      onUpdate(job);
    }
    return job;
  }

  private async upload(input: MediaInputRequest) {
    const file = Bun.file(input.path);
    if (!(await file.exists())) throw new Error(`Attachment not found: ${input.path}`);
    const form = new FormData();
    form.set("file", file, input.path.split("/").pop() ?? "media");
    const response = await this.sessions.authenticatedRequest("/media/uploads", {
      method: "POST",
      body: form,
      cache: "no-store",
    });
    const payload = await parseJSON(response);
    if (!response.ok) throw new Error(errorMessage(payload, "Unable to upload the media reference."));
    const id = stringValue(objectValue(objectValue(payload).upload).id);
    if (!id) throw new Error("Media upload returned an invalid identifier.");
    return id;
  }
}

function parseModels(value: unknown): MediaModelCapability[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((candidate) => {
    const model = objectValue(candidate);
    const id = stringValue(model.id);
    const displayName = stringValue(model.displayName);
    const kind = model.kind === "image" || model.kind === "video" ? model.kind : undefined;
    if (!id || !displayName || !kind) return [];
    return [{
      id,
      displayName,
      kind,
      description: stringValue(model.description),
      aspectRatios: parseOptions(model.aspectRatios),
      resolutions: parseOptions(model.resolutions),
      durations: Array.isArray(model.durations)
        ? model.durations.filter((item): item is number => typeof item === "number")
        : undefined,
      supportsAudio: model.supportsAudio === true,
      outputFormats: parseOptions(model.outputFormats),
      defaults: objectValue(model.defaults),
      inputRoles: Array.isArray(model.inputRoles)
        ? model.inputRoles.filter((item): item is string => typeof item === "string")
        : [],
      maxInputs: typeof model.maxInputs === "number" ? model.maxInputs : 0,
      maxInputsByRole: Object.entries(objectValue(model.maxInputsByRole)).reduce<Record<string, number>>((result, [role, limit]) => {
        if (typeof limit === "number" && Number.isInteger(limit) && limit > 0) result[role] = limit;
        return result;
      }, {}),
    }];
  });
}

function parseOptions(value: unknown): MediaConfigOption[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((candidate) => {
    const option = objectValue(candidate);
    const id = stringValue(option.id);
    const label = stringValue(option.label);
    return id && label ? [{ id, label }] : [];
  });
}

function parseJob(value: unknown): MediaJob {
  const job = objectValue(value);
  const id = stringValue(job.id);
  const kind = job.kind === "image" || job.kind === "video" ? job.kind : undefined;
  const model = stringValue(job.model);
  const state = stringValue(job.state);
  if (!id || !kind || !model || !state) throw new Error("Detach Cloud media returned an invalid job.");
  return {
    id,
    kind,
    model,
    state,
    progress: typeof job.progress === "number" ? job.progress : 0,
    prompt: stringValue(job.prompt),
    config: objectValue(job.config),
    quote: parseCredits(job.quote),
    actual: parseCredits(job.actual),
    error: parseError(job.error),
    assets: Array.isArray(job.assets) ? job.assets.flatMap(parseAsset) : [],
    createdAt: stringValue(job.createdAt),
    updatedAt: stringValue(job.updatedAt),
  };
}

function parseAsset(value: unknown): MediaAsset[] {
  const asset = objectValue(value);
  const id = stringValue(asset.id);
  const kind = asset.kind === "image" || asset.kind === "video" ? asset.kind : undefined;
  const mimeType = stringValue(asset.mimeType);
  const url = stringValue(asset.url);
  if (!id || !kind || !mimeType || !url) return [];
  return [{
    id,
    kind,
    mimeType,
    url,
    byteSize: typeof asset.byteSize === "number" ? asset.byteSize : undefined,
    width: typeof asset.width === "number" ? asset.width : undefined,
    height: typeof asset.height === "number" ? asset.height : undefined,
    durationSeconds: typeof asset.durationSeconds === "number" ? asset.durationSeconds : undefined,
  }];
}

function parseCredits(value: unknown) {
  const credits = objectValue(value);
  const kieCredits = stringValue(credits.kieCredits);
  const detachCredits = stringValue(credits.detachCredits);
  return kieCredits && detachCredits ? { kieCredits, detachCredits } : undefined;
}

function parseError(value: unknown) {
  const error = objectValue(value);
  const code = stringValue(error.code);
  const message = stringValue(error.message);
  return code && message ? { code, message } : undefined;
}

function terminalState(value: string) {
  return value === "succeeded" || value === "failed" || value === "reconciliation_required";
}

function objectValue(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  return value as Record<string, unknown>;
}

function stringValue(value: unknown) {
  return typeof value === "string" && value.trim() ? value.trim() : undefined;
}

async function parseJSON(response: Response) {
  return response.json().catch(() => undefined);
}

function errorMessage(value: unknown, fallback: string) {
  const root = objectValue(value);
  return stringValue(objectValue(root.error).message) ?? fallback;
}

function delay(ms: number, signal?: AbortSignal) {
  return new Promise<void>((resolve, reject) => {
    if (signal?.aborted) {
      reject(signal.reason);
      return;
    }
    const timeout = setTimeout(resolve, ms);
    signal?.addEventListener("abort", () => {
      clearTimeout(timeout);
      reject(signal.reason);
    }, { once: true });
  });
}
