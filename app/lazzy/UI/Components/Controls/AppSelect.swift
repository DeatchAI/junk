import SwiftUI

struct AppSelectOption<Value: Hashable>: Identifiable, Hashable {
  let title: String
  let value: Value
  var subtitle: String? = nil
  var symbol: String? = nil
  var asset: String? = nil
  var isEnabled = true
  var id: Value { value }
}

struct AppSelect<Value: Hashable>: View {
  let title: String
  @Binding var selection: Value
  let options: [AppSelectOption<Value>]
  var menuWidth: CGFloat = 232
  var fontSize: CGFloat = 12
  var opensOnHover = false
  var onSelect: ((Value) -> Void)? = nil

  @State private var presented = false
  @State private var hovered = false
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.colorScheme) private var colorScheme
  @ObservedObject private var theme = ThemeManager.shared

  private var selected: AppSelectOption<Value>? { options.first { $0.value == selection } }

  var body: some View {
    Button {
      presented = opensOnHover ? true : !presented
    } label: {
      HStack(spacing: 7) {
        if let asset = selected?.asset {
          Image(asset).resizable().renderingMode(.template).scaledToFit()
            .frame(width: 13, height: 13).accessibilityHidden(true)
        }
        Text(selected?.title ?? title).lineLimit(1)
        Spacer(minLength: 6)
        Image(systemName: "chevron.down")
          .font(.system(size: 8, weight: .semibold))
          .foregroundStyle(theme.secondaryTextColor)
      }
      .font(.appFont(size: fontSize))
      .foregroundStyle(theme.textColor)
      .padding(.horizontal, 9)
      .frame(height: AppControlMetrics.height)
      .background(theme.textColor.opacity(hovered || presented ? 0.08 : 0.045),
                  in: RoundedRectangle(cornerRadius: AppControlMetrics.radius))
      .overlay {
        RoundedRectangle(cornerRadius: AppControlMetrics.radius)
          .strokeBorder(theme.textColor.opacity(presented ? 0.25 : 0.12), lineWidth: 0.6)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .opacity(isEnabled ? 1 : 0.4)
    .accessibilityLabel(title)
    .accessibilityValue(selected?.title ?? "")
    .onHover {
      hovered = $0
      if $0 && opensOnHover && isEnabled { presented = true }
    }
    .background {
      DropdownPanelAnchor(
        isPresented: $presented, menuWidth: menuWidth,
        menu: AppSelectList(options: options, selection: selection, searchable: !opensOnHover && options.count > 7) {
          selection = $0
          presented = false
          onSelect?($0)
        }.environment(\.colorScheme, theme.surfaceColorScheme ?? colorScheme),
        opensOnHover: opensOnHover,
        contentRevision: AnyHashable([AnyHashable(selection), AnyHashable(options)]),
        acceptsKeyboardInput: !opensOnHover
      )
    }
  }
}

private struct AppSelectList<Value: Hashable>: View {
  let options: [AppSelectOption<Value>]
  let selection: Value
  let searchable: Bool
  let select: (Value) -> Void
  @State private var search = ""
  @State private var highlighted: Value?
  @State private var keyboardNavigation = false
  @FocusState private var searchFocused: Bool
  @FocusState private var listFocused: Bool
  @ObservedObject private var theme = ThemeManager.shared

  private var filtered: [AppSelectOption<Value>] {
    options.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }
  }

  var body: some View {
    VStack(spacing: 0) {
      if searchable {
        HStack(spacing: 7) {
          Image(systemName: "magnifyingglass").font(.system(size: 10))
          TextField("Search options", text: $search)
            .textFieldStyle(.plain).focused($searchFocused)
            .accessibilityLabel("Search options")
        }
        .font(.appFont(size: 12)).foregroundStyle(theme.secondaryTextColor)
        .padding(.horizontal, 11).frame(height: 35)
        Rectangle().fill(theme.textColor.opacity(0.08)).frame(height: 0.5)
      }
      ScrollViewReader { proxy in
        ScrollView {
          VStack(spacing: 2) {
            if filtered.isEmpty {
              Text("No matches").font(.appFont(size: 12))
                .foregroundStyle(theme.secondaryTextColor).padding(12)
            }
            ForEach(filtered) { option in
              Button { select(option.value) } label: {
                AppMenuRow(title: option.title, subtitle: option.subtitle,
                  symbol: option.symbol, asset: option.asset,
                  selected: option.value == selection, highlighted: option.value == highlighted)
              }
              .buttonStyle(.plain)
              .disabled(!option.isEnabled)
              .opacity(option.isEnabled ? 1 : 0.35)
              .onHover { if $0 { keyboardNavigation = false; highlighted = option.value } }
              .id(option.value)
            }
          }.padding(5)
        }
        .frame(height: min(CGFloat(max(1, filtered.count)) * 31 + 10, 236))
        .onChange(of: highlighted) { _, value in
          if keyboardNavigation, let value { proxy.scrollTo(value, anchor: .center) }
        }
      }
    }
    .focusable().focusEffectDisabled().focused($listFocused)
    .onKeyPress(.downArrow) { move(1); return .handled }
    .onKeyPress(.upArrow) { move(-1); return .handled }
    .onKeyPress(.return) {
      if let value = highlighted, filtered.contains(where: { $0.value == value && $0.isEnabled }) {
        select(value)
      }
      return .handled
    }
    .onAppear {
      highlighted = selection
      if searchable { searchFocused = true } else { listFocused = true }
    }
    .onChange(of: search) { _, _ in highlighted = filtered.first(where: \.isEnabled)?.value }
    .background(theme.backgroundColor)
    .clipShape(RoundedRectangle(cornerRadius: 9))
    .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(theme.textColor.opacity(0.16), lineWidth: 0.7) }
  }

  private func move(_ offset: Int) {
    keyboardNavigation = true
    let enabled = filtered.filter(\.isEnabled)
    guard !enabled.isEmpty else { return }
    let index = enabled.firstIndex { $0.value == highlighted } ?? (offset > 0 ? -1 : 0)
    highlighted = enabled[(index + offset + enabled.count) % enabled.count].value
  }
}

/// A shared row for selection menus and action menus.
struct AppMenuRow: View {
  let title: String
  var subtitle: String? = nil
  var symbol: String? = nil
  var asset: String? = nil
  var selected = false
  var highlighted = false
  @State private var hovered = false
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    HStack(spacing: 8) {
      if let asset {
        Image(asset).resizable().renderingMode(.template).scaledToFit().frame(width: 14, height: 14)
      } else if let symbol {
        Image(systemName: symbol).font(.system(size: 11)).frame(width: 14)
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.appFont(size: 12)).lineLimit(1)
        if let subtitle {
          Text(subtitle).font(.appFont(size: 10)).foregroundStyle(theme.secondaryTextColor)
        }
      }
      Spacer(minLength: 8)
      if selected { Image(systemName: "checkmark").font(.system(size: 10, weight: .medium)) }
    }
    .foregroundStyle(theme.textColor)
    .padding(.horizontal, 8)
    .frame(minHeight: AppControlMetrics.menuRowHeight)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(theme.textColor.opacity(hovered || highlighted ? 0.075 : 0),
                in: RoundedRectangle(cornerRadius: 5))
    .contentShape(Rectangle())
    .onHover { hovered = $0 }
  }
}
