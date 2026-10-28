import AppKit
import SwiftUI

struct ChatTranscriptView: View {
  let parts: [MessagePart]

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      ForEach(ChatTranscript.segments(parts)) { segment in
        if segment.isActivity {
          TranscriptActivityGroup(segment: segment)
        } else {
          MarkdownMessageView(text: segment.parts.compactMap(\.text).joined(separator: "\n\n"))
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct TranscriptActivityGroup: View {
  let segment: ChatTranscript.Segment
  @State private var isExpanded = false
  @ObservedObject private var theme = ThemeManager.shared

  private var isActive: Bool { segment.parts.contains { ["started", "updated", "in_progress"].contains($0.status ?? "") } }
  private var summary: String { isActive ? "Working · \(segment.parts.count) activities" : segment.summary }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Button { isExpanded.toggle() } label: {
        HStack(spacing: 7) {
          Image(systemName: isActive ? "ellipsis" : "checkmark")
            .frame(width: 14)
          Text(summary).lineLimit(1)
          Image(systemName: isExpanded ? "chevron.up" : "chevron.down").font(.system(size: 9))
          Spacer(minLength: 0)
        }
        .font(.appFont(size: 12))
        .foregroundStyle(theme.secondaryTextColor)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(summary)
      .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

      if isExpanded {
        LazyVStack(alignment: .leading, spacing: 10) {
          ForEach(Array(segment.parts.enumerated()), id: \.offset) { _, part in
            TranscriptActivityRow(part: part)
          }
        }
        .padding(.leading, 17)
        .overlay(alignment: .leading) { Rectangle().fill(theme.secondaryTextColor.opacity(0.2)).frame(width: 1) }
      }
    }
  }
}

private struct TranscriptActivityRow: View {
  let part: MessagePart
  @State private var isExpanded = false
  @ObservedObject private var theme = ThemeManager.shared

  private var detail: String {
    return [part.command, part.text, part.output].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n")
  }
  private var icon: String {
    if part.status == "failed" { return "exclamationmark.circle" }
    switch part.kind {
    case "command": return "terminal"
    case "file_change": return "doc.badge.ellipsis"
    case "read": return "doc.text.magnifyingglass"
    case "search": return "magnifyingglass"
    default: return "wrench.and.screwdriver"
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Button { isExpanded.toggle() } label: {
        HStack(spacing: 8) {
          Image(systemName: icon).frame(width: 14)
          Text(part.title ?? "Used tool").lineLimit(1)
          if part.status == "failed" { Text("Failed") }
          if !detail.isEmpty {
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down").font(.system(size: 9))
          }
          Spacer(minLength: 0)
        }
        .font(.appFont(size: 12))
        .foregroundStyle(theme.secondaryTextColor)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(detail.isEmpty)
      .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

      if isExpanded && !detail.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          ScrollView([.horizontal, .vertical]) {
            Text(detail)
              .font(.system(size: 11, design: .monospaced))
              .foregroundStyle(theme.textColor)
              .textSelection(.enabled)
              .fixedSize(horizontal: true, vertical: true)
              .padding(10)
          }
          .frame(height: 180)
          .background(theme.textColor.opacity(0.04))
          Button("Copy details") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(detail, forType: .string)
          }
          .buttonStyle(.plain)
          .font(.appFont(size: 11))
          .foregroundStyle(theme.secondaryTextColor)
        }
      }
    }
  }
}
