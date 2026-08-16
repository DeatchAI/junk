import SwiftUI

struct ComposerBrowserTabsMenu: View {
  @Binding var page: ComposerAttachmentMenuPage
  @ObservedObject var store: BrowserTabStore
  let selectedTabIds: Set<Int>
  @Binding var selectedIndex: Int
  let onAttach: (BrowserTab) -> Void
  let onRefresh: () -> Void

  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    Group {
      header

      if store.isLoading && store.tabs.isEmpty {
        HStack(spacing: 8) {
          ProgressView()
            .controlSize(.small)
          Text("Loading tabs…")
            .font(.appFont(size: 12))
            .foregroundColor(theme.secondaryTextColor)
        }
        .frame(maxWidth: .infinity, minHeight: 72)
      } else if let errorMessage = store.errorMessage, store.tabs.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          Text(errorMessage)
            .font(.appFont(size: 11))
            .foregroundColor(theme.secondaryTextColor)
            .lineLimit(3)

          Button("Retry", action: onRefresh)
            .font(.appFont(size: 11, weight: .medium))
            .buttonStyle(.plain)
            .foregroundColor(theme.accentColor)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(.horizontal, 4)
      } else if store.tabs.isEmpty {
        ComposerAttachmentMenuEmptyState(text: "No open web tabs found in Chrome")
      } else {
        ScrollView {
          VStack(spacing: 2) {
            ForEach(Array(store.tabs.enumerated()), id: \.element.id) { index, tab in
              ComposerBrowserTabRow(
                tab: tab,
                isSelected: selectedTabIds.contains(tab.id),
                isHighlighted: selectedIndex == index,
                onHover: { selectedIndex = index }
              ) {
                onAttach(tab)
              }
            }
          }
        }
        .frame(maxHeight: 250)
      }
    }
  }

  private var header: some View {
    HStack(spacing: 8) {
      Button(action: { page = .root }) {
        Image(systemName: "chevron.left")
          .font(.appFont(size: 11, weight: .semibold))
          .frame(width: 24, height: 28)
      }
      .buttonStyle(.plain)
      .help("Back")

      Text("Tabs")
        .font(.appFont(size: 13, weight: .semibold))

      Spacer()

      Button(action: onRefresh) {
        Image(systemName: "arrow.clockwise")
          .font(.appFont(size: 11, weight: .semibold))
          .frame(width: 24, height: 28)
      }
      .buttonStyle(.plain)
      .help("Refresh Chrome tabs")
    }
    .foregroundColor(theme.textColor)
    .padding(.horizontal, 4)
    .padding(.bottom, 3)
  }
}
