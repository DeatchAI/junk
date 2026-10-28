import Combine
import Foundation

/// Persists the folder the user explicitly chose as the composer's working
/// directory. A security-scoped bookmark keeps this working when the app is
/// later sandboxed; the path fallback keeps local non-sandboxed builds simple.
@MainActor
final class WorkingDirectoryStore: ObservableObject {
  @Published private(set) var url: URL?

  private static let bookmarkKey = "composer.working-directory.bookmark.v1"
  private static let pathKey = "composer.working-directory.path.v1"

  private let defaults: UserDefaults
  let projects: ComposerProjectLibrary
  private var activeSecurityScopedURL: URL?

  init(defaults: UserDefaults = .standard, projects: ComposerProjectLibrary? = nil) {
    self.defaults = defaults
    self.projects = projects ?? .shared
    restore()
  }

  deinit {
    activeSecurityScopedURL?.stopAccessingSecurityScopedResource()
  }

  var displayName: String {
    guard let url else {
      return "Projects"
    }
    return url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
  }

  func setDirectory(_ candidate: URL?) {
    guard let candidate else {
      clear()
      return
    }

    let normalized = candidate.standardizedFileURL
    let hasAccess = normalized.startAccessingSecurityScopedResource()
    defer { if hasAccess { normalized.stopAccessingSecurityScopedResource() } }
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
    projects.remember(directory)

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

