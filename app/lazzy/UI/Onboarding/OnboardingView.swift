import AppKit
import Auth
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// A deliberate first-run path. Every step is optional except the macOS permissions
/// required for Detach's selection and computer-use features.
struct OnboardingView: View {
  private enum Step: Int, CaseIterable {
    case welcome, account, permissions, agents, browser, secrets, hotkey, complete

    var title: String {
      switch self {
      case .welcome: "Welcome to\nDetach"
      case .account: "Make Detach\nyours"
      case .permissions: "Give Detach\na hand"
      case .agents: "Connect your\nagents"
      case .browser: "Bring your browser\nalong"
      case .secrets: "Let work continue\nthrough sign-in"
      case .hotkey: "Choose your launch\nshortcut"
      case .complete: "You're ready\nto detach"
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
  @AppStorage("browser_automation_mode") private var browserModeRaw = BrowserSettings.defaultMode

  var onComplete: () -> Void

  var body: some View {
    ZStack {
      LinearGradient(
        stops: [
          .init(color: Color(red: 0.07, green: 0.07, blue: 0.08), location: 0.0),
          .init(color: Color(red: 0.08, green: 0.08, blue: 0.09), location: 0.45),
          .init(color: Color(red: 0.42, green: 0.12, blue: 0.02), location: 0.65),
          .init(color: Color(red: 0.95, green: 0.35, blue: 0.05), location: 0.82),
          .init(color: Color(red: 0.98, green: 0.62, blue: 0.25), location: 0.93),
          .init(color: Color(red: 1.00, green: 0.92, blue: 0.82), location: 1.0)
        ],
        startPoint: .top,
        endPoint: .bottom
      )
      .ignoresSafeArea()

      VStack(spacing: 0) {
        topBar
        content
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        navigation
      }
    }
    .font(.system(size: 14))
    .foregroundStyle(Color.white)
    .frame(width: 900, height: 640)
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
    ZStack {
      HStack {
        if canGoBack {
          Button { goBack() } label: {
            Label("", systemImage: "chevron.left")
          }
          .buttonStyle(OnboardingSecondaryButtonStyle())
        }
        Spacer()
        if canSkip {
          Button("Skip for now") { goForward() }
            .buttonStyle(OnboardingSecondaryButtonStyle())
        }
      }

      HStack(spacing: 2) {
        Image("DetachedMark")
          .resizable()
          .scaledToFit()
          .frame(width: 26, height: 26)
        Text("Detach")
          .font(.system(size: 15, weight: .semibold))
          .tracking(-0.35)
      }
    }
    .padding(.horizontal, 32)
    .padding(.top, 20)
    .padding(.bottom, 12)
    .frame(height: 70)
  }

  private var canGoBack: Bool { step != .welcome && step != .complete }
  private var canSkip: Bool { step == .account || step == .browser || step == .secrets }

  private var stepProgress: some View {
    HStack(spacing: 6) {
      Text("\(step.rawValue) of \(Step.complete.rawValue - 1)")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
      HStack(spacing: 4) {
        ForEach(1..<Step.complete.rawValue, id: \.self) { value in
          Capsule()
            .fill(value <= step.rawValue ? OnboardingPalette.orange : Color.white.opacity(0.25))
            .frame(width: value == step.rawValue ? 16 : 5, height: 5)
        }
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
    OnboardingStepLayout(
      title: "Cursor for\nyour entire macOS",
      subtitle: "Detach is a desktop app that lets you work with AI across your text, files, browser tabs, and native apps."
    ) {
      Button(action: goForward) {
        Label("Let's Start", systemImage: "arrow.right")
      }
      .buttonStyle(OnboardingPrimaryButtonStyle())
    }
  }

  private var account: some View {
    OnboardingStepLayout(
      title: "Sign in, or\nkeep it local.",
      subtitle: "An account syncs your Detach preferences. You can use every local setup feature without one."
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
          HStack(spacing: 9) {
            Image("GoogleLogo")
              .resizable()
              .scaledToFit()
              .frame(width: 18, height: 18)
            Text("Continue with Google")
          }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.84))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.primary.opacity(0.15)))
        }
        .buttonStyle(.plain)
      }
      .frame(maxWidth: 390)
    }
  }

  private var permissionsSetup: some View {
    OnboardingStepLayout(
      title: "A little access\ngoes a long way.",
      subtitle: "Detach needs these permissions to understand selected context and let your agents interact with your Mac. It never runs in the background without your request."
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
      if granted {
        Label("Allowed", systemImage: "checkmark")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.secondary)
      } else {
        Button("Allow", action: action)
          .buttonStyle(OnboardingPrimaryButtonStyle())
      }
    }
    .padding(14)
    .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
  }

  private var agentsSetup: some View {
    OnboardingStepLayout(
      title: "Your subscriptions,\nyour agents.",
      subtitle: "Detach connects to the CLI agents already installed on your Mac. Nothing is routed through a hosted Detach model."
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
          .foregroundStyle(isInstalled ? Color.primary : Color.secondary)
      }
      .padding(13)
      .background(Color.primary.opacity(isSelected ? 0.09 : 0.035), in: RoundedRectangle(cornerRadius: 14))
      .overlay(RoundedRectangle(cornerRadius: 14).stroke(isSelected ? Color.primary.opacity(0.45) : .clear))
    }
    .buttonStyle(.plain)
  }

  private var browserSetup: some View {
    OnboardingStepLayout(
      title: "Choose where agents\nwork on the web.",
      subtitle: "Use your signed-in Chrome when existing logins matter, or choose a separate Power Browser for deeper, isolated automation."
    ) {
      VStack(alignment: .leading, spacing: 14) {
        HStack(spacing: 10) {
          onboardingBrowserMode(.signedIn, icon: "person.crop.circle.badge.checkmark")
          onboardingBrowserMode(.power, icon: "bolt.shield.fill")
        }

        if browserModeRaw == BrowserAutomationMode.signedIn.rawValue {
          setupInstruction(number: 1, "Open Chrome Extensions")
          setupInstruction(number: 2, "Enable Developer mode and choose Load unpacked")
          setupInstruction(number: 3, "Select Detach’s chrome-extension folder, then pin it")
          HStack(spacing: 10) {
            Button("Open Chrome Extensions") { NSWorkspace.shared.open(URL(string: "chrome://extensions")!) }
              .buttonStyle(OnboardingPrimaryButtonStyle())
            Button("Show extension folder") { showBrowserExtensionFolder() }
              .buttonStyle(OnboardingSecondaryButtonStyle())
          }
          Text("Open the extension popup once after installing to connect it to Detach.")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        } else {
          Label("No extension required", systemImage: "checkmark.circle.fill")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
          Text("Detach will use a separate persistent Chrome profile that becomes more established over time. Task tabs are isolated and automatically cleaned up.")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  private func onboardingBrowserMode(_ mode: BrowserAutomationMode, icon: String) -> some View {
    let selected = browserModeRaw == mode.rawValue
    return Button {
      browserModeRaw = mode.rawValue
      AppCoordinator.shared?.wsManager.syncBrowserSettings()
    } label: {
      HStack(spacing: 8) {
        Image(systemName: icon)
        Text(mode.title).font(.system(size: 12, weight: .semibold))
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 10)
      .background(.primary.opacity(selected ? 0.1 : 0.035), in: RoundedRectangle(cornerRadius: 10))
      .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Color.primary.opacity(0.45) : .clear))
    }
    .buttonStyle(.plain)
  }

  private func setupInstruction(number: Int, _ text: String) -> some View {
    HStack(spacing: 11) {
      Text("\(number)").font(.system(size: 11, weight: .bold)).frame(width: 22, height: 22).background(.primary.opacity(0.09), in: Circle())
      Text(text).font(.system(size: 13, weight: .medium))
    }
  }

  private var secretsSetup: some View {
    OnboardingStepLayout(
      title: "Let work continue\npast the login.",
      subtitle: "Import logins from Apple Passwords. Credentials stay encrypted in your Mac’s Keychain; agents can request a secure fill, but never see the values."
    ) {
      VStack(alignment: .leading, spacing: 15) {
        Label("End-to-end encrypted and 100% local", systemImage: "lock.shield.fill")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.primary)
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
            .background(OnboardingPalette.orange, in: RoundedRectangle(cornerRadius: 12))
            .foregroundColor(.white)
        }
        .buttonStyle(.plain)
        if !importStatus.isEmpty { Text(importStatus).font(.system(size: 12)).foregroundStyle(.secondary) }
      }
    }
  }

  private var hotkeySetup: some View {
    OnboardingStepLayout(
      title: "Your AI, one\nkeystroke away.",
      subtitle: "Press this anywhere to start a detached task. You can change every shortcut later in Settings."
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
          ShortcutRecorderView(
            shortcut: $hotkey,
            isRecording: $isRecordingShortcut,
            foregroundColor: .black,
            accentColor: OnboardingPalette.orange
          )
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
    OnboardingStepLayout(
      title: "You're ready\nto detach.",
      subtitle: "Start from the menu bar or press \(hotkey.displayString)."
    ) {
      VStack(spacing: 20) {
        ZStack {
          Circle().fill(.black).frame(width: 64, height: 64)
          Image(systemName: "checkmark")
            .font(.system(size: 25, weight: .bold))
            .foregroundStyle(.white)
        }
        HStack(spacing: 7) {
          featureChip("Workflows", "point.3.connected.trianglepath.dotted")
          featureChip("Quick Actions", "wand.and.stars")
          featureChip("Agent tasks", "square.stack.3d.up")
        }
        Text("Select text anywhere to run a quick action with that context, or send a task to one of your connected agents.")
          .font(.system(size: 13))
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: 460)
      }
    }
  }

  private func featureChip(_ title: String, _ icon: String) -> some View {
    Label(title, systemImage: icon)
      .font(.system(size: 12, weight: .semibold))
      .padding(.horizontal, 12).padding(.vertical, 9)
      .background(.primary.opacity(0.06), in: Capsule())
  }

  private var navigation: some View {
    ZStack(alignment: .trailing) {
      if step != .welcome && step != .complete {
        stepProgress
      }

      if step == .complete {
        Button("Start using Detach", action: onComplete)
          .buttonStyle(OnboardingPrimaryButtonStyle())
      } else if !canSkip && step != .welcome {
        Button("Continue") { goForward() }
          .buttonStyle(OnboardingPrimaryButtonStyle())
      }
    }
    .padding(.horizontal, 32)
    .padding(.bottom, 28)
    .frame(height: 72)
  }

  private func buttonLabel(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 14, weight: .bold))
      .frame(maxWidth: .infinity)
      .padding(.vertical, 13)
      .foregroundStyle(.white)
      .background(OnboardingPalette.orange, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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

}

private struct OnboardingStepLayout<Content: View>: View {
  let title: String
  let subtitle: String
  @ViewBuilder let content: () -> Content

  var body: some View {
    VStack(spacing: 0) {
      Spacer(minLength: 12)
      VStack(spacing: 0) {
        JitterTitle(title: title)
          .frame(maxWidth: .infinity)
          // The SVG filter extends past its glyph bounds; this preserves that
          // bleed without changing the title's 46-point, tight line-height.
          .frame(height: 136)
          .accessibilityLabel(title)
          .accessibilityAddTraits(.isHeader)
        Text(subtitle)
          .font(.system(size: 15, weight: .regular))
          .foregroundStyle(.secondary)
          .lineSpacing(2)
          .multilineTextAlignment(.center)
          .frame(maxWidth: 540)
          .padding(.top, 15)
        content()
          .frame(maxWidth: 470)
          .padding(.top, 30)
      }
      Spacer(minLength: 12)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.horizontal, 34)
  }
}

/// Renders the landing page's actual SVG turbulence/displacement animation.
/// AppKit does not apply SVG filters to native text, so a transparent WebKit
/// surface is used here to keep the filter and its four stop-motion frames exact.
private struct JitterTitle: NSViewRepresentable {
  let title: String
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeNSView(context: Context) -> WKWebView {
    let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
    webView.setValue(false, forKey: "drawsBackground")
    webView.wantsLayer = true
    webView.layer?.backgroundColor = NSColor.clear.cgColor
    loadHTML(into: webView)
    context.coordinator.renderedTitle = title
    context.coordinator.renderedReduceMotion = reduceMotion
    return webView
  }

  func updateNSView(_ webView: WKWebView, context: Context) {
    guard context.coordinator.renderedTitle != title || context.coordinator.renderedReduceMotion != reduceMotion else {
      return
    }
    loadHTML(into: webView)
    context.coordinator.renderedTitle = title
    context.coordinator.renderedReduceMotion = reduceMotion
  }

  private func loadHTML(into webView: WKWebView) {
    webView.loadHTMLString(Self.html(title: title, reduceMotion: reduceMotion), baseURL: nil)
  }

  static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
    webView.stopLoading()
  }

  final class Coordinator {
    var renderedTitle = ""
    var renderedReduceMotion = false
  }

  private static func html(title: String, reduceMotion: Bool) -> String {
    let animation = reduceMotion ? "none" : "stopmotion 0.4s steps(1) infinite"
    return """
    <!doctype html>
    <html>
      <head>
        <style>
          html, body { width: 100%; height: 100%; margin: 0; overflow: hidden; background: transparent; }
          h1 {
            display: flex; align-items: center; justify-content: center;
            width: 100%; height: 100%; margin: 0;
            color: white; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", sans-serif;
            font-size: 54px; font-weight: 700; letter-spacing: -2.7px; line-height: 46px;
            text-align: center; white-space: pre-line;
            animation: \(animation);
          }
          @keyframes stopmotion {
            0%, 24.9% { filter: url(#jitter-0); }
            25%, 49.9% { filter: url(#jitter-1); }
            50%, 74.9% { filter: url(#jitter-2); }
            75%, 99.9% { filter: url(#jitter-3); }
          }
        </style>
      </head>
      <body>
        <svg width="0" height="0" aria-hidden="true" focusable="false">
          <defs>
            <filter id="jitter-0" x="-5%" y="-5%" width="110%" height="110%">
              <feTurbulence type="turbulence" baseFrequency="0.04" numOctaves="3" seed="3" result="noise" />
              <feDisplacementMap in="SourceGraphic" in2="noise" scale="3" xChannelSelector="R" yChannelSelector="G" />
            </filter>
            <filter id="jitter-1" x="-5%" y="-5%" width="110%" height="110%">
              <feTurbulence type="turbulence" baseFrequency="0.04" numOctaves="3" seed="10" result="noise" />
              <feDisplacementMap in="SourceGraphic" in2="noise" scale="3" xChannelSelector="R" yChannelSelector="G" />
            </filter>
            <filter id="jitter-2" x="-5%" y="-5%" width="110%" height="110%">
              <feTurbulence type="turbulence" baseFrequency="0.04" numOctaves="3" seed="17" result="noise" />
              <feDisplacementMap in="SourceGraphic" in2="noise" scale="3" xChannelSelector="R" yChannelSelector="G" />
            </filter>
            <filter id="jitter-3" x="-5%" y="-5%" width="110%" height="110%">
              <feTurbulence type="turbulence" baseFrequency="0.04" numOctaves="3" seed="24" result="noise" />
              <feDisplacementMap in="SourceGraphic" in2="noise" scale="3" xChannelSelector="R" yChannelSelector="G" />
            </filter>
          </defs>
        </svg>
        <h1>\(title.htmlEscapedForJitterTitle)</h1>
      </body>
    </html>
    """
  }
}

private extension String {
  var htmlEscapedForJitterTitle: String {
    replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "'", with: "&#39;")
  }
}

private struct OnboardingPrimaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 13, weight: .bold))
      .foregroundStyle(.white)
      .padding(.horizontal, 18)
      .frame(height: 38)
      .background(OnboardingPalette.orange.opacity(configuration.isPressed ? 0.72 : 1), in: Capsule())
      .scaleEffect(configuration.isPressed ? 0.98 : 1)
      .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
  }
}

private struct OnboardingSecondaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 13, weight: .semibold))
      .foregroundStyle(.primary)
      .padding(.horizontal, 18)
      .frame(height: 38)
      .background(.black.opacity(configuration.isPressed ? 0.09 : 0.055), in: Capsule())
      .scaleEffect(configuration.isPressed ? 0.98 : 1)
      .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
  }
}

private enum OnboardingPalette {
  static let orange = Color(red: 0.88, green: 0.28, blue: 0.05)
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
