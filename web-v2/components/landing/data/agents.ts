export const agents = [
  { id: "codex", name: "Codex", models: ["GPT-6.1 Sol", "GPT-6 Sol", "Default"] },
  { id: "claude", name: "Claude", models: ["Sonnet", "Opus", "Default"] },
  { id: "opencode", name: "OpenCode", models: ["Default", "Sonnet", "GPT-6.1 Sol"] },
  { id: "pi", name: "Pi", models: ["Default", "Sonnet"] },
  { id: "omp", name: "Omp", models: ["Default", "Sonnet"] },
  { id: "amp", name: "Amp", models: ["Default", "Smart"] },
  { id: "grok", name: "Grok", models: ["Default", "Grok"] },
] as const;

