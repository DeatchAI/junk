import SwiftUI

struct AppMenuAction: Identifiable {
  let title: String
  var symbol: String? = nil
  var isEnabled = true
  let action: () -> Void
  var id: String { title }
}

struct AppActionMenu<Label: View>: View {
  let actions: [AppMenuAction]
  @ViewBuilder let label: () -> Label
  @State private var presented = false
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    Button { presented.toggle() } label: { label() }
      .buttonStyle(AppButtonStyle(kind: .quiet))
      .background {
        DropdownPanelAnchor(isPresented: $presented, menuWidth: 184, menu:
          VStack(spacing: 2) {
            ForEach(actions) { item in
              Button {
                presented = false
                item.action()
              } label: { AppMenuRow(title: item.title, symbol: item.symbol) }
              .buttonStyle(.plain).disabled(!item.isEnabled).opacity(item.isEnabled ? 1 : 0.35)
            }
          }
          .padding(5)
          .background(theme.backgroundColor)
          .clipShape(RoundedRectangle(cornerRadius: 9))
          .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(theme.textColor.opacity(0.16), lineWidth: 0.7) },
          contentRevision: AnyHashable(actions.map { "\($0.title):\($0.isEnabled)" })
        )
      }
  }
}
