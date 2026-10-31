import SwiftUI

struct AppColorControl: View {
  @Binding var selection: Color
  @State private var presented = false
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    Button { presented.toggle() } label: {
      HStack(spacing: 7) {
        RoundedRectangle(cornerRadius: 3).fill(selection).frame(width: 14, height: 14)
          .overlay { RoundedRectangle(cornerRadius: 3).strokeBorder(theme.textColor.opacity(0.2), lineWidth: 0.6) }
        Text(selection.toHex().uppercased()).font(.appFont(size: 11, design: .monospaced))
      }
    }
    .buttonStyle(AppButtonStyle())
    .background {
      DropdownPanelAnchor(isPresented: $presented, menuWidth: 216,
        menu: AppColorEditor(selection: $selection), acceptsKeyboardInput: true)
    }
  }
}

private struct AppColorEditor: View {
  @Binding var selection: Color
  @State private var hex = ""
  @ObservedObject private var theme = ThemeManager.shared
  private let shades = ["#000000", "#242424", "#444444", "#666666", "#999999", "#BBBBBB", "#DDDDDD", "#FFFFFF"]

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Color").font(.appFont(size: 11, weight: .medium)).foregroundStyle(theme.secondaryTextColor)
      HStack(spacing: 6) {
        ForEach(shades, id: \.self) { shade in
          Button { selection = Color(hex: shade); hex = shade } label: {
            RoundedRectangle(cornerRadius: 3).fill(Color(hex: shade)).frame(width: 19, height: 21)
              .overlay { RoundedRectangle(cornerRadius: 3).strokeBorder(theme.textColor.opacity(0.2), lineWidth: 0.6) }
          }
          .buttonStyle(.plain).accessibilityLabel(shade)
        }
      }
      AppTextField("Hex color", text: $hex)
        .onSubmit { commit() }
        .onChange(of: hex) { _, _ in commit() }
    }
    .padding(12).background(theme.backgroundColor)
    .clipShape(RoundedRectangle(cornerRadius: 9))
    .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(theme.textColor.opacity(0.16), lineWidth: 0.7) }
    .onAppear { hex = selection.toHex() }
  }

  private func commit() {
    let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    guard clean.count == 6, clean.allSatisfy(\.isHexDigit) else { return }
    guard selection.toHex().lowercased() != "#\(clean.lowercased())" else { return }
    selection = Color(hex: "#\(clean)")
  }
}
