import Combine
import Foundation
import Sparkle

final class UpdaterViewModel: ObservableObject {
  @Published var canCheckForUpdates = false

  private let controller: SPUStandardUpdaterController

  init() {
    // For SwiftUI apps, SPUStandardUpdaterController is the easiest way to integrate.
    // It handles the UI (the "Check for Updates" window) automatically.
    controller = SPUStandardUpdaterController(
      startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    // We can observe the updater's state
    controller.updater.publisher(for: \.canCheckForUpdates)
      .assign(to: &$canCheckForUpdates)

    // Force enable automatic checks and updates
    controller.updater.automaticallyChecksForUpdates = true
    controller.updater.automaticallyDownloadsUpdates = true
  }

  func checkForUpdates() {
    controller.checkForUpdates(nil)
  }
}
