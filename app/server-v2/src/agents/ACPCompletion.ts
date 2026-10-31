/** Progress commentary and a successful tool result are not a completed agent answer. */
export function assertACPCompletion(value: unknown, hasText: boolean, hasTools: boolean, textAfterLastTool: boolean) {
  const reason = value && typeof value === "object" ? (value as Record<string, unknown>).stopReason : undefined;
  if (reason && reason !== "end_turn") {
    const detail = reason === "cancelled" ? "The agent task was cancelled."
      : reason === "max_tokens" || reason === "max_turn_requests" ? "The agent reached its response limit."
      : reason === "refusal" ? "The agent declined to continue this task."
      : "The agent stopped before completing its response.";
    throw new Error(`${detail} The saved conversation remains available for a follow-up.`);
  }
  if (!hasText || hasTools && !textAfterLastTool) {
    throw new Error(hasTools
      ? "The agent completed its tool call but returned no final response. The saved conversation remains available; continue this chat to resume."
      : "The agent completed without returning a response.");
  }
}
