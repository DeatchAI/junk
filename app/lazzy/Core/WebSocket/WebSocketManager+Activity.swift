import Foundation
import Combine

extension WebSocketManager {
  func publishActivity(
    _ status: String,
    toolName: String?,
    event: AgentActivityEvent? = nil,
    runId: String? = nil,
    conversationId: String? = nil
  ) {
    // The runtime supplies the durable conversation ID before a long-running
    // task completes. Retain it here so the workspace can reopen the original
    // live composer instead of constructing a second, history-only panel.
    if let conversationId {
      currentConversationId = conversationId
    }

    let visibleStatus = event?.userFacing == false
      ? nil
      : visibleActivityStatus(status, event: event)
    if let visibleStatus {
      onActivityUpdate?(visibleStatus, toolName)
      activityListeners.forEach { $0(visibleStatus, toolName) }
    }

    // Keep provider lifecycle/debug events out of both user-facing activity surfaces.
    guard event?.userFacing != false,
      let islandStatus = visibleStatus ?? event?.subtitle ?? event?.title
    else { return }
    let update = AgentActivityUpdate(
      runId: runId ?? activeChatRequest?.runId,
      conversationId: conversationId ?? currentConversationId,
      status: islandStatus,
      toolName: toolName,
      event: event
    )
    onAgentActivityUpdate?(update)
    agentActivityListeners.forEach { $0(update) }
    print("📊 Activity: \(islandStatus)\(toolName != nil ? " (\(toolName!))" : "")")
  }


  func visibleActivityStatus(_ status: String, event: AgentActivityEvent? = nil) -> String? {
    let trimmed = status.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let combined = "\(trimmed) \(event?.title ?? "") \(event?.subtitle ?? "")".lowercased()
    if combined.contains("still working")
      || combined.contains("without a new")
      || combined.contains("no new event")
    {
      return "Working…"
    }
    if event?.action == "think" || combined.contains(" is thinking") {
      return "Thinking…"
    }
    if event?.action == "error" && [
      "network", "connection", "connect", "socket", "timed out", "timeout",
      "fetch failed", "econn", "enotfound", "dns", "temporary", "service unavailable",
      "bad gateway", "gateway timeout", "429", "502", "503", "504"
    ].contains(where: { combined.contains($0) }) {
      return "Retrying…"
    }

    let terminalPattern = #"\b(finished|complete|completed|done)\b"#
    if trimmed.range(of: terminalPattern, options: [.regularExpression, .caseInsensitive]) != nil {
      return nil
    }

    let lifecyclePatterns = [
      #"^Using\s+(Codex|Claude|Cursor|Grok|fx|OpenCode|Agent)\b"#,
      #"^Starting\s+(Codex|Claude|Cursor|Grok|fx|OpenCode)\b"#,
      #"^(Codex|Claude|Cursor|Grok|fx|OpenCode)\s+is\s+thinking\b"#,
      #"^(Codex|Claude|Cursor|Grok|fx|OpenCode)\s+is\s+still\s+working\b"#,
      #"^(Codex|Claude|Cursor|Grok|fx|OpenCode)\s+(thread|session)\s+started\b"#,
      #"^(Codex|Claude|Cursor|Grok|fx|OpenCode)\s+will\s+use\s+MCP\s+servers\b"#,
      #"^Loaded\s+\d+\s+MCP\s+server"#,
      #"^Thinking:\s*"#,
    ]

    if lifecyclePatterns.contains(where: {
      trimmed.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil
    }) {
      return nil
    }

    return trimmed
  }

}
