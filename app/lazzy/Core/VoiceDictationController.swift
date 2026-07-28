import AppKit
import AVFoundation
import Combine
import CoreGraphics
import Foundation
import Speech

enum VoiceDictationState: Equatable {
  case idle
  case requestingPermission
  case listening
  case processing
  case failed(String)
}

/// Owns the global Fn push-to-talk gesture and a single live microphone
/// transcription session. The finished text is handed back to the floating
/// workspace; this type never sends a chat message by itself.
final class VoiceDictationController: NSObject, ObservableObject {
  @Published private(set) var state: VoiceDictationState = .idle
  @Published private(set) var partialTranscript = ""

  var onHoldBegan: (() -> Void)?
  var onStateChanged: ((VoiceDictationState, String) -> Void)?
  var onTranscription: ((String) -> Void)?

  private let functionKeyCode: Int64 = 63
  private var eventTap: CFMachPort?
  private var eventTapSource: CFRunLoopSource?
  private var localFlagsMonitor: Any?
  private var globalFlagsMonitor: Any?

  private var isFunctionKeyHeld = false
  private var sessionID: UUID?
  private var audioEngine: AVAudioEngine?
  private var hasInstalledInputTap = false
  private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
  private var recognitionTask: SFSpeechRecognitionTask?
  private var finalizationWorkItem: DispatchWorkItem?

  func startMonitoring() {
    stopKeyboardMonitoring()

    if installFunctionKeyEventTap() {
      print("🎙️ Fn push-to-talk monitor started")
      return
    }

    // A local monitor keeps voice input usable while the composer is focused
    // even before Accessibility has been granted. The global monitor becomes
    // effective once macOS allows this app to observe keyboard input.
    localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) {
      [weak self] event in
      self?.handleFlagsChanged(
        keyCode: Int64(event.keyCode),
        functionIsDown: event.modifierFlags.contains(.function)
      )
      return event
    }
    globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) {
      [weak self] event in
      self?.handleFlagsChanged(
        keyCode: Int64(event.keyCode),
        functionIsDown: event.modifierFlags.contains(.function)
      )
    }
    print("🎙️ Fn push-to-talk monitor started in compatibility mode")
  }

  func restartMonitoring() {
    startMonitoring()
  }

  func stopMonitoring() {
    stopKeyboardMonitoring()
    isFunctionKeyHeld = false
    cancelRecognition()
    updateState(.idle, partial: "")
  }

  private func installFunctionKeyEventTap() -> Bool {
    let mask = CGEventMask(1) << CGEventType.flagsChanged.rawValue
    let callback: CGEventTapCallBack = { _, type, event, userInfo in
      guard let userInfo else {
        return Unmanaged.passUnretained(event)
      }

      let controller = Unmanaged<VoiceDictationController>
        .fromOpaque(userInfo)
        .takeUnretainedValue()

      if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let eventTap = controller.eventTap {
          CGEvent.tapEnable(tap: eventTap, enable: true)
        }
        return Unmanaged.passUnretained(event)
      }

      guard type == .flagsChanged,
        event.getIntegerValueField(.keyboardEventKeycode) == controller.functionKeyCode
      else {
        return Unmanaged.passUnretained(event)
      }

      controller.handleFlagsChanged(
        keyCode: controller.functionKeyCode,
        functionIsDown: event.flags.contains(.maskSecondaryFn)
      )

      // Fn is dedicated to Detach push-to-talk while the app is running. Do
      // not also open the macOS emoji/dictation action configured for Fn.
      return nil
    }

    guard
      let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: mask,
        callback: callback,
        userInfo: Unmanaged.passUnretained(self).toOpaque()
      )
    else {
      return false
    }

    guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
      CFMachPortInvalidate(tap)
      return false
    }

    eventTap = tap
    eventTapSource = source
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    return true
  }

  private func stopKeyboardMonitoring() {
    if let localFlagsMonitor {
      NSEvent.removeMonitor(localFlagsMonitor)
      self.localFlagsMonitor = nil
    }
    if let globalFlagsMonitor {
      NSEvent.removeMonitor(globalFlagsMonitor)
      self.globalFlagsMonitor = nil
    }
    if let eventTapSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
      self.eventTapSource = nil
    }
    if let eventTap {
      CFMachPortInvalidate(eventTap)
      self.eventTap = nil
    }
  }

  private func handleFlagsChanged(keyCode: Int64, functionIsDown: Bool) {
    guard keyCode == functionKeyCode else { return }

    if functionIsDown && !isFunctionKeyHeld {
      isFunctionKeyHeld = true
      beginHold()
    } else if !functionIsDown && isFunctionKeyHeld {
      isFunctionKeyHeld = false
      finishHold()
    }
  }

  private func beginHold() {
    if state == .processing, let sessionID {
      complete(sessionID: sessionID, transcript: partialTranscript)
    } else {
      cancelRecognition()
    }
    sessionID = UUID()
    partialTranscript = ""
    onHoldBegan?()
    updateState(.requestingPermission, partial: "")
    requestSpeechPermission()
  }

  private func requestSpeechPermission() {
    switch SFSpeechRecognizer.authorizationStatus() {
    case .authorized:
      requestMicrophonePermission()
    case .notDetermined:
      SFSpeechRecognizer.requestAuthorization { [weak self] status in
        DispatchQueue.main.async {
          guard let self else { return }
          if status == .authorized {
            self.requestMicrophonePermission()
          } else {
            self.fail("Speech recognition permission is required for Fn voice input.")
          }
        }
      }
    case .denied:
      fail("Allow Speech Recognition for Detach in System Settings.")
    case .restricted:
      fail("Speech recognition is restricted on this Mac.")
    @unknown default:
      fail("Speech recognition permission is unavailable.")
    }
  }

  private func requestMicrophonePermission() {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
      startRecognitionIfStillHeld()
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
        DispatchQueue.main.async {
          guard let self else { return }
          if granted {
            self.startRecognitionIfStillHeld()
          } else {
            self.fail("Microphone permission is required for Fn voice input.")
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

  private func startRecognitionIfStillHeld() {
    guard isFunctionKeyHeld, let sessionID else {
      updateState(.idle, partial: "")
      return
    }
    startRecognition(sessionID: sessionID)
  }

  private func startRecognition(sessionID: UUID) {
    guard let recognizer = SFSpeechRecognizer(locale: Locale.autoupdatingCurrent) else {
      fail("Speech recognition is not available for your current language.")
      return
    }
    guard recognizer.isAvailable else {
      fail("Apple speech recognition is currently unavailable.")
      return
    }

    let engine = AVAudioEngine()
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    request.taskHint = .dictation
    request.addsPunctuation = true
    if recognizer.supportsOnDeviceRecognition {
      request.requiresOnDeviceRecognition = true
    }

    let inputNode = engine.inputNode
    let recordingFormat = inputNode.outputFormat(forBus: 0)
    guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
      fail("No microphone input is available.")
      return
    }

    inputNode.installTap(
      onBus: 0,
      bufferSize: 1_024,
      format: recordingFormat
    ) { buffer, _ in
      request.append(buffer)
    }
    hasInstalledInputTap = true

    audioEngine = engine
    recognitionRequest = request
    recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
      DispatchQueue.main.async {
        guard let self, self.sessionID == sessionID else { return }

        if let result {
          let transcript = result.bestTranscription.formattedString
          self.partialTranscript = transcript
          self.onStateChanged?(self.state, transcript)
          if result.isFinal {
            self.complete(sessionID: sessionID, transcript: transcript)
            return
          }
        }

        if let error {
          if !self.partialTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.complete(sessionID: sessionID, transcript: self.partialTranscript)
          } else if self.state == .processing {
            self.complete(sessionID: sessionID, transcript: "")
          } else {
            self.fail("Voice transcription stopped: \(error.localizedDescription)")
          }
        }
      }
    }

    engine.prepare()
    do {
      try engine.start()
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

    guard state == .listening else {
      if state == .requestingPermission {
        updateState(.idle, partial: "")
      }
      return
    }

    audioEngine?.stop()
    removeInputTapIfNeeded()
    recognitionRequest?.endAudio()
    updateState(.processing, partial: partialTranscript)

    let workItem = DispatchWorkItem { [weak self] in
      guard let self, self.sessionID == sessionID else { return }
      self.complete(sessionID: sessionID, transcript: self.partialTranscript)
    }
    finalizationWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
  }

  private func complete(sessionID: UUID, transcript: String) {
    guard self.sessionID == sessionID else { return }
    let cleanedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    cancelRecognition()
    if !cleanedTranscript.isEmpty {
      onTranscription?(cleanedTranscript)
    }
    updateState(.idle, partial: "")
  }

  private func fail(_ message: String) {
    cancelRecognition()
    updateState(.failed(message), partial: "")

    DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
      guard case .failed = self?.state else { return }
      self?.updateState(.idle, partial: "")
    }
  }

  private func cancelRecognition() {
    finalizationWorkItem?.cancel()
    finalizationWorkItem = nil

    audioEngine?.stop()
    removeInputTapIfNeeded()
    recognitionRequest?.endAudio()
    recognitionTask?.cancel()

    audioEngine = nil
    recognitionRequest = nil
    recognitionTask = nil
    sessionID = nil
  }

  private func removeInputTapIfNeeded() {
    guard hasInstalledInputTap else { return }
    audioEngine?.inputNode.removeTap(onBus: 0)
    hasInstalledInputTap = false
  }

  private func updateState(_ state: VoiceDictationState, partial: String) {
    self.state = state
    partialTranscript = partial
    onStateChanged?(state, partial)
  }
}
