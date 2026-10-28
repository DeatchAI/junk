import { mkdtempSync, rmSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import { findExecutable } from "../runtime/CapabilityDetector";
import { runProcess } from "../runtime/ProcessRunner";
import { withTimeout } from "../agents/CliAdapterUtils";
import type { TitleRequest } from "./ConversationTitleService";
import { titleCatalog } from "./TitleCatalog";
import { chooseTitleModel } from "./TitleModels";
import { titleCommand, AMP_TITLE_SETTINGS } from "./TitleCommands";
import { cleanTitle, readTitleOutput, titlePrompt } from "./TitleText";

/** Serial auxiliary inference bounds CPU and provider load independently of chat runs. */
interface TitleGeneratorOptions {
  find?: typeof findExecutable;
  catalog?: typeof titleCatalog;
  run?: typeof runProcess;
  timeoutMs?: number;
  standardCodex?: () => Promise<boolean>;
}

export class TitleGenerator {
  private queue: Promise<unknown> = Promise.resolve();
  constructor(private readonly options: TitleGeneratorOptions = {}) {}

  generate(request: TitleRequest): Promise<string | undefined> {
    const job = this.queue.then(async () => {
      const abort = new AbortController();
      try { return await withTimeout(this.complete(request, abort.signal), this.options.timeoutMs ?? 40_000, () => abort.abort()); }
      finally { abort.abort(); }
    }).catch(() => undefined);
    this.queue = job;
    return job;
  }

  private async complete(request: TitleRequest, signal: AbortSignal) {
    if (request.agent === "fx") return;
    // Keep a custom Codex backend from silently switching to the default provider.
    if (request.agent === "codex" && !await (this.options.standardCodex ?? standardCodexConnection)()) return;
    const executable = await (this.options.find ?? findExecutable)(request.agent);
    if (!executable) return;
    const catalog = await (this.options.catalog ?? titleCatalog)(request.agent, executable);
    if (signal.aborted) return;
    const selected = chooseTitleModel(request.agent, request.model, catalog);
    const prompt = titlePrompt(request.message);
    const directory = mkdtempSync(join(tmpdir(), "detach-title-"));
    let child: ReturnType<typeof runProcess> | undefined;
    try {
      const files = { prompt: join(directory, "prompt.txt"), ampSettings: join(directory, "amp.json") };
      await Bun.write(files.prompt, prompt);
      if (request.agent === "amp") await Bun.write(files.ampSettings, JSON.stringify(AMP_TITLE_SETTINGS));
      const command = titleCommand(request.agent, selected.model, selected.effort, prompt, files);
      if (!command) return;
      child = (this.options.run ?? runProcess)({ command: executable!, cwd: directory, ...command,
        env: { NO_COLOR: "1", ...command.env } });
      signal.addEventListener("abort", () => child?.cancel(), { once: true });
      const result = await withTimeout(child.finished, 25_000, () => child?.cancel());
      if (result.exitCode !== 0 || result.stdout.length > 32_000) return;
      return readTitleOutput(result.stdout);
    } finally {
      child?.cancel();
      rmSync(directory, { recursive: true, force: true });
    }
  }

}

async function standardCodexConnection() {
  const file = Bun.file(join(Bun.env.CODEX_HOME || join(homedir(), ".codex"), "config.toml"));
  if (!await file.exists()) return true;
  try {
    const config = Bun.TOML.parse(await file.text()) as Record<string, any>;
    const profile = config.profiles?.[config.profile] ?? {};
    const provider = profile.model_provider ?? config.model_provider ?? "openai";
    return provider === "openai" && !config.model_providers?.openai?.base_url;
  } catch { return false; }
}
