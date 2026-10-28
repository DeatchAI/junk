import Foundation

/// Shared native presentation catalog; runtime capabilities remain authoritative.
enum AgentProvider: String, CaseIterable, Identifiable, Hashable {
  case codex, claude, grok, fx, opencode, pi, amp, omp
  var id: String { rawValue }
  var executable: String { rawValue }

  var name: String {
    switch self {
    case .codex: "Codex"
    case .claude: "Claude"
    case .grok: "Grok"
    case .fx: "fx"
    case .opencode: "OpenCode"
    case .pi: "Pi"
    case .amp: "Amp"
    case .omp: "Omp"
    }
  }

  var asset: String {
    "Provider" + (self == .fx ? "Fx" : name)
  }

  var symbol: String {
    switch self {
    case .codex: "chevron.left.forwardslash.chevron.right"
    case .claude: "brain.head.profile"
    case .grok: "bolt.fill"
    case .fx: "bolt.horizontal.circle"
    case .opencode: "shippingbox"
    case .pi: "function"
    case .amp: "waveform.path"
    case .omp: "option"
    }
  }

  func subtitle(isInstalled: Bool) -> String {
    if isInstalled {
      switch self {
      case .pi: return "Uses your Pi login and configured providers"
      case .amp: return "Uses your Amp account and model routing"
      case .omp: return "Uses your Oh My Pi login and configured providers"
      case .fx: return "Uses your fx and Vercel AI Gateway account"
      case .opencode: return "Uses your existing OpenCode configuration"
      default: return "Uses your \(name) account"
      }
    }
    switch self {
    case .pi: return "Install Pi from pi.dev and sign in with /login"
    case .amp: return "Install Amp from ampcode.com and run amp login"
    case .omp: return "Install Oh My Pi from omp.sh and sign in with /login"
    case .fx: return "Install the fx CLI and run fx login"
    case .opencode: return "The bundled OpenCode harness is unavailable"
    default: return "Install the \(name) CLI to connect"
    }
  }

  static var loadingOptions: [(String, Bool)] { allCases.map { ($0.name, true) } }
  static func displayName(for id: String) -> String { AgentProvider(rawValue: id)?.name ?? id.capitalized }
  static func identifier(for name: String) -> String { allCases.first { $0.name == name }?.id ?? name.lowercased() }
}
