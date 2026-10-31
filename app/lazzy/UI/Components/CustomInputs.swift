import SwiftUI

/// Compatibility adapters keep existing app callers on the shared control system.
struct CustomMenu: View {
  let options: [String]
  @Binding var selectedOption: String
  var onSelect: ((String) -> Void)? = nil
  var fontSize: CGFloat = 13
  var horizontalPadding: CGFloat = 12
  var verticalPadding: CGFloat = 6
  var iconSize: CGFloat = 10
  var backgroundColor: Color? = nil
  var borderRadius: CGFloat? = nil
  var showBorder = true
  var opensOnHover = false

  var body: some View {
    AppSelect(title: "Choose an option", selection: $selectedOption,
      options: options.map { .init(title: $0, value: $0) },
      fontSize: fontSize, opensOnHover: opensOnHover, onSelect: onSelect)
  }

  struct MenuOptionRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
      Button(action: action) { AppMenuRow(title: title, selected: isSelected) }.buttonStyle(.plain)
    }
  }
}

struct ModelMenu: View {
  let modelsWithAvailability: [(model: String, isAvailable: Bool)]
  @Binding var selectedOption: String
  var onSelect: ((String) -> Void)? = nil
  var fontSize: CGFloat = 13
  var horizontalPadding: CGFloat = 12
  var verticalPadding: CGFloat = 6
  var iconSize: CGFloat = 10
  var backgroundColor: Color? = nil
  var borderRadius: CGFloat? = nil
  var showBorder = true
  var unavailableHelp = "This model is not available on this Mac."
  var opensOnHover = false
  var showsProviderLogos = false

  var body: some View {
    AppSelect(title: "Choose a model", selection: $selectedOption,
      options: modelsWithAvailability.map { item in
        AppSelectOption(title: item.model, value: item.model,
          asset: showsProviderLogos ? AgentProvider.allCases.first { $0.name == item.model }?.asset : nil,
          isEnabled: item.isAvailable)
      }, fontSize: fontSize, opensOnHover: opensOnHover, onSelect: onSelect)
  }

  struct ModelOptionRow: View {
    let title: String
    let isSelected: Bool
    let isAvailable: Bool
    let unavailableHelp: String
    let showsProviderLogo: Bool
    var usesMonochromeSelection = false
    let action: () -> Void

    var body: some View {
      Button(action: action) {
        AppMenuRow(title: title, symbol: isAvailable ? nil : "lock",
          asset: showsProviderLogo ? AgentProvider.allCases.first { $0.name == title }?.asset : nil,
          selected: isSelected && isAvailable)
      }
      .buttonStyle(.plain).disabled(!isAvailable).opacity(isAvailable ? 1 : 0.4)
      .help(isAvailable ? "" : unavailableHelp)
    }
  }
}

struct CustomStepper: View {
  @Binding var value: Int
  let range: ClosedRange<Int>
  var onUpdate: (() -> Void)? = nil
  var fontSize: CGFloat = 13
  var buttonSize: CGFloat = 28
  var inputWidth: CGFloat = 40
  var horizontalPadding: CGFloat = 4

  var body: some View {
    AppStepper(value: $value, range: range).onChange(of: value) { _, _ in onUpdate?() }
  }
}

struct CustomSegmentedPicker<T: Hashable>: View {
  @Binding var selection: T
  let items: [T]
  let titleProvider: (T) -> String

  var body: some View {
    AppSegmentedControl(selection: $selection, items: items, title: titleProvider)
  }
}
