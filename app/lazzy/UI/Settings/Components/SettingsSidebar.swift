import SwiftUI

struct SettingsSidebar: View {
  private struct Entry: Identifiable {
    let id: String
    let title: String
    let icon: String
  }

  @Binding var selection: String
  @State private var search = ""
  @ObservedObject private var theme = ThemeManager.shared

  private var groups: [[Entry]] {
    [
      [.init(id: "general", title: "General", icon: "gearshape"),
       .init(id: "machines", title: "Machines", icon: "server.rack"),
       .init(id: "router", title: "Auto router", icon: "arrow.triangle.branch"),
       .init(id: "workflows", title: "Workflows", icon: "point.3.connected.trianglepath.dotted")],
      [.init(id: "mcp", title: "Tools & integrations", icon: "server.rack"),
       .init(id: "browser", title: "Browser", icon: "globe"),
       .init(id: "messages", title: "Messages Remote", icon: "message")],
      [.init(id: "appearance", title: "Appearance", icon: "paintbrush"),
       .init(id: "shortcuts", title: "Shortcuts", icon: "keyboard")],
      [.init(id: "license", title: "License", icon: "key.horizontal"),
       .init(id: "secrets", title: "Secrets", icon: "key"),
       .init(id: "privacy", title: "Privacy & data", icon: "hand.raised")],
    ].map { group in
      group.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }
    }.filter { !$0.isEmpty }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 13) {
      Text("Settings").font(.appFont(size: 13)).fontWeight(.semibold).foregroundStyle(theme.textColor)
        .padding(.horizontal, 8)
      AppTextField("Search settings", text: $search, symbol: "magnifyingglass")
      ScrollView {
        VStack(alignment: .leading, spacing: 9) {
          ForEach(groups.indices, id: \.self) { index in
            if index > 0 {
              Rectangle().fill(theme.textColor.opacity(0.08)).frame(height: 0.5)
                .padding(.horizontal, 8).padding(.vertical, 2)
            }
            VStack(spacing: 2) {
              ForEach(groups[index]) { item in
                SettingsNavigationRow(title: item.title, icon: item.icon,
                  selected: selection == item.id) { selection = item.id }
              }
            }
          }
          if groups.isEmpty {
            Text("No settings found").font(.appFont(size: 11))
              .foregroundStyle(theme.secondaryTextColor).padding(8)
          }
        }
      }
      .scrollIndicators(.hidden)
    }
    .padding(.horizontal, 12).padding(.vertical, 18)
    .frame(width: 188).frame(maxHeight: .infinity, alignment: .topLeading)
    .background(theme.textColor.opacity(0.012))
  }
}

private struct SettingsNavigationRow: View {
  let title: String
  let icon: String
  let selected: Bool
  let action: () -> Void
  @State private var hovered = false
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    Button(action: action) {
      HStack(spacing: 9) {
        Image(systemName: icon).font(.system(size: 11.5)).frame(width: 15)
          .foregroundStyle(theme.textColor.opacity(selected ? 0.9 : 0.52))
        Text(title).font(.appFont(size: 11.5, weight: selected ? .medium : .regular))
        Spacer(minLength: 0)
      }
      .foregroundStyle(theme.textColor.opacity(selected ? 1 : 0.76))
      .padding(.horizontal, 8).frame(height: 29)
      .background(theme.textColor.opacity(selected ? 0.075 : hovered ? 0.04 : 0),
                  in: RoundedRectangle(cornerRadius: 6))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain).onHover { hovered = $0 }
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}
