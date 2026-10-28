import { ProviderToolActivity } from "../../activity/ProviderToolActivity";
import type { AgentStreamCallbacks } from "../AgentAdapter";
import { asStringRecord, getString } from "../CliAdapterUtils";

export const AMP_MODES = ["low", "medium", "high", "ultra"] as const;

/** Amp sends whole assistant messages, not Claude's token-delta events. */
export class AmpStream {
  text = "";
  resultSeen = false;
  error?: string;
  private snapshots = new Map<string, string>();
  private readonly tools: ProviderToolActivity;
  constructor(private readonly callbacks: AgentStreamCallbacks) { this.tools = new ProviderToolActivity("amp", callbacks); }

  handle(value: unknown) {
    const event = asStringRecord(value);
    if (!event || event.parent_tool_use_id) return;
    if (event.type === "system" && event.subtype === "init") {
      const id = getString(event.session_id);
      if (id?.startsWith("T-")) this.callbacks.onSession?.({ id, workspacePath: getString(event.cwd), canResume: true });
    }
    if (event.type === "user") this.tools.blocks(asStringRecord(event.message)?.content);
    if (event.type === "assistant") {
      const message = asStringRecord(event.message);
      if (!Array.isArray(message?.content)) return;
      this.tools.blocks(message.content);
      const text = message.content.map((part) => {
        const block = asStringRecord(part);
        return block?.type === "text" ? getString(block.text) || "" : "";
      }).join("");
      const id = getString(message.id);
      const previous = id ? this.snapshots.get(id) || "" : "";
      this.emit(text.startsWith(previous) ? text.slice(previous.length) : text);
      if (id) this.snapshots.set(id, text);
    } else if (event.type === "result") {
      this.resultSeen = true;
      if (event.is_error === true || String(event.subtype).startsWith("error")) {
        this.error = getString(event.error) || "Amp could not finish this turn.";
      } else {
        const result = getString(event.result) || "";
        if (result && !this.text.endsWith(result)) this.emit(result);
      }
    } else if (event.type === "system" && String(event.subtype).startsWith("error")) {
      this.error = getString(event.error) || "Amp could not start this turn.";
    }
  }

  private emit(text: string) {
    if (!text) return;
    this.text += text;
    this.callbacks.onChunk(text);
  }
}
