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
  // The floating panel is 520pt wide. Start close to its usable text width so
  // the first render does not lay out at 400pt and then visibly reflow once
  // AppKit reports the actual width.
  @State private var viewWidth: CGFloat = 468

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      ForEach(segments, id: \.id) { segment in
        switch segment {
        case .textGroup(let blocks):
          SelectableTextView(blocks: blocks, baseWidth: viewWidth, theme: theme)
            .fixedSize(horizontal: false, vertical: true)

        case .codeBlock(let code, let lang):
          CodeBlockView(code: code, language: lang)

        case .image(let url, _):
          DownloadableImageView(url: url)
            .padding(.vertical, 4)
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
      HStack(spacing: 8) {
        if let languageName {
          Text(languageName)
            .font(.appFont(size: 10.5, weight: .medium))
            .foregroundStyle(theme.secondaryTextColor.opacity(0.85))
        }

        Spacer(minLength: 0)

        Button(action: copyCode) {
          HStack(spacing: 4) {
            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
            if isCopied {
              Text("Copied")
            }
          }
          .font(.appFont(size: 10.5, weight: .medium))
          .foregroundStyle(theme.secondaryTextColor)
          .padding(.horizontal, isCopied ? 7 : 6)
          .padding(.vertical, 5)
          .background(
            theme.textColor.opacity(isHovering ? 0.07 : 0.035),
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
          )
        }
        .buttonStyle(.plain)
        .help(isCopied ? "Copied" : "Copy code")
        .accessibilityLabel(isCopied ? "Code copied" : "Copy code")
      }
      .padding(.leading, 13)
      .padding(.trailing, 8)
      .padding(.top, 8)
      .padding(.bottom, languageName == nil ? 0 : 2)

      ScrollView(.horizontal, showsIndicators: false) {
        Text(code)
          .font(.system(size: 12.5, weight: .regular, design: .monospaced))
          .foregroundStyle(theme.textColor.opacity(0.92))
          .lineSpacing(3)
          .textSelection(.enabled)
          .fixedSize(horizontal: true, vertical: true)
          .padding(.horizontal, 13)
          .padding(.top, languageName == nil ? 4 : 6)
          .padding(.bottom, 12)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(
      RoundedRectangle(cornerRadius: codeCornerRadius, style: .continuous)
        .fill(theme.textColor.opacity(0.035))
    )
    .clipShape(RoundedRectangle(cornerRadius: codeCornerRadius, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: codeCornerRadius, style: .continuous)
        .stroke(theme.textColor.opacity(0.09), lineWidth: 0.75)
    }
    .onHover { hovering in
      withAnimation(.easeOut(duration: 0.14)) {
        isHovering = hovering
      }
    }
  }

  private var languageName: String? {
    guard let language = language?.trimmingCharacters(in: .whitespacesAndNewlines),
      !language.isEmpty
    else {
      return nil
    }

    let aliases = [
      "bash": "Shell",
      "sh": "Shell",
      "shell": "Shell",
      "js": "JavaScript",
      "jsx": "JavaScript",
      "ts": "TypeScript",
      "tsx": "TypeScript",
      "py": "Python",
      "rb": "Ruby",
      "rs": "Rust",
      "swift": "Swift",
      "json": "JSON",
      "yaml": "YAML",
      "yml": "YAML",
      "html": "HTML",
      "css": "CSS",
      "sql": "SQL",
      "diff": "Diff",
    ]

    return aliases[language.lowercased()] ?? language.capitalized
  }

  private var codeCornerRadius: CGFloat {
    min(max(theme.borderRadius * 0.65, 7), 10)
  }

  private func copyCode() {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(code, forType: .string)
    isCopied = true

    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
      isCopied = false
    }
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
