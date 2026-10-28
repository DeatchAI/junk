import Foundation

func runCancellableDetached<Value: Sendable>(
  _ operation: @escaping @Sendable () -> Value
) async -> Value {
  let worker = Task.detached(priority: .userInitiated, operation: operation)
  return await withTaskCancellationHandler(
    operation: { await worker.value },
    onCancel: { worker.cancel() }
  )
}

/// A small lock-protected cache for shallow directory listings. It is shared
/// only by background searches belonging to one composer instance.
nonisolated final class DirectoryListingCache: @unchecked Sendable {
  private let lock = NSLock()
  private var entries: [String: [InlineWorkspaceItem]] = [:]

  func value(for directory: URL) -> [InlineWorkspaceItem]? {
    lock.lock()
    defer { lock.unlock() }
    return entries[directory.standardizedFileURL.path]
  }

  func insert(_ children: [InlineWorkspaceItem], for directory: URL) {
    lock.lock()
    entries[directory.standardizedFileURL.path] = children
    lock.unlock()
  }

  func clear() {
    lock.lock()
    entries.removeAll(keepingCapacity: true)
    lock.unlock()
  }
}

nonisolated final class SpotlightFileSearchSession: NSObject, @unchecked Sendable {
  private let metadataQuery: NSMetadataQuery
  private let operationQueue: OperationQueue
  private var observerTokens: [NSObjectProtocol] = []
  private let onStarted: (Bool) -> Void
  private let onResults: ([InlineWorkspaceItem], Bool) -> Void
  private let queryText: String
  private let root: URL
  private let stateLock = NSLock()
  private var cancelled = false

  init(
    queryText: String,
    root: URL,
    onStarted: @escaping (Bool) -> Void,
    onResults: @escaping ([InlineWorkspaceItem], Bool) -> Void
  ) {
    self.queryText = queryText
    self.root = root.standardizedFileURL
    self.onStarted = onStarted
    self.onResults = onResults
    self.metadataQuery = NSMetadataQuery()
    self.operationQueue = OperationQueue()
    super.init()

    operationQueue.maxConcurrentOperationCount = 1
    operationQueue.qualityOfService = .userInitiated

    metadataQuery.operationQueue = operationQueue
    metadataQuery.searchScopes = [self.root]
    metadataQuery.notificationBatchingInterval = 0.08

    let escapedQuery = Self.escapeSpotlightValue(queryText)
    metadataQuery.predicate = NSPredicate(
      format: "kMDItemFSName ==[cd] %@",
      "*\(escapedQuery)*"
    )
    metadataQuery.sortDescriptors = [
      NSSortDescriptor(key: NSMetadataItemFSNameKey, ascending: true)
    ]

    let center = NotificationCenter.default
    observerTokens.append(
      center.addObserver(
        forName: NSNotification.Name.NSMetadataQueryDidUpdate,
        object: metadataQuery,
        queue: operationQueue
      ) { [weak self] _ in
        self?.emitIntermediateResults()
      }
    )
    observerTokens.append(
      center.addObserver(
        forName: NSNotification.Name.NSMetadataQueryDidFinishGathering,
        object: metadataQuery,
        queue: operationQueue
      ) { [weak self] _ in
        self?.finish()
      }
    )
  }

  deinit {
    metadataQuery.stop()
    removeObservers()
  }

  func start() {
    operationQueue.addOperation { [weak self] in
      guard let self, !self.isCancelled else { return }
      let started = self.metadataQuery.start()
      self.onStarted(started)
      if !started {
        self.removeObservers()
      }
    }
  }

  func cancel() {
    stateLock.lock()
    cancelled = true
    stateLock.unlock()

    operationQueue.addOperation { [weak self] in
      guard let self else { return }
      self.metadataQuery.stop()
      self.removeObservers()
    }
  }

  private var isCancelled: Bool {
    stateLock.lock()
    defer { stateLock.unlock() }
    return cancelled
  }

  private func emitIntermediateResults() {
    guard !isCancelled else { return }
    onResults(snapshot(), false)
  }

  private func finish() {
    guard !isCancelled else { return }
    metadataQuery.stop()
    onResults(snapshot(), true)
    removeObservers()
  }

  private func snapshot() -> [InlineWorkspaceItem] {
    guard !isCancelled else { return [] }

    metadataQuery.disableUpdates()
    defer { metadataQuery.enableUpdates() }

    let resultCount = min(metadataQuery.resultCount, 320)
    guard resultCount > 0 else { return [] }

    var items: [InlineWorkspaceItem] = []
    items.reserveCapacity(min(resultCount, 80))

    for index in 0..<resultCount {
      guard let metadataItem = metadataQuery.result(at: index) as? NSMetadataItem,
        let url = metadataItem.value(forAttribute: NSMetadataItemURLKey) as? URL,
        url.isFileURL,
        !HomeFileIndexer.shouldSkipPath(url, relativeTo: root)
      else {
        continue
      }

      guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey]) else {
        continue
      }

      let isDirectory = values.isDirectory == true
      guard isDirectory || values.isRegularFile == true else { continue }
      items.append(InlineWorkspaceItem(url: url, isDirectory: isDirectory))
    }

    let lowercasedQuery = queryText.lowercased()
    return items
      .sorted { lhs, rhs in
        let lhsRelevance = HomeFileIndexer.relevance(lhs, query: lowercasedQuery)
        let rhsRelevance = HomeFileIndexer.relevance(rhs, query: lowercasedQuery)
        if lhsRelevance != rhsRelevance { return lhsRelevance > rhsRelevance }
        if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
      }
      .prefix(80)
      .map { $0 }
  }

  private func removeObservers() {
    guard !observerTokens.isEmpty else { return }
    let center = NotificationCenter.default
    observerTokens.forEach(center.removeObserver)
    observerTokens.removeAll()
  }

  private static func escapeSpotlightValue(_ value: String) -> String {
    value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
      .replacingOccurrences(of: "*", with: "\\*")
      .replacingOccurrences(of: "?", with: "\\?")
  }
}

nonisolated enum HomeFileIndexer {
  private static let skippedDirectoryNames: Set<String> = [
    "Library", ".Trash", ".git", ".svn", ".hg", "node_modules", "DerivedData",
    ".build", "Pods", ".cache", "venv", "dist", "build",
  ]

  static func pathScopedMatches(
    for query: String,
    root: URL,
    cache: DirectoryListingCache
  ) -> [InlineWorkspaceItem]? {
    let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard normalized.contains("/") else { return nil }

    let wantsDirectoryContents = normalized.hasSuffix("/")
    let rootRelativeQuery = normalized.hasPrefix("./")
      ? String(normalized.dropFirst(2))
      : normalized
    let components = rootRelativeQuery
      .split(separator: "/", omittingEmptySubsequences: true)
      .map(String.init)

    guard !components.isEmpty else {
      return directoryChildren(of: root, matching: "", directoriesOnly: false, cache: cache)
    }

    let parentComponents = wantsDirectoryContents ? components : Array(components.dropLast())
    let childQuery = wantsDirectoryContents ? "" : components.last ?? ""
    guard let directory = resolveDirectory(
      components: parentComponents,
      root: root,
      cache: cache
    ) else { return [] }

    return directoryChildren(
      of: directory,
      matching: childQuery,
      directoriesOnly: false,
      cache: cache
    )
  }

  static func recursiveMatches(for query: String, root: URL) -> [InlineWorkspaceItem] {
    let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedQuery.isEmpty else { return [] }

    let fileManager = FileManager.default
    guard let enumerator = fileManager.enumerator(
      at: root,
      includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
      options: [.skipsHiddenFiles, .skipsPackageDescendants],
      errorHandler: { _, _ in true }
    ) else {
      return []
    }

    var matches: [InlineWorkspaceItem] = []
    matches.reserveCapacity(80)

    for case let url as URL in enumerator {
      guard !Task.isCancelled else { return [] }

      if skippedDirectoryNames.contains(url.lastPathComponent) {
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
          enumerator.skipDescendants()
        }
        continue
      }

      guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey]) else {
        continue
      }

      let isDirectory = values.isDirectory == true
      guard isDirectory || values.isRegularFile == true else { continue }
      guard url.lastPathComponent.localizedCaseInsensitiveContains(normalizedQuery) else { continue }

      matches.append(InlineWorkspaceItem(url: url, isDirectory: isDirectory))
      if matches.count >= 320 { break }
    }

    let lowercasedQuery = normalizedQuery.lowercased()
    return matches
      .sorted { lhs, rhs in
        let lhsRelevance = relevance(lhs, query: lowercasedQuery)
        let rhsRelevance = relevance(rhs, query: lowercasedQuery)
        if lhsRelevance != rhsRelevance { return lhsRelevance > rhsRelevance }
        if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
      }
      .prefix(80)
      .map { $0 }
  }

  static func directoryChildren(
    of directory: URL,
    matching query: String,
    directoriesOnly: Bool,
    cache: DirectoryListingCache
  ) -> [InlineWorkspaceItem] {
    let children: [InlineWorkspaceItem]
    if let cached = cache.value(for: directory) {
      children = cached
    } else {
      let fileManager = FileManager.default
      guard let urls = try? fileManager.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
        options: [.skipsHiddenFiles, .skipsPackageDescendants]
      ) else {
        return []
      }

      children = urls.compactMap { url in
        guard !skippedDirectoryNames.contains(url.lastPathComponent) else { return nil }
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey]) else {
          return nil
        }

        let isDirectory = values.isDirectory == true
        guard isDirectory || values.isRegularFile == true else { return nil }
        return InlineWorkspaceItem(url: url, isDirectory: isDirectory)
      }
      cache.insert(children, for: directory)
    }

    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    return children
      .filter { item in
        guard item.isDirectory || !directoriesOnly else { return false }
        return trimmedQuery.isEmpty
          || item.name.localizedCaseInsensitiveContains(trimmedQuery)
      }
      .sorted { lhs, rhs in
        if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
      }
      .prefix(80)
      .map { $0 }
  }

  static func shouldSkipPath(_ url: URL, relativeTo root: URL) -> Bool {
    let rootComponents = root.standardizedFileURL.pathComponents
    let pathComponents = url.standardizedFileURL.pathComponents
    guard pathComponents.starts(with: rootComponents) else { return true }

    return pathComponents.dropFirst(rootComponents.count)
      .contains { skippedDirectoryNames.contains($0) }
  }

  static func relevance(_ item: InlineWorkspaceItem, query: String) -> Int {
    let name = item.name.lowercased()
    if name == query { return 4 }
    if name.hasPrefix(query) { return 3 }
    if item.isDirectory { return 2 }
    return 1
  }

  private static func resolveDirectory(
    components: [String],
    root: URL,
    cache: DirectoryListingCache
  ) -> URL? {
    var directory = root

    for component in components where !component.isEmpty {
      let matchingDirectories = directoryChildren(
        of: directory,
        matching: component,
        directoriesOnly: true,
        cache: cache
      )
      guard let next = matchingDirectories.first(where: {
        $0.name.caseInsensitiveCompare(component) == .orderedSame
      }) ?? matchingDirectories.first else {
        return nil
      }
      directory = next.url
    }

    return directory
  }
}
