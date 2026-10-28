import type { AgentKind } from "../protocol/messages";
import { claudeModels, discoverCodexModels, discoverFxModels, discoverGrokModels, discoverOpenCodeModels } from "../runtime/CapabilityDetector";
import { discoverAdditionalAgents } from "../runtime/providers/AdditionalAgents";
import type { TitleModelCatalog } from "./TitleModels";

export async function titleCatalog(
  agent: AgentKind, executable: string | undefined,
): Promise<TitleModelCatalog> {
  if (!executable) return { models: [] };
  switch (agent) {
    case "claude": return { models: claudeModels };
    case "codex": return { models: await discoverCodexModels(executable) };
    case "grok": return discoverGrokModels(executable);
    case "fx": return discoverFxModels(executable);
    case "opencode": return discoverOpenCodeModels(executable);
    default:
      return (await discoverAdditionalAgents(async () => executable, agent))[0] ?? { models: [] };
  }
}
