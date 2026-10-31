import SwiftUI

struct AppSlider: View {
  @Binding var value: Double
  var range: ClosedRange<Double> = 0...1
  var step: Double = 0.01
  var title = "Value"
  @Environment(\.isEnabled) private var isEnabled
  @ObservedObject private var theme = ThemeManager.shared

  private var fraction: CGFloat {
    CGFloat(min(1, max(0, (value - range.lowerBound) / max(0.001, range.upperBound - range.lowerBound))))
  }

  var body: some View {
    GeometryReader { geometry in
      let travel = max(1, geometry.size.width - 12)
      ZStack(alignment: .leading) {
        Capsule().fill(theme.textColor.opacity(0.13)).frame(height: 3)
        Capsule().fill(theme.textColor.opacity(0.8)).frame(width: travel * fraction + 6, height: 3)
        Circle().fill(theme.textColor).frame(width: 11, height: 11)
          .offset(x: travel * fraction)
      }
      .frame(height: 24).contentShape(Rectangle())
      .gesture(DragGesture(minimumDistance: 0).onChanged {
        guard isEnabled else { return }
        update(range.lowerBound + Double(min(1, max(0, ($0.location.x - 6) / travel))) * (range.upperBound - range.lowerBound))
      })
    }
    .frame(height: 24)
    .opacity(isEnabled ? 1 : 0.35)
    .focusable().focusEffectDisabled()
    .onKeyPress(.leftArrow) { update(value - step); return .handled }
    .onKeyPress(.rightArrow) { update(value + step); return .handled }
    .accessibilityLabel(title)
    .accessibilityValue(String(format: "%.2g", value))
    .accessibilityAdjustableAction { update(value + ($0 == .increment ? step : -step)) }
  }

  private func update(_ next: Double) {
    guard isEnabled else { return }
    value = min(range.upperBound, max(range.lowerBound, range.lowerBound + ((next - range.lowerBound) / max(step, 0.0001)).rounded() * max(step, 0.0001)))
  }
}

struct AppStepper: View {
  @Binding var value: Int
  let range: ClosedRange<Int>
  var step = 1
  var title = "Value"
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    HStack(spacing: 0) {
      stepButton("minus", value: value - step, enabled: value > range.lowerBound)
      Text(String(value)).font(.appFont(size: 12, design: .monospaced))
        .foregroundStyle(theme.textColor).frame(minWidth: 34)
      stepButton("plus", value: value + step, enabled: value < range.upperBound)
    }
    .background(theme.textColor.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
    .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(theme.textColor.opacity(0.12), lineWidth: 0.6) }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(title)
  }

  private func stepButton(_ symbol: String, value next: Int, enabled: Bool) -> some View {
    Button { value = min(range.upperBound, max(range.lowerBound, next)) } label: {
      Image(systemName: symbol).font(.system(size: 9, weight: .medium))
        .frame(width: 26, height: 28).contentShape(Rectangle())
    }
    .buttonStyle(.plain).foregroundStyle(theme.textColor)
    .disabled(!enabled).opacity(enabled ? 1 : 0.3)
    .accessibilityLabel(symbol == "plus" ? "Increase \(title)" : "Decrease \(title)")
  }
}

struct AppSegmentedControl<Value: Hashable>: View {
  @Binding var selection: Value
  let items: [Value]
  let title: (Value) -> String
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    HStack(spacing: 2) {
      ForEach(items, id: \.self) { item in
        Button { selection = item } label: {
          Text(title(item)).font(.appFont(size: 11, weight: .medium))
            .foregroundStyle(theme.textColor.opacity(selection == item ? 1 : 0.6))
            .frame(maxWidth: .infinity).frame(height: 25)
            .background(theme.textColor.opacity(selection == item ? 0.1 : 0),
                        in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == item ? .isSelected : [])
      }
    }
    .padding(2)
    .background(theme.textColor.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
    .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(theme.textColor.opacity(0.08), lineWidth: 0.6) }
  }
}
