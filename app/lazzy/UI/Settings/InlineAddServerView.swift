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
    VStack(alignment: .leading, spacing: 24) {
      HStack(alignment: .top, spacing: 32) {
        // Left Column: Basic Info
        VStack(alignment: .leading, spacing: 16) {
          VStack(alignment: .leading, spacing: 6) {
            Text("Name")
              .font(.appFont(size: 11, weight: .bold))
              .foregroundColor(theme.secondaryTextColor)
            TextField("", text: $name)
              .placeholder(when: name.isEmpty) {
                Text("e.g. GitHub").foregroundColor(theme.secondaryTextColor)
              }
              .foregroundColor(theme.textColor)
              .textFieldStyle(.plain)
              .padding(10)
              .background(theme.inputBackgroundColor)
              .cornerRadius(theme.borderRadius / 1.5)
              .overlay(
                RoundedRectangle(cornerRadius: theme.borderRadius / 1.5).stroke(
                  theme.borderColor, lineWidth: 0.5))
          }

          VStack(alignment: .leading, spacing: 6) {
            Text("Transport")
              .font(.appFont(size: 11, weight: .bold))
              .foregroundColor(theme.secondaryTextColor)
            CustomSegmentedPicker(
              selection: $transport,
              items: ["stdio", "http"],
              titleProvider: { $0.uppercased() }
            )
          }
        }
        .frame(width: 180)

        // Right Column: Dynamic Config
        VStack(alignment: .leading, spacing: 16) {
          if transport == "stdio" {
            VStack(alignment: .leading, spacing: 6) {
              Text("Command")
                .font(.appFont(size: 11, weight: .bold))
                .foregroundColor(theme.secondaryTextColor)
              TextField("", text: $command)
                .placeholder(when: command.isEmpty) {
                  Text("e.g. npx").foregroundColor(theme.secondaryTextColor)
                }
                .foregroundColor(theme.textColor)
                .textFieldStyle(.plain)
                .padding(10)
                .background(theme.inputBackgroundColor)
                .cornerRadius(theme.borderRadius / 1.5)
                .foregroundStyle(theme.textColor)
                .overlay(
                  RoundedRectangle(cornerRadius: theme.borderRadius / 1.5).stroke(
                    theme.borderColor, lineWidth: 0.5)
                )
            }

            VStack(alignment: .leading, spacing: 6) {
              Text("Arguments")
                .font(.appFont(size: 11, weight: .bold))
                .foregroundColor(theme.secondaryTextColor)
              TextField("", text: $args)
                .placeholder(when: args.isEmpty) {
                  Text("e.g. @modelcontextprotocol/server-github")
                    .foregroundColor(theme.secondaryTextColor)
                }
                .foregroundColor(theme.textColor)
                .textFieldStyle(.plain)
                .padding(10)
                .background(theme.inputBackgroundColor)
                .cornerRadius(theme.borderRadius / 1.5)
                .foregroundStyle(theme.textColor)
                .overlay(
                  RoundedRectangle(cornerRadius: theme.borderRadius / 1.5).stroke(
                    theme.borderColor, lineWidth: 0.5)
                )
            }
          } else {
            VStack(alignment: .leading, spacing: 6) {
              Text("Server URL")
                .font(.appFont(size: 11, weight: .bold))
                .foregroundColor(theme.secondaryTextColor)
              TextField("", text: $url)
                .placeholder(when: url.isEmpty) {
                  Text("http://...").foregroundColor(theme.secondaryTextColor)
                }
                .foregroundColor(theme.textColor)
                .textFieldStyle(.plain)
                .padding(10)
                .background(theme.inputBackgroundColor)
                .cornerRadius(theme.borderRadius / 1.5)
                .foregroundStyle(theme.textColor)
                .overlay(
                  RoundedRectangle(cornerRadius: theme.borderRadius / 1.5).stroke(
                    theme.borderColor, lineWidth: 0.5)
                )
            }
          }
        }
      }

      HStack {
        Spacer()
        Button(action: addServer) {
          if isAdding {
            ProgressView().scaleEffect(0.6)
          } else {
            Text("Save Server Configuration")
              .font(.appFont(size: 13, weight: .bold))
              .foregroundColor(.white)
              .padding(.horizontal, 24)
              .padding(.vertical, 10)
              .background(canAdd ? theme.accentColor : Color.gray.opacity(0.3))
              .cornerRadius(theme.borderRadius / 1.5)
          }
        }
        .buttonStyle(.plain)
        .disabled(!canAdd || isAdding)
      }
      .padding(.top, 8)
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
