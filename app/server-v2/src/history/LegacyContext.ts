import type { ConversationContextMessage, Message } from "../protocol/messages";

/** Only for an explicit legacy-to-native continuation, never native session replay. */
export function legacyContext(messages: Message[]): ConversationContextMessage[] {
  const selected: ConversationContextMessage[] = [];
  let remaining = 48_000;
  for (const message of [...messages].reverse()) {
    if (selected.length >= 24 || remaining <= 0) break;
    const content = message.content.trim().slice(0, Math.min(8000, remaining));
    if (!content) continue;
    selected.push({ role: message.role, content }); remaining -= content.length;
  }
  return selected.reverse();
}
