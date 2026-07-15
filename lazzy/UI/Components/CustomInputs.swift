import AppKit
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
    .onHover { isHovered = $0 }
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
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 8)
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
    .onHover { isHovered = $0 }
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
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 8)
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
      .help(isAvailable ? "" : "Model only available to Pro users, upgrade to select")
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

/// Hosts dropdown content in its own borderless panel.
struct DropdownPanelAnchor<MenuContent: View>: NSViewRepresentable {
  @Binding var isPresented: Bool
  let menuWidth: CGFloat
  let menu: MenuContent

  func makeCoordinator() -> Coordinator {
    Coordinator(isPresented: $isPresented)
  }

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    view.postsFrameChangedNotifications = true
    return view
  }

  func updateNSView(_ anchorView: NSView, context: Context) {
    if isPresented {
      context.coordinator.present(menu: menu, menuWidth: menuWidth, from: anchorView)
    } else {
      context.coordinator.dismiss()
    }
  }

  static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
    coordinator.dismiss()
  }

  @MainActor
  final class Coordinator {
    @Binding var isPresented: Bool
    private var panel: NSPanel?
    private weak var parentWindow: NSWindow?
    private var clickMonitor: Any?

    init(isPresented: Binding<Bool>) {
      self._isPresented = isPresented
    }

    func present(menu: MenuContent, menuWidth: CGFloat, from anchorView: NSView) {
      guard let window = anchorView.window else { return }

      let hostingView = NSHostingView(rootView: menu.padding(22))
      hostingView.layer?.backgroundColor = NSColor.clear.cgColor

      let menuPanel: NSPanel
      if let panel {
        menuPanel = panel
        menuPanel.contentView = hostingView
      } else {
        menuPanel = NSPanel(
          contentRect: .zero,
          styleMask: [.borderless, .nonactivatingPanel],
          backing: .buffered,
          defer: false
        )
        menuPanel.isOpaque = false
        menuPanel.backgroundColor = .clear
        menuPanel.hasShadow = false
        menuPanel.hidesOnDeactivate = false
        menuPanel.isFloatingPanel = true
        menuPanel.becomesKeyOnlyIfNeeded = true
        menuPanel.level = window.level
        menuPanel.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        menuPanel.contentView = hostingView
        panel = menuPanel
        
        setupClickMonitor(panel: menuPanel)
      }

      if parentWindow !== window {
        parentWindow?.removeChildWindow(menuPanel)
        window.addChildWindow(menuPanel, ordered: .above)
        parentWindow = window
      }

      hostingView.frame.size.width = menuWidth + 44
      hostingView.layoutSubtreeIfNeeded()
      let fittingHeight = min(max(hostingView.fittingSize.height, 40), 320)
      menuPanel.setContentSize(NSSize(width: menuWidth + 44, height: fittingHeight))
      position(menuPanel, relativeTo: anchorView)
      menuPanel.orderFront(nil)
    }

    func dismiss() {
      removeClickMonitor()
      guard let panel else { return }
      parentWindow?.removeChildWindow(panel)
      panel.orderOut(nil)
      self.panel = nil
      parentWindow = nil
    }

    private func position(_ panel: NSPanel, relativeTo anchorView: NSView) {
      guard let window = anchorView.window else { return }
      let boundsInWindow = anchorView.convert(anchorView.bounds, to: nil)
      let boundsInScreen = window.convertToScreen(boundsInWindow)
      let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
      let panelSize = panel.frame.size

      // Align visual left edge of menu (origin.x + 22) with left of button (boundsInScreen.minX)
      var originX = boundsInScreen.minX - 22

      // Position the visual top edge of menu (origin.y + panelSize.height - 22) just below the button (boundsInScreen.minY - 4)
      var originY = boundsInScreen.minY - panelSize.height + 18

      originX = min(max(originX, visibleFrame.minX), visibleFrame.maxX - panelSize.width)
      originY = min(max(originY, visibleFrame.minY), visibleFrame.maxY - panelSize.height)
      panel.setFrameOrigin(NSPoint(x: originX, y: originY))
    }

    private func setupClickMonitor(panel: NSPanel) {
      guard clickMonitor == nil else { return }
      clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
        guard let self = self else { return event }
        // If click is outside the panel window, dismiss
        if !panel.frame.contains(NSEvent.mouseLocation) {
          DispatchQueue.main.async {
            self.isPresented = false
          }
        }
        return event
      }
    }

    private func removeClickMonitor() {
      if let clickMonitor {
        NSEvent.removeMonitor(clickMonitor)
        self.clickMonitor = nil
      }
    }
  }
}
