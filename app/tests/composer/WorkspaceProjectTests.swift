import Foundation

@main struct WorkspaceProjectTests {
  @MainActor static func main() throws {
    let suite = "detach-project-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
    defer {
      defaults.removePersistentDomain(forName: suite)
      try? FileManager.default.removeItem(at: root)
    }
    let first = root.appendingPathComponent("First project", isDirectory: true)
    let second = root.appendingPathComponent("Second project", isDirectory: true)
    try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)

    // Upgrade the existing single-folder preference without losing its selection.
    defaults.set(first.path, forKey: "composer.working-directory.path.v1")
    let library = ComposerProjectLibrary(defaults: defaults)
    let store = WorkingDirectoryStore(defaults: defaults, projects: library)
    assert(store.url?.path == first.path && library.projects.count == 1)
    store.setDirectory(second)
    store.setDirectory(first.appendingPathComponent("../First project"))
    assert(library.projects.count == 2, "Selecting a folder again must not duplicate projects")
    assert(library.matching("SECOND").map(\.path) == [second.path])
    assert(library.matching("  ").count == 2)

    store.clear()
    assert(store.url == nil && library.projects.count == 2, "Clearing selection must keep saved projects")
    let restored = ComposerProjectLibrary(defaults: defaults)
    let newStore = WorkingDirectoryStore(defaults: defaults, projects: restored)
    assert(newStore.url == nil && restored.projects.count == 2, "Saved projects survive a relaunch")
    newStore.setDirectory(restored.projects[1].resolvedURL())
    assert(newStore.url?.path == second.path)
    store.setDirectory(first)
    assert(newStore.url?.path == second.path, "Open composers keep independent selections")
    store.setDirectory(root.appendingPathComponent("Missing"))
    assert(store.url?.path == first.path && restored.projects.count == 2)
    print("Project migration, persistence, search, deduplication and independent composer selections passed")
  }
}
