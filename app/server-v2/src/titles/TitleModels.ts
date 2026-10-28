import type { AgentKind, AgentModelCapability } from "../protocol/messages";

export interface TitleModelCatalog { models: AgentModelCapability[]; defaultModel?: string }

/** Keep both the selected harness and any explicitly selected upstream vendor. */
export function chooseTitleModel(agent: AgentKind, selected: string | undefined, catalog: TitleModelCatalog) {
  const current = selected?.trim() || catalog.defaultModel;
  const vendor = modelVendor(current);
  const multiProvider = ["pi", "omp", "opencode"].includes(agent);
  const candidates = catalog.models.filter((model) =>
    !/(embed|image|video|audio|whisper|tts)/i.test(model.id)
    && (!multiProvider || (vendor ? modelVendor(model.id) === vendor : model.id === current)));
  const ranked = candidates.map((model) => ({ model, rank: lightweightRank(model.id) }))
    .filter(({ rank }) => rank < 100)
    .sort((a, b) => a.rank - b.rank || b.model.id.localeCompare(a.model.id, undefined, { numeric: true }));
  const model = ranked[0]?.model ?? candidates.find((model) => model.id === current);
  return {
    model: model?.id ?? current,
    effort: ["none", "off", "minimal", "low"].find((effort) => model?.reasoningEfforts?.includes(effort)),
  };
}

function modelVendor(id: string | undefined): string | undefined {
  if (!id) return;
  if (id.includes("/")) return id.split("/")[0];
  if (/^claude[-_]/i.test(id)) return "anthropic";
  if (/^(gpt[-_]|o[134][-_])/i.test(id)) return "openai";
  if (/^gemini[-_]/i.test(id)) return "google";
  if (/^grok[-_]/i.test(id)) return "xai";
}

function lightweightRank(id: string) {
  const name = id.toLowerCase();
  if (/(^|[/_-])(nano|haiku)([/_.-]|$)/.test(name)) return 0;
  if (/(^|[/_-])(mini|luna|flash-lite)([/_.-]|$)/.test(name)) return 1;
  if (/(^|[/_-])(flash|lite|small|smol|fast)([/_.-]|$)/.test(name)) return 2;
  if (["low", "rush"].includes(name)) return 3;
  return 100;
}
