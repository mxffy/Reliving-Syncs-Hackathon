/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// PersonaConversationService.swift
//
// The ReLiving conversational memory pipeline:
//   live microphone -> speech recognition -> persona trigger detection
//   -> semantic retrieval -> confidence threshold -> AVAudioPlayer -> persona UI state
//
// This never generates new dialogue and never clones a voice. It only ever plays back
// an authentic, previously uploaded/recorded clip from the active persona, and only when
// the live transcript is confidently similar to that clip's own transcript. If nothing
// stored is a confident match, it stays silent.
//

import AVFoundation
import Observation
import Speech

/// UI-facing state for the conversation pipeline.
enum PersonaConversationState: Equatable {
  /// Microphone is off (camera mode isn't active).
  case idle
  /// Microphone is on, waiting for a persona name or a query for the active persona.
  case listening
  /// Comparing a stabilised transcript against the active persona's stored clips.
  case matching
  /// Playing back the best-matching stored clip.
  case playing
}

/// Owns the full "hear a name, listen for a memory, play the real recording" pipeline.
/// Kept out of the view per design: the view only observes `conversationState`/`activePersonaID`.
@Observable
@MainActor
final class PersonaConversationService {
  private(set) var conversationState: PersonaConversationState = .idle
  private(set) var activePersonaID: UUID?
  private(set) var lastError: String?

  var isListening: Bool { conversationState != .idle }

  // Tunables kept in one place so the retrieval behaviour can be tuned during testing.
  private let similarityThreshold: Float = 0.70
  /// If the top match doesn't lead the runner-up by at least this much, treat it as ambiguous and stay silent.
  private let ambiguityMargin: Float = 0.08
  /// How long the transcript must stop changing before we treat an utterance as "settled" and run retrieval.
  private let stabilizationDelay: TimeInterval = 0.6
  /// Minimum time between two retrieval attempts, to absorb trailing partial-result noise.
  private let retrievalCooldown: TimeInterval = 1.5

  private static let farewellWords: Set<String> = ["bye", "goodbye"]

  @ObservationIgnored private let mediaStore: MediaCategoryStore
  @ObservationIgnored private let embeddingService: SentenceEmbeddingService
  @ObservationIgnored private let playbackService: PersonaAudioPlaybackService

  @ObservationIgnored private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
  @ObservationIgnored private let audioEngine = AVAudioEngine()
  @ObservationIgnored private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
  @ObservationIgnored private var recognitionTask: SFSpeechRecognitionTask?
  @ObservationIgnored private var wantsListening = false

  @ObservationIgnored private var stabilizationTask: Task<Void, Never>?
  @ObservationIgnored private var lastProcessedQueryTranscript = ""
  @ObservationIgnored private var lastRetrievalAt: Date?

  init(
    mediaStore: MediaCategoryStore = .shared,
    embeddingService: SentenceEmbeddingService = .shared,
    playbackService: PersonaAudioPlaybackService? = nil
  ) {
    self.mediaStore = mediaStore
    self.embeddingService = embeddingService
    self.playbackService = playbackService ?? PersonaAudioPlaybackService()
  }

  func start() {
    guard !wantsListening else { return }
    wantsListening = true

    SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
      guard authStatus == .authorized else {
        Task { @MainActor in self?.lastError = "Speech recognition permission denied." }
        return
      }
      AVAudioApplication.requestRecordPermission { granted in
        Task { @MainActor in
          guard granted, let self, self.wantsListening else { return }
          self.beginRecognition()
        }
      }
    }
  }

  func stop() {
    wantsListening = false
    stabilizationTask?.cancel()
    stabilizationTask = nil
    playbackService.stop()
    teardownRecognition()
    activePersonaID = nil
    conversationState = .idle
  }

  // MARK: - Speech recognition plumbing

  private func beginRecognition() {
    guard let speechRecognizer, speechRecognizer.isAvailable else {
      lastError = "Speech recognizer unavailable."
      return
    }

    let audioSession = AVAudioSession.sharedInstance()
    do {
      // .voiceChat enables echo cancellation, so audio we play back through the speaker
      // is suppressed from the mic input rather than being re-transcribed.
      try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
      try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    } catch {
      lastError = "Audio session error: \(error.localizedDescription)"
      return
    }

    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    if speechRecognizer.supportsOnDeviceRecognition {
      request.requiresOnDeviceRecognition = true
    }
    recognitionRequest = request

    let inputNode = audioEngine.inputNode
    let recordingFormat = inputNode.outputFormat(forBus: 0)
    inputNode.removeTap(onBus: 0)
    inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
      self?.recognitionRequest?.append(buffer)
    }

    audioEngine.prepare()
    do {
      try audioEngine.start()
      if conversationState == .idle {
        conversationState = .listening
      }
    } catch {
      lastError = "Audio engine error: \(error.localizedDescription)"
      return
    }

    recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
      guard let self else { return }
      if let result {
        let transcript = result.bestTranscription.formattedString
        Task { @MainActor in self.handleTranscript(transcript) }
      }
      if error != nil || (result?.isFinal ?? false) {
        Task { @MainActor in self.restartIfNeeded() }
      }
    }
  }

  private func teardownRecognition() {
    recognitionTask?.cancel()
    recognitionTask = nil
    recognitionRequest?.endAudio()
    recognitionRequest = nil
    if audioEngine.isRunning {
      audioEngine.stop()
    }
    audioEngine.inputNode.removeTap(onBus: 0)
  }

  /// The recognition task times out periodically; restart it to keep listening continuously.
  private func restartIfNeeded() {
    guard wantsListening else { return }
    teardownRecognition()
    beginRecognition()
  }

  // MARK: - Trigger detection

  private func handleTranscript(_ raw: String) {
    let words = Self.tokenize(raw)
    guard !words.isEmpty else { return }

    // Deactivation takes precedence: "Bye David" must not re-trigger David via the name it contains.
    if words.contains(where: Self.farewellWords.contains) {
      deactivatePersona()
      return
    }

    // Ignore everything else while a clip is playing, so the mic can't pick up our own
    // audio and recursively trigger another response.
    guard conversationState != .playing else { return }

    if activePersonaID == nil, let matched = matchPersonaName(in: words) {
      activatePersona(matched)
    }

    guard activePersonaID != nil else { return }
    scheduleRetrieval(for: raw)
  }

  private func matchPersonaName(in words: [String]) -> CapturedMediaItem? {
    for item in mediaStore.peopleItems where item.usdzURL != nil {
      guard let firstNameWord = Self.tokenize(item.name).first else { continue }
      let targetCode = Self.soundex(firstNameWord)
      if words.contains(where: { Self.soundex($0) == targetCode }) {
        return item
      }
    }
    return nil
  }

  private func activatePersona(_ item: CapturedMediaItem) {
    activePersonaID = item.id
    lastProcessedQueryTranscript = ""
    lastRetrievalAt = nil
    conversationState = .listening
  }

  private func deactivatePersona() {
    stabilizationTask?.cancel()
    stabilizationTask = nil
    playbackService.stop()
    activePersonaID = nil
    lastProcessedQueryTranscript = ""
    lastRetrievalAt = nil
    conversationState = wantsListening ? .listening : .idle
  }

  // MARK: - Semantic retrieval

  /// Debounces retrieval until the utterance has stopped changing for `stabilizationDelay`,
  /// so "David", "David do", "David do you", "David do you remember" only query once.
  private func scheduleRetrieval(for rawTranscript: String) {
    stabilizationTask?.cancel()
    let delay = stabilizationDelay
    stabilizationTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      guard !Task.isCancelled else { return }
      await self?.attemptRetrieval(rawTranscript: rawTranscript)
    }
  }

  private func attemptRetrieval(rawTranscript: String) async {
    guard let activePersonaID, conversationState != .playing else { return }

    let normalizedQuery = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !normalizedQuery.isEmpty, normalizedQuery != lastProcessedQueryTranscript else { return }
    if let lastRetrievalAt, Date().timeIntervalSince(lastRetrievalAt) < retrievalCooldown { return }

    guard
      let persona = mediaStore.peopleItems.first(where: { $0.id == activePersonaID })
    else { return }
    let candidates = persona.audioClips.compactMap { clip -> (MemoryAudioClip, [Float])? in
      guard let embedding = clip.embedding else { return nil }
      return (clip, embedding)
    }
    guard !candidates.isEmpty else { return }

    lastProcessedQueryTranscript = normalizedQuery
    lastRetrievalAt = Date()
    conversationState = .matching

    guard let queryEmbedding = embeddingService.embed(rawTranscript) else {
      conversationState = .listening
      return
    }

    let scored = candidates
      .map { clip, embedding in (clip, SentenceEmbeddingService.cosineSimilarity(queryEmbedding, embedding)) }
      .sorted { $0.1 > $1.1 }

    guard let best = scored.first else {
      conversationState = .listening
      return
    }
    let runnerUpSimilarity = scored.count > 1 ? scored[1].1 : -1
    let margin = best.1 - runnerUpSimilarity

    // Safe default: no confident match = no response.
    guard best.1 >= similarityThreshold, scored.count == 1 || margin >= ambiguityMargin else {
      conversationState = .listening
      return
    }

    playbackService.play(url: best.0.audioURL) { [weak self] in
      Task { @MainActor in
        guard let self, self.conversationState == .playing else { return }
        self.conversationState = self.wantsListening ? .listening : .idle
      }
    }
    conversationState = .playing
  }

  // MARK: - Tokenizing / phonetic matching

  private static func tokenize(_ text: String) -> [String] {
    text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
  }

  /// Phonetic code so misheard spellings (e.g. "Dovid", "Davad") still match the intended name ("David").
  private static func soundex(_ word: String) -> String {
    let letters = Array(word.uppercased().filter { $0.isLetter })
    guard let first = letters.first else { return "" }

    func digit(for char: Character) -> Character? {
      switch char {
      case "B", "F", "P", "V": return "1"
      case "C", "G", "J", "K", "Q", "S", "X", "Z": return "2"
      case "D", "T": return "3"
      case "L": return "4"
      case "M", "N": return "5"
      case "R": return "6"
      default: return nil
      }
    }

    var code = String(first)
    var previousDigit = digit(for: first)
    for char in letters.dropFirst() {
      let currentDigit = digit(for: char)
      if let currentDigit, currentDigit != previousDigit {
        code.append(currentDigit)
      }
      previousDigit = (char == "H" || char == "W") ? previousDigit : currentDigit
      if code.count == 4 { break }
    }
    while code.count < 4 { code.append("0") }
    return code
  }
}
