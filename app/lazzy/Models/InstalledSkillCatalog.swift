import Foundation

/// Discovers user-installed skills that can be explicitly attached to a chat.
/// The runtime performs its own path validation before reading any selected file.
enum InstalledSkillCatalog {
  /// Skills installed by Detach itself live in an app-owned project workspace.
  /// Keeping this separate from the user's other agents makes install/remove
  /// behavior predictable and lets the runtime validate one dedicated root.
  static var appManagedSkillRoot: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/Detach/skill-workspace/.agents/skills", isDirectory: true)
  }

  static func discover() -> [SkillAttachment] {
    let fileManager = FileManager.default
    let home = fileManager.homeDirectoryForCurrentUser
    let roots = [
      appManagedSkillRoot,
      home.appendingPathComponent(".codex/skills", isDirectory: true),
      home.appendingPathComponent(".agents/skills", isDirectory: true),
    ]
    var found: [String: SkillAttachment] = [:]

    for root in roots where fileManager.fileExists(atPath: root.path) {
      guard let enumerator = fileManager.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles, .skipsPackageDescendants]
      ) else {
        continue
      }

      for case let url as URL in enumerator where url.lastPathComponent == "SKILL.md" {
        let path = url.standardizedFileURL.path
        let metadata = metadata(for: url)
        found[path] = SkillAttachment(
          id: path,
          name: metadata.name,
          path: path,
          summary: metadata.summary
        )
      }
    }

    return found.values.sorted {
      $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
  }

  static func isAppManaged(_ skill: SkillAttachment) -> Bool {
    let skillURL = URL(fileURLWithPath: skill.path).standardizedFileURL
    let rootURL = appManagedSkillRoot.standardizedFileURL
    let rootPath = rootURL.path.hasSuffix("/") ? rootURL.path : "\(rootURL.path)/"
    return skillURL.path.hasPrefix(rootPath)
  }

  private static func metadata(for url: URL) -> (name: String, summary: String?) {
    let fallbackName = url.deletingLastPathComponent().lastPathComponent
    guard let content = try? String(contentsOf: url, encoding: .utf8) else {
      return (fallbackName, nil)
    }

    var name = fallbackName
    var summary: String?

    for rawLine in content.split(whereSeparator: \.isNewline) {
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      if line.hasPrefix("# ") {
        name = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
      } else if line.lowercased().hasPrefix("description:") {
        let value = line.dropFirst("description:".count).trimmingCharacters(in: .whitespaces)
        summary = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
      }

      if name != fallbackName && summary != nil { break }
    }

    return (name.isEmpty ? fallbackName : name, summary)
  }
}
