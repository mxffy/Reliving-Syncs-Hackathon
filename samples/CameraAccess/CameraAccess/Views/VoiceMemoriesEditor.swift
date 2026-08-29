/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// VoiceMemoriesEditor.swift
//
// Reusable "Voice Memories" section: lists a persona's real audio clips and lets the user
// upload an mp3/mp4 or record a new one. Shared between the initial creation review screen
// and the saved item's details screen, so memories can be added at either point.
//

import SwiftUI
import UniformTypeIdentifiers

struct VoiceMemoriesEditor: View {
  @Binding var audioClips: [MemoryAudioClip]

  @State private var recorder = MemoryAudioRecorder()
  @State private var isImportingAudio = false
  @State private var isProcessingAudioImport = false
  @State private var audioImportError: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Voice Memories")
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(Color.relivingBurgundy)

      Text("Upload a real recording (mp3/mp4) or record one now. Only these authentic clips are ever played back — nothing is ever generated.")
        .font(.system(size: 12))
        .foregroundStyle(Color.relivingDarkSage)

      if !audioClips.isEmpty {
        VStack(spacing: 8) {
          ForEach(audioClips) { clip in
            audioClipRow(clip)
          }
        }
      }

      HStack(spacing: 10) {
        Button {
          isImportingAudio = true
        } label: {
          Label("Upload", systemImage: "square.and.arrow.up")
            .font(.system(size: 13, weight: .semibold))
        }
        .buttonStyle(.bordered)
        .tint(Color.relivingBurgundy)
        .disabled(isProcessingAudioImport || recorder.isRecording)

        Button {
          toggleRecording()
        } label: {
          Label(
            recorder.isRecording ? "Stop Recording" : "Record",
            systemImage: recorder.isRecording ? "stop.circle.fill" : "mic.circle"
          )
          .font(.system(size: 13, weight: .semibold))
        }
        .buttonStyle(.bordered)
        .tint(recorder.isRecording ? .red : Color.relivingBurgundy)
        .disabled(isProcessingAudioImport)

        if isProcessingAudioImport {
          ProgressView()
            .tint(Color.relivingBurgundy)
        }
      }

      if let audioImportError {
        Text(audioImportError)
          .font(.system(size: 12))
          .foregroundStyle(.red)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.relivingBeige.opacity(0.5)))
    .fileImporter(
      isPresented: $isImportingAudio,
      allowedContentTypes: [.mp3, .mpeg4Audio, .audio, .mpeg4Movie, .movie],
      onCompletion: handleFileImport
    )
  }

  private func audioClipRow(_ clip: MemoryAudioClip) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: "waveform.circle.fill")
        .foregroundStyle(Color.relivingBurgundy)
      VStack(alignment: .leading, spacing: 2) {
        Text(clip.title ?? "Voice memory")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Color.relivingBurgundy)
        Text(clip.transcript.isEmpty ? "No transcript detected — it may still be matched less reliably." : clip.transcript)
          .font(.system(size: 12))
          .foregroundStyle(Color.relivingDarkSage)
          .lineLimit(2)
      }
      Spacer(minLength: 8)
      Button {
        audioClips.removeAll { $0.id == clip.id }
      } label: {
        Image(systemName: "trash")
          .foregroundStyle(.red.opacity(0.8))
      }
    }
    .padding(8)
    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.relivingIvory))
  }

  private func handleFileImport(_ result: Result<URL, Error>) {
    switch result {
    case .success(let url):
      importPickedFile(url)
    case .failure(let error):
      audioImportError = error.localizedDescription
    }
  }

  private func importPickedFile(_ url: URL) {
    isProcessingAudioImport = true
    audioImportError = nil
    Task {
      do {
        let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
        let clip: MemoryAudioClip
        if let contentType, contentType.conforms(to: .movie) {
          clip = try await MemoryAudioClipImporter.importVideoAudio(from: url, title: nil)
        } else {
          clip = try await MemoryAudioClipImporter.importAudio(from: url, title: nil)
        }
        await MainActor.run {
          audioClips.append(clip)
          isProcessingAudioImport = false
        }
      } catch {
        await MainActor.run {
          audioImportError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
          isProcessingAudioImport = false
        }
      }
    }
  }

  private func toggleRecording() {
    if recorder.isRecording {
      guard let recordedURL = recorder.stop() else { return }
      isProcessingAudioImport = true
      audioImportError = nil
      Task {
        do {
          let clip = try await MemoryAudioClipImporter.importRecording(from: recordedURL, title: nil)
          await MainActor.run {
            audioClips.append(clip)
            isProcessingAudioImport = false
          }
        } catch {
          await MainActor.run {
            audioImportError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            isProcessingAudioImport = false
          }
        }
      }
    } else {
      audioImportError = nil
      recorder.start()
    }
  }
}
