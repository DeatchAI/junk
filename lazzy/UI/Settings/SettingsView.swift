//
//  SettingsView.swift
//  lazzy
//
//  Main settings view that contains different settings sections
//

import SwiftUI

struct SettingsView: View {
  @ObservedObject var wsManager: WebSocketManager
  var onRunWorkflow: ((QuickAction) -> Void)? = nil
  var launchIntent: SettingsLaunchIntent?
  @Environment(\.dismiss) var dismiss

  @State private var selectedTab = "general"
  @State private var isCloseHovered = false
  @State private var isSidebarHovered = false
  @State private var isSidebarVisible = true

  // Theme manager
  @ObservedObject private var theme = ThemeManager.shared

  init(
    wsManager: WebSocketManager,
    onRunWorkflow: ((QuickAction) -> Void)? = nil,
    launchIntent: SettingsLaunchIntent? = nil
  ) {
    self.wsManager = wsManager
    self.onRunWorkflow = onRunWorkflow
    self.launchIntent = launchIntent
    _selectedTab = State(initialValue: launchIntent?.settingsTab ?? "general")
  }

  private var menuItems: [(String, String)] {
    return [
      ("General", "general"),
      ("Quick Actions", "quick_actions"),
      ("Workflows", "workflows"),
      ("MCP", "mcp"),
      ("Secrets", "secrets"),
      ("Appearance", "appearance"),
      ("Shortcuts", "shortcuts"),
      ("Privacy", "privacy"),
      ("About", "about"),
    ]
  }

  var body: some View {
    VStack(spacing: 0) {
      // Header / Navigation Bar
      HStack {
        // macOS Style Close Button
        Button(action: { dismiss() }) {
          Circle()
            .fill(Color.red)
            .frame(width: 12, height: 12)
            .overlay(
              Image(systemName: "xmark")
                .font(.appFont(size: 8, weight: .bold))
                .foregroundColor(.black.opacity(isCloseHovered ? 0.5 : 0))
            )
        }
        .buttonStyle(.plain)
        .padding(.leading, 12)
        // .padding(., theme.borderRadius / 2.5)
        .onHover { isCloseHovered = $0 }

        // Sidebar Toggle Button
        Button(action: {
          withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isSidebarVisible.toggle()
          }
        }) {
          Image(systemName: isSidebarVisible ? "sidebar.left" : "sidebar.right")
            .font(.appFont(size: 13))
            .foregroundColor(isSidebarHovered ? theme.accentColor : theme.textColor.opacity(0.6))
            .frame(width: 24, height: 24)
            .background(isSidebarHovered ? theme.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .onHover { isSidebarHovered = $0 }
        .help(isSidebarVisible ? "Hide Sidebar" : "Show Sidebar")

        Spacer()

        Text("Detach")
          .font(.appFont(size: 11, weight: .semibold))
          .foregroundColor(theme.secondaryTextColor)
          .padding(.trailing, 12)
      }
      .frame(height: 30)
      .border(theme.textColor.opacity(0.25), width: 0.25)
      .background(theme.backgroundColor)

      HStack(alignment: .top, spacing: 0) {
        if isSidebarVisible {
          // Sidebar
          VStack(alignment: .leading, spacing: 4) {
            ForEach(menuItems, id: \.0) { item in
              SidebarItem(title: item.0, isSelected: selectedTab == item.1) {
                selectedTab = item.1
              }
              .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer()
          }
          .frame(width: 130)
          .frame(maxHeight: .infinity, alignment: .topLeading)
          .padding(.leading, 8)
          .padding(.vertical, 20)
          .transition(
            .asymmetric(
              insertion: .move(edge: .leading).combined(with: .opacity),
              removal: .move(edge: .leading).combined(with: .opacity)
            ))

          // Vertical Divider
          Rectangle()
            .fill(theme.textColor.opacity(0.1))
            .frame(width: 1)
        }

        // Content Area
        content
      }
    }
    .frame(width: 730, height: 600)
    .background(theme.backgroundFill)
    .clipShape(RoundedRectangle(cornerRadius: theme.borderRadius))
  }

  struct SidebarItem: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
      Button(action: action) {
        Text(title)
          .font(.appFont(size: 12, weight: .light))
          // .font(.custom("Sick-Regular", size: 12))
          .foregroundColor(isSelected ? theme.backgroundColor : theme.textColor)
      }
      .buttonStyle(.plain)
      // .frame(maxWidth: .infinity)
      .padding(6)
      .background(
        RoundedRectangle(cornerRadius: theme.borderRadius)
          .fill(isSelected ? theme.accentColor : Color.clear)
      )
    }
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: 0) {

      // HStack {
      //   Text(contentTitle)
      //     .font(.appFont(size: 16, weight: .semibold))
      //     .foregroundColor(theme.textColor)
      //   Spacer()
      // }
      // .padding(.horizontal, 24)
      // .padding(.top, 24)
      // .padding(.bottom, 16)

      // Tab content
      VStack(alignment: .leading) {
        switch selectedTab {
        case "general":
          GeneralSettingsView(wsManager: wsManager)
        case "appearance":
          AppearanceSettingsView()
        case "shortcuts":
          ShortcutsSettingsView()
        case "quick_actions":
          QuickActionsSettingsView(
            wsManager: wsManager,
            startInCreateMode: launchIntent == .createQuickAction
          )
        case "workflows":
          WorkflowsSettingsView(
            wsManager: wsManager,
            onRunWorkflow: onRunWorkflow,
            startInCreateMode: launchIntent == .createWorkflow
          )
        case "mcp":
          MCPSettingsContentView(
            wsManager: wsManager,
            startInAddServerMode: launchIntent == .connectMCP
          )
        case "secrets":
          SecretsSettingsView()
        case "privacy":
          PrivacySettingsView()
        case "about":
          AboutSettingsView()
        default:
          EmptyView()
        }
      }
      .padding(.horizontal, 24)
      .padding(.vertical, 24)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private var contentTitle: String {
    switch selectedTab {
    case "general": return "General"
    case "appearance": return "Appearance"
    case "shortcuts": return "Shortcuts"
    case "quick_actions": return "Quick Actions"
    case "workflows": return "Workflows"
    case "mcp": return "MCP"
    case "about": return "About"
    default: return ""
    }
  }
}

// MARK: - Preview

#Preview {
  SettingsView(wsManager: WebSocketManager())
}
