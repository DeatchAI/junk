import type { AgentModelCapability } from "../protocol/messages";
import { asStringRecord, getString } from "./CliAdapterUtils";

function choices(value: unknown): { id: string; name: string }[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((entry) => {
    const item = asStringRecord(entry);
    if (Array.isArray(item?.options)) return choices(item.options);
    const id = getString(item?.value) ?? getString(item?.modelId);
    return id ? [{ id, name: getString(item?.name) || id }] : [];
  });
}

export function acpModelCatalog(session: Record<string, unknown>) {
  const configs = Array.isArray(session.configOptions) ? session.configOptions.map(asStringRecord) : [];
  const model = configs.find((option) => option?.category === "model" || option?.id === "model");
  const thinking = configs.find((option) => ["thought_level", "thinking", "effort"].includes(String(option?.category ?? option?.id)));
  const legacy = asStringRecord(session.models);
  const defaultModel = getString(model?.currentValue) ?? getString(legacy?.currentModelId);
  const efforts = choices(thinking?.options).map((option) => option.id);
  const models: AgentModelCapability[] = choices(model?.options ?? legacy?.availableModels).map((option) => ({
    id: option.id, displayName: option.name,
    ...(efforts.length && option.id === defaultModel ? { reasoningEfforts: efforts, reasoningLabel: "Thinking" } : {}),
  }));
  return { models, defaultModel };
}
