import AppKit
import Foundation
import UniformTypeIdentifiers

/// Represents a pending file attachment in the chat UI
struct ChatAttachment: Identifiable, Equatable {
  let id = UUID()
  let thumbnail: NSImage  // For preview in UI
  let fileRequest: FileAttachmentRequest  // For sending to server
  let fileName: String

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

  /// Generate a preview thumbnail for a file
  private static func generateThumbnail(for url: URL) -> NSImage {
    let maxSize: CGFloat = 60

    // For images and PDFs, try to get a content preview
    if let image = NSImage(contentsOf: url) {
      return createThumbnail(from: image, maxSize: maxSize)
    }

    // Fallback: Use the system icon for this file type
    return NSWorkspace.shared.icon(forFile: url.path)
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
      "pdf": "application/pdf",
      "txt": "text/plain",
      "md": "text/markdown",
    ]
    return mimeTypes[ext] ?? "application/octet-stream"
  }

  /// Check if clipboard contains an image or file paths
  static func getAttachmentsFromClipboard() -> [ChatAttachment] {
    let pasteboard = NSPasteboard.general
    var attachments: [ChatAttachment] = []

    // 1. Try file URLs (Finder copy)
    if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
      for url in urls {
        if let attachment = createAttachment(from: url) {
          attachments.append(attachment)
        }
      }
      if !attachments.isEmpty { return attachments }
    }

    // 2. Try raw image (Screenshot capture etc)
    if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
      let image = images.first
    {
      if let attachment = createAttachment(from: image) {
        attachments.append(attachment)
      }
    }

    return attachments
  }
}
