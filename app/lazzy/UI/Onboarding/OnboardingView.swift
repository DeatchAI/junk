import AppKit
import Auth
import SwiftUI
import WebKit

/// A deliberate first-run path. Provider choice comes before account setup;
/// Detach Cloud is the only branch that asks for a Detach account or credits.
struct OnboardingView: View {
  private enum Step {
    case welcome, source, agents, hosted, permissions, hotkey, complete
  }

  private enum SetupSource: String, CaseIterable, Identifiable {
    case existing, hosted, later

    var id: String { rawValue }

    var title: String {
      switch self {
      case .existing: "Use my existing AI accounts"
      case .hosted: "Use Detach Cloud"
      case .later: "Decide later"
      }
    }

    var symbol: String {
      switch self {
      case .existing: "person.crop.circle"
      case .hosted: "sparkles"
      case .later: "arrow.right"
      }
    }
  }

  @StateObject private var auth = AuthManager.shared
  @StateObject private var permissions = PermissionsManager()
  @StateObject private var hostedSubscription = HostedSubscriptionManager.shared
  @State private var step: Step = .welcome
  @State private var selectedSource: SetupSource?
  @State private var email = ""
  @State private var hostedMagicLinkSent = false
  @State private var selectedAgent = DetachSettings.selectedAgent
  @State private var detectedAgents = LocalAgentDetector.detect()
  @State private var hotkey = ShortcutSettings.floatingChat
  @State private var isRecordingShortcut = false
  @State private var hostedCheckoutStarted = false
  @State private var hostedCheckoutPlanID: String?

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
    .onAppear {
      permissions.checkPermissions()
      refreshLocalSetup()
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      permissions.checkPermissions()
      refreshLocalSetup()
    }
    .onChange(of: auth.isAuthenticated) { _, authenticated in
      if authenticated {
        hostedMagicLinkSent = false
        Task { await hostedSubscription.refresh() }
      }
    }
    .onChange(of: hostedSubscription.hasHostedCredits) { _, hasCredits in
      if hasCredits {
        hostedCheckoutStarted = false
        hostedCheckoutPlanID = nil
      }
    }
    .task(id: auth.isAuthenticated) {
      await hostedSubscription.refresh()
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
  private var canSkip: Bool { step == .agents || step == .permissions || step == .hotkey }

  private var progressPosition: Int? {
    switch step {
    case .source: 1
    case .agents, .hosted: 2
    case .permissions: 3
    case .hotkey: 4
    case .welcome, .complete: nil
    }
  }

  @ViewBuilder
  private var stepProgress: some View {
    if let position = progressPosition {
      HStack(spacing: 6) {
        Text("\(position) of 4")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(.secondary)
        HStack(spacing: 4) {
          ForEach(1...4, id: \.self) { value in
            Capsule()
              .fill(value <= position ? OnboardingPalette.orange : Color.white.opacity(0.25))
              .frame(width: value == position ? 16 : 5, height: 5)
          }
        }
      }
    }
  }

  @ViewBuilder
  private var content: some View {
    switch step {
    case .welcome: welcome
    case .source: source
    case .agents: agentsSetup
    case .hosted: hostedSetup
    case .permissions: permissionsSetup
    case .hotkey: hotkeySetup
    case .complete: complete
    }
  }

  private var welcome: some View {
    OnboardingStepLayout(
      title: "Your AI,\nacross your Mac",
      subtitle: "Use Agent, Image, and Video modes across your text, files, browser tabs, and native apps."
    ) {
      Button(action: goForward) {
        Label("Let's Start", systemImage: "arrow.right")
      }
      .buttonStyle(OnboardingPrimaryButtonStyle())
    }
  }

  private var source: some View {
    OnboardingStepLayout(
      title: "How do you want\nto run AI?",
      subtitle: "Use an AI account you already have, or use Detach Cloud for Agent, Image, and Video modes."
    ) {
      VStack(spacing: 10) {
        sourceCard(.existing)
        sourceCard(.hosted)
        sourceCard(.later)
      }
    }
  }

  private func sourceCard(_ source: SetupSource) -> some View {
    let isSelected = selectedSource == source

    return Button {
      selectedSource = source
      if source == .existing {
        prepareLocalSelection()
      }
    } label: {
      HStack(spacing: 13) {
        Image(systemName: source.symbol)
          .font(.system(size: 17, weight: .semibold))
          .frame(width: 34, height: 34)
          .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))

        VStack(alignment: .leading, spacing: 3) {
          Text(source.title)
            .font(.system(size: 14, weight: .semibold))
          Text(sourceSubtitle(source))
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        Spacer()

        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(isSelected ? Color.primary : Color.secondary)
      }
      .padding(13)
      .background(Color.primary.opacity(isSelected ? 0.09 : 0.035), in: RoundedRectangle(cornerRadius: 14))
      .overlay(RoundedRectangle(cornerRadius: 14).stroke(isSelected ? Color.primary.opacity(0.45) : .clear))
    }
    .buttonStyle(.plain)
  }

  private func sourceSubtitle(_ source: SetupSource) -> String {
    switch source {
    case .existing:
      if detectedAgents.isEmpty {
        return "Codex, Claude, Grok, fx, or OpenCode. Connect one from this Mac."
      }
      let names = detectedAgents
        .sorted { $0.name < $1.name }
        .map(\.name)
        .joined(separator: ", ")
      return "\(names) available on this Mac. No Detach account required."
    case .hosted:
      return "Agent, image, and video through Detach Cloud. Sign in only if you choose this."
    case .later:
      return "Start with the app and choose an AI source from Settings whenever you are ready."
    }
  }

  private var hostedSetup: some View {
    OnboardingStepLayout(
      title: hostedTitle,
      subtitle: hostedSubtitle
    ) {
      if !auth.isAuthenticated {
        hostedSignIn
      } else if hostedSubscription.canUseHostedAI {
        hostedReady
      } else {
        hostedPlanPicker
      }
    }
  }

  private var hostedTitle: String {
    if !auth.isAuthenticated { return "Use Detach\nCloud" }
    if hostedSubscription.canUseHostedAI { return "Detach Cloud\nis ready" }
    return "Choose a\nCloud plan"
  }

  private var hostedSubtitle: String {
    if !auth.isAuthenticated {
      return "Use Detach Cloud for Agent, Image, and Video. Sign in to continue."
    }
    if hostedSubscription.canUseHostedAI {
      return "Your Detach Cloud credits are active. Agent, Image, and Video modes are ready to use."
    }
    return "Choose a monthly plan for Agent, Image, and Video on Detach Cloud."
  }

  private var hostedSignIn: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Create your Detach account")
        .font(.system(size: 13, weight: .semibold))

      TextField("you@example.com", text: $email)
        .textFieldStyle(.plain)
        .padding(14)
        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.primary.opacity(0.12)))

      Button {
        Task {
          await auth.signInWithMagicLink(email: email)
          hostedMagicLinkSent = auth.lastError == nil
        }
      } label: {
        buttonLabel(auth.isLoading ? "Sending…" : "Continue with email")
      }
      .buttonStyle(.plain)
      .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || auth.isLoading)

      if hostedMagicLinkSent {
        Text("Check your inbox for the secure sign-in link.")
          .foregroundStyle(.secondary)
          .font(.system(size: 12))
      }
      if let error = auth.lastError {
        Text(error)
          .foregroundStyle(.red)
          .font(.system(size: 12))
      }

      HStack {
        Rectangle().fill(.primary.opacity(0.1)).frame(height: 1)
        Text("OR")
          .font(.system(size: 10, weight: .bold))
          .foregroundStyle(.tertiary)
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
      .disabled(auth.isLoading)
    }
    .frame(maxWidth: 390)
  }

  private var hostedReady: some View {
    VStack(spacing: 16) {
      ZStack {
        Circle().fill(.black).frame(width: 58, height: 58)
        Image(systemName: "checkmark")
          .font(.system(size: 23, weight: .bold))
          .foregroundStyle(.white)
      }

      if let percentage = hostedSubscription.availableCreditPercentage {
        Text("\(percentage)% of your allowance remains")
          .font(.system(size: 14, weight: .semibold))
      }

      Text("Detach Cloud is connected and ready for Agent, Image, and Video modes.")
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
  }

  private var hostedPlanPicker: some View {
    VStack(alignment: .leading, spacing: 10) {
      if hostedSubscription.isLoading && hostedSubscription.plans.isEmpty {
        ProgressView()
          .controlSize(.small)
          .frame(maxWidth: .infinity, alignment: .center)
          .padding(.vertical, 20)
      } else if hostedSubscription.plans.isEmpty {
        Text("Detach Cloud plans are unavailable right now.")
          .font(.system(size: 13))
          .foregroundStyle(.secondary)
        Button("Try again") {
          Task { await hostedSubscription.refresh() }
        }
        .buttonStyle(OnboardingSecondaryButtonStyle())
      } else {
        ForEach(hostedSubscription.plans) { plan in
          hostedPlanRow(plan)
        }
      }

      if hostedCheckoutStarted {
        Text("Checkout opened in your browser. Return here when you are done and Detach will confirm your Cloud access.")
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.top, 4)
      }

      if let error = hostedSubscription.errorMessage {
        Text(error)
          .font(.system(size: 12))
          .foregroundStyle(.red)
      }
    }
  }

  private func hostedPlanRow(_ plan: HostedSubscriptionPlan) -> some View {
    Button {
      hostedCheckoutStarted = true
      hostedCheckoutPlanID = plan.id
      Task {
        await hostedSubscription.startCheckout(planId: plan.id)
      }
    } label: {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Text(plan.displayName)
            .font(.system(size: 14, weight: .semibold))
          Text("Agent, Image & Video on Detach Cloud / month")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        Spacer()
        VStack(alignment: .trailing, spacing: 2) {
          Text("$\(plan.monthlyPriceCents / 100)/mo")
            .font(.system(size: 13, weight: .semibold))
          Text(hostedCheckoutPlanID == plan.id && hostedSubscription.isLoading ? "Opening…" : "Choose")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
        }
      }
      .padding(13)
      .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
      .overlay(RoundedRectangle(cornerRadius: 12).stroke(.primary.opacity(0.1)))
    }
    .buttonStyle(.plain)
    .disabled(hostedSubscription.isLoading)
  }

  private var permissionsSetup: some View {
    OnboardingStepLayout(
      title: "A little access\ngoes a long way.",
      subtitle: "Enable these when you want Detach to read selected context or inspect your screen. You can change them later in System Settings."
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
      title: "Choose your\nagent",
      subtitle: "Use an AI tool already connected to this Mac. You can add more agents later in Settings."
    ) {
      VStack(alignment: .leading, spacing: 10) {
        ForEach(LocalAgentDetector.Agent.allCases) { agent in
          agentRow(agent)
        }
        if detectedAgents.isEmpty {
          Text("No existing agents were found. You can connect one later, or go back and choose Detach Cloud.")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 3)
        }
        Button("Check again") { refreshLocalSetup() }
          .font(.system(size: 12, weight: .medium))
          .buttonStyle(.plain)
          .foregroundStyle(.secondary)
          .padding(.top, 4)
      }
    }
  }

  private func agentRow(_ agent: LocalAgentDetector.Agent) -> some View {
    let isInstalled = detectedAgents.contains(agent)
    let isSelected = isInstalled && selectedAgent == agent.id
    return Button {
      guard isInstalled else { return }
      selectedAgent = agent.id
    } label: {
      HStack(spacing: 13) {
        Image(systemName: agent.symbol)
          .font(.system(size: 17, weight: .semibold))
          .frame(width: 34, height: 34)
          .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        VStack(alignment: .leading, spacing: 2) {
          Text(agent.name).font(.system(size: 14, weight: .semibold))
          Text(agent.subtitle(isInstalled: isInstalled))
            .font(.system(size: 12)).foregroundStyle(.secondary)
        }
        Spacer()
        Image(systemName: isInstalled ? "checkmark.circle.fill" : "circle.dashed")
          .foregroundStyle(isInstalled ? Color.primary : Color.secondary)
      }
      .padding(13)
      .background(Color.primary.opacity(isSelected ? 0.09 : 0.035), in: RoundedRectangle(cornerRadius: 14))
      .overlay(RoundedRectangle(cornerRadius: 14).stroke(isSelected ? Color.primary.opacity(0.45) : .clear))
    }
    .buttonStyle(.plain)
  }

  private var hotkeySetup: some View {
    OnboardingStepLayout(
      title: "Your Agent, one\nkeystroke away.",
      subtitle: "Press this anywhere to start an Agent task. You can change every shortcut later in Settings."
    ) {
      VStack(alignment: .leading, spacing: 16) {
        Text("Launch Detach")
          .font(.system(size: 13, weight: .semibold))
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text("Agent mode") .font(.system(size: 14, weight: .semibold))
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
      subtitle: completeSubtitle
    ) {
      VStack(spacing: 20) {
        ZStack {
          Circle().fill(.black).frame(width: 64, height: 64)
          Image(systemName: "checkmark")
            .font(.system(size: 25, weight: .bold))
            .foregroundStyle(.white)
        }
        HStack(spacing: 7) {
          featureChip("Agent mode", "text.bubble")
          featureChip("Image mode", "photo")
          featureChip("Video mode", "video")
        }
        Text("Press your shortcut to open Agent mode. Choose Image or Video whenever Detach Cloud is active.")
          .font(.system(size: 13))
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: 460)
      }
    }
  }

  private var completeSubtitle: String {
    if selectedSource == .hosted {
      return "Start from the menu bar or press \(hotkey.displayString). Agent, Image, and Video are ready."
    }
    return "Start from the menu bar or press \(hotkey.displayString). Connect Detach Cloud later for Image and Video."
  }

  private func featureChip(_ title: String, _ icon: String) -> some View {
    Label(title, systemImage: icon)
      .font(.system(size: 12, weight: .semibold))
      .padding(.horizontal, 12).padding(.vertical, 9)
      .background(.primary.opacity(0.06), in: Capsule())
  }

  private var navigation: some View {
    ZStack(alignment: .trailing) {
      if progressPosition != nil {
        stepProgress
      }

      if step == .complete {
        Button("Start using Detach", action: onComplete)
          .buttonStyle(OnboardingPrimaryButtonStyle())
      } else if canShowContinueButton {
        Button("Continue") { goForward() }
          .buttonStyle(OnboardingPrimaryButtonStyle())
          .disabled(!canContinue)
          .opacity(canContinue ? 1 : 0.5)
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

  private var canShowContinueButton: Bool {
    switch step {
    case .welcome, .complete: false
    case .hosted: hostedSubscription.canUseHostedAI
    default: true
    }
  }

  private var canContinue: Bool {
    switch step {
    case .source: selectedSource != nil
    case .hosted: hostedSubscription.canUseHostedAI
    case .welcome, .agents, .permissions, .hotkey, .complete: true
    }
  }

  private func goForward() {
    guard canContinue else { return }

    switch step {
    case .welcome:
      transition(to: .source)
    case .source:
      switch selectedSource ?? .later {
      case .existing:
        prepareLocalSelection()
        transition(to: .agents)
      case .hosted:
        transition(to: .hosted)
      case .later:
        transition(to: .permissions)
      }
    case .agents:
      if let selected = detectedAgents.first(where: { $0.id == selectedAgent }) {
        DetachSettings.selectedAgent = selected.id
      }
      transition(to: .permissions)
    case .hosted:
      DetachSettings.selectedAgent = "hosted"
      transition(to: .permissions)
    case .permissions:
      transition(to: .hotkey)
    case .hotkey:
      ShortcutSettings.floatingChat = hotkey
      transition(to: .complete)
    case .complete:
      onComplete()
    }
  }

  private func goBack() {
    switch step {
    case .source:
      transition(to: .welcome)
    case .agents, .hosted:
      transition(to: .source)
    case .permissions:
      switch selectedSource ?? .later {
      case .existing: transition(to: .agents)
      case .hosted: transition(to: .hosted)
      case .later: transition(to: .source)
      }
    case .hotkey:
      transition(to: .permissions)
    case .welcome, .complete:
      break
    }
  }

  private func transition(to nextStep: Step) {
    withAnimation(.easeInOut(duration: 0.2)) {
      step = nextStep
    }
  }

  private func refreshLocalSetup() {
    detectedAgents = LocalAgentDetector.detect()
    if selectedSource == nil {
      selectedSource = detectedAgents.isEmpty ? .hosted : .existing
    }
    if selectedSource == .existing {
      prepareLocalSelection()
    }
  }

  private func prepareLocalSelection() {
    guard !detectedAgents.isEmpty else { return }
    guard !detectedAgents.contains(where: { $0.id == selectedAgent }) else { return }
    if let firstInstalled = LocalAgentDetector.Agent.allCases.first(where: { detectedAgents.contains($0) }) {
      selectedAgent = firstInstalled.id
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
    case codex, claude, grok, fx, opencode

    var id: String { rawValue }

    var name: String {
      switch self {
      case .codex: "Codex"
      case .claude: "Claude"
      case .grok: "Grok"
      case .fx: "fx"
      case .opencode: "OpenCode"
      }
    }

    var symbol: String {
      switch self {
      case .codex: "chevron.left.forwardslash.chevron.right"
      case .claude: "brain.head.profile"
      case .grok: "bolt.fill"
      case .fx: "bolt.horizontal.circle"
      case .opencode: "shippingbox"
      }
    }

    var executable: String { rawValue }

    func subtitle(isInstalled: Bool) -> String {
      if isInstalled {
        switch self {
        case .codex: return "Uses your Codex account"
        case .claude: return "Uses your Claude Code account"
        case .grok: return "Uses your Grok account"
        case .fx: return "Uses your fx and Vercel AI Gateway account"
        case .opencode: return "Uses your existing OpenCode configuration"
        }
      }
      switch self {
      case .fx: return "Install the fx CLI and run fx login"
      case .opencode: return "The bundled OpenCode harness is unavailable"
      default: return "Install the \(name) CLI to connect"
      }
    }
  }

  static func detect() -> Set<Agent> {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let pathDirectories = (ProcessInfo.processInfo.environment["PATH"] ?? "")
      .split(separator: ":")
      .map(String.init)
    let executableDirectories = pathDirectories + [
      "\(home)/.grok/bin",
      "\(home)/.local/bin",
      "\(home)/.bun/bin",
      "/Applications/ChatGPT.app/Contents/Resources",
      "/Applications/Codex.app/Contents/Resources",
      "/opt/homebrew/bin",
      "/usr/local/bin",
      "/usr/bin",
      "/bin",
    ]

    return Set(Agent.allCases.filter { agent in
      let foundOnPath = executableDirectories.contains {
        FileManager.default.isExecutableFile(
          atPath: URL(fileURLWithPath: $0).appendingPathComponent(agent.executable).path
        )
      }
      let bundledOpenCode = agent == .opencode && bundledOpenCodeExists
      return foundOnPath || bundledOpenCode
    })
  }

  private static var bundledOpenCodeExists: Bool {
    if let bundled = Bundle.main.url(forResource: "opencode", withExtension: nil),
      FileManager.default.isExecutableFile(atPath: bundled.path)
    {
      return true
    }

    let developmentPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent("app/lazzy/opencode")
    return FileManager.default.isExecutableFile(atPath: developmentPath.path)
  }
}
