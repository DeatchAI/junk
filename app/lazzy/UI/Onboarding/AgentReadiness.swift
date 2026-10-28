import Foundation

struct AgentReadiness: Equatable {
  enum State { case missing, installed, checking, signInNeeded, ready }
  let state: State
  let detail: String

  var title: String {
    switch state {
    case .missing: "Not installed"
    case .installed: "Installed"
    case .checking: "Checking…"
    case .signInNeeded: "Sign in needed"
    case .ready: "Ready"
    }
  }

  static let installed = Self(state: .installed, detail: "Sign-in could not be verified. Open the setup guide or try a first task.")

  static func parse(agent: AgentProvider, exitCode: Int32, output: String) -> Self {
    let object = output.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
    let signedIn: Bool?
    switch agent {
    case .claude: signedIn = object?["loggedIn"] as? Bool
    case .fx:
      let auth = object?["auth"] as? String
      signedIn = auth == "missing" ? false : ["authenticated", "configured", "logged_in"].contains(auth ?? "") ? true : nil
    case .codex:
      let text = output.lowercased()
      signedIn = text.contains("not logged in") || text.contains("not authenticated") ? false
        : exitCode == 0 && text.contains("logged in") ? true : nil
    default: signedIn = nil
    }
    if signedIn == true && exitCode == 0 {
      return Self(state: .ready, detail: "Sign-in confirmed. A first task checks that your agent can respond.")
    }
    if signedIn == false {
      return Self(state: .signInNeeded, detail: "Sign in with your agent, then check again.")
    }
    return .installed
  }
}

extension AgentProvider {
  var setupURL: URL {
    let address: String
    switch self {
    case .codex: address = "https://developers.openai.com/codex/cli/"
    case .claude: address = "https://code.claude.com/docs/en/quickstart"
    case .grok: address = "https://x.ai"
    case .fx: address = "https://fx.sh/docs"
    case .opencode: address = "https://opencode.ai/docs/"
    case .pi: address = "https://pi.dev"
    case .amp: address = "https://ampcode.com/manual"
    case .omp: address = "https://omp.sh"
    }
    return URL(string: address)!
  }

  var signInCommand: String {
    switch self {
    case .codex: "codex login"
    case .claude: "claude auth login"
    case .fx: "fx login"
    case .amp: "amp login"
    case .opencode: "opencode auth login"
    case .pi, .omp: "\(executable)  # then type /login"
    case .grok: "grok  # follow the sign-in instructions"
    }
  }
}
