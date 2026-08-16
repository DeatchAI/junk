import SwiftUI

/// A custom-styled menu that uses a popover for a premium feel
struct CustomMenu: View {
  let options: [String]
  @Binding var selectedOption: String
  var onSelect: ((String) -> Void)? = nil

  // Configurable properties
  var fontSize: CGFloat = 13
  var horizontalPadding: CGFloat = 12
  var verticalPadding: CGFloat = 6
  var iconSize: CGFloat = 10
  var backgroundColor: Color? = nil
  var borderRadius: CGFloat? = nil
  var showBorder: Bool = true
  var opensOnHover: Bool = false

  @State private var isPopoverPresented = false
  @State private var isHovered = false
  @ObservedObject private var theme = ThemeManager.shared

  private var effectiveBackgroundColor: Color {
    backgroundColor ?? theme.inputBackgroundColor
  }

  private var effectiveBorderRadius: CGFloat {
    borderRadius ?? (theme.borderRadius / 1.5)
  }

  var body: some View {
    Button(action: { isPopoverPresented.toggle() }) {
      HStack(spacing: 8) {
        Text(selectedOption)
          .font(.appFont(size: fontSize))
          .foregroundColor(theme.textColor)
          .lineLimit(1)

        Spacer()

        Image(systemName: "chevron.up")
          .font(.appFont(size: iconSize, weight: .bold))
          .foregroundColor(theme.secondaryTextColor)
      }
      .padding(.horizontal, horizontalPadding)
      .padding(.vertical, verticalPadding)
      .background(effectiveBackgroundColor)
      .cornerRadius(effectiveBorderRadius)
      .overlay(
        showBorder
          ? RoundedRectangle(cornerRadius: effectiveBorderRadius)
            .stroke(isHovered ? theme.accentColor.opacity(0.5) : theme.borderColor, lineWidth: 0.5)
          : nil
      )
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      isHovered = hovering
      if opensOnHover && hovering {
        isPopoverPresented = true
      }
    }
    .background {
      DropdownPanelAnchor(
        isPresented: $isPopoverPresented,
        menuWidth: 160,
        menu: ScrollView {
          VStack(alignment: .leading, spacing: 0) {
            ForEach(options, id: \.self) { option in
              MenuOptionRow(
                title: option,
                isSelected: selectedOption == option,
                action: {
                  selectedOption = option
                  isPopoverPresented = false
                  onSelect?(option)
                }
              )
            }
          }
          .padding(6)
        }
        .frame(maxHeight: 240)
        .background(menuBackground)
        .overlay {
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(theme.textColor.opacity(0.1), lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous)),
        opensOnHover: opensOnHover
      )
    }
  }

  @ViewBuilder
  private var menuBackground: some View {
    if theme.usesGlassEffect {
      ZStack {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(.ultraThinMaterial)
        if let overlay = theme.glassOverlay {
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(overlay)
        }
      }
    } else {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(theme.solidBackground)
    }
  }

  struct MenuOptionRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
      Button(action: action) {
        HStack {
          Text(title)
            .font(.appFont(size: 12, weight: isSelected ? .medium : .regular))
            .foregroundColor(textColor)
          Spacer()
          if isSelected {
            Image(systemName: "checkmark")
              .font(.appFont(size: 10, weight: .bold))
              .foregroundColor(textColor)
          }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
          RoundedRectangle(cornerRadius: 8)
            .fill(backgroundFill)
        )
      }
      .buttonStyle(.plain)
      .onHover { isHovered = $0 }
    }

    private var textColor: Color {
      if isSelected {
        return .white
      }
      return theme.textColor
    }

    private var backgroundFill: Color {
      if isSelected {
        return theme.accentColor
      } else if isHovered {
        return theme.textColor.opacity(0.06)
      }
      return Color.clear
    }
  }
}

/// A model menu that shows premium models as disabled with upgrade tooltip
/// Used for AI model selection with plan-based restrictions
struct ModelMenu: View {
  let modelsWithAvailability: [(model: String, isAvailable: Bool)]
  @Binding var selectedOption: String
  var onSelect: ((String) -> Void)? = nil

  // Configurable properties
  var fontSize: CGFloat = 13
  var horizontalPadding: CGFloat = 12
  var verticalPadding: CGFloat = 6
  var iconSize: CGFloat = 10
  var backgroundColor: Color? = nil
  var borderRadius: CGFloat? = nil
  var showBorder: Bool = true
  var unavailableHelp: String = "Model only available to Pro users, upgrade to select"
  var opensOnHover: Bool = false

  @State private var isPopoverPresented = false
  @State private var isHovered = false
  @ObservedObject private var theme = ThemeManager.shared

  private var effectiveBackgroundColor: Color {
    backgroundColor ?? theme.inputBackgroundColor
  }

  private var effectiveBorderRadius: CGFloat {
    borderRadius ?? (theme.borderRadius / 1.5)
  }

  var body: some View {
    Button(action: { isPopoverPresented.toggle() }) {
      HStack(spacing: 8) {
        Text(selectedOption)
          .font(.appFont(size: fontSize))
          .foregroundColor(theme.textColor)
          .lineLimit(1)
          .padding(.trailing, 4)
        Image(systemName: "chevron.up")
          .font(.appFont(size: iconSize, weight: .bold))
          .foregroundColor(theme.secondaryTextColor)
      }
      .padding(.horizontal, horizontalPadding)
      .padding(.vertical, verticalPadding)
      .background(effectiveBackgroundColor)
      .cornerRadius(effectiveBorderRadius)
      .overlay(
        showBorder
          ? RoundedRectangle(cornerRadius: effectiveBorderRadius)
            .stroke(isHovered ? theme.accentColor.opacity(0.5) : theme.borderColor, lineWidth: 0.5)
          : nil
      )
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      isHovered = hovering
      if opensOnHover && hovering {
        isPopoverPresented = true
      }
    }
    .background {
      DropdownPanelAnchor(
        isPresented: $isPopoverPresented,
        menuWidth: 200,
        menu: ScrollView {
          VStack(alignment: .leading, spacing: 0) {
            ForEach(modelsWithAvailability, id: \.model) { item in
              ModelOptionRow(
                title: item.model,
                isSelected: selectedOption == item.model,
                isAvailable: item.isAvailable,
                unavailableHelp: unavailableHelp,
                action: {
                  if item.isAvailable {
                    selectedOption = item.model
                    isPopoverPresented = false
                    onSelect?(item.model)
                  }
                }
              )
            }
          }
          .padding(6)
        }
        .frame(maxHeight: 240)
        .background(menuBackground)
        .overlay {
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(theme.textColor.opacity(0.1), lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous)),
        opensOnHover: opensOnHover
      )
    }
  }

  @ViewBuilder
  private var menuBackground: some View {
    if theme.usesGlassEffect {
      ZStack {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(.ultraThinMaterial)
        if let overlay = theme.glassOverlay {
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(overlay)
        }
      }
    } else {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(theme.solidBackground)
    }
  }

  struct ModelOptionRow: View {
    let title: String
    let isSelected: Bool
    let isAvailable: Bool
    let unavailableHelp: String
    let action: () -> Void

    @State private var isHovered = false
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
      Button(action: action) {
        HStack {
          Text(title)
            .font(.appFont(size: 12, weight: isSelected && isAvailable ? .medium : .regular))
            .foregroundColor(textColor)
          
          Spacer()
          
          if !isAvailable {
            Image(systemName: "lock.fill")
              .font(.appFont(size: 9))
              .foregroundColor(theme.secondaryTextColor.opacity(0.5))
          } else if isSelected {
            Image(systemName: "checkmark")
              .font(.appFont(size: 10, weight: .bold))
              .foregroundColor(textColor)
          }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
          RoundedRectangle(cornerRadius: 8)
            .fill(backgroundFill)
        )
      }
      .buttonStyle(.plain)
      .disabled(!isAvailable)
      .onHover { isHovered = $0 }
      .help(isAvailable ? "" : unavailableHelp)
    }
    
    private var textColor: Color {
      if isSelected && isAvailable {
        return .white
      } else if !isAvailable {
        return theme.textColor.opacity(0.4)
      }
      return theme.textColor
    }
    
    private var backgroundFill: Color {
      if isSelected && isAvailable {
        return theme.accentColor
      } else if isHovered && isAvailable {
        return theme.textColor.opacity(0.06)
      }
      return Color.clear
    }
  }
}

/// A custom-styled stepper with a premium look
struct CustomStepper: View {
  @Binding var value: Int
  let range: ClosedRange<Int>
  var onUpdate: (() -> Void)? = nil

  // Configurable properties
  var fontSize: CGFloat = 13
  var buttonSize: CGFloat = 28
  var inputWidth: CGFloat = 40
  var horizontalPadding: CGFloat = 4

  @ObservedObject private var theme = ThemeManager.shared
  @State private var isMinusHovered = false
  @State private var isPlusHovered = false

  var body: some View {
    HStack(spacing: 0) {
      // Minus Button
      Button(action: {
        if value > range.lowerBound {
          value -= 1
          onUpdate?()
        }
      }) {
        Image(systemName: "minus")
          .font(.appFont(size: fontSize - 3, weight: .bold))
          .foregroundColor(theme.textColor)
          .frame(width: buttonSize, height: buttonSize)
          .background(isMinusHovered ? theme.textColor.opacity(0.1) : Color.clear)
      }
      .buttonStyle(.plain)
      .disabled(value <= range.lowerBound)
      .onHover { isMinusHovered = $0 }

      Divider()
        .frame(height: buttonSize * 0.6)
        .padding(.horizontal, horizontalPadding)

      // Value Display
      TextField("", value: $value, format: .number)
        .textFieldStyle(.plain)
        .multilineTextAlignment(.center)
        .font(.appFont(size: fontSize, weight: .medium, design: .monospaced))
        .foregroundColor(theme.textColor)
        .frame(width: inputWidth)
        .onChange(of: value) { _, newValue in
          if !range.contains(newValue) {
            value = max(range.lowerBound, min(range.upperBound, newValue))
          }
          onUpdate?()
        }

      Divider()
        .frame(height: buttonSize * 0.6)
        .padding(.horizontal, horizontalPadding)

      // Plus Button
      Button(action: {
        if value < range.upperBound {
          value += 1
          onUpdate?()
        }
      }) {
        Image(systemName: "plus")
          .font(.appFont(size: fontSize - 3, weight: .bold))
          .foregroundColor(theme.textColor)
          .frame(width: buttonSize, height: buttonSize)
          .background(isPlusHovered ? theme.textColor.opacity(0.1) : Color.clear)
      }
      .buttonStyle(.plain)
      .disabled(value >= range.upperBound)
      .onHover { isPlusHovered = $0 }
    }
    .background(theme.inputBackgroundColor)
    .cornerRadius(theme.borderRadius / 1.5)
    .overlay(
      RoundedRectangle(cornerRadius: theme.borderRadius / 1.5)
        .stroke(theme.borderColor, lineWidth: 0.5)
    )
  }
}

/// A custom-styled segmented picker that works better with themes than the default macOS one
struct CustomSegmentedPicker<T: Hashable>: View {
  @Binding var selection: T
  let items: [T]
  let titleProvider: (T) -> String

  @ObservedObject private var theme = ThemeManager.shared
  @State private var hoveredItem: T? = nil

  var body: some View {
    HStack(spacing: 0) {
      ForEach(items, id: \.self) { item in
        let isSelected = selection == item

        Button(action: {
          withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            selection = item
          }
        }) {
          Text(titleProvider(item))
            .font(.appFont(size: 11, weight: isSelected ? .bold : .medium))
            .foregroundColor(isSelected ? .white : theme.textColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
              ZStack {
                if isSelected {
                  RoundedRectangle(cornerRadius: (theme.borderRadius / 1.5) - 2)
                    .fill(theme.accentColor)
                    .transition(.scale.combined(with: .opacity))
                } else if hoveredItem == item {
                  RoundedRectangle(cornerRadius: (theme.borderRadius / 1.5) - 2)
                    .fill(theme.textColor.opacity(0.1))
                }
              }
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
          hoveredItem = isHovering ? item : nil
        }
      }
    }
    .padding(2)
    .background(theme.inputBackgroundColor)
    .cornerRadius(theme.borderRadius / 1.5)
    .overlay(
      RoundedRectangle(cornerRadius: theme.borderRadius / 1.5)
        .stroke(theme.borderColor, lineWidth: 0.5)
    )
  }
}
