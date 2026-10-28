import SwiftUI

/// Captured text is also visible and removable inside the composer.
struct ComposerTextContextPill: View {
  let text: String
  var onRemove: () -> Void
  @State private var isPresented = false
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    HStack(spacing: 5) {
      Button { isPresented.toggle() } label: {
        Label("Selected text", systemImage: "text.quote")
          .font(.appFont(size: 12))
      }
      .help("Preview selected text")
      Button(action: onRemove) {
        Image(systemName: "xmark").font(.system(size: 8, weight: .medium))
          .frame(width: 18, height: 20)
      }
      .accessibilityLabel("Remove selected text")
    }
    .buttonStyle(.plain).foregroundStyle(theme.secondaryTextColor)
    .padding(.leading, 8).padding(.trailing, 3).padding(.vertical, 3)
    .background(theme.textColor.opacity(0.065), in: RoundedRectangle(cornerRadius: 7))
    .background {
      DropdownPanelAnchor(isPresented: $isPresented, menuWidth: 320,
        menu: ScrollView {
          Text(text).font(.appFont(size: 12)).foregroundStyle(theme.textColor)
            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(12)
        }
        .frame(maxHeight: 200)
        .themedSurface(in: RoundedRectangle(cornerRadius: 10)), acceptsKeyboardInput: true)
    }
  }
}
