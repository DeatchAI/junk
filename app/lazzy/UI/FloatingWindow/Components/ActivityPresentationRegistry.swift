import SwiftUI

struct ActivityPresentation {
  let iconAsset: String?
  let title: String
  let subtitle: String?
  let isGeneric: Bool
}

enum ActivityPresentationRegistry {
  static func presentation(
    status: String,
    event: AgentActivityEvent?,
    toolName: String?
  ) -> ActivityPresentation {
    let title = event?.title.nonEmpty ?? status
    let action = event?.action ?? inferredAction(
      kind: event?.kind,
      title: title,
      toolName: event?.toolName ?? toolName
    )
    let isGeneric = action == "prepare" || action == "think" || action == "generic"

    return ActivityPresentation(
      iconAsset: isGeneric ? nil : iconAsset(for: action),
      title: title,
      subtitle: visibleSubtitle(event?.subtitle, title: title),
      isGeneric: isGeneric
    )
  }

  private static func iconAsset(for action: String) -> String {
    switch action {
    case "plan": return "activity-plan"
    case "search": return "activity-search"
    case "read": return "activity-file-search"
    case "create": return "activity-file-plus"
    case "edit": return "activity-file-edit"
    case "delete": return "activity-trash"
    case "terminal": return "activity-terminal"
    case "build": return "activity-build"
    case "test": return "activity-test"
    case "browser.navigate": return "activity-compass"
    case "browser.inspect": return "activity-scan-search"
    case "browser.interact": return "activity-pointer"
    case "browser.type": return "activity-keyboard"
    case "browser.capture": return "activity-camera"
    case "desktop.inspect": return "activity-monitor-search"
    case "desktop.interact": return "activity-monitor-pointer"
    case "image": return "activity-image"
    case "credential": return "activity-fingerprint"
    case "approval": return "activity-shield"
    case "wait": return "activity-clock"
    case "error": return "activity-warning"
    default: return "activity-plug"
    }
  }

  private static func inferredAction(
    kind: String?,
    title: String,
    toolName: String?
  ) -> String {
    if let toolName {
      let lower = toolName.lowercased()
      if lower.contains("secret") || lower.contains("credential") { return "credential" }
      if lower.contains("browser") { return "browser.inspect" }
      if lower.contains("macos") || lower.contains("desktop") { return "desktop.interact" }
      if lower.contains("search") || lower.contains("grep") { return "search" }
      if lower.contains("read") || lower.contains("list") { return "read" }
      if lower.contains("image") || lower.contains("screenshot") { return "image" }
      if lower.contains("terminal") || lower.contains("bash") || lower.contains("command") {
        return "terminal"
      }
    }

    switch kind {
    case "attachment": return "image"
    case "file_change": return inferredFileAction(title)
    case "command": return inferredCommandAction(title)
    case "plan": return "plan"
    case "error": return "error"
    case "mcp_tool": return "connector"
    case "lifecycle", "status": return inferredGenericAction(title)
    default: return inferredGenericAction(title)
    }
  }

  private static func inferredFileAction(_ title: String) -> String {
    let lower = title.lowercased()
    if lower.contains("creat") || lower.contains("add") { return "create" }
    if lower.contains("delet") || lower.contains("remov") { return "delete" }
    return "edit"
  }

  private static func inferredCommandAction(_ title: String) -> String {
    let lower = title.lowercased()
    if lower.contains("test") || lower.contains("validat") || lower.contains("verify") {
      return "test"
    }
    if lower.contains("build") || lower.contains("compil") || lower.contains("packag") {
      return "build"
    }
    if lower.contains("search") || lower.contains("find") { return "search" }
    if lower.contains("read") || lower.contains("review") { return "read" }
    return "terminal"
  }

  private static func inferredGenericAction(_ title: String) -> String {
    let lower = title.lowercased()
    if lower.contains("prepar") || lower.contains("connect") || lower.contains("start") {
      return "prepare"
    }
    if lower.contains("think") || lower.contains("working") { return "think" }
    if lower.contains("wait") { return "wait" }
    if lower.contains("error") || lower.contains("fail") { return "error" }
    return "generic"
  }

  private static func visibleSubtitle(_ subtitle: String?, title: String) -> String? {
    guard let subtitle = subtitle?.trimmingCharacters(in: .whitespacesAndNewlines),
      !subtitle.isEmpty,
      subtitle.caseInsensitiveCompare(title) != .orderedSame,
      subtitle.count <= 120
    else {
      return nil
    }

    let lower = subtitle.lowercased()
    if lower.hasPrefix("detach_") || lower.hasPrefix("mcp__") || lower.contains("_tools") {
      return nil
    }
    if ["started", "in_progress", "completed", "success"].contains(lower) {
      return nil
    }
    return subtitle
  }
}

private extension String {
  var nonEmpty: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
