#if DEBUG
import Foundation

enum DebugDemoFixtures {
  private static let fixtureDirectory = "app/server-v2/src/demo/fixtures"

  static func url(for relativePath: String) -> URL? {
    let fileManager = FileManager.default
    let candidates = [
      repoRoot(startingAt: URL(fileURLWithPath: #filePath).deletingLastPathComponent()),
      repoRoot(startingAt: URL(fileURLWithPath: fileManager.currentDirectoryPath)),
      repoRoot(startingAt: Bundle.main.bundleURL),
    ].compactMap { $0 }

    for root in candidates {
      let candidate = root.appendingPathComponent(fixtureDirectory).appendingPathComponent(relativePath)
      guard fileManager.fileExists(atPath: candidate.path) else { continue }
      let isDirectory = (try? candidate.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
      return URL(fileURLWithPath: candidate.path, isDirectory: isDirectory)
    }

    return nil
  }

  private static func repoRoot(startingAt start: URL) -> URL? {
    var directory = start.standardizedFileURL
    for _ in 0..<8 {
      let fixturePath = directory.appendingPathComponent(fixtureDirectory).path
      if FileManager.default.fileExists(atPath: fixturePath) {
        return directory
      }
      directory.deleteLastPathComponent()
    }
    return nil
  }
}
#endif
