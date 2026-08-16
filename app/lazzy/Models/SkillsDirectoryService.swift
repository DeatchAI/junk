import Combine
import Foundation

/// A skill returned by the public search endpoint used by the skills CLI.
/// The directory is treated as discovery metadata only until the user explicitly
/// installs and attaches the skill.
struct RemoteSkill: Codable, Identifiable, Hashable {
  let id: String
  let skillId: String?
  let name: String
  let installs: Int
  let source: String
  let installUrl: String?

  var selectionName: String {
    if let skillId {
      let trimmed = skillId.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty { return trimmed }
    }

    return id.split(separator: "/").last.map(String.init) ?? name
  }

  var detailURL: URL? {
    URL(string: "https://skills.sh/\(id)")
  }

  var installSource: String {
    if let installUrl {
      let trimmed = installUrl.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty { return trimmed }
    }

    if source.contains("/") { return source }
    if source.contains(".") { return "https://" + source }
    return source
  }

  var formattedInstalls: String {
    guard installs > 0 else { return "" }
    if installs >= 1_000_000 {
      return "\((Double(installs) / 1_000_000).formatted(.number.precision(.fractionLength(1))))M installs"
    }
    if installs >= 1_000 {
      return "\((Double(installs) / 1_000).formatted(.number.precision(.fractionLength(1))))K installs"
    }
    return "\(installs) install\(installs == 1 ? "" : "s")"
  }
}

private nonisolated struct SkillsDirectorySearchResponse: Decodable {
  let skills: [RemoteSkill]
}

/// Discovers and installs skills without putting remote content directly on the
/// chat request. Installed files are re-discovered through the same catalog as
/// local Codex/agent skills and are validated again by server-v2.
@MainActor
final class SkillsDirectoryService: ObservableObject {
  /// Curated, verified directory entries shown before the user supplies a
  /// query. These make the discovery surface useful without an extra field.
  static let featuredSkills: [RemoteSkill] = [
    RemoteSkill(
      id: "vercel-labs/skills/find-skills",
      skillId: "find-skills",
      name: "Find Skills",
      installs: 2_776_087,
      source: "vercel-labs/skills",
      installUrl: nil
    ),
    RemoteSkill(
      id: "vercel-labs/agent-browser/agent-browser",
      skillId: "agent-browser",
      name: "Agent Browser",
      installs: 611_368,
      source: "vercel-labs/agent-browser",
      installUrl: nil
    ),
    RemoteSkill(
      id: "vercel-labs/agent-skills/vercel-react-best-practices",
      skillId: "vercel-react-best-practices",
      name: "React Best Practices",
      installs: 598_249,
      source: "vercel-labs/agent-skills",
      installUrl: nil
    ),
    RemoteSkill(
      id: "vercel-labs/agent-skills/web-design-guidelines",
      skillId: "web-design-guidelines",
      name: "Web Design Guidelines",
      installs: 508_065,
      source: "vercel-labs/agent-skills",
      installUrl: nil
    ),
    RemoteSkill(
      id: "vercel-labs/agent-skills/vercel-composition-patterns",
      skillId: "vercel-composition-patterns",
      name: "Composition Patterns",
      installs: 271_589,
      source: "vercel-labs/agent-skills",
      installUrl: nil
    ),
  ]

  @Published private(set) var installedSkills: [SkillAttachment]
  @Published private(set) var searchResults: [RemoteSkill] = []
  @Published private(set) var isSearching = false
  @Published private(set) var installingSkillID: String?
  @Published private(set) var errorMessage: String?

  private static let searchCacheDefaultsKey = "skills.directory.search-cache.v1"
  private static let searchCacheLifetime: TimeInterval = 15 * 60
  private static let searchSession: URLSession = {
    let configuration = URLSessionConfiguration.default
    configuration.waitsForConnectivity = false
    configuration.timeoutIntervalForRequest = 10
    configuration.timeoutIntervalForResource = 12
    configuration.urlCache = URLCache(
      memoryCapacity: 2 * 1024 * 1024,
      diskCapacity: 8 * 1024 * 1024,
      diskPath: "skills-directory"
    )
    configuration.requestCachePolicy = .useProtocolCachePolicy
    return URLSession(configuration: configuration)
  }()

  private struct SearchCacheEntry: Codable {
    let fetchedAt: Date
    let skills: [RemoteSkill]
  }

  private var searchCache: [String: SearchCacheEntry]
  private var searchTask: Task<Void, Never>?
  private var searchGeneration = 0

  init() {
    installedSkills = InstalledSkillCatalog.discover()
    searchCache = Self.loadSearchCache()
  }

  deinit {
    searchTask?.cancel()
  }

  func refreshInstalledSkills() {
    installedSkills = InstalledSkillCatalog.discover()
  }

  func clearError() {
    errorMessage = nil
  }

  func installedSkill(for remoteSkill: RemoteSkill) -> SkillAttachment? {
    let directory = remoteSkill.selectionName.lowercased()
    return installedSkills.first(where: {
      InstalledSkillCatalog.isAppManaged($0) && Self.directoryName(for: $0) == directory
    }) ?? installedSkills.first(where: { Self.directoryName(for: $0) == directory })
  }

  private func appManagedInstalledSkill(for remoteSkill: RemoteSkill) -> SkillAttachment? {
    let directory = remoteSkill.selectionName.lowercased()
    return installedSkills.first(where: {
      InstalledSkillCatalog.isAppManaged($0) && Self.directoryName(for: $0) == directory
    })
  }

  func search(query: String) {
    searchTask?.cancel()
    searchGeneration &+= 1
    let generation = searchGeneration
    errorMessage = nil

    let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard normalizedQuery.count >= 2 else {
      searchResults = []
      isSearching = false
      return
    }

    if let cachedResults = cachedSearchResults(for: normalizedQuery) {
      searchResults = cachedResults
      isSearching = false
      return
    }

    searchResults = []
    isSearching = true
    searchTask = Task { [weak self] in
      defer {
        if let self, self.searchGeneration == generation {
          self.isSearching = false
          self.searchTask = nil
        }
      }

      do {
        try await Task.sleep(for: .milliseconds(420))
        let results = try await Self.fetchSearchResults(query: normalizedQuery)
        guard !Task.isCancelled else { return }
        guard let self, self.searchGeneration == generation else { return }
        self.searchResults = results
        self.storeSearchResults(results, for: normalizedQuery)
      } catch is CancellationError {
        // The defer above clears the spinner if this was the active request.
      } catch {
        guard !Task.isCancelled, let self, self.searchGeneration == generation else { return }
        self.searchResults = []
        self.errorMessage = error.localizedDescription
      }
    }
  }

  func install(_ skill: RemoteSkill) async -> Result<SkillAttachment, Error> {
    guard installingSkillID == nil else {
      return .failure(InstallerError.installInProgress)
    }

    if let existingAttachment = appManagedInstalledSkill(for: skill) {
      return .success(existingAttachment)
    }

    errorMessage = nil
    installingSkillID = skill.id
    defer { installingSkillID = nil }

    let workspacePath = Self.appManagedWorkspace.path
    let source = skill.installSource
    let skillName = skill.selectionName

    do {
      let result = try await Task.detached(priority: .userInitiated) {
        try Self.runInstaller(
          source: source,
          skillName: skillName,
          workspacePath: workspacePath
        )
      }.value

      guard result.exitCode == 0 else {
        throw InstallerError.commandFailed(output: result.output)
      }

      refreshInstalledSkills()
      guard let attachment = appManagedInstalledSkill(for: skill) else {
        throw InstallerError.installedSkillNotFound(output: result.output)
      }

      return .success(attachment)
    } catch {
      errorMessage = error.localizedDescription
      return .failure(error)
    }
  }

  private static var appManagedWorkspace: URL {
    InstalledSkillCatalog.appManagedSkillRoot
      .deletingLastPathComponent() // .agents
      .deletingLastPathComponent() // skill-workspace
  }

  private static func loadSearchCache() -> [String: SearchCacheEntry] {
    guard let data = UserDefaults.standard.data(forKey: searchCacheDefaultsKey),
      let decoded = try? JSONDecoder().decode([String: SearchCacheEntry].self, from: data)
    else {
      return [:]
    }

    let now = Date()
    return decoded.filter { now.timeIntervalSince($0.value.fetchedAt) < searchCacheLifetime }
  }

  private func cachedSearchResults(for query: String) -> [RemoteSkill]? {
    guard let entry = searchCache[query] else { return nil }
    guard Date().timeIntervalSince(entry.fetchedAt) < Self.searchCacheLifetime else {
      searchCache.removeValue(forKey: query)
      return nil
    }
    return entry.skills
  }

  private func storeSearchResults(_ results: [RemoteSkill], for query: String) {
    searchCache[query] = SearchCacheEntry(fetchedAt: Date(), skills: results)
    if searchCache.count > 32 {
      let oldestKeys = searchCache
        .sorted { $0.value.fetchedAt < $1.value.fetchedAt }
        .prefix(searchCache.count - 32)
        .map(\.key)
      for key in oldestKeys {
        searchCache.removeValue(forKey: key)
      }
    }

    if let data = try? JSONEncoder().encode(searchCache) {
      UserDefaults.standard.set(data, forKey: Self.searchCacheDefaultsKey)
    }
  }

  private nonisolated static func fetchSearchResults(query: String) async throws -> [RemoteSkill] {
    guard var components = URLComponents(string: "https://skills.sh/api/search") else {
      throw DirectoryError.invalidURL
    }
    components.queryItems = [
      URLQueryItem(name: "q", value: query),
      URLQueryItem(name: "limit", value: "10"),
    ]

    guard let url = components.url else { throw DirectoryError.invalidURL }
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.timeoutInterval = 10
    request.cachePolicy = .useProtocolCachePolicy
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    let (data, response): (Data, URLResponse)
    do {
      (data, response) = try await searchSession.data(for: request)
    } catch let error as URLError where error.code == .timedOut {
      throw DirectoryError.timedOut
    }
    guard let response = response as? HTTPURLResponse else {
      throw DirectoryError.invalidResponse
    }
    guard (200..<300).contains(response.statusCode) else {
      throw DirectoryError.httpStatus(response.statusCode)
    }

    let decoded = try JSONDecoder().decode(SkillsDirectorySearchResponse.self, from: data)
    return decoded.skills
  }

  private nonisolated static func runInstaller(
    source: String,
    skillName: String,
    workspacePath: String
  ) throws -> InstallerResult {
    guard isSafeSource(source), isSafeSkillName(skillName) else {
      throw InstallerError.invalidSource
    }

    let workspaceURL = URL(fileURLWithPath: workspacePath, isDirectory: true)
    try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

    let executable: String
    let arguments: [String]
    if let skills = resolveExecutable(named: "skills") {
      executable = skills
      arguments = [
        "add", source,
        "--skill", skillName,
        "--agent", "codex",
        "--copy",
        "--yes",
      ]
    } else if let npx = resolveExecutable(named: "npx") {
      executable = npx
      arguments = [
        "--yes", "skills", "add", source,
        "--skill", skillName,
        "--agent", "codex",
        "--copy",
        "--yes",
      ]
    } else {
      throw InstallerError.cliUnavailable
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = workspaceURL

    var environment = ProcessInfo.processInfo.environment
    environment["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
    environment["DISABLE_TELEMETRY"] = "1"
    environment["NO_COLOR"] = "1"
    environment["CI"] = "1"
    environment["GIT_TERMINAL_PROMPT"] = "0"
    environment["NPM_CONFIG_UPDATE_NOTIFIER"] = "false"
    environment["NPM_CONFIG_AUDIT"] = "false"
    environment["NPM_CONFIG_FUND"] = "false"
    environment["NPM_CONFIG_PROGRESS"] = "false"
    environment["NPM_CONFIG_FETCH_RETRIES"] = "1"
    environment["NPM_CONFIG_FETCH_RETRY_MINTIMEOUT"] = "1000"
    environment["NPM_CONFIG_FETCH_RETRY_MAXTIMEOUT"] = "5000"
    environment["NPM_CONFIG_FETCH_TIMEOUT"] = "30000"

    var pathEntries = environment["PATH"]?.split(separator: ":").map(String.init) ?? []
    for path in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"] {
      if !pathEntries.contains(path) { pathEntries.append(path) }
    }
    environment["PATH"] = pathEntries.joined(separator: ":")
    process.environment = environment

    // A pipe must be drained while the process is running. The skills CLI can
    // emit enough git/npm output to fill a pipe buffer, which would block the
    // child process forever while this thread waits for it to exit. A temporary
    // file keeps the installer non-blocking and still preserves diagnostics.
    let outputURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("detach-skills-installer-\(UUID().uuidString).log")
    guard FileManager.default.createFile(atPath: outputURL.path, contents: nil) else {
      throw InstallerError.processLaunchFailed("Could not create a temporary installer log.")
    }

    let outputHandle: FileHandle
    do {
      outputHandle = try FileHandle(forWritingTo: outputURL)
    } catch {
      try? FileManager.default.removeItem(at: outputURL)
      throw InstallerError.processLaunchFailed(error.localizedDescription)
    }
    defer {
      try? outputHandle.close()
      try? FileManager.default.removeItem(at: outputURL)
    }

    // --yes covers the skills CLI prompts. A null stdin also prevents npx,
    // git, or npm from waiting on an invisible GUI-app terminal prompt.
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = outputHandle
    process.standardError = outputHandle

    do {
      try process.run()
    } catch {
      throw InstallerError.processLaunchFailed(error.localizedDescription)
    }

    let deadline = Date().addingTimeInterval(90)
    while process.isRunning && Date() < deadline {
      Thread.sleep(forTimeInterval: 0.1)
    }

    if process.isRunning {
      process.terminate()
      process.waitUntilExit()
      throw InstallerError.timedOut
    }

    let output = (try? String(contentsOf: outputURL, encoding: .utf8)) ?? ""
    return InstallerResult(exitCode: process.terminationStatus, output: output)
  }

  private nonisolated static func resolveExecutable(named name: String) -> String? {
    let fileManager = FileManager.default
    var candidates: [String] = []

    if let path = ProcessInfo.processInfo.environment["PATH"] {
      candidates.append(contentsOf: path.split(separator: ":").map { "\($0)/\(name)" })
    }

    candidates.append(contentsOf: [
      "/opt/homebrew/bin/\(name)",
      "/usr/local/bin/\(name)",
      "/usr/bin/\(name)",
    ])

    return candidates.first(where: { fileManager.isExecutableFile(atPath: $0) })
  }

  private nonisolated static func isSafeSource(_ source: String) -> Bool {
    if let url = URL(string: source), url.scheme == "https", url.host != nil,
      url.query == nil, url.fragment == nil
    {
      return true
    }

    let components = source.split(separator: "/", omittingEmptySubsequences: true)
    guard components.count == 2 else { return false }
    return components.allSatisfy { component in
      !component.isEmpty
        && component != "."
        && component != ".."
        && component.allSatisfy { $0.isLetter || $0.isNumber || "._-".contains($0) }
    }
  }

  private nonisolated static func isSafeSkillName(_ name: String) -> Bool {
    !name.isEmpty
      && name.count <= 200
      && !name.contains("/")
      && !name.contains("\\")
      && !name.contains("..")
      && !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
  }

  private nonisolated static func directoryName(for attachment: SkillAttachment) -> String {
    URL(fileURLWithPath: attachment.path)
      .deletingLastPathComponent()
      .lastPathComponent
      .lowercased()
  }

  private struct InstallerResult: Sendable {
    let exitCode: Int32
    let output: String
  }

  private enum DirectoryError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
    case timedOut

    var errorDescription: String? {
      switch self {
      case .invalidURL:
        return "The skills directory URL is invalid."
      case .invalidResponse:
        return "The skills directory returned an invalid response."
      case .httpStatus(let status):
        return "The skills directory returned HTTP " + String(status) + "."
      case .timedOut:
        return "skills.sh took too long to respond. Try the search again."
      }
    }
  }

  private enum InstallerError: LocalizedError {
    case invalidSource
    case cliUnavailable
    case processLaunchFailed(String)
    case commandFailed(output: String)
    case installedSkillNotFound(output: String)
    case timedOut
    case installInProgress

    var errorDescription: String? {
      switch self {
      case .invalidSource:
        return "This skill source is not supported by the skills installer."
      case .cliUnavailable:
        return "Install requires the skills CLI or npx. Install Node.js or the skills CLI, then try again."
      case .processLaunchFailed(let message):
        return "The skills installer could not start: " + message
      case .commandFailed(let output):
        return installerOutputMessage("The skills installer failed.", output: output)
      case .installedSkillNotFound(let output):
        return installerOutputMessage("The installer finished, but Lazzy could not find the installed skill.", output: output)
      case .timedOut:
        return "The skills installer timed out after 90 seconds."
      case .installInProgress:
        return "Another skill is still installing."
      }
    }

    private func installerOutputMessage(_ prefix: String, output: String) -> String {
      let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { return prefix }
      return prefix + "\n\n" + String(trimmed.suffix(800))
    }
  }
}
