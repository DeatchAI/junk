import AVFoundation
import Combine
import Foundation

enum VoiceDictationState: Equatable {
  case idle
  case requestingPermission
  case listening
  case processing
  case failed(String)
}

/// Owns one microphone transcription session for the focused floating
/// composer. The composer owns the Fn gesture; this type never sends a chat
/// message by itself.
final class VoiceDictationController: NSObject, ObservableObject {
  @Published private(set) var state: VoiceDictationState = .idle
  @Published private(set) var partialTranscript = ""

  var onHoldBegan: (() -> Void)?
  var onStateChanged: ((VoiceDictationState, String) -> Void)?
  var onTranscription: ((String) -> Void)?

  private let whisperTranscriber = LocalWhisperTranscriber()
  private var isPushToTalkActive = false
  private var sessionID: UUID?
  private var audioRecorder: AVAudioRecorder?
  private var recordingURL: URL?
  private var transcriptionTask: Task<Void, Never>?

  func beginPushToTalk() {
    guard !isPushToTalkActive else { return }
    isPushToTalkActive = true
    beginHold()
  }

  func endPushToTalk() {
    guard isPushToTalkActive else { return }
    isPushToTalkActive = false
    finishHold()
  }

  func toggleRecording() {
    isPushToTalkActive ? endPushToTalk() : beginPushToTalk()
  }

  func stop() {
    isPushToTalkActive = false
    cancelRecognition()
    updateState(.idle, partial: "")
  }

  private func beginHold() {
    guard hasMicrophoneUsageDescription else {
      isPushToTalkActive = false
      fail(
        "Voice input is unavailable in this build. Rebuild or reinstall Detach so its microphone permission is included."
      )
      return
    }

    // A new press while a previous transcription is finishing cancels that
    // session and starts a clean recording for the same focused composer.
    cancelRecognition()
    let newSessionID = UUID()
    sessionID = newSessionID
    partialTranscript = ""
    onHoldBegan?()
    updateState(.requestingPermission, partial: "")
    requestMicrophonePermission(sessionID: newSessionID)
  }

  private func requestMicrophonePermission(sessionID: UUID) {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
      startRecordingIfStillHeld(sessionID: sessionID)
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
        DispatchQueue.main.async {
          guard let self,
            self.isPushToTalkActive,
            self.sessionID == sessionID
          else { return }
          if granted {
            self.startRecordingIfStillHeld(sessionID: sessionID)
          } else {
            self.fail("Microphone permission is required for local voice input.")
          }
        }
      }
    case .denied:
      fail("Allow Microphone access for Detach in System Settings.")
    case .restricted:
      fail("Microphone access is restricted on this Mac.")
    @unknown default:
      fail("Microphone permission is unavailable.")
    }
  }

  private func startRecordingIfStillHeld(sessionID: UUID) {
    guard isPushToTalkActive, self.sessionID == sessionID else { return }
    startRecording(sessionID: sessionID)
  }

  private func startRecording(sessionID: UUID) {
    guard AVCaptureDevice.default(for: .audio) != nil else {
      fail("No microphone input is available on this Mac.")
      return
    }

    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("detach-voice-\(sessionID.uuidString).wav")
    let settings: [String: Any] = [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVSampleRateKey: 16_000,
      AVNumberOfChannelsKey: 1,
      AVLinearPCMBitDepthKey: 16,
      AVLinearPCMIsFloatKey: false,
      AVLinearPCMIsBigEndianKey: false,
    ]

    do {
      let recorder = try AVAudioRecorder(url: url, settings: settings)
      recorder.isMeteringEnabled = true
      guard recorder.record() else {
        fail("Could not start the microphone recorder.")
        return
      }
      recordingURL = url
      audioRecorder = recorder
      updateState(.listening, partial: "")
    } catch {
      fail("Could not start the microphone: \(error.localizedDescription)")
    }
  }

  private func finishHold() {
    guard let sessionID else {
      updateState(.idle, partial: "")
      return
    }

    guard state == .listening, let recorder = audioRecorder, let url = recordingURL else {
      if state == .requestingPermission {
        cancelRecognition()
        updateState(.idle, partial: "")
      }
      return
    }

    recorder.stop()
    audioRecorder = nil
    updateState(.processing, partial: partialTranscript)

    transcriptionTask = Task { [weak self] in
      do {
        let transcript = try await self?.whisperTranscriber.transcribe(audioURL: url) ?? ""
        guard !Task.isCancelled else { return }
        await MainActor.run {
          guard let self, self.sessionID == sessionID else { return }
          self.complete(sessionID: sessionID, transcript: transcript)
        }
      } catch {
        guard !Task.isCancelled else { return }
        await MainActor.run {
          guard let self, self.sessionID == sessionID else { return }
          self.fail("Local Whisper could not transcribe this recording: \(error.localizedDescription)")
        }
      }
    }
  }

  private func complete(sessionID: UUID, transcript: String) {
    guard self.sessionID == sessionID else { return }
    let cleanedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    isPushToTalkActive = false
    cancelRecognition()
    if !cleanedTranscript.isEmpty {
      onTranscription?(cleanedTranscript)
    }
    updateState(.idle, partial: "")
  }

  private func fail(_ message: String) {
    isPushToTalkActive = false
    cancelRecognition()
    updateState(.failed(message), partial: "")

    DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
      guard case .failed = self?.state else { return }
      self?.updateState(.idle, partial: "")
    }
  }

  private func cancelRecognition() {
    transcriptionTask?.cancel()
    transcriptionTask = nil

    audioRecorder?.stop()
    audioRecorder = nil

    if let recordingURL {
      try? FileManager.default.removeItem(at: recordingURL)
    }
    recordingURL = nil
    sessionID = nil
  }

  private func updateState(_ state: VoiceDictationState, partial: String) {
    self.state = state
    partialTranscript = partial
    onStateChanged?(state, partial)
  }

  private var hasMicrophoneUsageDescription: Bool {
    guard let value = Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") as? String else {
      return false
    }
    return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}
