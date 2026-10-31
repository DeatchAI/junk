import SwiftUI

/// Settings pages share one inset, row rhythm, and trailing control column.
struct SettingsPage<Content: View>: View {
  let title: String
  let subtitle: String
  @ViewBuilder let content: () -> Content

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        SettingsPageHeader(title: title, subtitle: subtitle)
        content()
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.bottom, 16)
    }
  }
}

struct SettingsPageHeader: View {
  let title: String
  let subtitle: String
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title).font(.appFont(size: 20)).fontWeight(.semibold).foregroundStyle(theme.textColor)
      Text(subtitle).font(.appFont(size: 11.5)).foregroundStyle(theme.secondaryTextColor)
        .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 14)
  }
}

struct SettingsSectionHeader: View {
  let title: String
  var subtitle: String? = nil
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title).font(.appFont(size: 11.5)).fontWeight(.medium)
      if let subtitle {
        Text(subtitle).font(.appFont(size: 10.5)).lineSpacing(2)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .foregroundStyle(theme.secondaryTextColor)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 14)
  }
}

struct SettingsSection<Content: View>: View {
  let title: String
  var subtitle: String? = nil
  @ViewBuilder let content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      SettingsSectionHeader(title: title, subtitle: subtitle)
      SettingsCard(content: content)
    }
  }
}

struct SettingsCard<Content: View>: View {
  let content: Content
  @ObservedObject private var theme = ThemeManager.shared

  init(@ViewBuilder content: () -> Content) { self.content = content() }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) { content }
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(theme.textColor.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
      .overlay {
        RoundedRectangle(cornerRadius: 10)
          .strokeBorder(theme.textColor.opacity(0.045), lineWidth: 0.5)
      }
  }
}

struct SettingsRow<Trailing: View>: View {
  let title: String
  let subtitle: String?
  let controlWidth: CGFloat?
  let trailing: Trailing
  @ObservedObject private var theme = ThemeManager.shared

  init(title: String, subtitle: String? = nil, controlWidth: CGFloat? = 190,
       @ViewBuilder trailing: () -> Trailing) {
    self.title = title
    self.subtitle = subtitle
    self.controlWidth = controlWidth
    self.trailing = trailing()
  }

  var body: some View {
    HStack(alignment: .center, spacing: 20) {
      VStack(alignment: .leading, spacing: 3) {
        Text(title).font(.appFont(size: 12)).fontWeight(.medium).foregroundStyle(theme.textColor)
        if let subtitle, !subtitle.isEmpty {
          Text(subtitle).font(.appFont(size: 10.5)).foregroundStyle(theme.secondaryTextColor)
            .lineSpacing(1).fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      trailing.frame(width: controlWidth, alignment: .trailing)
    }
    .frame(minHeight: 28)
    .padding(.horizontal, 14)
    .padding(.vertical, 9)
  }
}

struct SettingsToggleRow: View {
  let title: String
  var subtitle: String? = nil
  @Binding var isOn: Bool

  var body: some View {
    SettingsRow(title: title, subtitle: subtitle) {
      AppToggle(title: title, isOn: $isOn)
    }
  }
}

struct SettingsCardDivider: View {
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    Rectangle().fill(theme.textColor.opacity(0.07)).frame(height: 0.5).padding(.horizontal, 14)
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
      Image(systemName: icon).font(.system(size: 11))
        .foregroundStyle(tint ?? theme.secondaryTextColor).frame(width: 10)
    }
    .buttonStyle(AppButtonStyle(kind: .quiet))
    .accessibilityLabel(accessibilityLabel)
  }
}
