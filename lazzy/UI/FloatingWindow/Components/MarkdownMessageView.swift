import AppKit
import SwiftUI
import UniformTypeIdentifiers

private struct WidthPreferenceKey: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}

struct MarkdownMessageView: View {
  let text: String
  @ObservedObject private var theme = ThemeManager.shared

  @State private var segments: [ContentSegment] = []
  @State private var viewWidth: CGFloat = 400  // Default fallback

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      ForEach(segments, id: \.id) { segment in
        switch segment {
        case .textGroup(let blocks):
          SelectableTextView(blocks: blocks, baseWidth: viewWidth, theme: theme)
            .fixedSize(horizontal: false, vertical: true)

        case .codeBlock(let code, let lang):
          CodeBlockView(code: code, language: lang)

        case .image(let url, _):
          DownloadableImageView(url: url)
            .padding(.vertical, 8)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      GeometryReader { geo in
        Color.clear
          .preference(key: WidthPreferenceKey.self, value: geo.size.width)
      }
    )
    .onPreferenceChange(WidthPreferenceKey.self) { width in
      guard width > 0, abs(width - viewWidth) >= 0.5 else { return }
      DispatchQueue.main.async {
        viewWidth = width
      }
    }
    .onAppear {
      segments = MarkdownParser.shared.parse(text)
    }
    .onChange(of: text) { _, newValue in
      segments = MarkdownParser.shared.parse(newValue)
    }
  }
}

struct CodeBlockView: View {
  let code: String
  let language: String?
  @ObservedObject private var theme = ThemeManager.shared
  @State private var isHovering = false
  @State private var isCopied = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Header with language and copy button
      HStack {
        if let lang = language {
          Text(lang.uppercased())
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(theme.secondaryTextColor)
        }
        Spacer()
        Button(action: {
          let pasteboard = NSPasteboard.general
          pasteboard.clearContents()
          pasteboard.setString(code, forType: .string)
          isCopied = true

          DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isCopied = false
          }
        }) {
          HStack(spacing: 4) {
            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
            Text(isCopied ? "Copied" : "Copy")
          }
          .font(.system(size: 10))
          .foregroundStyle(theme.secondaryTextColor)
        }
        .buttonStyle(.plain)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(Color.black.opacity(0.2))

      // Code Content
      Text(code)
        .font(.system(size: 13, weight: .regular, design: .monospaced))
        .foregroundStyle(theme.textColor)
        .padding(12)
        .textSelection(.enabled)  // Allow selection within code block
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(Color.black.opacity(0.1))
    .cornerRadius(8)
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .stroke(Color.white.opacity(0.1), lineWidth: 1)
    )
  }
}

// MARK: - Image Views

struct DownloadableImageView: View {
  let url: URL?
  @State private var isHovering = false
  @State private var image: NSImage?
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    ZStack(alignment: .bottomTrailing) {
      if let img = image {
        // Use AppKit-based view to properly handle drag events
        DraggableImageView(image: img, url: url)
          .aspectRatio(contentMode: .fit)
          .cornerRadius(theme.borderRadius)
      } else {
        VStack {
          ProgressView()
            .controlSize(.small)
          Text("Loading image...")
            .font(.appFont(size: 10))
            .foregroundColor(theme.secondaryTextColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(Color.black.opacity(0.1))
        .cornerRadius(theme.borderRadius)
      }

      if isHovering && image != nil {
        HStack(spacing: 8) {
          Button(action: downloadImage) {
            HStack(spacing: 4) {
              Image(systemName: "square.and.arrow.down")
              Text("Save")
            }
            .font(.appFont(size: 10, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
            .foregroundColor(.white)
          }
          .buttonStyle(.plain)
          .help("Download Image")
        }
        .padding(8)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
      }
    }
    .onHover { hovering in
      withAnimation(.easeInOut(duration: 0.2)) {
        isHovering = hovering
      }
    }
    .onAppear {
      loadImage()
    }
  }

  private func loadImage() {
    guard let url = url else { return }
    URLSession.shared.dataTask(with: url) { data, _, _ in
      if let data = data, let img = NSImage(data: data) {
        DispatchQueue.main.async {
          self.image = img
        }
      }
    }.resume()
  }

  private func downloadImage() {
    guard let img = image else { return }
    let savePanel = NSSavePanel()
    savePanel.allowedContentTypes = [.png]
    savePanel.nameFieldStringValue = url?.lastPathComponent ?? "image.png"
    savePanel.message = "Choose where to save your generated image"

    savePanel.begin { response in
      if response == .OK, let targetURL = savePanel.url {
        if let tiffData = img.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:])
        {
          try? pngData.write(to: targetURL)
        }
      }
    }
  }
}

/// AppKit-based draggable image view that prevents window movement
struct DraggableImageView: NSViewRepresentable {
  let image: NSImage
  let url: URL?

  func makeNSView(context: Context) -> DraggableNSImageView {
    let view = DraggableNSImageView()
    view.image = image
    view.imageURL = url
    return view
  }

  func updateNSView(_ nsView: DraggableNSImageView, context: Context) {
    nsView.image = image
    nsView.imageURL = url
  }
}

class DraggableNSImageView: NSView {
  var image: NSImage? {
    didSet {
      needsDisplay = true
      prepareFileForDrag()
    }
  }
  var imageURL: URL?
  private var cachedTempFile: URL?

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    image?.draw(in: bounds)
  }

  private func prepareFileForDrag() {
    guard let image = image else { return }
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let tempDir = FileManager.default.temporaryDirectory
      let fileName = self?.imageURL?.lastPathComponent ?? "generated_image.png"
      let tempFile = tempDir.appendingPathComponent(fileName)

      if let tiffData = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiffData),
        let pngData = bitmap.representation(using: .png, properties: [:])
      {
        try? pngData.write(to: tempFile)
        DispatchQueue.main.async {
          self?.cachedTempFile = tempFile
        }
      }
    }
  }

  override var mouseDownCanMoveWindow: Bool { false }

  override func mouseDown(with event: NSEvent) {
    // Start a drag session - do NOT call super to prevent window movement
    guard let image = image else { return }

    // Use cached file or create one synchronously as fallback
    let tempFile: URL
    if let cached = cachedTempFile {
      tempFile = cached
    } else {
      let tempDir = FileManager.default.temporaryDirectory
      let fileName = imageURL?.lastPathComponent ?? "generated_image.png"
      tempFile = tempDir.appendingPathComponent(fileName)

      if let tiffData = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiffData),
        let pngData = bitmap.representation(using: .png, properties: [:])
      {
        try? pngData.write(to: tempFile)
      }
    }

    let draggingItem = NSDraggingItem(pasteboardWriter: tempFile as NSURL)

    // Use a smaller drag image for smoothness
    let dragImage = image.resized(to: NSSize(width: 100, height: 100))
    draggingItem.setDraggingFrame(NSRect(x: 0, y: 0, width: 100, height: 100), contents: dragImage)

    beginDraggingSession(with: [draggingItem], event: event, source: self)
  }
}

extension NSImage {
  func resized(to newSize: NSSize) -> NSImage {
    let newImage = NSImage(size: newSize)
    newImage.lockFocus()
    draw(
      in: NSRect(origin: .zero, size: newSize),
      from: NSRect(origin: .zero, size: size),
      operation: .copy,
      fraction: 1.0)
    newImage.unlockFocus()
    return newImage
  }
}

extension DraggableNSImageView: NSDraggingSource {
  func draggingSession(
    _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
  ) -> NSDragOperation {
    return .copy
  }
}
