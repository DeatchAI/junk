import Combine
import Foundation

struct ComposerProject: Codable, Identifiable, Equatable {
  let path: String
  let bookmark: Data?

  var id: String { path }
  var name: String {
    let name = URL(fileURLWithPath: path).lastPathComponent
    return name.isEmpty ? path : name
  }

  var isAvailable: Bool {
    let url = resolvedURL()
    let hasAccess = url.startAccessingSecurityScopedResource()
    defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
    return (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
  }

  func resolvedURL() -> URL {
    if let bookmark {
      var stale = false
      if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope],
        relativeTo: nil, bookmarkDataIsStale: &stale) { return url }
    }
    return URL(fileURLWithPath: path, isDirectory: true)
  }
}

/// The project list is shared by composers; each composer keeps its own selection.
@MainActor
final class ComposerProjectLibrary: ObservableObject {
  static let shared = ComposerProjectLibrary()
  @Published private(set) var projects: [ComposerProject]
  private static let key = "composer.projects.v1"
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    projects = defaults.data(forKey: Self.key)
      .flatMap { try? JSONDecoder().decode([ComposerProject].self, from: $0) } ?? []
  }

  func remember(_ directory: URL) {
    let url = directory.standardizedFileURL
    let bookmark = try? url.bookmarkData(options: [.withSecurityScope],
      includingResourceValuesForKeys: nil, relativeTo: nil)
    let existing = projects.first { $0.path == url.path }
    let project = ComposerProject(path: url.path, bookmark: bookmark ?? existing?.bookmark)
    if let index = projects.firstIndex(where: { $0.id == project.id }) {
      guard projects[index] != project else { return }
      projects[index] = project
    } else {
      projects.append(project)
    }
    if let data = try? JSONEncoder().encode(projects) { defaults.set(data, forKey: Self.key) }
  }

  func matching(_ query: String) -> [ComposerProject] {
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    return query.isEmpty ? projects : projects.filter {
      $0.name.localizedCaseInsensitiveContains(query) || $0.path.localizedCaseInsensitiveContains(query)
    }
  }
}
