import SwiftUI

struct InlineAddServerView: View {
  @ObservedObject var wsManager: WebSocketManager
  @Binding var isPresented: Bool
  @Binding var selectedType: MCPSettingsContentView.MCPType

  @State private var name = ""
  @State private var transport = "stdio"
  @State private var command = ""
  @State private var args = ""
  @State private var url = ""
  @State private var isAdding = false

  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      SettingsCard {
        SettingsRow(title: "Name", controlWidth: 280) {
          AppTextField("For example: GitHub", text: $name)
        }
        SettingsCardDivider()
        SettingsRow(title: "Connection", subtitle: "Run a local command or use a remote endpoint.") {
          AppSegmentedControl(selection: $transport, items: ["stdio", "http"],
            title: { $0 == "stdio" ? "Local" : "Remote" })
        }
        SettingsCardDivider()
        if transport == "stdio" {
          SettingsRow(title: "Command", controlWidth: 280) {
            AppTextField("For example: npx", text: $command)
          }
          SettingsCardDivider()
          SettingsRow(title: "Arguments", controlWidth: 280) {
            AppTextField("@modelcontextprotocol/server-github", text: $args)
          }
        } else {
          SettingsRow(title: "Server URL", controlWidth: 280) {
            AppTextField("https://…", text: $url)
          }
        }
      }
      HStack {
        Spacer()
        Button(action: addServer) {
          HStack(spacing: 7) {
            if isAdding { AppSpinner() }
            Text(isAdding ? "Saving…" : "Save server")
          }
        }
        .buttonStyle(AppButtonStyle(kind: .primary))
        .disabled(!canAdd || isAdding)
      }
    }
  }

  private var canAdd: Bool {
    !name.isEmpty && (transport == "stdio" ? !command.isEmpty : !url.isEmpty)
  }

  private func addServer() {
    isAdding = true
    let argsArray = args.isEmpty ? nil : args.components(separatedBy: " ")
    wsManager.addMCPServer(
      name: name,
      transport: transport,
      command: transport == "stdio" ? command : nil,
      args: argsArray,
      url: (transport == "http") ? url : nil
    )
    // Wait longer to ensure WebSocket response refreshes the list
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
      isAdding = false
      // Switch to Custom tab to show the newly added server
      selectedType = .custom
      withAnimation { isPresented = false }
      // Reset form
      name = ""
      command = ""
      args = ""
      url = ""
    }
  }
}
