import Combine
import Foundation

/// A file or directory inside the selected working directory.
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

  func relativePath(from root: URL?) -> String {
    guard let root else { return relativePath }

    let rootPath = root.standardizedFileURL.path
    let itemPath = url.standardizedFileURL.path
    guard itemPath == rootPath || itemPath.hasPrefix(rootPath + "/") else {
      return relativePath
    }

    let suffix = String(itemPath.dropFirst(rootPath.count))
      .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    return suffix.isEmpty ? root.lastPathComponent : suffix
  }

  func rootRelativeQueryPath(from root: URL?) -> String {
    relativePath(from: root)
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

/// Persists the folder the user explicitly chose as the composer's working
/// directory. A security-scoped bookmark keeps this working when the app is
/// later sandboxed; the path fallback keeps local non-sandboxed builds simple.
@MainActor
final class WorkingDirectoryStore: ObservableObject {
  @Published private(set) var url: URL?

  private static let bookmarkKey = "composer.working-directory.bookmark.v1"
  private static let pathKey = "composer.working-directory.path.v1"

  private let defaults = UserDefaults.standard
  private var activeSecurityScopedURL: URL?

  init() {
    restore()
  }

  deinit {
    activeSecurityScopedURL?.stopAccessingSecurityScopedResource()
  }

  var displayName: String {
    guard let url else {
      return "No working directory"
    }
    return url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
  }

  func setDirectory(_ candidate: URL?) {
    guard let candidate else {
      clear()
      return
    }

    let normalized = candidate.standardizedFileURL
    guard Self.isDirectory(normalized) else { return }
    activate(normalized, persist: true)
  }

  func clear() {
    activeSecurityScopedURL?.stopAccessingSecurityScopedResource()
    activeSecurityScopedURL = nil
    url = nil
    defaults.removeObject(forKey: Self.bookmarkKey)
    defaults.removeObject(forKey: Self.pathKey)
  }

  private func restore() {
    if let bookmark = defaults.data(forKey: Self.bookmarkKey) {
      var isStale = false
      if let resolved = try? URL(
        resolvingBookmarkData: bookmark,
        options: [.withSecurityScope],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      ), Self.isDirectory(resolved)
      {
        activate(resolved.standardizedFileURL, persist: isStale)
        return
      }
    }

    if let path = defaults.string(forKey: Self.pathKey) {
      let candidate = URL(fileURLWithPath: path).standardizedFileURL
      if Self.isDirectory(candidate) {
        activate(candidate, persist: true)
        return
      }
    }

    defaults.removeObject(forKey: Self.bookmarkKey)
    defaults.removeObject(forKey: Self.pathKey)
  }

  private func activate(_ directory: URL, persist: Bool) {
    activeSecurityScopedURL?.stopAccessingSecurityScopedResource()
    _ = directory.startAccessingSecurityScopedResource()
    activeSecurityScopedURL = directory
    url = directory

    guard persist else { return }
    if let bookmark = try? directory.bookmarkData(
      options: [.withSecurityScope],
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    ) {
      defaults.set(bookmark, forKey: Self.bookmarkKey)
    }
    defaults.set(directory.path, forKey: Self.pathKey)
  }

  private static func isDirectory(_ url: URL) -> Bool {
    guard FileManager.default.fileExists(atPath: url.path) else { return false }
    return (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
  }
}

enum InlineWorkspaceSearchState: Equatable {
  case idle
  case noWorkingDirectory
  case needsMoreCharacters
  case searching
  case ready
  case spotlightUnavailable
}

/// Provides an explicit, privacy-respecting file browser for the composer.
///
/// Plain filename searches use the system Spotlight metadata store. Path
/// browsing only reads the directory the user is actively navigating to, and
/// all filesystem work is performed away from the main actor.
@MainActor
final class InlineWorkspaceCatalog: ObservableObject {
  @Published private(set) var results: [InlineWorkspaceItem] = []
  @Published private(set) var isSearching = false
  @Published private(set) var query = ""
  @Published private(set) var workingDirectory: URL?
  @Published private(set) var state: InlineWorkspaceSearchState = .idle

  private static let debounceNanoseconds: UInt64 = 120_000_000
  private static let minimumGlobalQueryLength = 2

  private let directoryCache = DirectoryListingCache()
  private var debounceTask: Task<Void, Never>?
  private var spotlightSession: SpotlightFileSearchSession?
  private var spotlightTimeoutTask: Task<Void, Never>?
  private var fallbackSearchTask: Task<Void, Never>?
  private var searchGeneration: UInt64 = 0

  init(workingDirectory: URL? = nil) {
    self.workingDirectory = workingDirectory?.standardizedFileURL
    if self.workingDirectory == nil {
      state = .noWorkingDirectory
    }
  }

  deinit {
    debounceTask?.cancel()
    spotlightTimeoutTask?.cancel()
    fallbackSearchTask?.cancel()
    spotlightSession?.cancel()
  }

  func setWorkingDirectory(_ directory: URL?) {
    let normalized = directory?.standardizedFileURL
    guard normalized?.path != workingDirectory?.path else { return }

    cancel()
    directoryCache.clear()
    workingDirectory = normalized
    query = ""

    guard let normalized else {
      results = []
      state = .noWorkingDirectory
      return
    }

    let generation = searchGeneration
    loadRootContents(normalized, generation: generation)
  }

  func search(query rawQuery: String) {
    let normalizedQuery = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    // The panel can receive the same query once from the parent and once when
    // its SwiftUI host appears. Let the in-flight request own that transition.
    guard !(normalizedQuery == query && (isSearching || state == .needsMoreCharacters)) else { return }

    searchGeneration &+= 1
    let generation = searchGeneration

    debounceTask?.cancel()
    spotlightTimeoutTask?.cancel()
    spotlightTimeoutTask = nil
    fallbackSearchTask?.cancel()
    fallbackSearchTask = nil
    spotlightSession?.cancel()
    spotlightSession = nil

    query = normalizedQuery

    guard let workingDirectory else {
      results = []
      isSearching = false
      state = .noWorkingDirectory
      return
    }

    if normalizedQuery.isEmpty {
      loadRootContents(workingDirectory, generation: generation)
      return
    }

    if normalizedQuery.contains("/") {
      isSearching = true
      state = .searching
      let cache = directoryCache
      debounceTask = Task { [weak self] in
        do {
          try await Task.sleep(nanoseconds: Self.debounceNanoseconds)
        } catch {
          return
        }

        guard !Task.isCancelled else { return }
        let found = await runCancellableDetached {
          HomeFileIndexer.pathScopedMatches(
            for: normalizedQuery,
            root: workingDirectory,
            cache: cache
          ) ?? []
        }

        guard !Task.isCancelled, let self, self.searchGeneration == generation else { return }
        self.results = found
        self.isSearching = false
        self.state = .ready
      }
      return
    }

    guard normalizedQuery.count >= Self.minimumGlobalQueryLength else {
      results = []
      isSearching = false
      state = .needsMoreCharacters
      return
    }

    results = []
    isSearching = true
    state = .searching

    debounceTask = Task { [weak self] in
      do {
        try await Task.sleep(nanoseconds: Self.debounceNanoseconds)
      } catch {
        return
      }

      guard !Task.isCancelled, let self, self.searchGeneration == generation else { return }
      self.startSpotlightSearch(query: normalizedQuery, generation: generation)
    }
  }

  func cancel() {
    searchGeneration &+= 1
    debounceTask?.cancel()
    spotlightTimeoutTask?.cancel()
    fallbackSearchTask?.cancel()
    spotlightSession?.cancel()
    debounceTask = nil
    spotlightTimeoutTask = nil
    fallbackSearchTask = nil
    spotlightSession = nil
    isSearching = false
  }

  private func loadRootContents(_ root: URL, generation: UInt64) {
    isSearching = true
    state = .searching
    let cache = directoryCache
    debounceTask = Task { [weak self] in
      let found = await runCancellableDetached {
        HomeFileIndexer.directoryChildren(
          of: root,
          matching: "",
          directoriesOnly: false,
          cache: cache
        )
      }

      guard !Task.isCancelled, let self, self.searchGeneration == generation else { return }
      self.results = found
      self.isSearching = false
      self.state = .ready
    }
  }

  private func startSpotlightSearch(query: String, generation: UInt64) {
    guard let workingDirectory else { return }
    let session = SpotlightFileSearchSession(queryText: query, root: workingDirectory) { [weak self] started in
      Task { @MainActor [weak self] in
        guard let self, self.searchGeneration == generation else { return }
        guard started else {
          self.spotlightTimeoutTask?.cancel()
          self.spotlightTimeoutTask = nil
          self.spotlightSession = nil
          self.startFallbackSearch(query: query, generation: generation)
          return
        }
      }
    } onResults: { [weak self] found, isFinal in
      Task { @MainActor [weak self] in
        guard let self, self.searchGeneration == generation else { return }
        self.results = found
        self.isSearching = !isFinal
        self.state = .ready
        if isFinal {
          self.spotlightTimeoutTask?.cancel()
          self.spotlightTimeoutTask = nil
          self.spotlightSession = nil
          if found.isEmpty {
            self.startFallbackSearch(query: query, generation: generation)
          }
        }
      }
    }

    spotlightSession = session

    // A disabled or stale Spotlight store may accept start() but never emit a
    // finish notification. Give the UI a deterministic fallback instead of
    // leaving the attachment panel in a permanent loading state.
    spotlightTimeoutTask = Task { [weak self] in
      do {
        try await Task.sleep(nanoseconds: 1_500_000_000)
      } catch {
        return
      }

      guard let self,
        self.searchGeneration == generation,
        self.isSearching,
        self.results.isEmpty
      else { return }

      self.startFallbackSearch(query: query, generation: generation)
    }

    session.start()
  }

  private func startFallbackSearch(query: String, generation: UInt64) {
    guard let workingDirectory else { return }

    spotlightTimeoutTask?.cancel()
    spotlightTimeoutTask = nil
    spotlightSession?.cancel()
    spotlightSession = nil
    fallbackSearchTask?.cancel()

    results = []
    isSearching = true
    state = .searching

    fallbackSearchTask = Task { [weak self] in
      let found = await runCancellableDetached {
        HomeFileIndexer.recursiveMatches(for: query, root: workingDirectory)
      }

      guard !Task.isCancelled, let self, self.searchGeneration == generation else { return }
      self.results = found
      self.isSearching = false
      self.state = .ready
      self.fallbackSearchTask = nil
    }
  }
}

private func runCancellableDetached<Value: Sendable>(
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
nonisolated private final class DirectoryListingCache: @unchecked Sendable {
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

nonisolated private final class SpotlightFileSearchSession: NSObject, @unchecked Sendable {
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

nonisolated private enum HomeFileIndexer {
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
