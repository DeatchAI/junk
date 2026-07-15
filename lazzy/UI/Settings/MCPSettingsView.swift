//
//  MCPSettingsView.swift
//  lazzy
//
//  MCP Server configuration view - polished UI
//

import SDWebImageSwiftUI
import SwiftUI

// MARK: - MCP Settings Content View (embedded in SettingsView)

struct MCPSettingsContentView: View {
  @ObservedObject var wsManager: WebSocketManager
  @ObservedObject private var theme = ThemeManager.shared

  @State private var searchText = ""
  @State private var isAddingServer = false
  @State private var currentOffset = 0
  private let pageSize = 10
  @State private var searchTask: Task<Void, Never>? = nil

  enum MCPType: String, CaseIterable, Identifiable {
    case builtin = "Built-in"
    case custom = "Custom"
    var id: String { self.rawValue }
  }
  @State private var selectedType: MCPType = .builtin

  init(wsManager: WebSocketManager, startInAddServerMode: Bool = false) {
    self.wsManager = wsManager
    _isAddingServer = State(initialValue: startInAddServerMode)
    _selectedType = State(initialValue: startInAddServerMode ? .custom : .builtin)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      if isAddingServer {
        // Add Server View
        VStack(alignment: .leading, spacing: 24) {
          // Inner Header with Back Button
          HStack(spacing: 12) {
            Button(action: { withAnimation(.easeInOut) { isAddingServer = false } }) {
              Image(systemName: "arrow.left")
                .font(.appFont(size: 14, weight: .semibold))
                .foregroundColor(theme.textColor)
                .frame(width: 32, height: 32)
                .background(theme.textColor.opacity(0.1))
                .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Text("Add MCP Server")
              // .font(.appFont(size: 20, weight: .bold))
              .font(.custom("Sick-Regular", size: 20))
              .foregroundColor(theme.textColor)
          }

          InlineAddServerView(
            wsManager: wsManager, isPresented: $isAddingServer, selectedType: $selectedType
          )
        }
      } else {
        // Main List View
        VStack(alignment: .leading, spacing: 20) {
          // Header Section
          VStack(alignment: .leading, spacing: 12) {
            Text(selectedType == .builtin ? "Built-in Integrations" : "Custom MCP Servers")
              // .font(.appFont(size: 24, weight: .bold))
              .font(.custom("Sick-Regular", size: 24))
              .foregroundColor(theme.textColor)

            Text(
              "MCP servers / Integrations expose data sources or tools to get the Agent through a standardized interface - essentially acting like plugins for Detach. Add a custom server, or use the presets from over 500+ integrations to get started with popular servers. [Learn more.](https://docs.modelcontextprotocol.io)"
            )
            .font(.appFont(size: 13))
            .foregroundColor(theme.secondaryTextColor)
            .lineSpacing(4)

            CustomSegmentedPicker(
              selection: $selectedType,
              items: MCPType.allCases,
              titleProvider: { $0.rawValue }
            )
            .frame(width: 200)
            .padding(.top, 4)
          }
          .padding(.bottom, 8)

          // Search bar + Add button row
          HStack(spacing: 12) {
            // Search field
            HStack(spacing: 8) {
              Image(systemName: "magnifyingglass")
                .font(.appFont(size: 12))
                .foregroundColor(theme.secondaryTextColor)

              TextField("", text: $searchText)
                .placeholder(when: searchText.isEmpty) {
                  Text("Search MCP Servers")
                    .foregroundColor(theme.secondaryTextColor)
                }
                .textFieldStyle(.plain)
                .font(.appFont(size: 13))
                .foregroundColor(theme.textColor)
                .onChange(of: searchText) { oldValue, newValue in
                  // Debounced search for Composio integrations
                  searchTask?.cancel()
                  searchTask = Task {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    if !Task.isCancelled {
                      currentOffset = 0
                      loadIntegrations()
                    }
                  }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(theme.inputBackgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: theme.borderRadius / 1.5))
            .overlay(
              RoundedRectangle(cornerRadius: theme.borderRadius / 1.5)
                .stroke(theme.borderColor, lineWidth: 0.5)
            )

            // Add button
            Button(action: {
              withAnimation(.easeInOut) {
                isAddingServer = true
              }
            }) {
              HStack(spacing: 4) {
                Image(systemName: "plus")
                  .font(.appFont(size: 12, weight: .semibold))
                Text("Add")
                  .font(.appFont(size: 12, weight: .semibold))
              }
              .foregroundColor(theme.textColor)
              .padding(.horizontal, 14)
              .padding(.vertical, 8)
              .background(Color.clear)
              .clipShape(RoundedRectangle(cornerRadius: theme.borderRadius / 1.5))
              .overlay(
                RoundedRectangle(cornerRadius: theme.borderRadius / 1.5)
                  .stroke(theme.borderColor, lineWidth: 0.5)
              )
            }
            .buttonStyle(.plain)
          }

          // List Section
          ScrollView {
            VStack(alignment: .leading, spacing: 12) {
              if wsManager.isLoadingComposio && wsManager.mcpServers.isEmpty
                && wsManager.composioIntegrations.isEmpty
              {
                loadingView
              } else if let error = wsManager.composioError {
                errorView(message: error)
              } else {
                LazyVStack(spacing: 12) {
                  let list = filteredList
                  if list.isEmpty {
                    emptyStateView
                  } else {
                    ForEach(list) { item in
                      UnifiedServerRow(
                        item: item,
                        wsManager: wsManager
                      )
                    }

                    if selectedType == .builtin && wsManager.hasMoreComposioIntegrations {
                      Button(action: loadMore) {
                        HStack {
                          if wsManager.isLoadingComposio {
                            ProgressView().scaleEffect(0.6)
                          } else {
                            Text(
                              "Load More (\(wsManager.totalComposioIntegrations - wsManager.composioIntegrations.count) remaining)"
                            )
                            .font(.appFont(size: 12, weight: .medium))
                            .foregroundColor(theme.backgroundColor)
                          }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(theme.accentColor)
                        .cornerRadius(5)
                      }
                      .buttonStyle(.plain)
                    }
                  }
                }
              }
            }
            .padding(.bottom, 20)
          }
          .scrollIndicators(selectedType == .builtin ? .hidden : .visible)
        }
      }
    }
    .onAppear {
      wsManager.listMCPServers()
      loadIntegrations()
    }
    .onChange(of: selectedType) { oldValue, newValue in
      if newValue == .custom {
        wsManager.listMCPServers()
      }
    }
  }

  // MARK: - Combined List Logic

  enum SettingsItem: Identifiable {
    case custom(MCPServer)
    case preset(ComposioIntegration)

    var id: String {
      switch self {
      case .custom(let server): return "custom-\(server.id)"
      case .preset(let integration): return "preset-\(integration.id)"
      }
    }

    var name: String {
      switch self {
      case .custom(let server): return server.name
      case .preset(let integration): return integration.name
      }
    }

    var description: String {
      switch self {
      case .custom(let server):
        if server.transport == "stdio" {
          return server.command ?? "STDIO server"
        } else {
          return server.url ?? "Remote server"
        }
      case .preset(let integration):
        return integration.description
      }
    }
  }

  private var filteredList: [SettingsItem] {
    switch selectedType {
    case .builtin:
      // Add presets (already filtered/paginated by server)
      return wsManager.composioIntegrations.map { .preset($0) }
    case .custom:
      // Add custom servers (filtered locally by name)
      return wsManager.mcpServers.filter {
        searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText)
          || ($0.command?.localizedCaseInsensitiveContains(searchText) ?? false)
          || ($0.url?.localizedCaseInsensitiveContains(searchText) ?? false)
      }.map { .custom($0) }
    }
  }

  // MARK: - Integration Logic

  private func loadIntegrations() {
    wsManager.listComposioIntegrations(
      limit: pageSize,
      offset: currentOffset,
      query: searchText.isEmpty ? nil : searchText
    )
  }

  private func loadMore() {
    currentOffset += pageSize
    loadIntegrations()
  }

  // MARK: - Components

  private func errorView(message: String) -> some View {
    VStack(spacing: 12) {
      Image(systemName: "exclamationmark.triangle")
        .font(.appFont(size: 24))
        .foregroundColor(.orange)
      Text(message)
        .font(.appFont(size: 13))
        .foregroundColor(theme.secondaryTextColor)
        .multilineTextAlignment(.center)
        .padding(.horizontal)
      Button("Retry") {
        currentOffset = 0
        loadIntegrations()
      }
      .buttonStyle(.bordered)
    }
    .frame(maxWidth: .infinity, minHeight: 100)
  }

  private var loadingView: some View {
    HStack {
      ProgressView()
        .scaleEffect(0.7)
      Text("Loading integrations...")
        .font(.appFont(size: 13))
        .foregroundColor(theme.secondaryTextColor)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 40)
  }

  private var emptyStateView: some View {
    VStack(spacing: 12) {
      Image(systemName: "puzzlepiece.extension")
        .font(.appFont(size: 40))
        .foregroundColor(theme.secondaryTextColor.opacity(0.3))

      Text("No Integrations Found")
        .font(.appFont(size: 15, weight: .semibold))
        .foregroundColor(theme.textColor.opacity(0.6))

      Text("Search for another toolkit or add a custom MCP server")
        .font(.appFont(size: 13))
        .foregroundColor(theme.secondaryTextColor)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 60)
  }
}

// MARK: - Inline Add Server View

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
            Text("NAME")
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
            Text("TRANSPORT")
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
              Text("COMMAND")
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
              Text("ARGUMENTS")
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
              Text("SERVER URL")
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

// MARK: - Unified Server Row

struct UnifiedServerRow: View {
  let item: MCPSettingsContentView.SettingsItem
  @ObservedObject var wsManager: WebSocketManager

  @State private var isHovered = false
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    HStack(spacing: 14) {
      // Icon
      iconView

      // Info
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 8) {
          Text(item.name)
            .font(.appFont(size: 14, weight: .semibold))
            .foregroundColor(theme.textColor)

          if case .custom(let server) = item {
            statusBadge(server: server)
          }
        }

        Text(item.description)
          .font(.appFont(size: 11))
          .foregroundColor(theme.secondaryTextColor)
          .lineLimit(1)
      }

      Spacer()

      // Actions
      actionView
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 14)
    .background(
      RoundedRectangle(cornerRadius: theme.borderRadius / 1.5)
        .fill(isHovered ? theme.textColor.opacity(0.05) : theme.textColor.opacity(0.02))
    )
    .overlay(
      RoundedRectangle(cornerRadius: theme.borderRadius / 1.5)
        .stroke(theme.borderColor, lineWidth: 0.5)
    )
    .onHover { hovering in
      withAnimation(.easeInOut(duration: 0.15)) {
        isHovered = hovering
      }
    }
  }

  @ViewBuilder
  private var iconView: some View {
    switch item {
    case .custom(let server):
      ZStack {
        RoundedRectangle(cornerRadius: 8)
          .fill(iconGradient(for: server.name))
          .frame(width: 36, height: 36)

        Text(String(server.name.prefix(1)).uppercased())
          .font(.appFont(size: 14, weight: .bold))
          .foregroundColor(.white)
      }
    case .preset(let integration):
      if let url = URL(string: integration.icon), integration.icon.contains("://") {
        WebImage(
          url: url, options: [],
          context: [.imageThumbnailPixelSize: CGSize.zero]
        )
        .resizable()
        .frame(width: 36, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 8))
      } else {
        ZStack {
          RoundedRectangle(cornerRadius: 8)
            .fill(theme.textColor.opacity(0.05))
            .frame(width: 36, height: 36)
          Text(integration.icon)
            .font(.appFont(size: 20))
        }
      }
    }
  }

  @ViewBuilder
  private var actionView: some View {
    switch item {
    case .custom(let server):
      HStack(spacing: 12) {
        if let status = server.status, status.connected {
          Button(action: { wsManager.disconnectMCPServer(id: server.id) }) {
            Image(systemName: "stop.fill")
              .font(.appFont(size: 12))
              .padding(6)
              .background(Color.white.opacity(0.1))
              .clipShape(Circle())
          }
          .buttonStyle(.plain)
          .help("Disconnect")
        } else {
          Button(action: { wsManager.connectMCPServer(id: server.id) }) {
            Image(systemName: "play.fill")
              .font(.appFont(size: 12))
              .padding(6)
              .background(Color.white.opacity(0.1))
              .clipShape(Circle())
          }
          .buttonStyle(.plain)
          .help("Connect")
        }

        Button(action: { wsManager.deleteMCPServer(id: server.id) }) {
          Image(systemName: "trash")
            .font(.appFont(size: 14))
            .foregroundColor(Color.red.opacity(0.7))
        }
        .buttonStyle(.plain)
        .help("Delete")
      }
      .opacity(isHovered ? 1 : 0)

    case .preset(let integration):
      if integration.connected {
        HStack(spacing: 8) {
          HStack(spacing: 4) {
            Circle().fill(Color.green).frame(width: 6, height: 6)
            Text("Connected")
              .font(.appFont(size: 11, weight: .medium))
              .foregroundColor(Color.green)
          }
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(Color.green.opacity(0.1))
          .clipShape(Capsule())

          Button(action: {
            if let connectionId = integration.connectionId {
              wsManager.disconnectComposioAccount(connectionId: connectionId)
            }
          }) {
            Image(systemName: "xmark.circle.fill")
              .font(.appFont(size: 14))
              .foregroundColor(theme.secondaryTextColor.opacity(0.8))
              .frame(width: 24, height: 24)
              .background(Color.clear)
          }
          .buttonStyle(.plain)
          .help("Disconnect")
        }
      } else {
        Button(action: {
          wsManager.connectComposioAccount(toolkit: integration.id)
        }) {
          if wsManager.connectingToolkit == integration.id {
            ProgressView().scaleEffect(0.5).tint(theme.textColor)
          } else {
            Image(systemName: "plus")
              .font(.appFont(size: 12, weight: .bold))
              .foregroundColor(theme.textColor)
          }
        }
        .buttonStyle(.plain)
        .frame(width: 28, height: 28)
        .background(theme.textColor.opacity(0.1))
        .clipShape(Circle())
        .disabled(wsManager.connectingToolkit != nil)
      }
    }
  }

  private func statusBadge(server: MCPServer) -> some View {
    Group {
      if let status = server.status, status.connected {
        Text("\(status.tools?.count ?? 0) tools")
          .font(.appFont(size: 10, weight: .medium))
          .foregroundColor(Color.green.opacity(0.8))
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(Color.green.opacity(0.1))
          .clipShape(Capsule())
      } else if server.status?.error != nil {
        Text("Error")
          .font(.appFont(size: 10, weight: .medium))
          .foregroundColor(Color.red.opacity(0.8))
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(Color.red.opacity(0.1))
          .clipShape(Capsule())
      }
    }
  }

  private func iconGradient(for name: String) -> LinearGradient {
    let hash = name.hashValue
    let hue = Double(abs(hash) % 360) / 360.0
    return LinearGradient(
      colors: [
        Color(hue: hue, saturation: 0.6, brightness: 0.7),
        Color(hue: hue, saturation: 0.7, brightness: 0.5),
      ],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }
}

// MARK: - Preview

#Preview {
  MCPSettingsContentView(wsManager: WebSocketManager())
    .frame(width: 500, height: 400)
    .background(Color(nsColor: NSColor(white: 0.08, alpha: 1.0)))
}
