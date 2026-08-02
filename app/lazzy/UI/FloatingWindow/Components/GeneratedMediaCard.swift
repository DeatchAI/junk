import AVKit
import AppKit
import SwiftUI

struct GeneratedMediaCard: View {
  let job: MediaJob

  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if job.assets.isEmpty {
        generationStatus
      } else {
        ForEach(job.assets) { asset in
          GeneratedMediaAssetView(asset: asset)
        }
      }

      HStack(spacing: 8) {
        Text(modelLabel)
          .font(.appFont(size: 10, weight: .medium))
          .foregroundColor(theme.secondaryTextColor)
        if let credits = job.actual?.detachCredits ?? job.quote?.detachCredits {
          Text("· \(credits) credits")
            .font(.appFont(size: 10))
            .foregroundColor(theme.secondaryTextColor)
        }
        Spacer()
        if let asset = job.assets.first, let url = URL(string: asset.url) {
          Button {
            copy(url)
          } label: {
            Image(systemName: "doc.on.doc")
          }
          .buttonStyle(.plain)
          .help("Copy media link")

          Button {
            save(asset, from: url)
          } label: {
            Image(systemName: "square.and.arrow.down")
          }
          .buttonStyle(.plain)
          .help("Save media")
        }
      }
      .foregroundColor(theme.secondaryTextColor)
    }
    .padding(10)
    .background(
      RoundedRectangle(cornerRadius: theme.borderRadius, style: .continuous)
        .fill(theme.textColor.opacity(0.045))
    )
    .overlay {
      RoundedRectangle(cornerRadius: theme.borderRadius, style: .continuous)
        .stroke(theme.textColor.opacity(0.09), lineWidth: 0.5)
    }
  }

  @ViewBuilder
  private var generationStatus: some View {
    HStack(spacing: 10) {
      if job.state == "failed" || job.state == "reconciliation_required" {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundColor(.red)
      } else {
        ProgressView(value: Double(job.progress), total: 100)
          .progressViewStyle(.circular)
          .controlSize(.small)
      }
      VStack(alignment: .leading, spacing: 3) {
        Text(statusTitle)
          .font(.appFont(size: 12, weight: .medium))
          .foregroundColor(theme.textColor)
        Text(job.error?.message ?? "\(job.progress)% complete")
          .font(.appFont(size: 10))
          .foregroundColor(theme.secondaryTextColor)
          .lineLimit(2)
      }
      Spacer()
    }
    .frame(minHeight: 52)
  }

  private var statusTitle: String {
    switch job.state {
    case "persisting": return "Saving generated media"
    case "failed", "reconciliation_required": return "Generation couldn’t finish"
    default: return "Generating \(job.kind)"
    }
  }

  private var modelLabel: String {
    job.model.replacingOccurrences(of: "-", with: " ").capitalized
  }

  private func copy(_ url: URL) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(url.absoluteString, forType: .string)
  }

  private func save(_ asset: GeneratedMediaAsset, from url: URL) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "Detach-\(asset.id).\(fileExtension(asset.mimeType))"
    guard panel.runModal() == .OK, let destination = panel.url else { return }
    Task {
      let (temporary, _) = try await URLSession.shared.download(from: url)
      try? FileManager.default.removeItem(at: destination)
      try FileManager.default.moveItem(at: temporary, to: destination)
    }
  }

  private func fileExtension(_ mimeType: String) -> String {
    switch mimeType {
    case "image/jpeg": return "jpg"
    case "image/webp": return "webp"
    case "video/quicktime": return "mov"
    case "video/webm": return "webm"
    case let value where value.hasPrefix("video/"): return "mp4"
    default: return "png"
    }
  }
}

private struct GeneratedMediaAssetView: View {
  let asset: GeneratedMediaAsset

  var body: some View {
    Group {
      if asset.kind == "video", let url = URL(string: asset.url) {
        VideoPlayer(player: AVPlayer(url: url))
          .frame(minHeight: 220)
      } else if let url = URL(string: asset.url) {
        AsyncImage(url: url) { phase in
          switch phase {
          case .success(let image):
            image
              .resizable()
              .scaledToFit()
          case .failure:
            ContentUnavailableView("Media unavailable", systemImage: "photo.badge.exclamationmark")
          default:
            ProgressView()
              .frame(maxWidth: .infinity, minHeight: 180)
          }
        }
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    .onDrag {
      guard let url = URL(string: asset.url) else { return NSItemProvider() }
      return NSItemProvider(object: url as NSURL)
    }
  }
}
