import SwiftUI

struct RemoteMachinesSettingsView: View {
  @ObservedObject private var store = RemoteMachineStore.shared
  @ObservedObject private var theme = ThemeManager.shared
  @State private var showingAddMachine = false

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 5) {
          Text("Machines").font(.appFont(size: 19, weight: .semibold))
          Text("Run agents on a Mac or Linux machine you can reach over SSH.")
            .font(.appFont(size: 12)).foregroundStyle(theme.secondaryTextColor)
        }
        Spacer()
        Button { showingAddMachine = true } label: {
          Label("Add machine", systemImage: "plus").font(.appFont(size: 12, weight: .medium))
        }
      }

      if store.machines.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          Image(systemName: "server.rack").font(.system(size: 19)).foregroundStyle(theme.secondaryTextColor)
          Text("No remote machines yet").font(.appFont(size: 13, weight: .medium))
          Text("Choose a host from your SSH config, or enter user@host. Add a folder on that machine, then select it in the composer.")
            .font(.appFont(size: 11)).foregroundStyle(theme.secondaryTextColor)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.textColor.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
      } else {
        ScrollView {
          VStack(spacing: 10) {
            ForEach(store.machines) { machine in
              RemoteMachineCard(machine: machine, store: store)
            }
          }
        }
        .scrollIndicators(.hidden)
      }

      Spacer(minLength: 0)
      Text("Detach installs its runner in your home folder on first use. SSH keys stay with your Mac; the runner only listens on the machine’s loopback interface.")
        .font(.appFont(size: 10)).foregroundStyle(theme.secondaryTextColor)
        .fixedSize(horizontal: false, vertical: true)
      Text("Sign in to your coding-agent CLIs on the remote machine first. Detach keeps their credentials on that machine and does not copy your Mac’s provider keys.")
        .font(.appFont(size: 10)).foregroundStyle(theme.secondaryTextColor)
        .fixedSize(horizontal: false, vertical: true)
    }
    .foregroundStyle(theme.textColor)
    .sheet(isPresented: $showingAddMachine) { AddRemoteMachineSheet(store: store) }
  }
}

private struct RemoteMachineCard: View {
  let machine: RemoteMachine
  @ObservedObject var store: RemoteMachineStore
  @ObservedObject private var theme = ThemeManager.shared
  @State private var showingAddWorkspace = false

  private var currentMachine: RemoteMachine? { store.machine(id: machine.id) }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 9) {
        Image(systemName: "server.rack").foregroundStyle(theme.secondaryTextColor)
        VStack(alignment: .leading, spacing: 2) {
          Text(machine.name).font(.appFont(size: 13, weight: .medium))
          Text("\(machine.host) · \(machine.platform.title)")
            .font(.appFont(size: 10)).foregroundStyle(theme.secondaryTextColor)
        }
        Spacer()
        Button { showingAddWorkspace = true } label: {
          Label("Add folder", systemImage: "plus").font(.appFont(size: 11))
        }.buttonStyle(.plain)
      }

      if let workspaces = currentMachine?.workspaces, !workspaces.isEmpty {
        ForEach(workspaces) { workspace in
          HStack(spacing: 8) {
            Image(systemName: "folder").foregroundStyle(theme.secondaryTextColor)
            VStack(alignment: .leading, spacing: 1) {
              Text(workspace.name).font(.appFont(size: 11, weight: .medium))
              Text(workspace.path).font(.appFont(size: 9)).foregroundStyle(theme.secondaryTextColor)
                .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 4)
            Button {
              store.removeWorkspace(machineID: machine.id, workspaceID: workspace.id)
            } label: {
              Image(systemName: "xmark").font(.system(size: 9)).frame(width: 22, height: 22)
            }.buttonStyle(.plain).help("Remove folder")
          }
          .padding(.horizontal, 8).padding(.vertical, 5)
          .background(theme.textColor.opacity(0.025), in: RoundedRectangle(cornerRadius: 6))
        }
      } else {
        Text("Add a folder to make this machine available in the composer.")
          .font(.appFont(size: 10)).foregroundStyle(theme.secondaryTextColor)
      }
    }
    .padding(12)
    .background(theme.textColor.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    .sheet(isPresented: $showingAddWorkspace) { AddRemoteWorkspaceSheet(machine: machine, store: store) }
  }
}

private struct AddRemoteMachineSheet: View {
  @ObservedObject var store: RemoteMachineStore
  @ObservedObject private var theme = ThemeManager.shared
  @Environment(\.dismiss) private var dismiss
  @State private var host = ""
  @State private var name = ""
  @State private var isConnecting = false
  @State private var error: String?

  private var aliases: [String] { RemoteSSHClient.configuredHostAliases() }

  var body: some View {
    VStack(alignment: .leading, spacing: 13) {
      Text("Add a machine").font(.appFont(size: 17, weight: .semibold))
      Text("Detach connects over SSH and installs its runner the first time you use a remote folder.")
        .font(.appFont(size: 12)).foregroundStyle(theme.secondaryTextColor)
        .fixedSize(horizontal: false, vertical: true)
      Text("SSH host").font(.appFont(size: 11, weight: .medium))
      AppTextField("Host alias or user@host", text: $host)

      if !aliases.isEmpty {
        Text("From your SSH config").font(.appFont(size: 10)).foregroundStyle(theme.secondaryTextColor)
        ScrollView(.horizontal) {
          HStack(spacing: 6) {
            ForEach(aliases, id: \.self) { alias in
              Button(alias) { host = alias }
                .font(.appFont(size: 10)).buttonStyle(.plain)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(theme.textColor.opacity(0.06), in: Capsule())
            }
          }
        }.scrollIndicators(.hidden)
      }

      Text("Name (optional)").font(.appFont(size: 11, weight: .medium))
      AppTextField("Build server", text: $name)
      if let error {
        Text(error).font(.appFont(size: 11)).foregroundStyle(theme.textColor)
          .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
      }
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button { addMachine() } label: {
          if isConnecting { ProgressView().controlSize(.small) } else { Text("Connect") }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(isConnecting || host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .padding(22).frame(width: 430).foregroundStyle(theme.textColor)
    .background(theme.solidBackground).tint(theme.textColor)
  }

  private func addMachine() {
    let candidate = host.trimmingCharacters(in: .whitespacesAndNewlines)
    guard RemoteSSHClient.isValidHost(candidate) else { error = RemoteMachineError.invalidHost.localizedDescription; return }
    isConnecting = true; error = nil
    Task {
      do {
        let platform = try await RemoteSSHClient.inspect(host: candidate)
        _ = try store.addMachine(host: candidate, name: name, platform: platform)
        dismiss()
      } catch {
        self.error = error.localizedDescription
      }
      isConnecting = false
    }
  }
}

private struct AddRemoteWorkspaceSheet: View {
  let machine: RemoteMachine
  @ObservedObject var store: RemoteMachineStore
  @ObservedObject private var theme = ThemeManager.shared
  @Environment(\.dismiss) private var dismiss
  @State private var path = ""
  @State private var name = ""
  @State private var isChecking = false
  @State private var error: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 13) {
      Text("Add a remote folder").font(.appFont(size: 17, weight: .semibold))
      Text("Folder on \(machine.name)").font(.appFont(size: 12)).foregroundStyle(theme.secondaryTextColor)
      AppTextField("/home/you/project", text: $path)
      Text("Folder name (optional)").font(.appFont(size: 11, weight: .medium))
      AppTextField("Project", text: $name)
      Text("Detach checks that the folder exists over SSH.")
        .font(.appFont(size: 10)).foregroundStyle(theme.secondaryTextColor)
      if let error {
        Text(error).font(.appFont(size: 11)).foregroundStyle(theme.textColor)
          .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
      }
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button { addWorkspace() } label: {
          if isChecking { ProgressView().controlSize(.small) } else { Text("Add folder") }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(isChecking || path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .padding(22).frame(width: 430).foregroundStyle(theme.textColor)
    .background(theme.solidBackground).tint(theme.textColor)
  }

  private func addWorkspace() {
    isChecking = true; error = nil
    Task {
      do {
        let canonicalPath = try await RemoteSSHClient.validateWorkspace(host: machine.host, path: path)
        try store.addWorkspace(machineID: machine.id, name: name, path: canonicalPath)
        dismiss()
      } catch {
        self.error = error.localizedDescription
      }
      isChecking = false
    }
  }
}
