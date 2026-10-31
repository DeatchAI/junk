import Combine
import Foundation

enum RemoteMachinePlatform: String, Codable, CaseIterable {
  case macOSArm64 = "darwin-arm64"
  case macOSIntel = "darwin-x64"
  case linuxArm64 = "linux-arm64"
  case linuxIntel = "linux-x64"

  var title: String {
    switch self {
    case .macOSArm64: "macOS · Apple silicon"
    case .macOSIntel: "macOS · Intel"
    case .linuxArm64: "Linux · ARM64"
    case .linuxIntel: "Linux · x64"
    }
  }

  static func detect(os: String, architecture: String) throws -> Self {
    let normalizedOS = os.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let normalizedArchitecture = architecture.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    switch (normalizedOS, normalizedArchitecture) {
    case ("darwin", "arm64"), ("darwin", "aarch64"): return .macOSArm64
    case ("darwin", "x86_64"), ("darwin", "amd64"): return .macOSIntel
    case ("linux", "arm64"), ("linux", "aarch64"): return .linuxArm64
    case ("linux", "x86_64"), ("linux", "amd64"): return .linuxIntel
    default: throw RemoteMachineError.unsupportedPlatform
    }
  }
}

struct RemoteWorkspace: Codable, Identifiable, Equatable {
  var id: UUID = UUID()
  var name: String
  var path: String
}

struct RemoteMachine: Codable, Identifiable, Equatable {
  var id: UUID = UUID()
  var name: String
  var host: String
  var platform: RemoteMachinePlatform
  var remotePort: Int
  var workspaces: [RemoteWorkspace] = []
}

struct RemoteWorkspaceSelection: Equatable, Identifiable {
  let machineID: UUID
  let machineName: String
  let host: String
  let platform: RemoteMachinePlatform
  let workspaceID: UUID
  let name: String
  let path: String

  var id: String { "\(machineID.uuidString):\(workspaceID.uuidString)" }
}

enum RemoteMachineConnectionStatus: Equatable {
  case idle
  case connecting
  case connected
  case failed(String)
}

enum RemoteMachineError: LocalizedError {
  case invalidHost
  case unsupportedPlatform
  case invalidWorkspacePath
  case machineNotFound
  case runtimeArtifactUnavailable
  case ssh(String)
  case tunnelUnavailable

  var errorDescription: String? {
    switch self {
    case .invalidHost:
      "Enter an SSH host alias or user@host."
    case .unsupportedPlatform:
      "This machine needs macOS or Linux on Apple silicon, Intel, or AMD64."
    case .invalidWorkspacePath:
      "Enter a folder path that exists on the remote machine."
    case .machineNotFound:
      "This machine is no longer in your saved list."
    case .runtimeArtifactUnavailable:
      "Detach could not download the remote runner. Check your connection and try again."
    case .ssh(let detail):
      detail
    case .tunnelUnavailable:
      "Detach could not open a secure connection to the remote runner. Check that SSH is reachable and try again."
    }
  }
}

@MainActor
final class RemoteMachineStore: ObservableObject {
  static let shared = RemoteMachineStore()

  @Published private(set) var machines: [RemoteMachine] = []
  private let defaults: UserDefaults
  private let storageKey = "remote.machines.v1"

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    if let data = defaults.data(forKey: storageKey),
      let stored = try? JSONDecoder().decode([RemoteMachine].self, from: data)
    {
      machines = stored
    }
  }

  var workspaces: [RemoteWorkspaceSelection] {
    machines.flatMap { machine in
      machine.workspaces.map { workspace in
        RemoteWorkspaceSelection(
          machineID: machine.id,
          machineName: machine.name,
          host: machine.host,
          platform: machine.platform,
          workspaceID: workspace.id,
          name: workspace.name,
          path: workspace.path
        )
      }
    }
  }

  func machine(id: UUID) -> RemoteMachine? { machines.first { $0.id == id } }

  func selection(machineID: UUID, path: String) -> RemoteWorkspaceSelection? {
    guard let machine = machine(id: machineID) else { return nil }
    let saved = machine.workspaces.first { $0.path == path }
    return RemoteWorkspaceSelection(
      machineID: machine.id,
      machineName: machine.name,
      host: machine.host,
      platform: machine.platform,
      workspaceID: saved?.id ?? UUID(),
      name: saved?.name ?? URL(fileURLWithPath: path).lastPathComponent,
      path: path
    )
  }

  func firstWorkspaceSelection(machineID: UUID) -> RemoteWorkspaceSelection? {
    guard let machine = machine(id: machineID), let workspace = machine.workspaces.first else { return nil }
    return RemoteWorkspaceSelection(
      machineID: machine.id, machineName: machine.name, host: machine.host,
      platform: machine.platform, workspaceID: workspace.id, name: workspace.name, path: workspace.path
    )
  }

  @discardableResult
  func addMachine(host: String, name: String, platform: RemoteMachinePlatform) throws -> RemoteMachine {
    let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
    guard RemoteSSHClient.isValidHost(normalizedHost) else { throw RemoteMachineError.invalidHost }
    if let existing = machines.first(where: { $0.host.caseInsensitiveCompare(normalizedHost) == .orderedSame }) {
      return existing
    }
    let machine = RemoteMachine(
      name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? normalizedHost : name,
      host: normalizedHost,
      platform: platform,
      remotePort: Int.random(in: 38_000...53_000)
    )
    machines.append(machine)
    persist()
    return machine
  }

  func addWorkspace(machineID: UUID, name: String, path: String) throws {
    guard let index = machines.firstIndex(where: { $0.id == machineID }) else {
      throw RemoteMachineError.machineNotFound
    }
    guard path.hasPrefix("/") || path == "~" || path.hasPrefix("~/") else {
      throw RemoteMachineError.invalidWorkspacePath
    }
    guard !machines[index].workspaces.contains(where: { $0.path == path }) else { return }
    let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
    machines[index].workspaces.append(RemoteWorkspace(
      name: title.isEmpty ? URL(fileURLWithPath: path).lastPathComponent : title,
      path: path
    ))
    persist()
  }

  func removeWorkspace(machineID: UUID, workspaceID: UUID) {
    guard let index = machines.firstIndex(where: { $0.id == machineID }) else { return }
    machines[index].workspaces.removeAll { $0.id == workspaceID }
    persist()
  }

  func removeMachine(id: UUID) {
    machines.removeAll { $0.id == id }
    RemoteMachineRuntimeConnector.shared.disconnect(machineID: id)
    try? RemoteMachineTokenVault.remove(machineID: id)
    persist()
  }

  private func persist() {
    guard let data = try? JSONEncoder().encode(machines) else { return }
    defaults.set(data, forKey: storageKey)
  }
}
