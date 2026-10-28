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
