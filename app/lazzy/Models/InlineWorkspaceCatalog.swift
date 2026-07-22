import Foundation

/// A file or directory from the user's home directory.
nonisolated struct InlineWorkspaceItem: Identifiable, Hashable, Codable, Sendable {
  let url: URL
  let isDirectory: Bool

  var id: String { url.path }
  var name: String { url.lastPathComponent }

  var relativePath: String {
    let homePath = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
    let path = url.standardizedFileURL.path
    guard path.hasPrefix(homePath) else { return path }

    let suffix = String(path.dropFirst(homePath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    return suffix.isEmpty ? "~" : "~/\(suffix)"
  }

  var homeRelativeQueryPath: String {
    let relative = relativePath
    guard relative.hasPrefix("~/") else { return relative == "~" ? "" : relative }
    return String(relative.dropFirst(2))
  }

  var systemImage: String {
    if isDirectory { return "folder" }

    switch url.pathExtension.lowercased() {
    case "png", "jpg", "jpeg", "gif", "webp", "heic": return "photo"
    case "swift": return "swift"
    case "js", "jsx", "ts", "tsx": return "chevron.left.forwardslash.chevron.right"
    case "md", "txt", "rtf": return "doc.text"
    case "pdf": return "doc.richtext"
    default: return "doc"
    }
  }
}

/// Keeps a small, cached filename index for the home directory. The first use
/// loads the previous snapshot immediately and refreshes it in the background;
/// later `@` searches are only in-memory filtering.
@MainActor
final class InlineWorkspaceCatalog {
  static let shared = InlineWorkspaceCatalog()

  private var items: [InlineWorkspaceItem] = []
  private var hasLoadedCache = false
  private var indexTask: Task<Void, Never>?
  private var latestQuery = ""
  private var latestCompletion: (([InlineWorkspaceItem], Bool) -> Void)?

  deinit {
    indexTask?.cancel()
  }

  func search(
    query: String,
    completion: @escaping ([InlineWorkspaceItem], Bool) -> Void
  ) {
    loadCachedIndexIfNeeded()
    latestQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    latestCompletion = completion
    startIndexingIfNeeded()

    completion(matches(for: latestQuery), indexTask != nil)
  }

  func warm() {
    loadCachedIndexIfNeeded()
    startIndexingIfNeeded()
  }

  /// Stops delivery to a view that has disappeared; the background index can
  /// still finish and populate the on-disk cache for the next composer use.
  func cancel() {
    latestCompletion = nil
  }

  private func loadCachedIndexIfNeeded() {
    guard !hasLoadedCache else { return }
    hasLoadedCache = true
    items = HomeFileIndexStore.load()
  }

  private func startIndexingIfNeeded() {
    guard indexTask == nil else { return }

    indexTask = Task { [weak self] in
      let snapshot = await Task.detached(priority: .utility) {
        HomeFileIndexer.buildSnapshot()
      }.value

      guard !Task.isCancelled else { return }
      HomeFileIndexStore.save(snapshot)
      self?.replaceIndex(with: snapshot)
    }
  }

  private func replaceIndex(with snapshot: [InlineWorkspaceItem]) {
    items = snapshot
    indexTask = nil
    latestCompletion?(matches(for: latestQuery), false)
  }

  private func matches(for query: String) -> [InlineWorkspaceItem] {
    guard !query.isEmpty else { return HomeFileIndexer.homeDirectories() }

    if let pathScopedMatches = HomeFileIndexer.pathScopedMatches(for: query) {
      return pathScopedMatches
    }

    let lowercasedQuery = query.lowercased()
    return items.lazy
      .filter {
        $0.name.localizedCaseInsensitiveContains(lowercasedQuery)
          || $0.homeRelativeQueryPath.localizedCaseInsensitiveContains(lowercasedQuery)
      }
      .sorted { lhs, rhs in
        relevance(lhs, query: lowercasedQuery) > relevance(rhs, query: lowercasedQuery)
      }
      .prefix(40)
      .map { $0 }
  }

  private func relevance(_ item: InlineWorkspaceItem, query: String) -> Int {
    let name = item.name.lowercased()
    if name == query { return 4 }
    if name.hasPrefix(query) { return 3 }
    if item.isDirectory { return 2 }
    return 1
  }
}

nonisolated private enum HomeFileIndexer {
  private static let skippedDirectoryNames: Set<String> = [
    "Library", ".Trash", ".git", ".svn", ".hg", "node_modules", "DerivedData",
    ".build", "Pods", ".cache", "venv", "dist", "build",
  ]
  private static let maximumItemCount = 250_000

  static func buildSnapshot() -> [InlineWorkspaceItem] {
    let fileManager = FileManager.default
    let home = fileManager.homeDirectoryForCurrentUser
    guard let enumerator = fileManager.enumerator(
      at: home,
      includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
      options: [.skipsHiddenFiles, .skipsPackageDescendants]
    ) else {
      return []
    }

    var snapshot: [InlineWorkspaceItem] = []
    while let url = enumerator.nextObject() as? URL, snapshot.count < maximumItemCount {
      if skippedDirectoryNames.contains(url.lastPathComponent) {
        enumerator.skipDescendants()
        continue
      }

      guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey]) else {
        continue
      }
      let isDirectory = values.isDirectory == true
      guard isDirectory || values.isRegularFile == true else { continue }

      snapshot.append(InlineWorkspaceItem(url: url, isDirectory: isDirectory))
    }
    return snapshot
  }

  static func homeDirectories() -> [InlineWorkspaceItem] {
    let fileManager = FileManager.default
    let home = fileManager.homeDirectoryForCurrentUser
    guard let children = try? fileManager.contentsOfDirectory(
      at: home,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles, .skipsPackageDescendants]
    ) else {
      return []
    }

    return children.compactMap { url in
      guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
      return InlineWorkspaceItem(url: url, isDirectory: true)
    }
    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  static func pathScopedMatches(for query: String) -> [InlineWorkspaceItem]? {
    let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard normalized.contains("/") else { return nil }

    let wantsDirectoryContents = normalized.hasSuffix("/")
    let components = normalized
      .split(separator: "/", omittingEmptySubsequences: true)
      .map(String.init)

    guard !components.isEmpty else { return homeDirectories() }

    let parentComponents = wantsDirectoryContents ? components : Array(components.dropLast())
    let childQuery = wantsDirectoryContents ? "" : components.last ?? ""
    guard let directory = resolveDirectory(components: parentComponents) else { return [] }

    return directoryChildren(of: directory, matching: childQuery, directoriesOnly: false)
  }

  static func directoryChildren(
    of directory: URL,
    matching query: String,
    directoriesOnly: Bool
  ) -> [InlineWorkspaceItem] {
    let fileManager = FileManager.default
    guard let children = try? fileManager.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
      options: [.skipsHiddenFiles, .skipsPackageDescendants]
    ) else {
      return []
    }

    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    return children.compactMap { url in
      guard !skippedDirectoryNames.contains(url.lastPathComponent) else { return nil }
      guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey]) else {
        return nil
      }

      let isDirectory = values.isDirectory == true
      guard isDirectory || (!directoriesOnly && values.isRegularFile == true) else { return nil }
      guard trimmedQuery.isEmpty || url.lastPathComponent.localizedCaseInsensitiveContains(trimmedQuery) else {
        return nil
      }

      return InlineWorkspaceItem(url: url, isDirectory: isDirectory)
    }
    .sorted { lhs, rhs in
      if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
      return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
    .prefix(80)
    .map { $0 }
  }

  private static func resolveDirectory(components: [String]) -> URL? {
    let fileManager = FileManager.default
    var directory = fileManager.homeDirectoryForCurrentUser

    for component in components where !component.isEmpty {
      guard let next = directoryChildren(of: directory, matching: component, directoriesOnly: true)
        .first(where: { $0.name.caseInsensitiveCompare(component) == .orderedSame })
        ?? directoryChildren(of: directory, matching: component, directoriesOnly: true).first
      else {
        return nil
      }
      directory = next.url
    }

    return directory
  }
}

nonisolated private enum HomeFileIndexStore {
  private static let filename = "inline-home-file-index-v1.json"

  static func load() -> [InlineWorkspaceItem] {
    guard let data = try? Data(contentsOf: cacheURL()) else { return [] }
    return (try? JSONDecoder().decode([InlineWorkspaceItem].self, from: data)) ?? []
  }

  static func save(_ items: [InlineWorkspaceItem]) {
    guard let data = try? JSONEncoder().encode(items) else { return }
    let url = cacheURL()
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: url, options: .atomic)
  }

  private static func cacheURL() -> URL {
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return appSupport.appendingPathComponent("Lazzy", isDirectory: true).appendingPathComponent(filename)
  }
}
