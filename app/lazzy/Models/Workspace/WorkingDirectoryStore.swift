import Combine
import Foundation

/// Persists the folder the user explicitly chose as the composer's working
/// directory. A security-scoped bookmark keeps this working when the app is
/// later sandboxed; the path fallback keeps local non-sandboxed builds simple.
@MainActor
final class WorkingDirectoryStore: ObservableObject {
  @Published private(set) var url: URL?
  @Published private(set) var remoteWorkspace: RemoteWorkspaceSelection?
  @Published private(set) var remoteConnectionStatus: RemoteMachineConnectionStatus = .idle
  @Published private(set) var selectionLocked = false

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
    if let remoteWorkspace { return "\(remoteWorkspace.name) · \(remoteWorkspace.machineName)" }
    guard let url else {
      return "Projects"
    }
    return url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
  }

  var path: String? { remoteWorkspace?.path ?? url?.path }
  var isRemote: Bool { remoteWorkspace != nil }

  func isReady(on endpoint: RuntimeEndpoint) -> Bool {
    guard let remoteWorkspace else { return endpoint.machineID == nil }
    return remoteConnectionStatus == .connected && endpoint.machineID == remoteWorkspace.machineID
  }

  func setRemoteConnectionStatus(_ status: RemoteMachineConnectionStatus) {
    remoteConnectionStatus = status
  }

  func lockSelection() { selectionLocked = true }
  func unlockSelectionForNewChat() { selectionLocked = false }

  func setRemoteWorkspace(_ selection: RemoteWorkspaceSelection) {
    guard !selectionLocked else { return }
    remoteWorkspace = selection
    remoteConnectionStatus = .connecting
  }

  func setDirectory(_ candidate: URL?) {
    guard !selectionLocked else { return }
    remoteWorkspace = nil
    remoteConnectionStatus = .idle
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
    guard !selectionLocked else { return }
    activeSecurityScopedURL?.stopAccessingSecurityScopedResource()
    activeSecurityScopedURL = nil
    url = nil
    remoteWorkspace = nil
    remoteConnectionStatus = .idle
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

