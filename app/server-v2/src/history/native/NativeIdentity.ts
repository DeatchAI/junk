import { homedir } from "node:os";
import { join, resolve } from "node:path";
import { realpathSync } from "node:fs";
import type { AgentKind } from "../../protocol/messages";
import { sourceKey } from "../../imports/Transcript";

export function providerHistoryRoot(provider: AgentKind) {
  const home = homedir();
  if (provider === "codex") return Bun.env.CODEX_HOME || join(home, ".codex");
  if (provider === "claude") return join(Bun.env.CLAUDE_CONFIG_DIR || join(home, ".claude"), "projects");
  if (provider === "opencode") return Bun.env.XDG_DATA_HOME || join(home, ".local", "share");
  if (provider === "pi") return Bun.env.PI_CODING_AGENT_SESSION_DIR || join(Bun.env.PI_CODING_AGENT_DIR || join(home, ".pi", "agent"), "sessions");
  if (provider === "omp") return join(Bun.env.OMP_AGENT_DIR || join(home, ".omp", "agent"), "sessions");
  return resolve(home, `.${provider}`);
}
export function nativeSourceKey(provider: AgentKind, id: string, namespace?: string) {
  let root = namespace ?? providerHistoryRoot(provider);
  try { root = realpathSync(root); } catch { root = resolve(root); }
  return sourceKey(provider, root, id);
}
export const nativeConversationID = (sourceKey: string) => `native_${sourceKey}`;
export const isNativeID = (id: string) => /^native_[a-f0-9]{64}$/.test(id);
