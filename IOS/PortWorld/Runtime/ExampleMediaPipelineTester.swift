import AVFAudio
import Foundation
import UIKit

struct ExampleMediaPipelineResult {
  let statusCode: Int
  let responseBytes: Int
  let playbackDurationMs: Int
}

enum ExampleMediaPipelineError: LocalizedError {
  case mediaNotFound(String)
  case mediaUnreadable(String)
  case backendURLInvalid
  case invalidHTTPResponse
  case backendFailure(statusCode: Int, message: String)
  case audioPlaybackFailed

  var errorDescription: String? {
    switch self {
    case .mediaNotFound(let name):
      return "Example media not found in app bundle: \(name)"
    case .mediaUnreadable(let name):
      return "Example media is unreadable: \(name)"
    case .backendURLInvalid:
      return "Unable to build backend test URL /v1/pipeline/tts-stream"
    case .invalidHTTPResponse:
      return "Backend returned a non-HTTP response."
    case .backendFailure(let statusCode, let message):
      if message.isEmpty {
        return "Backend test failed with HTTP \(statusCode)."
      }
      return "Backend test failed with HTTP \(statusCode): \(message)"
    case .audioPlaybackFailed:
      return "Unable to play backend audio response on iPhone."
    }
  }
}

@MainActor
final class ExampleMediaPipelineTester {
  private struct ExampleBundle {
    let imageData: Data
    let imageFileName: String
    let imageMimeType: String
    let audioData: Data
    let audioFileName: String
    let audioMimeType: String
    let videoData: Data
    let videoFileName: String
    let videoMimeType: String
  }

  private let runtimeConfig: RuntimeConfig
  private let urlSession: URLSession
  private let audioSession: AVAudioSession

  private var audioPlayer: AVAudioPlayer?

  init(
    runtimeConfig: RuntimeConfig,
    urlSession: URLSession = .shared,
    audioSession: AVAudioSession = .sharedInstance()
  ) {
    self.runtimeConfig = runtimeConfig
    self.urlSession = urlSession
    self.audioSession = audioSession
  }

  func runExamplePipeline(prompt: String = "Analyse ces medias et donne un conseil court en francais.") async throws -> ExampleMediaPipelineResult {
    let media = try loadBundledMedia()
    let endpointURL = try makePipelineTTSURL(from: runtimeConfig.backendBaseURL)
    let boundary = "Boundary-\(UUID().uuidString)"

    let body = makeMultipartBody(
      boundary: boundary,
      prompt: prompt,
      media: media
    )

    var request = URLRequest(url: endpointURL)
    request.httpMethod = "POST"
    request.timeoutInterval = 90
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    for (name, value) in runtimeConfig.requestHeaders {
      request.setValue(value, forHTTPHeaderField: name)
    }
    request.httpBody = body

    let (responseData, response) = try await urlSession.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw ExampleMediaPipelineError.invalidHTTPResponse
    }

    guard (200..<300).contains(httpResponse.statusCode) else {
      let message = String(data: responseData, encoding: .utf8) ?? ""
      throw ExampleMediaPipelineError.backendFailure(statusCode: httpResponse.statusCode, message: message)
    }

    let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type")?.lowercased()
    let durationMs = try playResponseAudio(data: responseData, contentType: contentType)

    return ExampleMediaPipelineResult(
      statusCode: httpResponse.statusCode,
      responseBytes: responseData.count,
      playbackDurationMs: durationMs
    )
  }

  private func loadBundledMedia() throws -> ExampleBundle {
    let imageURL = try findResourceURL(candidates: [("ImageText", "webp"), ("ImageText", "png")])
    let audioURL = try findResourceURL(candidates: [("EnregistrementTest", "m4a")])
    let videoURL = try findResourceURL(candidates: [("VideoTest", "mov")])

    guard let imageRaw = try? Data(contentsOf: imageURL) else {
      throw ExampleMediaPipelineError.mediaUnreadable("ImageText.webp")
    }
    guard let audioData = try? Data(contentsOf: audioURL) else {
      throw ExampleMediaPipelineError.mediaUnreadable("EnregistrementTest.m4a")
    }
    guard let videoData = try? Data(contentsOf: videoURL) else {
      throw ExampleMediaPipelineError.mediaUnreadable("VideoTest.mov")
    }

    let imageData: Data
    let imageFileName: String
    let imageMimeType: String
    if let image = UIImage(data: imageRaw), let jpeg = image.jpegData(compressionQuality: 0.85) {
      imageData = jpeg
      imageFileName = "example.jpg"
      imageMimeType = "image/jpeg"
    } else {
      imageData = imageRaw
      imageFileName = "ImageText.webp"
      imageMimeType = "image/webp"
    }

    return ExampleBundle(
      imageData: imageData,
      imageFileName: imageFileName,
      imageMimeType: imageMimeType,
      audioData: audioData,
      audioFileName: "EnregistrementTest.m4a",
      audioMimeType: "audio/mp4",
      videoData: videoData,
      videoFileName: "VideoTest.mov",
      videoMimeType: "video/quicktime"
    )
  }

  private func findResourceURL(candidates: [(String, String)]) throws -> URL {
    for (name, ext) in candidates {
      if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "ExampleMedia") {
        return url
      }
      if let url = Bundle.main.url(forResource: name, withExtension: ext) {
        return url
      }
    }

    let first = candidates.first.map { "\($0.0).\($0.1)" } ?? "unknown"
    throw ExampleMediaPipelineError.mediaNotFound(first)
  }

  private func makePipelineTTSURL(from baseURL: URL) throws -> URL {
    guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
      throw ExampleMediaPipelineError.backendURLInvalid
    }

    let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    if basePath.isEmpty {
      components.path = "/v1/pipeline/tts-stream"
    } else {
      components.path = "/\(basePath)/v1/pipeline/tts-stream"
    }

    guard let url = components.url else {
      throw ExampleMediaPipelineError.backendURLInvalid
    }
    return url
  }

  private func makeMultipartBody(
    boundary: String,
    prompt: String,
    media: ExampleBundle
  ) -> Data {
    var body = Data()

    body.appendUTF8("--\(boundary)\r\n")
    body.appendUTF8("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n")
    body.appendUTF8("\(prompt)\r\n")

    body.appendUTF8("--\(boundary)\r\n")
    body.appendUTF8("Content-Disposition: form-data; name=\"history_json\"\r\n\r\n")
    body.appendUTF8("[]\r\n")

    body.appendUTF8("--\(boundary)\r\n")
    body.appendUTF8("Content-Disposition: form-data; name=\"output_format\"\r\n\r\n")
    body.appendUTF8("pcm_16000\r\n")

    body.appendUTF8("--\(boundary)\r\n")
    body.appendUTF8("Content-Disposition: form-data; name=\"images\"; filename=\"\(media.imageFileName)\"\r\n")
    body.appendUTF8("Content-Type: \(media.imageMimeType)\r\n\r\n")
    body.append(media.imageData)
    body.appendUTF8("\r\n")

    body.appendUTF8("--\(boundary)\r\n")
    body.appendUTF8("Content-Disposition: form-data; name=\"audio\"; filename=\"\(media.audioFileName)\"\r\n")
    body.appendUTF8("Content-Type: \(media.audioMimeType)\r\n\r\n")
    body.append(media.audioData)
    body.appendUTF8("\r\n")

    body.appendUTF8("--\(boundary)\r\n")
    body.appendUTF8("Content-Disposition: form-data; name=\"video\"; filename=\"\(media.videoFileName)\"\r\n")
    body.appendUTF8("Content-Type: \(media.videoMimeType)\r\n\r\n")
    body.append(media.videoData)
    body.appendUTF8("\r\n")

    body.appendUTF8("--\(boundary)--\r\n")

    return body
  }

  private func playResponseAudio(data: Data, contentType: String?) throws -> Int {
    do {
      try audioSession.setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetoothA2DP])
      try audioSession.setActive(true, options: [])
    } catch {
      throw ExampleMediaPipelineError.audioPlaybackFailed
    }

    // Try direct playback first (works for mp3/wav containers).
    if let durationMs = tryPlayAudio(data: data) {
      return durationMs
    }

    // If direct playback failed, fallback to raw PCM->WAV wrapping.
    let type = contentType ?? ""
    if !type.contains("mpeg") && !type.contains("mp3") {
      let wavData = wrapPCM16MonoAsWAV(pcmData: data, sampleRate: 16_000)
      if let durationMs = tryPlayAudio(data: wavData) {
        return durationMs
      }
    }

    throw ExampleMediaPipelineError.audioPlaybackFailed
  }

  private func tryPlayAudio(data: Data) -> Int? {
    guard let player = try? AVAudioPlayer(data: data) else {
      return nil
    }
    player.prepareToPlay()
    guard player.play() else {
      return nil
    }
    audioPlayer = player
    return Int((player.duration * 1000).rounded())
  }

  private func wrapPCM16MonoAsWAV(pcmData: Data, sampleRate: Int) -> Data {
    let channels: UInt16 = 1
    let bitsPerSample: UInt16 = 16
    let byteRate: UInt32 = UInt32(sampleRate) * UInt32(channels) * UInt32(bitsPerSample / 8)
    let blockAlign: UInt16 = channels * (bitsPerSample / 8)
    let subchunk2Size: UInt32 = UInt32(pcmData.count)
    let chunkSize: UInt32 = 36 + subchunk2Size

    var wav = Data(capacity: 44 + pcmData.count)
    wav.appendUTF8("RIFF")
    wav.appendLE32(chunkSize)
    wav.appendUTF8("WAVE")

    wav.appendUTF8("fmt ")
    wav.appendLE32(16)
    wav.appendLE16(1)
    wav.appendLE16(channels)
    wav.appendLE32(UInt32(sampleRate))
    wav.appendLE32(byteRate)
    wav.appendLE16(blockAlign)
    wav.appendLE16(bitsPerSample)

    wav.appendUTF8("data")
    wav.appendLE32(subchunk2Size)
    wav.append(pcmData)

    return wav
  }
}

private extension Data {
  mutating func appendUTF8(_ string: String) {
    if let data = string.data(using: .utf8) {
      append(data)
    }
  }

  mutating func appendLE16(_ value: UInt16) {
    var little = value.littleEndian
    Swift.withUnsafeBytes(of: &little) { append($0.bindMemory(to: UInt8.self)) }
  }

  mutating func appendLE32(_ value: UInt32) {
    var little = value.littleEndian
    Swift.withUnsafeBytes(of: &little) { append($0.bindMemory(to: UInt8.self)) }
  }
}
