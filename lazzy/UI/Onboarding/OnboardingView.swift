import AppKit
import Auth
import SwiftUI
import UniformTypeIdentifiers

/// A deliberate first-run path. Every step is optional except the macOS permissions
/// required for Detach's selection and computer-use features.
struct OnboardingView: View {
  private enum Step: Int, CaseIterable {
    case welcome, account, permissions, agents, browser, secrets, hotkey, complete

    var title: String {
      switch self {
      case .welcome: "Welcome to Detach"
      case .account: "Make Detach yours"
      case .permissions: "Give Detach a hand"
      case .agents: "Connect your agents"
      case .browser: "Bring your browser along"
      case .secrets: "Let work continue through sign-in"
      case .hotkey: "Choose your launch shortcut"
      case .complete: "You're ready to detach"
      }
    }
  }

  @StateObject private var auth = AuthManager.shared
  @StateObject private var permissions = PermissionsManager()
  @State private var step: Step = .welcome
  @State private var email = ""
  @State private var magicLinkSent = false
  @State private var selectedAgent = DetachSettings.selectedAgent
  @State private var detectedAgents = LocalAgentDetector.detect()
  @State private var hotkey = ShortcutSettings.floatingChat
  @State private var isRecordingShortcut = false
  @State private var showImporter = false
  @State private var importStatus = ""

  var onComplete: () -> Void
  var onClose: () -> Void

  var body: some View {
    ZStack(alignment: .topTrailing) {
      Color(nsColor: .windowBackgroundColor)
        .ignoresSafeArea()

      VStack(spacing: 0) {
        topBar
        content
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        navigation
      }
      .padding(36)

      Button(action: onClose) {
        Image(systemName: "xmark")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.secondary)
          .frame(width: 36, height: 36)
          .contentShape(Circle())
      }
      .buttonStyle(.plain)
      .padding(22)
      .help("Finish setup later")
    }
    .frame(width: 1_020, height: 680)
    .fileImporter(isPresented: $showImporter, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
      guard case .success(let url) = result else {
        if case .failure(let error) = result { importStatus = error.localizedDescription }
        return
      }
      importApplePasswords(from: url)
    }
    .onAppear {
      permissions.checkPermissions()
      detectedAgents = LocalAgentDetector.detect()
    }
    .onChange(of: auth.isAuthenticated) { _, authenticated in
      if authenticated && step == .account { goForward() }
    }
  }

  private var topBar: some View {
    HStack {
      HStack(spacing: 9) {
        Image(systemName: "arrow.up.right.circle.fill")
          .font(.system(size: 22, weight: .medium))
        Text("Detach")
          .font(.system(size: 15, weight: .semibold))
      }
      Spacer()
      if step != .welcome && step != .complete {
        Text("Step \(step.rawValue) of \(Step.complete.rawValue - 1)")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(.secondary)
      }
    }
  }

  @ViewBuilder
  private var content: some View {
    switch step {
    case .welcome: welcome
    case .account: account
    case .permissions: permissionsSetup
    case .agents: agentsSetup
    case .browser: browserSetup
    case .secrets: secretsSetup
    case .hotkey: hotkeySetup
    case .complete: complete
    }
  }

  private var welcome: some View {
    VStack(spacing: 24) {
      Spacer()
      Image(systemName: "arrow.down.left.and.arrow.up.right")
        .font(.system(size: 42, weight: .medium))
        .frame(width: 84, height: 84)
        .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 24))

      VStack(spacing: 12) {
        Text("Use AI the\ndetached way.")
          .font(.system(size: 52, weight: .semibold, design: .rounded))
          .multilineTextAlignment(.center)
          .lineSpacing(-4)
        Text("Detach brings your own CLI agents to the text, apps,\nand browser you already work in.")
          .font(.system(size: 18))
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }

      HStack(spacing: 8) {
        welcomePill("Select text", icon: "text.cursor")
        welcomePill("Launch an agent", icon: "sparkles")
        welcomePill("Keep working", icon: "arrow.right")
      }
      Spacer()
    }
  }

  private func welcomePill(_ label: String, icon: String) -> some View {
    Label(label, systemImage: icon)
      .font(.system(size: 13, weight: .medium))
      .padding(.horizontal, 13)
      .padding(.vertical, 8)
      .background(.primary.opacity(0.06), in: Capsule())
  }

  private var account: some View {
    OnboardingSplit(
      title: "Sign in, or keep it local.",
      subtitle: "An account syncs your Detach preferences. You can use every local setup feature without one.",
      visual: { accountVisual }
    ) {
      VStack(alignment: .leading, spacing: 16) {
        Text("Email")
          .font(.system(size: 13, weight: .semibold))
        TextField("you@example.com", text: $email)
          .textFieldStyle(.plain)
          .padding(14)
          .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
          .overlay(RoundedRectangle(cornerRadius: 12).stroke(.primary.opacity(0.12)))
        Button {
          Task {
            await auth.signInWithMagicLink(email: email)
            magicLinkSent = auth.lastError == nil
          }
        } label: {
          buttonLabel(auth.isLoading ? "Sending…" : "Continue with email")
        }
        .buttonStyle(.plain)
        .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || auth.isLoading)

        if magicLinkSent { Text("Check your inbox for the secure sign-in link.").foregroundStyle(.secondary).font(.system(size: 12)) }
        if let error = auth.lastError { Text(error).foregroundStyle(.red).font(.system(size: 12)) }

        HStack {
          Rectangle().fill(.primary.opacity(0.1)).frame(height: 1)
          Text("OR").font(.system(size: 10, weight: .bold)).foregroundStyle(.tertiary)
          Rectangle().fill(.primary.opacity(0.1)).frame(height: 1)
        }
        Button {
          Task { await auth.signInWithOAuth(provider: .google) }
        } label: {
          Label("Continue with Google", systemImage: "g.circle.fill")
            .font(.system(size: 14, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.primary.opacity(0.15)))
        }
        .buttonStyle(.plain)
      }
      .frame(maxWidth: 390)
    }
  }

  private var permissionsSetup: some View {
    OnboardingSplit(
      title: "A little access goes a long way.",
      subtitle: "Detach needs these permissions to understand selected context and let your agents interact with your Mac. It never runs in the background without your request.",
      visual: { permissionVisual }
    ) {
      VStack(spacing: 10) {
        permissionRow(
          icon: "cursorarrow.click.2", title: "Accessibility", description: "Read selected text and perform the actions you approve.", granted: permissions.hasAccessibilityPermission
        ) { permissions.requestAccessibilityPermission() }
        permissionRow(
          icon: "rectangle.on.rectangle", title: "Screen & System Audio Recording", description: "Let agents inspect your screen when you ask them to.", granted: permissions.hasScreenCapturePermission
        ) { permissions.requestScreenCapturePermission() }
        Text("You can change these any time in System Settings.")
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.top, 4)
      }
    }
  }

  private func permissionRow(icon: String, title: String, description: String, granted: Bool, action: @escaping () -> Void) -> some View {
    HStack(spacing: 14) {
      Image(systemName: icon)
        .font(.system(size: 18, weight: .medium))
        .frame(width: 38, height: 38)
        .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
      VStack(alignment: .leading, spacing: 3) {
        Text(title).font(.system(size: 14, weight: .semibold))
        Text(description).font(.system(size: 12)).foregroundStyle(.secondary)
      }
      Spacer()
      Button(granted ? "Allowed" : "Allow", action: action)
        .buttonStyle(.bordered)
        .tint(granted ? .green : .primary)
        .disabled(granted)
    }
    .padding(14)
    .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
  }

  private var agentsSetup: some View {
    OnboardingSplit(
      title: "Your subscriptions,\nyour agents.",
      subtitle: "Detach connects to the CLI agents already installed on your Mac. Nothing is routed through a hosted Detach model.",
      visual: { agentVisual }
    ) {
      VStack(alignment: .leading, spacing: 10) {
        ForEach(LocalAgentDetector.Agent.allCases) { agent in
          agentRow(agent)
        }
        Button("Check again") { detectedAgents = LocalAgentDetector.detect() }
          .font(.system(size: 12, weight: .medium))
          .buttonStyle(.plain)
          .foregroundStyle(.secondary)
          .padding(.top, 4)
      }
    }
  }

  private func agentRow(_ agent: LocalAgentDetector.Agent) -> some View {
    let isSelected = selectedAgent == agent.id
    let isInstalled = detectedAgents.contains(agent)
    return Button { selectedAgent = agent.id } label: {
      HStack(spacing: 13) {
        Image(systemName: agent.symbol)
          .font(.system(size: 17, weight: .semibold))
          .frame(width: 34, height: 34)
          .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        VStack(alignment: .leading, spacing: 2) {
          Text(agent.name).font(.system(size: 14, weight: .semibold))
          Text(isInstalled ? "Found on this Mac" : "Install the \(agent.name) CLI to connect")
            .font(.system(size: 12)).foregroundStyle(.secondary)
        }
        Spacer()
        Image(systemName: isInstalled ? "checkmark.circle.fill" : "arrow.down.circle")
          .foregroundStyle(isInstalled ? Color.green : Color.secondary)
      }
      .padding(13)
      .background(Color.primary.opacity(isSelected ? 0.09 : 0.035), in: RoundedRectangle(cornerRadius: 14))
      .overlay(RoundedRectangle(cornerRadius: 14).stroke(isSelected ? Color.primary.opacity(0.45) : .clear))
    }
    .buttonStyle(.plain)
  }

  private var browserSetup: some View {
    OnboardingSplit(
      title: "Agents work in\nyour real browser.",
      subtitle: "The Detach Browser Agent extension connects securely to the local runtime, so it can work in the Chrome profile where you are already signed in.",
      visual: { browserVisual }
    ) {
      VStack(alignment: .leading, spacing: 14) {
        setupInstruction(number: 1, "Open Chrome Extensions")
        setupInstruction(number: 2, "Enable Developer mode and choose Load unpacked")
        setupInstruction(number: 3, "Select Detach’s chrome-extension folder, then pin it")
        HStack(spacing: 10) {
          Button("Open Chrome Extensions") { NSWorkspace.shared.open(URL(string: "chrome://extensions")!) }
            .buttonStyle(.borderedProminent)
          Button("Show extension folder") { showBrowserExtensionFolder() }
            .buttonStyle(.bordered)
        }
        Text("Open the extension popup once after installing to connect it to Detach.")
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
      }
    }
  }

  private func setupInstruction(number: Int, _ text: String) -> some View {
    HStack(spacing: 11) {
      Text("\(number)").font(.system(size: 11, weight: .bold)).frame(width: 22, height: 22).background(.primary.opacity(0.09), in: Circle())
      Text(text).font(.system(size: 13, weight: .medium))
    }
  }

  private var secretsSetup: some View {
    OnboardingSplit(
      title: "Let work continue\npast the login.",
      subtitle: "Import logins from Apple Passwords. Credentials stay encrypted in your Mac’s Keychain; agents can request a secure fill, but never see the values.",
      visual: { secretsVisual }
    ) {
      VStack(alignment: .leading, spacing: 15) {
        Label("End-to-end encrypted and 100% local", systemImage: "lock.shield.fill")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.green)
        Text("In Passwords, choose File → Export Passwords, then select the CSV below. Detach only reads the file locally and moves credentials into Keychain.")
          .font(.system(size: 13))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        Button {
          showImporter = true
        } label: {
          Label("Import from Apple Passwords", systemImage: "key.fill")
            .font(.system(size: 14, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(.primary, in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.background)
        }
        .buttonStyle(.plain)
        if !importStatus.isEmpty { Text(importStatus).font(.system(size: 12)).foregroundStyle(.secondary) }
      }
    }
  }

  private var hotkeySetup: some View {
    OnboardingSplit(
      title: "Your AI, one keystroke away.",
      subtitle: "Press this anywhere to start a detached task. You can change every shortcut later in Settings.",
      visual: { hotkeyVisual }
    ) {
      VStack(alignment: .leading, spacing: 16) {
        Text("Launch Detach")
          .font(.system(size: 13, weight: .semibold))
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text("Floating chat") .font(.system(size: 14, weight: .semibold))
            Text("Open a fresh task from anywhere on your Mac.").font(.system(size: 12)).foregroundStyle(.secondary)
          }
          Spacer()
          ShortcutRecorderView(shortcut: $hotkey, isRecording: $isRecordingShortcut)
        }
        .padding(16)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
        Label("Tip: select text first, then invoke Detach to give your agent instant context.", systemImage: "text.cursor")
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
      }
    }
  }

  private var complete: some View {
    VStack(spacing: 22) {
      Spacer()
      Image(systemName: "checkmark")
        .font(.system(size: 40, weight: .bold))
        .foregroundStyle(.white)
        .frame(width: 82, height: 82)
        .background(.primary, in: Circle())
      VStack(spacing: 10) {
        Text("You're ready to detach.")
          .font(.system(size: 42, weight: .semibold, design: .rounded))
        Text("Start from the menu bar or press \(hotkey.displayString).")
          .font(.system(size: 17))
          .foregroundStyle(.secondary)
      }
      HStack(spacing: 10) {
        featureChip("Create workflows", "point.3.connected.trianglepath.dotted")
        featureChip("Use quick actions", "wand.and.stars")
        featureChip("Run agent tasks", "square.stack.3d.up")
      }
      Text("Select text anywhere to run a quick action with that context, or send multiple tasks to your connected agents.")
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 550)
      Spacer()
    }
  }

  private func featureChip(_ title: String, _ icon: String) -> some View {
    Label(title, systemImage: icon)
      .font(.system(size: 12, weight: .semibold))
      .padding(.horizontal, 12).padding(.vertical, 9)
      .background(.primary.opacity(0.06), in: Capsule())
  }

  private var navigation: some View {
    HStack {
      if step != .welcome && step != .complete {
        Button { goBack() } label: { Label("Back", systemImage: "chevron.left") }
          .buttonStyle(.bordered)
      } else { Color.clear.frame(width: 70, height: 30) }
      Spacer()
      HStack(spacing: 6) {
        ForEach(1..<Step.complete.rawValue, id: \.self) { value in
          Capsule().fill(Color.primary.opacity(value == step.rawValue ? 1 : 0.12)).frame(width: value == step.rawValue ? 20 : 7, height: 7)
        }
      }
      Spacer()
      if step == .complete {
        Button("Start using Detach", action: onComplete).buttonStyle(.borderedProminent)
      } else if step == .account || step == .browser || step == .secrets {
        Button("Skip for now") { goForward() }.buttonStyle(.bordered)
      } else {
        Button(step == .welcome ? "Let's start" : "Continue") { goForward() }
          .buttonStyle(.borderedProminent)
      }
    }
    .frame(height: 44)
  }

  private func buttonLabel(_ title: String) -> some View {
    Text(title).font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 13)
      .background(.primary, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(.background)
  }

  private func goForward() {
    if step == .agents { DetachSettings.selectedAgent = selectedAgent }
    if step == .hotkey { ShortcutSettings.floatingChat = hotkey }
    guard let next = Step(rawValue: step.rawValue + 1) else { return }
    withAnimation(.easeInOut(duration: 0.2)) { step = next }
  }

  private func goBack() {
    guard let previous = Step(rawValue: step.rawValue - 1) else { return }
    withAnimation(.easeInOut(duration: 0.2)) { step = previous }
  }

  private func showBrowserExtensionFolder() {
    let appSupport = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("chrome-extension")
    let repositoryExtension = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("chrome-extension")
    NSWorkspace.shared.activateFileViewerSelecting([FileManager.default.fileExists(atPath: appSupport.path) ? appSupport : repositoryExtension])
  }

  private func importApplePasswords(from url: URL) {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    do {
      let preview = try SecretVault.shared.previewApplePasswordsCSV(at: url)
      let result = try SecretVault.shared.commitImport(preview)
      importStatus = "Imported \(result.importedCount) credential\(result.importedCount == 1 ? "" : "s") into your Keychain."
    } catch {
      importStatus = error.localizedDescription
    }
  }

  private var accountVisual: some View { OnboardingIllustration(icon: "person.crop.circle.badge.checkmark", tint: .blue, headline: "Your setup, wherever you work") }
  private var permissionVisual: some View { OnboardingIllustration(icon: "hand.raised.fill", tint: .orange, headline: "Always in your control") }
  private var agentVisual: some View { OnboardingIllustration(icon: "sparkles", tint: .purple, headline: "Codex · Claude · Grok") }
  private var browserVisual: some View { OnboardingIllustration(icon: "globe", tint: .cyan, headline: "Your tabs, with your sessions") }
  private var secretsVisual: some View { OnboardingIllustration(icon: "lock.shield.fill", tint: .indigo, headline: "Local by design") }
  private var hotkeyVisual: some View { OnboardingIllustration(icon: "command", tint: .pink, headline: hotkey.displayString) }
}

private struct OnboardingSplit<Content: View, Visual: View>: View {
  let title: String
  let subtitle: String
  @ViewBuilder let visual: () -> Visual
  @ViewBuilder let content: () -> Content

  var body: some View {
    HStack(spacing: 48) {
      VStack(alignment: .leading, spacing: 28) {
        Spacer()
        VStack(alignment: .leading, spacing: 12) {
          Text(title).font(.system(size: 37, weight: .semibold, design: .rounded)).lineSpacing(-3)
          Text(subtitle).font(.system(size: 16)).foregroundStyle(.secondary).lineSpacing(3)
        }
        content()
        Spacer()
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      visual().frame(width: 400, height: 450)
    }
    .padding(.horizontal, 26)
  }
}

private struct OnboardingIllustration: View {
  let icon: String
  let tint: Color
  let headline: String

  var body: some View {
    ZStack {
      LinearGradient(colors: [tint.opacity(0.18), tint.opacity(0.54)], startPoint: .topLeading, endPoint: .bottomTrailing)
      Circle().fill(.white.opacity(0.18)).frame(width: 290).blur(radius: 35).offset(x: 90, y: -110)
      VStack(spacing: 20) {
        Image(systemName: icon).font(.system(size: 64, weight: .medium)).foregroundStyle(.white)
        Text(headline).font(.system(size: 18, weight: .semibold)).foregroundStyle(.white).multilineTextAlignment(.center)
      }
      .padding(32)
      .background(.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 26))
    }
    .clipShape(RoundedRectangle(cornerRadius: 28))
  }
}

private enum LocalAgentDetector {
  enum Agent: String, CaseIterable, Identifiable, Hashable {
    case codex, claude, grok
    var id: String { rawValue }
    var name: String { rawValue.capitalized }
    var symbol: String { switch self { case .codex: "chevron.left.forwardslash.chevron.right"; case .claude: "brain.head.profile"; case .grok: "bolt.fill" } }
    var executable: String { rawValue }
  }

  static func detect() -> Set<Agent> {
    let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
    return Set(Agent.allCases.filter { agent in
      paths.contains { FileManager.default.isExecutableFile(atPath: URL(fileURLWithPath: $0).appendingPathComponent(agent.executable).path) }
    })
  }
}
