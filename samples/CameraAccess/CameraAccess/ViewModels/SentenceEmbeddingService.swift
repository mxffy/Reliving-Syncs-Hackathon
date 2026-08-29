/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// SentenceEmbeddingService.swift
//
// Local, on-device sentence embeddings for semantic retrieval, using Apple's
// NaturalLanguage framework (NLEmbedding.sentenceEmbedding). This ships with the OS
// (no model download, no CoreML conversion, no network calls) and is a practical
// stand-in for a converted sentence-transformers model for a hackathon MVP.
//

import Foundation
@preconcurrency import NaturalLanguage

/// Computes local sentence embeddings and compares them via cosine similarity.
/// Never sends transcripts off-device.
final class SentenceEmbeddingService: Sendable {
  static let shared = SentenceEmbeddingService()

  private let embedding: NLEmbedding?

  init(language: NLLanguage = .english) {
    embedding = NLEmbedding.sentenceEmbedding(for: language)
  }

  /// Returns a normalized embedding vector for `text`, or nil if the model is unavailable.
  func embed(_ text: String) -> [Float]? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let vector = embedding?.vector(for: trimmed) else { return nil }
    return vector.map(Float.init)
  }

  /// Cosine similarity in [-1, 1]; higher means more semantically similar.
  static func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Float {
    guard lhs.count == rhs.count, !lhs.isEmpty else { return -1 }
    var dot: Float = 0
    var lhsMagnitude: Float = 0
    var rhsMagnitude: Float = 0
    for index in 0..<lhs.count {
      dot += lhs[index] * rhs[index]
      lhsMagnitude += lhs[index] * lhs[index]
      rhsMagnitude += rhs[index] * rhs[index]
    }
    let denominator = (lhsMagnitude.squareRoot() * rhsMagnitude.squareRoot())
    guard denominator > 0 else { return -1 }
    return dot / denominator
  }
}
