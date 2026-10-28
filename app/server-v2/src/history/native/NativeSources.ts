import { CodexImportSource } from "../../imports/CodexImportSource";
import { ClaudeImportSource } from "../../imports/ClaudeImportSource";
import { OpenCodeImportSource } from "../../imports/OpenCodeImportSource";
import type { ImportSource } from "../../imports/ImportTypes";
import { FileSessionSource } from "./FileSessionSource";
import { ACPHistorySource } from "./ACPHistorySource";
import { AmpHistorySource } from "./AmpHistorySource";

export function nativeHistorySources(): ImportSource[] {
  const sources: ImportSource[] = [new CodexImportSource(), new ClaudeImportSource(), new OpenCodeImportSource(), new FileSessionSource("pi"),
    new FileSessionSource("omp"), new AmpHistorySource(), new ACPHistorySource("fx"), new ACPHistorySource("grok")];
  const configured = Bun.env.DETACH_HISTORY_PROVIDERS?.split(",").map((id) => id.trim());
  return configured ? sources.filter((source) => configured.includes(source.provider)) : sources;
}
