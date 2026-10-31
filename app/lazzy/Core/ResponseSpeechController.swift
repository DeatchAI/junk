import AVFoundation
import Combine
import Foundation

@MainActor final class ResponseSpeechController: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
  static let shared = ResponseSpeechController()
  @Published private(set) var speakingID: String?
  private let synthesizer = AVSpeechSynthesizer()
  private var utterance: AVSpeechUtterance?

  override init() {
    super.init()
    synthesizer.delegate = self
  }

  static func spokenText(_ markdown: String) -> String {
    let text = (try? AttributedString(markdown: markdown)).map { String($0.characters) } ?? markdown
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  func toggle(text: String, id: String) {
    if speakingID == id { stop(); return }
    stop()
    let text = Self.spokenText(text)
    guard !text.isEmpty else { return }
    let next = AVSpeechUtterance(string: text)
    next.voice = AVSpeechSynthesisVoice(language: Locale.current.language.languageCode?.identifier ?? "en")
    next.rate = AVSpeechUtteranceDefaultSpeechRate
    utterance = next; speakingID = id
    synthesizer.speak(next)
  }

  func stop() {
    speakingID = nil; utterance = nil
    synthesizer.stopSpeaking(at: .immediate)
  }

  nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    let id = ObjectIdentifier(utterance)
    Task { @MainActor [weak self] in self?.finished(id) }
  }

  nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
    let id = ObjectIdentifier(utterance)
    Task { @MainActor [weak self] in self?.finished(id) }
  }

  private func finished(_ completed: ObjectIdentifier) {
    guard utterance.map(ObjectIdentifier.init) == completed else { return }
    speakingID = nil; utterance = nil
  }
}
