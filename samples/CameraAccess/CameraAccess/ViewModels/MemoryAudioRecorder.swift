/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// MemoryAudioRecorder.swift
//
// Records a short microphone clip to a temporary file for use as a persona voice memory.
//

import AVFoundation
import Observation

@Observable
@MainActor
final class MemoryAudioRecorder {
  private(set) var isRecording = false
  private(set) var lastError: String?

  private var recorder: AVAudioRecorder?

  func start() {
    let audioSession = AVAudioSession.sharedInstance()
    do {
      try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
      try audioSession.setActive(true)
    } catch {
      lastError = "Audio session error: \(error.localizedDescription)"
      return
    }

    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
    let settings: [String: Any] = [
      AVFormatIDKey: kAudioFormatMPEG4AAC,
      AVSampleRateKey: 44_100,
      AVNumberOfChannelsKey: 1,
      AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
    ]

    do {
      let recorder = try AVAudioRecorder(url: url, settings: settings)
      recorder.record()
      self.recorder = recorder
      isRecording = true
    } catch {
      lastError = "Couldn't start recording: \(error.localizedDescription)"
    }
  }

  /// Stops recording and returns the URL of the recorded clip, if any.
  func stop() -> URL? {
    guard let recorder else { return nil }
    recorder.stop()
    isRecording = false
    self.recorder = nil
    return recorder.url
  }
}
