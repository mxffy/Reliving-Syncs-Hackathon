/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// PersonaAudioPlaybackService.swift
//
// Plays back a persona's original uploaded/recorded memory clips. Never synthesizes
// speech or clones a voice — only plays the authentic audio file for the matched clip.
//

import AVFoundation
import Observation

/// Plays one memory clip at a time and reports completion so the conversation
/// pipeline can resume listening.
@Observable
@MainActor
final class PersonaAudioPlaybackService: NSObject {
  private(set) var isPlaying = false

  private var player: AVAudioPlayer?
  private var completion: (() -> Void)?

  /// Plays `url`, stopping any clip already in progress first.
  func play(url: URL, onFinished: @escaping () -> Void) {
    stop()
    do {
      let player = try AVAudioPlayer(contentsOf: url)
      player.delegate = self
      self.player = player
      completion = onFinished
      isPlaying = player.play()
      if !isPlaying {
        completion = nil
        onFinished()
      }
    } catch {
      completion = nil
      onFinished()
    }
  }

  func stop() {
    guard isPlaying || player != nil else { return }
    player?.stop()
    player = nil
    isPlaying = false
    let finishedCallback = completion
    completion = nil
    finishedCallback?()
  }
}

extension PersonaAudioPlaybackService: AVAudioPlayerDelegate {
  nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    Task { @MainActor in
      guard self.player === player else { return }
      self.player = nil
      self.isPlaying = false
      let finishedCallback = self.completion
      self.completion = nil
      finishedCallback?()
    }
  }
}
