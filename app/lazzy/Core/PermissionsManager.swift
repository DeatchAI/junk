import Foundation
import AppKit
import Combine

/// Manages app permissions (Accessibility, Automation)
class PermissionsManager: ObservableObject {
    
    @Published private(set) var hasAccessibilityPermission = false
    @Published private(set) var hasAutomationPermission = false
    @Published private(set) var hasScreenCapturePermission = false
    private var lastLoggedAccessibilityPermission: Bool?
    private var screenCapturePollTimer: Timer?
    
    init() {
        checkPermissions()
    }
    
    // MARK: - Permission Checks
    
    func checkPermissions() {
        let isTrusted = AXIsProcessTrusted()
        hasAccessibilityPermission = isTrusted
        hasScreenCapturePermission = CGPreflightScreenCaptureAccess()
        // Automation permission is checked when we try to use AppleScript
        if lastLoggedAccessibilityPermission != isTrusted {
            print("🔐 Accessibility: \(isTrusted ? "✅" : "❌")")
            lastLoggedAccessibilityPermission = isTrusted
        }
    }
    
    var allPermissionsGranted: Bool {
        hasAccessibilityPermission && hasScreenCapturePermission
    }
    
    // MARK: - Request Permissions
    
    func requestAccessibilityPermission() {
        checkPermissions()
        guard !hasAccessibilityPermission else { return }

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        
        // Poll for permission changes
        startPermissionPolling()
    }

    func requestScreenCapturePermission() {
        checkPermissions()
        guard !hasScreenCapturePermission else { return }

        hasScreenCapturePermission = CGRequestScreenCaptureAccess()
        startScreenCapturePermissionPolling()
        if !hasScreenCapturePermission {
            openScreenCaptureSystemPreferences()
        }
    }
    
    func openSystemPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func openScreenCaptureSystemPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
    
    // MARK: - Polling
    
    private var pollTimer: Timer?
    
    private func startPermissionPolling() {
        pollTimer?.invalidate()
        var attempts = 0
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            attempts += 1
            self?.checkPermissions()
            if self?.hasAccessibilityPermission == true {
                self?.pollTimer?.invalidate()
                self?.pollTimer = nil
                print("✅ Accessibility permission granted!")
            } else if attempts >= 10 {
                self?.pollTimer?.invalidate()
                self?.pollTimer = nil
                print("⚠️ Accessibility still not available. If it looks enabled, toggle Detach off and on in System Settings.")
            }
        }
    }

    /// Screen-recording access changes outside the app in System Settings. Keep
    /// this value fresh while the user completes that handoff so menu-bar and
    /// onboarding UI do not continue to report a permission that is now granted.
    private func startScreenCapturePermissionPolling() {
        screenCapturePollTimer?.invalidate()
        var attempts = 0
        screenCapturePollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            attempts += 1
            self?.checkPermissions()
            if self?.hasScreenCapturePermission == true || attempts >= 30 {
                self?.screenCapturePollTimer?.invalidate()
                self?.screenCapturePollTimer = nil
            }
        }
    }
}
