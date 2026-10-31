import SwiftUI

struct AppToggle: View {
  let title: String
  @Binding var isOn: Bool
  @Environment(\.isEnabled) private var isEnabled
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    Button {
      withAnimation(.easeOut(duration: 0.15)) { isOn.toggle() }
    } label: {
      Capsule()
        .fill(theme.textColor.opacity(isOn ? 0.95 : 0.16))
        .frame(width: 30, height: 18)
        .overlay(alignment: isOn ? .trailing : .leading) {
          Circle().fill(theme.backgroundColor).frame(width: 14, height: 14).padding(2)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }
    .buttonStyle(.plain)
    .opacity(isEnabled ? 1 : 0.35)
    .accessibilityLabel(title)
    .accessibilityValue(isOn ? "On" : "Off")
    .accessibilityAdjustableAction { direction in
      guard isEnabled else { return }
      if direction == .increment { isOn = true }
      if direction == .decrement { isOn = false }
    }
  }
}

struct AppLabeledToggle: View {
  let title: String
  @Binding var isOn: Bool
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    HStack(spacing: 16) {
      Text(title).font(.appFont(size: 12)).foregroundStyle(theme.textColor)
      Spacer(minLength: 8)
      AppToggle(title: title, isOn: $isOn)
    }
  }
}

struct AppDisclosure<Content: View>: View {
  let title: String
  var isExpanded: Binding<Bool>?
  let content: Content
  @State private var localExpanded = false
  @ObservedObject private var theme = ThemeManager.shared

  init(_ title: String, isExpanded: Binding<Bool>? = nil, @ViewBuilder content: () -> Content) {
    self.title = title
    self.isExpanded = isExpanded
    self.content = content()
  }

  private var expanded: Bool { isExpanded?.wrappedValue ?? localExpanded }

  var body: some View {
    VStack(alignment: .leading, spacing: expanded ? 6 : 0) {
      Button {
        withAnimation(.easeOut(duration: 0.15)) {
          if let isExpanded { isExpanded.wrappedValue.toggle() }
          else { localExpanded.toggle() }
        }
      } label: {
        HStack(spacing: 7) {
          Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold))
            .rotationEffect(.degrees(expanded ? 90 : 0)).frame(width: 9)
          Text(title).font(.appFont(size: 11, weight: .medium))
          Spacer(minLength: 0)
        }
        .foregroundStyle(theme.secondaryTextColor)
        .frame(minHeight: 26).contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityValue(expanded ? "Expanded" : "Collapsed")
      if expanded {
        content.font(.appFont(size: 11)).foregroundStyle(theme.secondaryTextColor)
          .padding(.leading, 16).padding(.bottom, 8)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
