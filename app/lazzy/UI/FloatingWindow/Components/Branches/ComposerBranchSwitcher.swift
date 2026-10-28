import SwiftUI

struct ComposerBranchSwitcher: View {
  let branches: [ConversationBranch]
  let currentID: String?
  let isBusy: Bool
  var onSelect: (String) -> Void
  @State private var isPresented = false
  @ObservedObject private var theme = ThemeManager.shared

  private var index: Int { branches.firstIndex { $0.id == currentID } ?? 0 }

  var body: some View {
    HStack(spacing: 0) {
      arrow("chevron.left", offset: -1)
      Button { isPresented.toggle() } label: {
        Text("\(index + 1) / \(branches.count)")
          .font(.appFont(size: 10)).monospacedDigit().frame(minHeight: 25)
      }
      .accessibilityLabel("Conversation branch \(index + 1) of \(branches.count)")
      .help(branches.indices.contains(index) ? branches[index].label : "Conversation branches")
      arrow("chevron.right", offset: 1)
    }
    .buttonStyle(.plain).foregroundStyle(theme.secondaryTextColor)
    .disabled(isBusy)
    .background {
      DropdownPanelAnchor(isPresented: $isPresented, menuWidth: 240, menu: branchMenu,
        contentRevision: AnyHashable("\(currentID ?? ""): \(branches.map(\.id).joined())"))
    }
  }

  private func arrow(_ symbol: String, offset: Int) -> some View {
    Button {
      if branches.indices.contains(index + offset) { onSelect(branches[index + offset].id) }
    } label: {
      Image(systemName: symbol).font(.system(size: 9, weight: .medium))
        .frame(width: 19, height: 25).contentShape(Rectangle())
    }
    .disabled(!branches.indices.contains(index + offset))
    .accessibilityLabel(offset < 0 ? "Previous conversation branch" : "Next conversation branch")
  }

  private var branchMenu: some View {
    ScrollView {
      VStack(spacing: 2) {
      ForEach(Array(branches.enumerated()), id: \.element.id) { number, branch in
        Button {
          isPresented = false
          onSelect(branch.id)
        } label: {
          HStack(spacing: 8) {
            Text("\(number + 1)").font(.appFont(size: 11)).frame(width: 15)
            Text(branch.label).font(.appFont(size: 12)).lineLimit(1)
            Spacer(minLength: 0)
            if branch.id == currentID { Image(systemName: "checkmark").font(.system(size: 10)) }
          }
          .foregroundStyle(theme.textColor).padding(.horizontal, 8).padding(.vertical, 6)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
      }
    }
    .frame(height: min(CGFloat(branches.count) * 29 + 4, 280))
    .padding(5).themedSurface(in: RoundedRectangle(cornerRadius: 10))
  }
}
