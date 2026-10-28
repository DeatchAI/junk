import Foundation

enum BrowserExtensionInstaller {
  private static let folderName = "ChromeExtension"

  static func prepareForManualSetup() throws -> URL {
    let fileManager = FileManager.default
    guard let destination = installedExtensionDirectory,
      let bundledURL = bundledExtensionURL,
      fileManager.fileExists(atPath: bundledURL.path)
    else { throw CocoaError(.fileNoSuchFile) }

    try fileManager.createDirectory(
      at: destination.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try syncBundledContents(
      from: bundledURL,
      to: destination,
      preserveExistingRuntimeConfiguration: true
    )
    return destination
  }

  static var installedExtensionURL: URL? {
    guard let url = installedExtensionDirectory else { return nil }
    return FileManager.default.fileExists(atPath: url.path) ? url : nil
  }

  static func prepare(port: UInt16, runtimeToken: String) throws {
    guard let bundledURL = bundledExtensionURL,
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
    guard let destination = installedExtensionDirectory else { throw CocoaError(.fileNoSuchFile) }
    try fileManager.createDirectory(
      at: destination.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try syncBundledContents(
      from: bundledURL,
      to: destination,
      preserveExistingRuntimeConfiguration: false
    )

    let configuration: [String: Any] = [
      "port": Int(port),
      "token": runtimeToken,
    ]
    let data = try JSONSerialization.data(withJSONObject: configuration, options: [.prettyPrinted, .sortedKeys])
    let configurationURL = destination.appendingPathComponent("runtime-config.json")
    try data.write(to: configurationURL, options: .atomic)
    try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configurationURL.path)
  }

  private static var installedExtensionDirectory: URL? {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
      .appendingPathComponent("Detach", isDirectory: true)
      .appendingPathComponent(folderName, isDirectory: true)
  }

  private static var bundledExtensionURL: URL? {
    Bundle.main.resourceURL?.appendingPathComponent("chrome-extension", isDirectory: true)
  }

  private static func syncBundledContents(
    from sourceDirectory: URL,
    to destinationDirectory: URL,
    preserveExistingRuntimeConfiguration: Bool
  ) throws {
    let fileManager = FileManager.default
    try fileManager.createDirectory(
      at: destinationDirectory,
      withIntermediateDirectories: true
    )

    guard let enumerator = fileManager.enumerator(
      at: sourceDirectory,
      includingPropertiesForKeys: [.isDirectoryKey]
    ) else { throw CocoaError(.fileReadNoPermission) }

    while let sourceURL = enumerator.nextObject() as? URL {
      let isDirectory = try sourceURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
      let relativePath = String(sourceURL.path.dropFirst(sourceDirectory.path.count + 1))
      let destinationURL = destinationDirectory.appendingPathComponent(relativePath, isDirectory: isDirectory)

      if isDirectory {
        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        continue
      }

      if sourceURL.lastPathComponent == "runtime-config.json" {
        if !preserveExistingRuntimeConfiguration
          || fileManager.fileExists(atPath: destinationURL.path) {
          continue
        }
      }

      try fileManager.createDirectory(
        at: destinationURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      let data = try Data(contentsOf: sourceURL)
      try data.write(to: destinationURL, options: .atomic)
    }
  }
}
