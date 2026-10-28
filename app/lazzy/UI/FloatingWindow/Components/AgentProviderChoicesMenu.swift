import SwiftUI

struct AgentProviderChoicesMenu: View {
  let agents: [(model: String, isAvailable: Bool)]
  let selectedAgentName: String
  var autoSelected = false
  var showsAuto = false
  var onSelectAuto: () -> Void = {}
  let onSelect: (String) -> Void
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    ScrollView(.vertical, showsIndicators: false) {
      VStack(alignment: .leading, spacing: 2) {
        if showsAuto {
          ModelMenu.ModelOptionRow(title: "Auto", isSelected: autoSelected,
            isAvailable: true, unavailableHelp: "", showsProviderLogo: false, usesMonochromeSelection: true) { onSelectAuto() }
          Divider().padding(.vertical, 3)
        }
        ForEach(agents, id: \.model) { agent in
          ModelMenu.ModelOptionRow(title: agent.model, isSelected: !autoSelected && selectedAgentName == agent.model,
            isAvailable: agent.isAvailable, unavailableHelp: "This provider is not available on this Mac.",
            showsProviderLogo: true, usesMonochromeSelection: true) { onSelect(agent.model) }
        }
      }
      .padding(6)
    }
    .frame(width: 220).frame(maxHeight: 280)
    .themedSurface(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
  }
}
