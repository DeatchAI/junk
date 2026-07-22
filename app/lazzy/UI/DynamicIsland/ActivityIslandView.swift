import SwiftUI

/// A deliberately small, single-purpose status surface. It is meant to read like
/// a live headline in the cutout, not a second window for the agent conversation.
struct ActivityIslandView: View {
  @ObservedObject var store: DetachedRunStore
  @ObservedObject var controller: ActivityIslandWindowController
  let physicalNotchHeight: CGFloat
  let onToggle: () -> Void
  let onDismiss: () -> Void
  let onOpenConversation: (String) -> Void
  let onApprovalResponse: (String, Bool) -> Void

  private var approval: DetachedRunApproval? {
    store.presentationRuns.compactMap(\.approval).first
  }

  private var credential: DetachedRunCredential? {
    store.presentationRuns.compactMap(\.credential).first
  }

  var body: some View {
    VStack(spacing: 0) {
      if controller.isExpanded {
        // In the open state this preserves the physical cutout above the
        // expanded task panel. In the compact state, content belongs inside
        // that exact cutout instead of beneath it.
        Color.clear.frame(height: physicalNotchHeight)
        expandedTaskList
      } else {
        // The hardware cutout occupies the first lane. Keep live text in a
        // matching second lane so it is never covered by the camera housing.
        Color.clear.frame(height: physicalNotchHeight)
        compactHeadline
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(
      islandSurfaceShape
        .fill(islandBackground)
        // .shadow(color: .black.opacity(0.45), radius: 18, x: 0, y: 9)
        // .overlay(islandSurfaceShape.stroke(.white.opacity(0.1), lineWidth: 0.8))
    )
    .animation(.easeInOut(duration: 0.28), value: controller.isExpanded)
    .onHover { controller.setHovering($0) }
  }

  /// The compact treatment mirrors the original, readable activity-island
  /// headline while the expanded task switcher carries the richer detail.
  private var compactHeadline: some View {
    return Button(action: openPrimaryRun) {
      HStack(spacing: 10) {
        if let run = store.primaryRun, run.state == .completed {
          completionMark
        } else {
          DetachedMarkLoader(isLoading: store.primaryRun?.state == .running)
        }

        MarqueeHeadline(text: headline(for: store.primaryRun))

        Spacer(minLength: 12)

        Image(systemName: "arrow.up.right")
          .font(.system(size: 11, weight: .bold))
          .foregroundStyle(.white.opacity(0.52))
      }
      .padding(.horizontal, 28)
      .frame(height: physicalNotchHeight)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help("Hover to see active tasks")
  }

  private func credentialHeadline(_ credential: DetachedRunCredential) -> some View {
    HStack(spacing: 10) {
      Image(systemName: "touchid")
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(.white)
      VStack(alignment: .leading, spacing: 1) {
        Text("Touch ID required")
          .font(.appFont(size: 12, weight: .semibold))
          .foregroundStyle(.white)
        Text("Use \(credential.label) for \(credential.origin)")
          .font(.appFont(size: 10))
          .foregroundStyle(.white.opacity(0.56))
          .lineLimit(1)
      }
      Spacer(minLength: 4)
      Text("Credential hidden")
        .font(.appFont(size: 10, weight: .medium))
        .foregroundStyle(.green)
      dismissButton
    }
    .padding(.horizontal, 52)
    .frame(height: 52)
    .padding(.bottom, 12)
  }

  private func approvalHeadline(_ approval: DetachedRunApproval) -> some View {
    HStack(spacing: 10) {
      DetachedMarkLoader(isLoading: false)

      Text(approval.description.isEmpty ? approval.command : approval.description)
        .font(.appFont(size: 12, weight: .medium))
        .foregroundStyle(.white.opacity(0.9))
        .lineLimit(1)
        .truncationMode(.tail)

      Spacer(minLength: 2)

      dismissButton

      approvalButton(icon: "xmark", tint: .white.opacity(0.15), title: "Deny") {
        onApprovalResponse(approval.id, false)
      }
      approvalButton(icon: "checkmark", tint: .white, title: "Approve", foreground: .black) {
        onApprovalResponse(approval.id, true)
      }
    }
    .padding(.horizontal, 52)
    .frame(height: 52)
    .padding(.bottom, 12)
  }

  private func approvalButton(
    icon: String,
    tint: Color,
    title: String,
    foreground: Color = .white,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: icon)
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(foreground)
        .frame(width: 27, height: 27)
        .background(tint, in: Circle())
    }
    .buttonStyle(IslandIconButtonStyle())
    .help(title)
  }

  private func openPrimaryRun() {
    if store.visibleActiveRuns.count > 1 {
      onToggle()
      return
    }
    if let conversationId = store.primaryRun?.conversationId {
      onOpenConversation(conversationId)
    }
  }

  private var expandedTaskList: some View {
    VStack(spacing: 0) {
      if let approval {
        approvalInterrupt(approval)
      } else {
        HStack(spacing: 8) {
          Text("TASKS")
            .font(.appFont(size: 11, weight: .bold))
            .foregroundStyle(.white.opacity(0.52))
            .tracking(0.8)
          Spacer()
          dismissButton
        }
        .padding(.horizontal, 50)
        .frame(height: 20)

        ForEach(Array(store.presentationRuns.prefix(5).enumerated()), id: \.element.id) { index, run in
          taskRow(run)
          if index < min(store.presentationRuns.count, 5) - 1 {
            Divider().overlay(.white.opacity(0.08)).padding(.leading, 50)
          }
        }
      }
    }
  }

  /// This is intentionally distinct from ordinary task rows: it calls out
  /// exactly what is blocking progress and keeps the decision controls close.
  private func approvalInterrupt(_ approval: DetachedRunApproval) -> some View {
    HStack(spacing: 10) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(.orange)

      VStack(alignment: .leading, spacing: 2) {
        Text("Approval required")
          .font(.appFont(size: 12, weight: .semibold))
          .foregroundStyle(.white)
        Text(approval.description.isEmpty ? approval.command : approval.description)
          .font(.appFont(size: 10, weight: .regular))
          .foregroundStyle(.white.opacity(0.62))
          .lineLimit(1)
      }

      Spacer(minLength: 4)

      approvalButton(icon: "xmark", tint: .white.opacity(0.15), title: "Deny") {
        onApprovalResponse(approval.id, false)
      }
      approvalButton(icon: "checkmark", tint: .white, title: "Approve", foreground: .black) {
        onApprovalResponse(approval.id, true)
      }
    }
    .padding(.horizontal, 50)
    .frame(height: 70)
  }

  private func taskRow(_ run: DetachedAgentRun) -> some View {
    HStack(alignment: .center, spacing: 12) {
      Button {
        if let conversationId = run.conversationId {
          onOpenConversation(conversationId)
        }
      } label: {
        VStack(alignment: .leading, spacing: 5) {
          Text(run.taskTitle)
            .font(.appFont(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
          Text(run.currentActivity)
            .font(.appFont(size: 12, weight: .regular))
            .foregroundStyle(.white.opacity(0.56))
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(run.conversationId == nil)

      taskStateIcon(for: run)

      if let approval = run.approval {
        approvalButton(icon: "xmark", tint: .white.opacity(0.15), title: "Deny") {
          onApprovalResponse(approval.id, false)
        }
        approvalButton(icon: "checkmark", tint: .white, title: "Approve", foreground: .black) {
          onApprovalResponse(approval.id, true)
        }
      }
    }
    .padding(.horizontal, 50)
    .frame(height: 64)
  }

  private func taskStateIcon(for run: DetachedAgentRun) -> some View {
    Group {
      switch run.state {
      case .running:
        DetachedMarkLoader(isLoading: true, size: 24)
      case .awaitingApproval:
        Image(systemName: "questionmark.circle.fill")
          .foregroundStyle(.orange)
      case .awaitingCredential:
        Image(systemName: "lock.fill")
          .foregroundStyle(.green)
      case .completed:
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(.green)
      case .failed:
        Image(systemName: "xmark.circle.fill")
          .foregroundStyle(.red)
      }
    }
    .font(.system(size: 13, weight: .semibold))
    .frame(width: 24, height: 24)
  }

  private func headline(for run: DetachedAgentRun?) -> String {
    guard let run else { return "" }
    if run.state == .completed {
      return "\(run.displayTitle) — Completed"
    }
    return "\(run.displayTitle) — \(run.status)"
  }

  private var completionMark: some View {
    Image(systemName: "checkmark")
      .font(.system(size: 11, weight: .bold))
      .foregroundStyle(.black)
      .frame(width: 28, height: 28)
      .background(Color.green, in: Circle())
      .shadow(color: .green.opacity(0.35), radius: 5)
      .accessibilityHidden(true)
  }

  private var dismissButton: some View {
    Button(action: onDismiss) {
      Image(systemName: "xmark")
        .font(.system(size: 9, weight: .bold))
        .foregroundStyle(.white.opacity(0.52))
        .frame(width: 24, height: 24)
        .background(.white.opacity(0.08), in: Circle())
    }
    .buttonStyle(IslandIconButtonStyle())
    .help("Dismiss task island")
  }

  private var islandSurfaceShape: NotchIslandShape {
    NotchIslandShape(topRadius: 30, bottomRadius: 25)
  }

  private var islandBackground: LinearGradient {
    LinearGradient(colors: [.black.opacity(0.985), .black], startPoint: .top, endPoint: .bottom)
  }
}

/// A continuous ticker for tool and status text. Long messages move at a calm,
/// readable speed instead of being line-clamped and faded by the island edges.
private struct MarqueeHeadline: View {
  let text: String
  @State private var startedAt = Date.now

  private let gap: CGFloat = 42
  private let speed: CGFloat = 28

  var body: some View {
    GeometryReader { proxy in
      let textWidth = measuredWidth
      let shouldScroll = textWidth > proxy.size.width
      let distance = textWidth + gap

      TimelineView(.animation) { timeline in
        let elapsed = timeline.date.timeIntervalSince(startedAt)
        let offset = shouldScroll
          ? -CGFloat(elapsed * Double(speed)).truncatingRemainder(dividingBy: distance)
          : 0

        HStack(spacing: gap) {
          label
          if shouldScroll { label }
        }
        .fixedSize(horizontal: true, vertical: false)
        .offset(x: offset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 20, maxHeight: 20, alignment: .leading)
    .clipped()
    .onChange(of: text) { _, _ in
      startedAt = .now
    }
    .accessibilityLabel(text)
  }

  private var label: some View {
    Text(text)
      .font(.appFont(size: 12.5, weight: .semibold))
      .foregroundStyle(.white.opacity(0.9))
      .lineLimit(1)
  }

  private var measuredWidth: CGFloat {
    let attributes: [NSAttributedString.Key: Any] = [.font: AppFont.nsFont(size: 12.5)]
    return ceil((text as NSString).size(withAttributes: attributes).width)
  }
}

private struct DetachedMarkLoader: View {
  let isLoading: Bool
  var size: CGFloat = 28
  @State private var isAnimating = false

  var body: some View {
    ZStack {
      markPanel("DetachedMarkLeft", horizontalOffset: isLoading && isAnimating ? -(size * 0.09) : 0)
      markPanel("DetachedMarkRight", horizontalOffset: isLoading && isAnimating ? (size * 0.09) : 0)
    }
      .frame(width: size, height: size)
      .background(.black, in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
      .shadow(color: .white.opacity(isLoading ? 0.12 : 0), radius: size * 0.14)
      .onAppear {
        guard isLoading else { return }
        withAnimation(.easeInOut(duration: 0.82).repeatForever(autoreverses: true)) {
          isAnimating = true
        }
      }
      .onChange(of: isLoading) { _, loading in
        if loading {
          withAnimation(.easeInOut(duration: 0.82).repeatForever(autoreverses: true)) {
            isAnimating = true
          }
        } else {
          isAnimating = false
        }
      }
      .accessibilityHidden(true)
  }

  private func markPanel(_ assetName: String, horizontalOffset: CGFloat) -> some View {
    Image(assetName)
      .resizable()
      .scaledToFit()
      .frame(width: size, height: size)
      .offset(x: horizontalOffset)
      .opacity(isLoading && isAnimating ? 0.78 : 1)
  }
}

private struct IslandIconButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.9 : 1)
      .opacity(configuration.isPressed ? 0.7 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }
}

private struct NotchIslandShape: Shape {
  var topRadius: CGFloat
  var bottomRadius: CGFloat

  func path(in rect: CGRect) -> Path {
    let top = min(topRadius, rect.width / 4, rect.height / 4)
    let bottom = min(bottomRadius, rect.width / 4, rect.height / 2)
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.minY))
    path.addQuadCurve(
      to: CGPoint(x: rect.minX + top, y: rect.minY + top),
      control: CGPoint(x: rect.minX + top, y: rect.minY)
    )
    path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
    path.addQuadCurve(
      to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY),
      control: CGPoint(x: rect.minX + top, y: rect.maxY)
    )
    path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
    path.addQuadCurve(
      to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom),
      control: CGPoint(x: rect.maxX - top, y: rect.maxY)
    )
    path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
    path.addQuadCurve(
      to: CGPoint(x: rect.maxX, y: rect.minY),
      control: CGPoint(x: rect.maxX - top, y: rect.minY)
    )
    path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
    path.closeSubpath()
    return path
  }
}
