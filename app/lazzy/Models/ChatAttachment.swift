import AppKit
import AVFoundation
import Foundation
import UniformTypeIdentifiers

/// Represents a pending file attachment in the chat UI
struct ChatAttachment: Identifiable, Equatable {
  let id = UUID()
  let thumbnail: NSImage  // For preview in UI
  let fileRequest: FileAttachmentRequest  // For sending to server
  let fileName: String

  var isMedia: Bool {
    fileRequest.mimeType.hasPrefix("image/") || fileRequest.mimeType.hasPrefix("video/")
  }

  static func == (lhs: ChatAttachment, rhs: ChatAttachment) -> Bool {
    lhs.id == rhs.id
  }
}

/// Helper to handle attachments of various types
enum AttachmentHelper {

  /// Create an attachment from an existing file URL
  static func createAttachment(from url: URL) -> ChatAttachment? {
    let mimeType = url.hasDirectoryPath ? "inode/directory" : getMimeType(for: url)

    let fileRequest = FileAttachmentRequest(
      path: url.path,
      mimeType: mimeType
    )

    // Generate thumbnail: image/PDF content or generic file icon
    let thumbnail = generateThumbnail(for: url)

    return ChatAttachment(
      thumbnail: thumbnail,
      fileRequest: fileRequest,
      fileName: url.lastPathComponent
    )
  }

  /// Save an NSImage (e.g. from clipboard) to a temp file and create a ChatAttachment
  static func createAttachment(from image: NSImage) -> ChatAttachment? {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("lazzy-attachments")
    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let timestamp = ISO8601DateFormatter().string(from: Date())
      .replacingOccurrences(of: ":", with: "-")
    let filename = "pasted-image-\(timestamp).png"
    let fileURL = tempDir.appendingPathComponent(filename)

    guard let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let pngData = bitmap.representation(using: .png, properties: [:])
    else {
      return nil
    }

    do {
      try pngData.write(to: fileURL)
    } catch {
      return nil
    }

    let fileRequest = FileAttachmentRequest(
      path: fileURL.path,
      mimeType: "image/png"
    )

    let thumbnail = createThumbnail(from: image, maxSize: 60)

    return ChatAttachment(
      thumbnail: thumbnail,
      fileRequest: fileRequest,
      fileName: filename
    )
  }

  /// Downloads a media URL that came from a browser drag and turns it into a
  /// normal local attachment. Browser image drags frequently expose a web URL
  /// instead of a file URL, so keeping the download here makes every caller
  /// use the same size/type/thumbnail rules.
  static func createAttachment(fromRemoteURL url: URL) async -> ChatAttachment? {
    guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http"
    else { return nil }

    var request = URLRequest(url: url)
    request.timeoutInterval = 30
    request.setValue("image/avif,image/webp,image/apng,image/*,video/*;q=0.8,*/*;q=0.1", forHTTPHeaderField: "Accept")

    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard data.count <= 100 * 1024 * 1024 else { return nil }
      if let httpResponse = response as? HTTPURLResponse,
        !(200..<300).contains(httpResponse.statusCode)
      {
        return nil
      }

      let responseMime = response.mimeType?.lowercased()
      let pathExtension = url.pathExtension.lowercased()
      let mimeType: String?
      if let responseMime {
        // If the server tells us this is HTML (for example a Pinterest page),
        // do not reinterpret it as an image just because the URL ends in .jpg.
        mimeType = mediaMimeType(responseMime)
      } else {
        mimeType = mediaMimeTypeForPathExtension(pathExtension)
      }

      // A Pinterest page URL returns HTML, not the image itself. Do not save
      // arbitrary pages into the attachment directory.
      guard let mimeType, mimeType.hasPrefix("image/") || mimeType.hasPrefix("video/") else {
        return nil
      }

      let ext = preferredExtension(for: mimeType, fallback: pathExtension)
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "lazzy-attachments",
        isDirectory: true
      )
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let fileURL = directory.appendingPathComponent("dropped-\(UUID().uuidString).\(ext)")
      try data.write(to: fileURL, options: .atomic)
      return createAttachment(from: fileURL)
    } catch {
      return nil
    }
  }

  /// Generate a preview thumbnail for a file
  private static func generateThumbnail(for url: URL) -> NSImage {
    let maxSize: CGFloat = 60

    // For images and PDFs, try to get a content preview
    if let image = NSImage(contentsOf: url) {
      return createThumbnail(from: image, maxSize: maxSize)
    }

    // A first-frame preview keeps dragged videos identifiable in the compact
    // pill bar; fall back to the system movie icon if the asset is unavailable.
    if getMimeType(for: url).hasPrefix("video/"),
      let image = videoThumbnail(for: url)
    {
      return createThumbnail(from: image, maxSize: maxSize)
    }

    // Fallback: Use the system icon for this file type
    return NSWorkspace.shared.icon(forFile: url.path)
  }

  private static func videoThumbnail(for url: URL) -> NSImage? {
    let asset = AVAsset(url: url)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = NSSize(width: 120, height: 120)
    guard let image = try? generator.copyCGImage(at: .zero, actualTime: nil) else { return nil }
    return NSImage(cgImage: image, size: .zero)
  }

  /// Create a scaled thumbnail from an image
  private static func createThumbnail(from image: NSImage, maxSize: CGFloat) -> NSImage {
    let originalSize = image.size
    let scale = min(
      maxSize / max(originalSize.width, 1), maxSize / max(originalSize.height, 1), 1.0)
    let newSize = NSSize(
      width: originalSize.width * scale,
      height: originalSize.height * scale
    )

    let thumbnail = NSImage(size: newSize)
    thumbnail.lockFocus()
    image.draw(
      in: NSRect(origin: .zero, size: newSize),
      from: NSRect(origin: .zero, size: originalSize),
      operation: .copy,
      fraction: 1.0
    )
    thumbnail.unlockFocus()

    return thumbnail
  }

  /// Get MIME type for file URL
  static func getMimeType(for url: URL) -> String {
    if let uti = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
      if let mime = uti.preferredMIMEType {
        return mime
      }
    }

    let ext = url.pathExtension.lowercased()
    let mimeTypes: [String: String] = [
      "png": "image/png",
      "jpg": "image/jpeg",
      "jpeg": "image/jpeg",
      "gif": "image/gif",
      "webp": "image/webp",
      "heic": "image/heic",
      "mp3": "audio/mpeg",
      "wav": "audio/wav",
      "m4a": "audio/mp4",
      "mp4": "video/mp4",
      "mov": "video/quicktime",
      "webm": "video/webm",
      "pdf": "application/pdf",
      "txt": "text/plain",
      "md": "text/markdown",
    ]
    return mimeTypes[ext] ?? "application/octet-stream"
  }

  private static func mediaMimeType(_ mimeType: String) -> String? {
    let normalized = mimeType.split(separator: ";", maxSplits: 1).first.map(String.init) ?? mimeType
    guard normalized.hasPrefix("image/") || normalized.hasPrefix("video/") else { return nil }
    return normalized
  }

  private static func mediaMimeTypeForPathExtension(_ ext: String) -> String? {
    guard !ext.isEmpty else { return nil }
    let type = UTType(filenameExtension: ext)
    guard let mime = type?.preferredMIMEType,
      mime.hasPrefix("image/") || mime.hasPrefix("video/")
    else { return nil }
    return mime
  }

  private static func preferredExtension(for mimeType: String, fallback: String) -> String {
    if let ext = UTType(mimeType: mimeType)?.preferredFilenameExtension, !ext.isEmpty {
      return ext
    }
    return fallback.isEmpty ? (mimeType.hasPrefix("video/") ? "mp4" : "png") : fallback
  }

  /// Check if clipboard contains an image or file paths
  @MainActor
  static func getAttachmentsFromClipboard() -> [ChatAttachment] {
    let pasteboard = NSPasteboard.general
    let fileObjects = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) ?? []
    let fileURLs = fileObjects.compactMap { object -> URL? in
      if let url = object as? URL {
        return url
      }
      if let url = object as? NSURL {
        return url as URL
      }
      return nil
    }.filter(\.isFileURL)

    let fileAttachments = fileURLs.compactMap(createAttachment(from:))
    if !fileAttachments.isEmpty {
      return fileAttachments
    }

    // NSImage handles the common TIFF/PNG pasteboard representations.
    if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
      !images.isEmpty
    {
      let attachments = images.compactMap(createAttachment(from:))
      if !attachments.isEmpty {
        return attachments
      }
    }

    // Some apps publish only a raw image UTI, which does not always bridge
    // through NSPasteboard's NSImage reader. Decode any image-conforming data
    // representation as a final fallback.
    guard let imageType = pasteboard.types?.first(where: {
      UTType($0.rawValue)?.conforms(to: .image) == true
    }), let imageData = pasteboard.data(forType: imageType),
      let image = NSImage(data: imageData),
      let attachment = createAttachment(from: image)
    else {
      return []
    }

    return [attachment]
  }
}
