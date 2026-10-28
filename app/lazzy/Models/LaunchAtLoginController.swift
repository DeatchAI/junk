import Combine
import Foundation
import ServiceManagement

enum LoginItemStatus { case enabled, disabled, requiresApproval, unavailable }

@MainActor protocol LoginItemService {
  var status: LoginItemStatus { get }
  func register() throws
  func unregister() throws
}

@MainActor private struct SystemLoginItemService: LoginItemService {
  var status: LoginItemStatus {
    switch SMAppService.mainApp.status {
    case .enabled: .enabled
    case .requiresApproval: .requiresApproval
    case .notRegistered: .disabled
    default: .unavailable
    }
  }
  func register() throws { try SMAppService.mainApp.register() }
  func unregister() throws { try SMAppService.mainApp.unregister() }
}

/// macOS owns the setting; a saved preference must never masquerade as registration.
@MainActor final class LaunchAtLoginController: ObservableObject {
  @Published private(set) var isEnabled = false
  @Published private(set) var needsApproval = false
  @Published private(set) var error: String?
  private let service: any LoginItemService

  init(service: (any LoginItemService)? = nil) {
    self.service = service ?? SystemLoginItemService()
    refresh()
  }

  func refresh() {
    let status = service.status
    isEnabled = status == .enabled || status == .requiresApproval
    needsApproval = status == .requiresApproval
  }

  func setEnabled(_ enabled: Bool) {
    error = nil
    do {
      if enabled { try service.register() }
      else { try service.unregister() }
    } catch {
      self.error = "Could not change launch at login. \(error.localizedDescription)"
    }
    refresh()
  }

  func openLoginItems() { SMAppService.openSystemSettingsLoginItems() }
}
