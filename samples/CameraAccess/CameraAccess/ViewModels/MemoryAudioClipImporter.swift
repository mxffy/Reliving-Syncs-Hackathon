/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// MemoryAudioClipImporter.swift
//
// Turns a picked audio/video file or a fresh microphone recording into a persisted
// MemoryAudioClip: copies the audio into the app's Documents directory, transcribes it
// on-device with Speech, and precomputes its sentence embedding for later retrieval.
//

import AVFoundation
import Foundation
import Speech

enum MemoryAudioClipImporterError: LocalizedError {
  case unreadableSource
  case noAudioTrack
  case exportFailed

  var errorDescription: String? {
    switch self {
    case .unreadableSource:
      return "Couldn't read the selected file."
    case .noAudioTrack:
      return "That video doesn't contain an audio track."
    case .exportFailed:
      return "Couldn't extract audio from the selected video."
    }
  }
}

enum MemoryAudioClipImporter {
  /// Imports an audio file (e.g. .mp3, .m4a) picked from Files/Photos.
  static func importAudio(from sourceURL: URL, title: String?) async throws -> MemoryAudioClip {
    let didStartAccess = sourceURL.startAccessingSecurityScopedResource()
    defer { if didStartAccess { sourceURL.stopAccessingSecurityScopedResource() } }

    let destination = try persistedURL(preferredExtension: sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension)
    try FileManager.default.copyItem(at: sourceURL, to: destination)
    return try await finalizeClip(audioURL: destination, title: title)
  }

  /// Imports a video file (e.g. .mp4, .mov) and strips it down to just the audio track.
  static func importVideoAudio(from sourceURL: URL, title: String?) async throws -> MemoryAudioClip {
    let didStartAccess = sourceURL.startAccessingSecurityScopedResource()
    defer { if didStartAccess { sourceURL.stopAccessingSecurityScopedResource() } }

    let asset = AVURLAsset(url: sourceURL)
    let audioTracks = try await asset.loadTracks(withMediaType: .audio)
    guard !audioTracks.isEmpty else { throw MemoryAudioClipImporterError.noAudioTrack }

    guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
      throw MemoryAudioClipImporterError.exportFailed
    }
    let destination = try persistedURL(preferredExtension: "m4a")
    exportSession.outputURL = destination
    exportSession.outputFileType = .m4a
    try await exportSession.export(to: destination, as: .m4a)

    return try await finalizeClip(audioURL: destination, title: title)
  }

  /// Imports audio just recorded via the microphone (already at `recordingURL`).
  static func importRecording(from recordingURL: URL, title: String?) async throws -> MemoryAudioClip {
    let destination = try persistedURL(preferredExtension: "m4a")
    try FileManager.default.copyItem(at: recordingURL, to: destination)
    return try await finalizeClip(audioURL: destination, title: title)
  }

  private static func finalizeClip(audioURL: URL, title: String?) async throws -> MemoryAudioClip {
    let transcript = (try? await transcribe(audioURL: audioURL)) ?? ""
    let embedding = transcript.isEmpty ? nil : SentenceEmbeddingService.shared.embed(transcript)
    return MemoryAudioClip(audioURL: audioURL, transcript: transcript, embedding: embedding, title: title)
  }

  /// Transcribes a local audio file on-device using Speech (separate from the live mic pipeline).
  private static func transcribe(audioURL: URL) async throws -> String {
    guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), recognizer.isAvailable else {
      return ""
    }
    let authStatus = await withCheckedContinuation { continuation in
      SFSpeechRecognizer.requestAuthorization { status in continuation.resume(returning: status) }
    }
    guard authStatus == .authorized else { return "" }

    return try await withCheckedThrowingContinuation { continuation in
      let request = SFSpeechURLRecognitionRequest(url: audioURL)
      if recognizer.supportsOnDeviceRecognition {
        request.requiresOnDeviceRecognition = true
      }
      recognizer.recognitionTask(with: request) { result, error in
        guard let result else {
          if let error {
            continuation.resume(throwing: error)
          }
          return
        }
        if result.isFinal {
          continuation.resume(returning: result.bestTranscription.formattedString)
        }
      }
    }
  }

  private static func persistedURL(preferredExtension: String) throws -> URL {
    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let folder = documents.appendingPathComponent("PersonaAudioMemories", isDirectory: true)
    if !FileManager.default.fileExists(atPath: folder.path) {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    return folder.appendingPathComponent("\(UUID().uuidString).\(preferredExtension)")
  }
}
