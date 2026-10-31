import SwiftUI

struct SettingsWindowToolbar: View {
  @Binding var sidebarVisible: Bool
  let onClose: () -> Void
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    HStack(spacing: 4) {
      Button { onClose() } label: {
        Image(systemName: "xmark").font(.system(size: 10)).frame(width: 10)
      }
      .buttonStyle(AppButtonStyle(kind: .quiet)).accessibilityLabel("Close settings")
      Button {
        withAnimation(.easeInOut(duration: 0.18)) { sidebarVisible.toggle() }
      } label: {
        Image(systemName: "sidebar.left").font(.system(size: 12)).frame(width: 12)
      }
      .buttonStyle(AppButtonStyle(kind: .quiet))
      .accessibilityLabel(sidebarVisible ? "Hide sidebar" : "Show sidebar")
      SettingsWindowDragRegion().frame(maxWidth: .infinity, maxHeight: .infinity)
      Text("Detach").font(.appFont(size: 10.5, weight: .medium))
        .foregroundStyle(theme.secondaryTextColor).padding(.trailing, 14)
    }
    .padding(.leading, 10).frame(height: 36)
    .overlay(alignment: .bottom) {
      Rectangle().fill(theme.textColor.opacity(0.065)).frame(height: 0.5)
    }
  }

}
