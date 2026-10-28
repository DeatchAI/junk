import Foundation

enum KeepAwakeWorkPolicy {
  static func isWorking(_ runs: [DetachedAgentRun]) -> Bool {
    runs.contains { !$0.isDebugPreview && ($0.state == .running || $0.state == .stopping) }
  }
}
