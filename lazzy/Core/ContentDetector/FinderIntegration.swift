import Foundation
import AppKit
import Combine

/// Detects selected files in Finder using AppleScript
class FinderIntegration: ObservableObject {
    
    @Published private(set) var selectedFiles: [URL] = []
    @Published private(set) var hasAutomationPermission = true
    
    // MARK: - File Detection
    
    /// Get currently selected files in Finder
    func getSelectedFinderFiles() -> [URL] {
        // Skip if we know we don't have permission
        guard hasAutomationPermission else {
            return []
        }
        
        let script = """
        tell application "Finder"
            set selectedItems to selection
            set fileList to {}
            repeat with anItem in selectedItems
                set end of fileList to POSIX path of (anItem as alias)
            end repeat
            return fileList
        end tell
        """
        
        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else {
            return []
        }
        
        let result = appleScript.executeAndReturnError(&error)
        
        if let error = error {
            let errorNumber = error["NSAppleScriptErrorNumber"] as? Int ?? 0
            
            // -1743 = Not authorized
            if errorNumber == -1743 {
                hasAutomationPermission = false
                print("⚠️ Finder automation not authorized. Enable in System Preferences > Security > Privacy > Automation")
            }
            // Only log other errors once
            return []
        }
        
        // Parse result
        var files: [URL] = []
        
        if let listDescriptor = result.coerce(toDescriptorType: typeAEList) {
            for i in 1...listDescriptor.numberOfItems {
                if let itemDescriptor = listDescriptor.atIndex(i),
                   let path = itemDescriptor.stringValue {
                    let url = URL(fileURLWithPath: path)
                    files.append(url)
                }
            }
        }
        
        selectedFiles = files
        return files
    }
    
    /// Check if Finder is the frontmost application
    func isFinderFrontmost() -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return false
        }
        return frontApp.bundleIdentifier == "com.apple.finder"
    }
    
    /// Get MIME type for a file
    func getMimeType(for url: URL) -> String {
        let pathExtension = url.pathExtension.lowercased()
        
        let mimeTypes: [String: String] = [
            "pdf": "application/pdf",
            "png": "image/png",
            "jpg": "image/jpeg",
            "jpeg": "image/jpeg",
            "gif": "image/gif",
            "webp": "image/webp",
            "txt": "text/plain",
            "md": "text/markdown",
            "swift": "text/x-swift",
            "ts": "text/typescript",
            "js": "text/javascript",
            "html": "text/html",
            "css": "text/css",
            "json": "application/json",
        ]
        
        return mimeTypes[pathExtension] ?? "application/octet-stream"
    }
}
