import Foundation

enum RemoteSSHClient {
  static func isValidHost(_ host: String) -> Bool {
    guard !host.isEmpty, !host.hasPrefix("-") else { return false }
    return host.range(of: #"^[A-Za-z0-9_.@:-]{1,255}$"#, options: .regularExpression) != nil
  }

  static func configuredHostAliases() -> [String] {
    let configURL = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".ssh", isDirectory: true)
      .appendingPathComponent("config")
    guard let contents = try? String(contentsOf: configURL, encoding: .utf8) else { return [] }
    var aliases = Set<String>()
    for line in contents.split(whereSeparator: \.isNewline) {
      let fields = line.split(whereSeparator: \.isWhitespace)
      guard fields.first?.lowercased() == "host" else { continue }
      for alias in fields.dropFirst().map(String.init) where !alias.contains("*") && !alias.contains("?") && !alias.hasPrefix("!") {
        if isValidHost(alias) { aliases.insert(alias) }
      }
    }
    return aliases.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
  }

  static func inspect(host: String) async throws -> RemoteMachinePlatform {
    let response = try await run(host: host, command: "uname -s && uname -m")
    let values = response.split(whereSeparator: \.isNewline).map(String.init)
    guard values.count >= 2 else { throw RemoteMachineError.unsupportedPlatform }
    return try RemoteMachinePlatform.detect(os: values[0], architecture: values[1])
  }

  static func validateWorkspace(host: String, path: String) async throws -> String {
    guard path.hasPrefix("/") || path == "~" || path.hasPrefix("~/") else {
      throw RemoteMachineError.invalidWorkspacePath
    }
    let directory: String
    if path == "~" {
      directory = "\"$HOME\""
    } else if path.hasPrefix("~/") {
      directory = "\"$HOME\"/\(shellQuote(String(path.dropFirst(2))))"
    } else {
      directory = shellQuote(path)
    }
    let command = "REMOTE_PATH=\(directory); test -d \"$REMOTE_PATH\" && cd \"$REMOTE_PATH\" && pwd -P"
    let canonicalPath = try await run(host: host, command: command).trimmingCharacters(in: .whitespacesAndNewlines)
    guard canonicalPath.hasPrefix("/") else { throw RemoteMachineError.invalidWorkspacePath }
    return canonicalPath
  }

  static func upload(runtime: URL, to host: String) async throws {
    let command = "umask 077; mkdir -p \"$HOME/.local/share/detach\" && cat > \"$HOME/.local/share/detach/detach-runtime.new\" && chmod 700 \"$HOME/.local/share/detach/detach-runtime.new\" && mv \"$HOME/.local/share/detach/detach-runtime.new\" \"$HOME/.local/share/detach/detach-runtime\""
    _ = try await run(host: host, command: command, inputFile: runtime)
  }

  static func ensureRuntime(host: String, port: Int, token: String) async throws {
    let command = "if ! curl -fsS -H 'Authorization: Bearer \(token)' http://127.0.0.1:\(port)/ >/dev/null 2>&1; then nohup env PORT=\(port) DETACH_RUNTIME_TOKEN=\(token) \"$HOME/.local/share/detach/detach-runtime\" >/dev/null 2>&1 </dev/null & sleep 1; fi; curl -fsS -H 'Authorization: Bearer \(token)' http://127.0.0.1:\(port)/ >/dev/null"
    _ = try await run(host: host, command: command)
  }

  static func runtimeIsReady(host: String, port: Int, token: String) async -> Bool {
    let command = "curl -fsS -H 'Authorization: Bearer \(token)' http://127.0.0.1:\(port)/ >/dev/null 2>&1"
    do {
      _ = try await run(host: host, command: command)
      return true
    } catch {
      return false
    }
  }

  static func startTunnel(host: String, localPort: Int, remotePort: Int) throws -> Process {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
    process.arguments = [
      "-N", "-T",
      "-o", "BatchMode=yes",
      "-o", "ConnectTimeout=8",
      "-o", "ExitOnForwardFailure=yes",
      "-o", "ServerAliveInterval=15",
      "-o", "ServerAliveCountMax=3",
      "-L", "\(localPort):127.0.0.1:\(remotePort)",
      host,
    ]
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    return process
  }

  private static func run(host: String, command: String, inputFile: URL? = nil) async throws -> String {
    guard isValidHost(host) else { throw RemoteMachineError.invalidHost }
    return try await Task.detached(priority: .userInitiated) {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
      process.arguments = [
        "-T", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", host,
        "sh -c \(shellQuote(command))",
      ]
      let output = Pipe()
      let errors = Pipe()
      let input = Pipe()
      process.standardOutput = output
      process.standardError = errors
      process.standardInput = input
      do {
        try process.run()
        if let inputFile {
          let file = try FileHandle(forReadingFrom: inputFile)
          defer { try? file.close() }
          while let data = try file.read(upToCount: 1024 * 1024), !data.isEmpty {
            try input.fileHandleForWriting.write(contentsOf: data)
          }
        }
        try? input.fileHandleForWriting.close()
        let response = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
          let detail = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
          throw RemoteMachineError.ssh(detail?.isEmpty == false ? detail! : "SSH could not connect to \(host). Check the host and your SSH key.")
        }
        return String(data: response, encoding: .utf8) ?? ""
      } catch let error as RemoteMachineError {
        throw error
      } catch {
        process.terminate()
        throw RemoteMachineError.ssh(error.localizedDescription)
      }
    }.value
  }

  nonisolated private static func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }
}
