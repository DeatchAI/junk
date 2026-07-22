import Foundation
import AppKit
import Combine

/// Unified content manager that coordinates detection of text and files
class ContentManager: ObservableObject {
    
    // MARK: - Sub-managers
    
    let selectionDetector = SelectionDetector()
    let finderIntegration = FinderIntegration()
    
    // MARK: - Published State
    
    @Published private(set) var detectedContent: DetectedContent?
    
    // MARK: - Content Detection
    
    /// Detect content from the current context (selected text or files)
    func detectContent() -> DetectedContent? {
        // Check if Finder is frontmost - get selected files
        if finderIntegration.isFinderFrontmost() {
            let files = finderIntegration.getSelectedFinderFiles()
            if !files.isEmpty {
                let attachments = files.map { url in
                    FileAttachmentRequest(
                        path: url.path,
                        mimeType: finderIntegration.getMimeType(for: url)
                    )
                }
                let content = DetectedContent(
                    type: .files,
                    text: nil,
                    files: attachments
                )
                detectedContent = content
                return content
            }
        }
        
        // Otherwise, try to get selected text
        if let text = selectionDetector.getSelectedText(), !text.isEmpty {
            let content = DetectedContent(
                type: .text,
                text: text,
                files: nil
            )
            detectedContent = content
            return content
        }
        
        // Fallback: try clipboard method
        if let text = selectionDetector.getSelectedTextViaClipboard(), !text.isEmpty {
            let content = DetectedContent(
                type: .text,
                text: text,
                files: nil
            )
            detectedContent = content
            return content
        }
        
        detectedContent = nil
        return nil
    }
    
    /// Clear detected content
    func clearContent() {
        detectedContent = nil
    }
}

// MARK: - Models

struct DetectedContent: Equatable {
    enum ContentType: Equatable {
        case text
        case files
        case mixed
        case screenshot
    }
    
    let type: ContentType
    let text: String?
    let files: [FileAttachmentRequest]?
    
    var description: String {
        switch type {
        case .text:
            let preview = text?.prefix(50) ?? ""
            return "Text: \"\(preview)...\""
        case .files:
            let count = files?.count ?? 0
            return "\(count) file(s) selected"
        case .mixed:
            return "Text + Files selected"
        case .screenshot:
            return "Screenshot captured"
        }
    }
}
