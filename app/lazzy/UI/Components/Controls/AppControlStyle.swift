import SwiftUI

/// Shared dimensions for controls in settings, onboarding, and floating panels.
enum AppControlMetrics {
  static let height: CGFloat = 28
  static let radius: CGFloat = 6
  static let menuRowHeight: CGFloat = 29
}

enum AppButtonKind { case primary, secondary, quiet }

struct AppButtonStyle: ButtonStyle {
  var kind: AppButtonKind = .secondary

  func makeBody(configuration: Configuration) -> some View {
    AppButtonBody(configuration: configuration, kind: kind)
  }
}

private struct AppButtonBody: View {
  let configuration: ButtonStyleConfiguration
  let kind: AppButtonKind
  @Environment(\.isEnabled) private var isEnabled
  @ObservedObject private var theme = ThemeManager.shared
  @State private var hovered = false

  var body: some View {
    configuration.label
      .font(.appFont(size: 11.5)).fontWeight(.medium)
      .foregroundStyle(kind == .primary ? theme.backgroundColor : theme.textColor)
      .padding(.horizontal, 10)
      .frame(minHeight: AppControlMetrics.height)
      .background(background, in: RoundedRectangle(cornerRadius: AppControlMetrics.radius))
      .overlay {
        RoundedRectangle(cornerRadius: AppControlMetrics.radius)
          .strokeBorder(theme.textColor.opacity(kind == .secondary ? 0.12 : 0), lineWidth: 0.6)
      }
      .contentShape(RoundedRectangle(cornerRadius: AppControlMetrics.radius))
      .opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.35)
      .onHover { hovered = $0 }
      .animation(.easeOut(duration: 0.12), value: hovered)
  }

  private var background: Color {
    switch kind {
    case .primary: return theme.textColor
    case .secondary: return theme.textColor.opacity(hovered ? 0.09 : 0.045)
    case .quiet: return theme.textColor.opacity(hovered ? 0.065 : 0)
    }
  }
}

struct AppTextField: View {
  let title: String
  @Binding var text: String
  var secure = false
  var symbol: String? = nil
  @FocusState private var focused: Bool
  @Environment(\.isEnabled) private var isEnabled
  @ObservedObject private var theme = ThemeManager.shared

  init(_ title: String, text: Binding<String>, secure: Bool = false, symbol: String? = nil) {
    self.title = title
    _text = text
    self.secure = secure
    self.symbol = symbol
  }

  var body: some View {
    HStack(spacing: 7) {
      if let symbol {
        Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(theme.secondaryTextColor)
      }
      Group {
        if secure { SecureField(title, text: $text) }
        else { TextField(title, text: $text) }
      }
      .textFieldStyle(.plain)
      .focused($focused)
      .font(.appFont(size: 12))
      .foregroundStyle(theme.textColor)
      .accessibilityLabel(title)
    }
    .padding(.horizontal, 9)
    .frame(height: AppControlMetrics.height)
    .background(theme.textColor.opacity(0.035), in: RoundedRectangle(cornerRadius: AppControlMetrics.radius))
    .overlay {
      RoundedRectangle(cornerRadius: AppControlMetrics.radius)
        .strokeBorder(theme.textColor.opacity(focused ? 0.35 : 0.12), lineWidth: 0.7)
    }
    .opacity(isEnabled ? 1 : 0.4)
  }
}

struct AppTextEditor: View {
  let title: String
  @Binding var text: String
  var height: CGFloat = 90
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    TextEditor(text: $text)
      .font(.appFont(size: 12))
      .foregroundStyle(theme.textColor)
      .scrollContentBackground(.hidden)
      .padding(8)
      .frame(height: height)
      .background(theme.textColor.opacity(0.025), in: RoundedRectangle(cornerRadius: 7))
      .overlay {
        RoundedRectangle(cornerRadius: 7)
          .strokeBorder(theme.textColor.opacity(0.1), lineWidth: 0.6)
      }
      .accessibilityLabel(title)
  }
}

struct AppSpinner: View {
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    TimelineView(.animation) { context in
      Circle().trim(from: 0.15, to: 0.85)
        .stroke(theme.secondaryTextColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        .rotationEffect(.degrees(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.9) / 0.9 * 360))
    }
    .frame(width: 12, height: 12).accessibilityLabel("Working")
  }
}
