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

  private var menuItems: [(title: String, id: String, icon: String)] {
    return [
      ("General", "general", "gearshape"),
      ("Quick Actions", "quick_actions", "bolt"),
      ("Workflows", "workflows", "point.3.connected.trianglepath.dotted"),
      ("MCP", "mcp", "server.rack"),
      ("Browser", "browser", "globe"),
      ("Secrets", "secrets", "key"),
      ("Appearance", "appearance", "paintbrush"),
      ("Shortcuts", "shortcuts", "keyboard"),
      // ("Privacy", "privacy", "hand.raised"),
      // ("About", "about", "info.circle"),
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
      .frame(height: 42)
      .border(theme.textColor.opacity(0.25), width: 0.25)
      .background(theme.backgroundColor)

      HStack(alignment: .top, spacing: 0) {
        if isSidebarVisible {
          // Sidebar
          VStack(alignment: .leading, spacing: 4) {
            Text("SETTINGS")
              .font(.appFont(size: 9, weight: .bold))
              .foregroundColor(theme.secondaryTextColor.opacity(0.7))
              .tracking(1.1)
              .padding(.horizontal, 10)
              .padding(.bottom, 7)

            ForEach(menuItems, id: \.id) { item in
              SidebarItem(
                title: item.title,
                icon: item.icon,
                isSelected: selectedTab == item.id
              ) {
                selectedTab = item.id
              }
              .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer()
          }
          .frame(width: 174)
          .frame(maxHeight: .infinity, alignment: .topLeading)
          .padding(.horizontal, 10)
          .padding(.vertical, 22)
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
    .frame(width: 920, height: 680)
    .background(theme.backgroundFill)
    .clipShape(RoundedRectangle(cornerRadius: theme.borderRadius))
  }

  struct SidebarItem: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
      Button(action: action) {
        HStack(spacing: 9) {
          Image(systemName: icon)
            .font(.system(size: 12, weight: .medium))
            .frame(width: 16)

          Text(title)
            .font(.appFont(size: 12, weight: .medium))

          Spacer(minLength: 0)
        }
        .foregroundColor(isSelected ? theme.backgroundColor : theme.textColor.opacity(0.78))
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .buttonStyle(.plain)
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
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
        case "browser":
          BrowserSettingsView(wsManager: wsManager)
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
      .padding(.horizontal, 34)
      .padding(.top, 30)
      .padding(.bottom, 24)
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
    case "browser": return "Browser"
    case "about": return "About"
    default: return ""
    }
  }
}

// MARK: - Shared Settings UI

struct SettingsPageHeader: View {
  let title: String
  let subtitle: String
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(title)
        .font(.appFont(size: 25, weight: .semibold))
        .foregroundColor(theme.textColor)
        .tracking(-0.45)

      Text(subtitle)
        .font(.appFont(size: 12))
        .foregroundColor(theme.secondaryTextColor)
        .lineSpacing(3)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

struct SettingsSectionHeader: View {
  let title: String
  var subtitle: String? = nil
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title)
        .font(.appFont(size: 13, weight: .semibold))
        .foregroundColor(theme.textColor)

      if let subtitle {
        Text(subtitle)
          .font(.appFont(size: 10.5))
          .foregroundColor(theme.secondaryTextColor.opacity(0.85))
      }
    }
  }
}

struct SettingsCard<Content: View>: View {
  let content: Content
  @ObservedObject private var theme = ThemeManager.shared

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    VStack(spacing: 0) {
      content
    }
    .background(theme.textColor.opacity(0.025))
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(theme.textColor.opacity(0.085), lineWidth: 0.7)
    )
  }
}

struct SettingsRow<Trailing: View>: View {
  let title: String
  let subtitle: String?
  let trailing: Trailing
  @ObservedObject private var theme = ThemeManager.shared

  init(
    title: String,
    subtitle: String? = nil,
    @ViewBuilder trailing: () -> Trailing
  ) {
    self.title = title
    self.subtitle = subtitle
    self.trailing = trailing()
  }

  var body: some View {
    HStack(spacing: 18) {
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.appFont(size: 12.5, weight: .medium))
          .foregroundColor(theme.textColor)

        if let subtitle {
          Text(subtitle)
            .font(.appFont(size: 10.5))
            .foregroundColor(theme.secondaryTextColor)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      Spacer(minLength: 20)
      trailing
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 13)
  }
}

struct SettingsCardDivider: View {
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    Rectangle()
      .fill(theme.textColor.opacity(0.075))
      .frame(height: 0.5)
      .padding(.horizontal, 16)
  }
}

struct SettingsIconButton: View {
  let icon: String
  let accessibilityLabel: String
  var tint: Color? = nil
  let action: () -> Void
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    Button(action: action) {
      Image(systemName: icon)
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(tint ?? theme.textColor.opacity(0.8))
        .frame(width: 28, height: 26)
        .background(theme.textColor.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(accessibilityLabel)
  }
}

// MARK: - Preview

#Preview {
  SettingsView(wsManager: WebSocketManager())
}
