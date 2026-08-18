import Foundation
import WhisperKit

/// Keeps the Whisper model in-process and performs all decoding on the Mac.
/// The first transcription downloads the model into WhisperKit's local cache;
/// later recordings never leave the device.
actor LocalWhisperTranscriber {
  private static let modelVariant = "large-v3-v20240930_turbo_632MB"
  private var pipeline: WhisperKit?

  func transcribe(audioURL: URL) async throws -> String {
    if pipeline == nil {
      let configuration = WhisperKitConfig(
        model: Self.modelVariant,
        verbose: false,
        load: true,
        download: true
      )
      pipeline = try await WhisperKit(configuration)
    }

    guard let pipeline else {
      throw LocalWhisperError.pipelineUnavailable
    }

    let options = DecodingOptions(
      verbose: false,
      withoutTimestamps: true,
      concurrentWorkerCount: 2,
      chunkingStrategy: .vad
    )
    let results = try await pipeline.transcribe(
      audioPath: audioURL.path,
      decodeOptions: options
    )
    let transcript = results.map { $0.text }.joined(separator: " ")
    return transcript.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
  }
}

private enum LocalWhisperError: LocalizedError {
  case pipelineUnavailable

  var errorDescription: String? {
    "The local Whisper model could not be loaded."
  }
}
