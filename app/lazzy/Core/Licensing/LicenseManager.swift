import AppKit
import Combine
import Foundation

@MainActor
final class LicenseManager: ObservableObject {
  enum Status: Equatable { case checking, locked, trial, licensed, offline }

  static let shared = LicenseManager()
  @Published private(set) var status: Status = .checking
  @Published private(set) var hasAccess = false
  @Published private(set) var isWorking = false
  @Published private(set) var message: String?
  var onAccessRequired: (() -> Void)?

  private var stored = LicenseStoredState()
  private var storageAvailable = true
  private var verifiedThisSession = false
  private var allowOfflineCache = false
  private var lastAttempt = Date.distantPast
  private var timer: Timer?
  private var observers = Set<AnyCancellable>()
  private let client = PolarLicenseClient()

  var canStartTrial: Bool { storageAvailable && stored.trialStartedAt == nil }
  var hasSavedLicense: Bool { stored.license != nil }
  var displayKey: String? { stored.license.map { "•••• " + String($0.key.suffix(6)) } }
  var trialEndsAt: Date? { stored.trialStartedAt?.addingTimeInterval(LicenseConfiguration.trialDuration) }
  var hasExpiredTrial: Bool { trialEndsAt.map { $0 <= effectiveNow } ?? false }
  var statusDescription: String {
    switch status {
    case .checking: return "Checking your license…"
    case .licensed: return "Detach is unlocked on this Mac."
    case .offline: return "Offline access is available for up to 3 days after your last license check."
    case .trial:
      guard let end = trialEndsAt else { return "Your trial is active." }
      return "Your trial ends " + end.formatted(date: .abbreviated, time: .shortened) + "."
    case .locked:
      return hasExpiredTrial ? "Your trial has ended. Unlock Detach to keep using your agents." : "Start your trial or unlock Detach with a license key."
    }
  }

  private var effectiveNow: Date { max(Date(), stored.lastObservedAt) }

  private init() {
    do { stored = try LicenseStore.load() ?? LicenseStoredState() }
    catch { storageAvailable = false; message = LicenseError.storage.localizedDescription }
    recomputeAccess()
    if stored.license != nil, storageAvailable, !hasAccess { status = .checking }
  }

  func beginMonitoring() {
    guard timer == nil else { return }
    timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
      Task { @MainActor in
        self?.recomputeAccess()
        await self?.refresh()
      }
    }
    for name in [NSApplication.didBecomeActiveNotification, NSNotification.Name("NSSystemClockDidChangeNotification")] {
      NotificationCenter.default.publisher(for: name)
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
          self?.recomputeAccess()
          Task { await self?.refresh() }
        }.store(in: &observers)
    }
    NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        self?.recomputeAccess()
        Task { await self?.refresh(force: true) }
      }.store(in: &observers)
    Task { await refresh(force: true) }
  }

  @discardableResult
  func requireAccess() -> Bool {
    recomputeAccess()
    if !hasAccess { onAccessRequired?() }
    return hasAccess
  }

  func startTrial() {
    guard canStartTrial, !isWorking else { return }
    guard Date().addingTimeInterval(300) >= stored.lastObservedAt else {
      message = "Set your Mac's date and time correctly to start your trial."
      return
    }
    var next = stored
    next.trialStartedAt = effectiveNow
    next.lastObservedAt = effectiveNow
    do { try persist(next); message = nil; recomputeAccess() }
    catch { failStorage() }
  }

  func activate(_ input: String) async {
    guard !isWorking, storageAvailable else { return }
    let key = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty, key.count <= 4096, !key.contains(where: { $0.isWhitespace }) else {
      message = "Enter the license key from your Polar purchase."
      return
    }
    isWorking = true
    message = nil
    defer { isWorking = false; recomputeAccess() }
    do {
      let previous = stored.license
      let license = try await client.unlock(key: key, previous: previous, installationID: stored.installationID)
      var next = stored
      next.license = license
      next.lastObservedAt = max(effectiveNow, license.validatedAt)
      do { try persist(next) }
      catch {
        if license.activationID != previous?.activationID { try? await client.deactivate(license) }
        throw LicenseError.storage
      }
      verifiedThisSession = true
      allowOfflineCache = false
      lastAttempt = Date()
    } catch {
      if let error = error as? LicenseError, case .storage = error {
        failStorage()
      } else if let error = error as? LicenseError, case .rejected = error,
        stored.license?.key == key {
        invalidateSavedLicense(error)
      } else {
        message = (error as? LicenseError)?.localizedDescription ?? LicenseError.unavailable.localizedDescription
      }
    }
  }

  func refresh(force: Bool = false) async {
    guard !isWorking else { return }
    if !storageAvailable {
      do {
        stored = try LicenseStore.load() ?? LicenseStoredState()
        storageAvailable = true
        message = nil
      } catch { failStorage(); return }
    }
    guard let license = stored.license else { recomputeAccess(); return }
    guard force || Date().timeIntervalSince(lastAttempt) >= 15 * 60 else { return }
    guard force || !verifiedThisSession
      || Date().timeIntervalSince(license.validatedAt) >= LicenseConfiguration.revalidationInterval else { return }
    isWorking = true
    lastAttempt = Date()
    defer { isWorking = false; recomputeAccess() }
    do {
      var next = stored
      next.license = try await client.validate(license, installationID: stored.installationID)
      next.lastObservedAt = effectiveNow
      try persist(next)
      verifiedThisSession = true
      allowOfflineCache = false
      message = nil
    } catch {
      verifiedThisSession = false
      if let error = error as? LicenseError, case .rejected = error {
        invalidateSavedLicense(error)
      } else if let error = error as? LicenseError, case .storage = error {
        failStorage()
      } else {
        allowOfflineCache = true
        message = LicenseError.unavailable.localizedDescription
      }
    }
  }

  func deactivate() async {
    guard !isWorking, let license = stored.license else { return }
    isWorking = true
    message = nil
    defer { isWorking = false; recomputeAccess() }
    do {
      try await client.deactivate(license)
      verifiedThisSession = false
      allowOfflineCache = false
      var next = stored
      next.license = nil
      do { try persist(next) } catch { failStorage(); return }
    } catch {
      message = (error as? LicenseError)?.localizedDescription ?? LicenseError.unavailable.localizedDescription
    }
  }

  func openCheckout() { NSWorkspace.shared.open(LicenseConfiguration.checkoutURL) }
  func openPortal() { NSWorkspace.shared.open(LicenseConfiguration.portalURL) }

  private func recomputeAccess() {
    guard storageAvailable else { status = .locked; hasAccess = false; return }
    guard Date().addingTimeInterval(300) >= stored.lastObservedAt else {
      status = .locked
      hasAccess = false
      message = "Set your Mac's date and time correctly to check your license or trial."
      return
    }
    let now = effectiveNow
    if let license = stored.license, license.matchesProduct, !license.invalidated,
      verifiedThisSession || allowOfflineCache,
      license.validatedAt <= now.addingTimeInterval(300),
      now.timeIntervalSince(license.validatedAt) < LicenseConfiguration.offlineGrace,
      license.expiresAt.map({ $0 > now }) ?? true {
      status = verifiedThisSession ? .licensed : .offline
      hasAccess = true
    } else if let end = trialEndsAt, end > now {
      status = .trial
      hasAccess = true
    } else {
      status = isWorking && stored.license != nil ? .checking : .locked
      hasAccess = false
    }
    if now.timeIntervalSince(stored.lastObservedAt) >= 60,
      stored.trialStartedAt != nil || stored.license != nil {
      var next = stored
      next.lastObservedAt = now
      do { try persist(next) } catch { failStorage() }
    }
  }

  private func invalidateSavedLicense(_ error: LicenseError) {
    verifiedThisSession = false
    allowOfflineCache = false
    var next = stored
    next.license?.invalidated = true
    do { try persist(next); message = error.localizedDescription }
    catch { failStorage() }
  }

  private func persist(_ value: LicenseStoredState) throws {
    try LicenseStore.save(value)
    stored = value
  }

  private func failStorage() {
    storageAvailable = false
    hasAccess = false
    status = .locked
    message = LicenseError.storage.localizedDescription
  }
}
