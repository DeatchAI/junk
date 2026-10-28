import SwiftUI

/// Presentation-only catalog. Unknown/future adapters get a safe generic mark.
struct ProviderIdentity {
  let name: String
  let asset: String?
  let symbol: String

  init(_ id: String) {
    if let provider = AgentProvider(rawValue: id.lowercased()) {
      (name, asset, symbol) = (provider.name, provider.asset, provider.symbol)
      return
    }
    switch id.lowercased() {
    default: (name, asset, symbol) = (id.isEmpty ? "Agent" : id.capitalized, nil, "terminal")
    }
  }
}

struct ProviderLogo: View {
  let agent: String
  var size: CGFloat = 24
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    let provider = ProviderIdentity(agent)
    Group {
      if let asset = provider.asset {
        Image(asset).renderingMode(.template).resizable().scaledToFit()
      } else {
        Image(systemName: provider.symbol).resizable().scaledToFit().padding(3)
      }
    }
    .foregroundStyle(theme.textColor)
    .frame(width: size, height: size)
    .accessibilityLabel(provider.name)
  }
}
