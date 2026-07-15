import SwiftUI

/// Horizontal quick actions menu view
struct QuickActionsMenuView: View {
  let actions: [QuickAction]
  let onActionSelected: (QuickAction) -> Void
  var onHoverStatusChanged: ((Bool) -> Void)? = nil

  @State private var showOverflow = false
  @State private var isMoreHovered = false
  @ObservedObject private var theme = ThemeManager.shared

  private var topActions: [QuickAction] {
    // Filter out any "more" action if it exists in the list
    let filtered = actions.filter { $0.id != "more" }
    return Array(filtered.prefix(5))
  }

  private var overflowActions: [QuickAction] {
    let filtered = actions.filter { $0.id != "more" }
    if filtered.count > 5 {
      return Array(filtered.dropFirst(5))
    }
    return []
  }

  var body: some View {
    HStack(spacing: 0) {
      ForEach(topActions) { action in
        QuickActionButton(
          action: action,
          theme: theme,
          onTap: { onActionSelected(action) }
        )
      }

      if !overflowActions.isEmpty {
        Button(action: { showOverflow.toggle() }) {
          Image(systemName: "ellipsis")
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(theme.textColor)
            .frame(width: 28, height: 28)
            .background(
              RoundedRectangle(cornerRadius: theme.borderRadius)
                .fill(isMoreHovered ? theme.accentColor : theme.backgroundColor)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
          isMoreHovered = hovering
          if hovering {
            showOverflow = true
          }
        }
        .popover(isPresented: $showOverflow, arrowEdge: .bottom) {
          VStack(alignment: .leading, spacing: 0) {
            ForEach(overflowActions) { action in
              QuickActionButton(
                action: action,
                theme: theme,
                onTap: {
                  onActionSelected(action)
                  showOverflow = false
                }
              )
            }
          }
          .padding(5)
          .background(theme.backgroundColor)
        }
        .contentShape(RoundedRectangle(cornerRadius: theme.borderRadius / 2.5))
      }
    }
    .background(theme.backgroundColor)
    .frame(height: 28)
    .clipShape(RoundedRectangle(cornerRadius: theme.borderRadius / 2.5))
    .onHover { hovering in
      onHoverStatusChanged?(hovering)
    }
  }
}

/// Individual action button
struct QuickActionButton: View {
  let action: QuickAction
  let theme: ThemeManager
  let onTap: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button(action: onTap) {
      Text(action.title)
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(theme.textColor)
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      if hovering {
        NSCursor.pointingHand.push()
      } else {
        NSCursor.pop()
      }
      withAnimation(.easeInOut(duration: 0.15)) {
        isHovered = hovering
      }
    }
    .padding(.horizontal, 8)
    // .padding(.vertical, 5)
    .frame(height: 28)
    .background(isHovered ? theme.accentColor : Color.clear)
    .contentShape(RoundedRectangle(cornerRadius: theme.borderRadius / 2.5))
  }
}
