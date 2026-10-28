import Combine
import Foundation

@MainActor final class RouterTestState: ObservableObject {
  @Published var prompt = ""
  @Published private(set) var result: RouterEvaluation?
  @Published private(set) var error: String?
  @Published private(set) var isRunning = false
  private var task: Task<Void, Never>?
  private var generation: UUID?

  func run(evaluate: @escaping (String) async throws -> RouterEvaluation) {
    guard !isRunning else { return }
    let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    let id = UUID()
    generation = id
    result = nil
    error = nil
    isRunning = true
    task = Task { [weak self] in
      do {
        try Task.checkCancellation()
        let result = try await evaluate(text)
        try Task.checkCancellation()
        guard let self, self.generation == id else { return }
        self.result = result
        self.finish()
      } catch {
        guard let self, self.generation == id, !Task.isCancelled else { return }
        self.error = error.localizedDescription
        self.finish()
      }
    }
  }

  func cancel(clearResult: Bool = false) {
    task?.cancel()
    generation = nil
    task = nil
    isRunning = false
    if clearResult { result = nil; error = nil }
  }

  private func finish() { task = nil; generation = nil; isRunning = false }
}
