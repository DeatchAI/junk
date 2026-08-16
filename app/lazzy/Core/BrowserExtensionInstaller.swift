import Foundation

enum BrowserExtensionInstaller {
  private static let folderName = "ChromeExtension"

  static var installedExtensionURL: URL? {
    guard let applicationSupport = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first else { return nil }
    let url = applicationSupport
      .appendingPathComponent("Detach", isDirectory: true)
      .appendingPathComponent(folderName, isDirectory: true)
    return FileManager.default.fileExists(atPath: url.path) ? url : nil
  }

  static func prepare(port: UInt16, runtimeToken: String) throws {
    guard let bundledURL = Bundle.main.resourceURL?
      .appendingPathComponent("chrome-extension", isDirectory: true),
      FileManager.default.fileExists(atPath: bundledURL.path)
    else {
      #if DEBUG
        // Source builds can still expose the repository copy when the build
        // phase has not run yet.
        return
      #else
        throw CocoaError(.fileNoSuchFile)
      #endif
    }

    let fileManager = FileManager.default
    guard let applicationSupport = fileManager.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first else { throw CocoaError(.fileNoSuchFile) }

    let detachDirectory = applicationSupport.appendingPathComponent("Detach", isDirectory: true)
    let destination = detachDirectory.appendingPathComponent(folderName, isDirectory: true)
    try fileManager.createDirectory(at: detachDirectory, withIntermediateDirectories: true)
    if fileManager.fileExists(atPath: destination.path) {
      try fileManager.removeItem(at: destination)
    }
    try fileManager.copyItem(at: bundledURL, to: destination)

    let configuration: [String: Any] = [
      "port": Int(port),
      "token": runtimeToken,
    ]
    let data = try JSONSerialization.data(withJSONObject: configuration, options: [.prettyPrinted, .sortedKeys])
    let configurationURL = destination.appendingPathComponent("runtime-config.json")
    try data.write(to: configurationURL, options: .atomic)
    try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configurationURL.path)
  }
}
