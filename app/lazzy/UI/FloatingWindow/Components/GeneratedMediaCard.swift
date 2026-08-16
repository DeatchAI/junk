import AVKit
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct GeneratedMediaCard: View {
  let job: MediaJob

  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    if job.assets.isEmpty {
      generationStatus
    } else {
      generatedMedia
    }
  }

  @ViewBuilder
  private var generationStatus: some View {
    let title = isFailed ? "Generation couldn’t finish" : generationTitle

    HStack(spacing: 9) {
      Image(systemName: isFailed ? "exclamationmark.triangle.fill" : generationIcon)
        .font(.appFont(size: 13, weight: .medium))
        .foregroundColor(isFailed ? .red : theme.accentColor)
        .frame(width: 16)

      generationLabel(title)

      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
    .padding(.horizontal, 6)
    .padding(.vertical, 4)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
  }

  @ViewBuilder
  private var generatedMedia: some View {
    VStack(alignment: .leading, spacing: 10) {
      ForEach(job.assets) { asset in
        GeneratedMediaAssetView(asset: asset)
      }

      HStack(spacing: 8) {
        Spacer(minLength: 0)
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

  private var generationTitle: String {
    job.kind.lowercased() == "video" ? "Generating your video" : "Generating your image"
  }

  private var generationIcon: String {
    job.kind.lowercased() == "video" ? "video" : "photo"
  }

  @ViewBuilder
  private func generationLabel(_ title: String) -> some View {
    let label = Text(title)
      .font(.appFont(size: 12, weight: .medium))
      .foregroundColor(isFailed ? .red : theme.textColor.opacity(0.86))
      .lineLimit(1)

    if isFailed {
      label
    } else {
      label.shimmer()
    }
  }

  private var isFailed: Bool {
    job.state == "failed" || job.state == "reconciliation_required"
  }

  private func copy(_ url: URL) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(url.absoluteString, forType: .string)
  }

  private func save(_ asset: GeneratedMediaAsset, from url: URL) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "Detach-\(asset.id).\(fileExtension(asset.mimeType))"
    guard panel.runModal() == .OK, let destination = panel.url else { return }

    if url.isFileURL {
      try? FileManager.default.removeItem(at: destination)
      try? FileManager.default.copyItem(at: url, to: destination)
      return
    }

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
      if asset.kind == "image" {
        GeneratedMediaImageAssetView(asset: asset)
      } else if asset.kind == "video", let url = URL(string: asset.url) {
        GeneratedMediaVideoPlayer(url: url)
          .frame(maxWidth: .infinity, minHeight: 220, alignment: .center)
          .onDrag {
            guard let url = URL(string: asset.url) else { return NSItemProvider() }
            return mediaDragProvider(for: asset, url: url)
          }
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
  }
}

private struct GeneratedMediaImageAssetView: View {
  let asset: GeneratedMediaAsset
  @State private var image: NSImage?

  var body: some View {
    Group {
      if let image, let url = URL(string: asset.url) {
        // DraggableNSImageView overrides mouseDownCanMoveWindow and starts an
        // AppKit drag session, so the borderless panel never moves with the
        // generated image.
        DraggableImageView(image: image, url: url)
          .aspectRatio(contentMode: .fit)
          .frame(maxWidth: .infinity, alignment: .center)
      } else {
        ProgressView()
          .frame(maxWidth: .infinity, minHeight: 180)
      }
    }
    .onAppear(perform: loadImage)
  }

  private func loadImage() {
    guard let url = URL(string: asset.url) else { return }
    if url.isFileURL {
      image = NSImage(contentsOf: url)
      return
    }

    URLSession.shared.dataTask(with: url) { data, _, _ in
      guard let data, let loadedImage = NSImage(data: data) else { return }
      DispatchQueue.main.async {
        image = loadedImage
      }
    }.resume()
  }
}

private func mediaDragProvider(for asset: GeneratedMediaAsset, url: URL) -> NSItemProvider {
  let provider = NSItemProvider(object: url as NSURL)
  let typeIdentifier = UTType(mimeType: asset.mimeType)?.identifier
    ?? (asset.kind == "video" ? UTType.movie.identifier : UTType.image.identifier)

  provider.registerFileRepresentation(
    forTypeIdentifier: typeIdentifier,
    fileOptions: [],
    visibility: .all
  ) { completion in
    if url.isFileURL {
      completion(url, false, nil)
      return nil
    }

    let progress = Progress(totalUnitCount: 100)
    let task = URLSession.shared.downloadTask(with: url) { temporaryURL, response, error in
      guard let temporaryURL, error == nil else {
        completion(nil, false, error)
        return
      }
      if let httpResponse = response as? HTTPURLResponse,
        !(200..<300).contains(httpResponse.statusCode)
      {
        completion(
          nil,
          false,
          NSError(
            domain: NSURLErrorDomain,
            code: httpResponse.statusCode,
            userInfo: [NSLocalizedDescriptionKey: "Generated media download failed."]
          )
        )
        return
      }
      completion(temporaryURL, false, nil)
    }
    task.resume()
    return progress
  }
  return provider
}

/// SwiftUI's macOS `VideoPlayer` is backed by a private `_AVKit_SwiftUI`
/// subclass of `AVPlayerView`. On macOS 26.0 that class can abort while its
/// superclass metadata is initialized. Use AVKit's Objective-C view directly
/// so completed media never takes down the composer.
private struct GeneratedMediaVideoPlayer: NSViewRepresentable {
  let url: URL

  func makeCoordinator() -> Coordinator {
    Coordinator(url: url)
  }

  func makeNSView(context: Context) -> AVPlayerView {
    let playerView = NonMovableAVPlayerView()
    playerView.controlsStyle = .floating
    playerView.videoGravity = .resizeAspect
    playerView.player = context.coordinator.player
    return playerView
  }

  func updateNSView(_ playerView: AVPlayerView, context: Context) {
    context.coordinator.update(url: url)
    if playerView.player !== context.coordinator.player {
      playerView.player = context.coordinator.player
    }
  }

  static func dismantleNSView(_ playerView: AVPlayerView, coordinator: Coordinator) {
    coordinator.player.pause()
    playerView.player = nil
  }

  @MainActor
  final class Coordinator {
    private(set) var url: URL
    let player: AVPlayer

    init(url: URL) {
      self.url = url
      self.player = AVPlayer(url: url)
    }

    func update(url: URL) {
      guard url != self.url else { return }
      self.url = url
      player.pause()
      player.replaceCurrentItem(with: AVPlayerItem(url: url))
    }
  }
}

/// The panel remains movable from its background, but media surfaces must own
/// their mouse gesture so a drag exports the asset instead of moving the panel.
private final class NonMovableAVPlayerView: AVPlayerView {
  override var mouseDownCanMoveWindow: Bool { false }
}
