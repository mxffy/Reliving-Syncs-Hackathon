/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// Rendering-Description.swift
//
// Lets the user add a short description for a captured photo, optionally enhances
// the photo with OpenAI, then sends it to Meshy's Image to 3D API.
//

import AVFoundation
import QuickLook
import SwiftUI
import UIKit

private let descriptionCharacterLimit = 200

/// Progress checkpoints reported while a Meshy generation task runs.
enum GenerationStage {
  case connecting
  case rendering
}

enum ImageEnhancementStage {
  case connecting
  case recoloring
}

struct RenderingDescriptionView: View {
  let image: UIImage
  let category: MediaCategoryKind
  let existingItem: CapturedMediaItem?
  let enhancementPrompt: String?
  let onComplete: (CapturedMediaItem) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var name: String
  @State private var description: String
  @State private var isGenerating: Bool
  @State private var progressMessage: String
  @State private var hasStartedGeneration = false
  @State private var errorMessage: String?
  @State private var showError = false
  @State private var showDiscardConfirmation = false
  @State private var generatedItem: CapturedMediaItem?
  @State private var showSuccessCelebration = false
  @State private var successScale = 0.65
  @State private var successOpacity = 0.0
  @State private var audioClips: [MemoryAudioClip]

  init(
    image: UIImage,
    category: MediaCategoryKind,
    existingItem: CapturedMediaItem? = nil,
    enhancementPrompt: String? = nil,
    onComplete: @escaping (CapturedMediaItem) -> Void
  ) {
    self.image = image
    self.category = category
    self.existingItem = existingItem
    self.enhancementPrompt = enhancementPrompt
    self.onComplete = onComplete
    _name = State(initialValue: existingItem?.name ?? "")
    _description = State(initialValue: existingItem?.description ?? enhancementPrompt ?? "")
    _audioClips = State(initialValue: existingItem?.audioClips ?? [])
    _isGenerating = State(initialValue: true)
    _progressMessage = State(
      initialValue: enhancementPrompt == nil ? "Connecting to Meshy…" : "Connecting to OpenAI…"
    )
  }

  var body: some View {
    NavigationStack {
      Group {
        if let generatedItem {
          reviewView(for: generatedItem)
        } else {
          generationView
        }
      }
      .navigationTitle(showSuccessCelebration ? "Ready!" : generatedItem == nil ? "Creating \(category.title)" : "Preview")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarLeading) {
          Button {
            if generatedItem == nil {
              dismiss()
            } else {
              showDiscardConfirmation = true
            }
          } label: {
            Image(systemName: generatedItem == nil ? "chevron.left" : "xmark")
              .font(.system(size: 18, weight: .semibold))
          }
          .disabled(isGenerating)
        }
      }
      .tint(Color.relivingBurgundy)
      .alert("Couldn’t finish generation", isPresented: $showError) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(errorMessage ?? "Something went wrong. Please try again.")
      }
      .confirmationDialog(
        "Do you wish to discard this 3D model?",
        isPresented: $showDiscardConfirmation,
        titleVisibility: .visible
      ) {
        Button("Discard", role: .destructive) {
          discardGeneratedModel()
        }
        Button("Cancel", role: .cancel) {}
      }
    }
    .task {
      guard !hasStartedGeneration else { return }
      hasStartedGeneration = true
      generate()
    }
    .interactiveDismissDisabled(isGenerating)
  }

  private var generationView: some View {
    ZStack {
      Color.relivingIvory.ignoresSafeArea()

      VStack(spacing: 24) {
        if showSuccessCelebration {
          Image(.remiFinished)
            .resizable()
            .scaledToFit()
            .frame(width: 260, height: 260)
            .scaleEffect(successScale)
            .opacity(successOpacity)

          Text("Your memory is ready!")
            .font(.system(size: 23, weight: .bold))
            .foregroundStyle(Color.relivingBurgundy)
            .scaleEffect(successScale)
            .opacity(successOpacity)
        } else {
          LoopingLoadingVideoView()
            .frame(width: 230, height: 270)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

          if isGenerating {
            ProgressView()
              .tint(Color.relivingBurgundy)
              .scaleEffect(1.5)
              .padding(.top, 4)

            Text(progressMessage)
              .font(.system(size: 17, weight: .semibold))
              .foregroundStyle(Color.relivingBurgundy)
              .multilineTextAlignment(.center)
          } else {
            CustomButton(title: "Try Again", style: .primary, isDisabled: false) {
              generate()
            }
          }
        }
      }
      .padding(24)
    }
  }

  private func reviewView(for item: CapturedMediaItem) -> some View {
    ScrollView {
      VStack(spacing: 20) {
        VStack(spacing: 8) {
          TextField("Name this \(category.title.lowercased())", text: $name)
            .textFieldStyle(.plain)
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(Color.relivingBurgundy)
            .multilineTextAlignment(.center)
            .submitLabel(.done)
          Divider()
        }

        if let usdzURL = item.usdzURL {
          USDZPreviewView(url: usdzURL)
            .frame(height: 340)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(8)
            .background(Color.relivingBeige, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }

        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text("Description")
              .font(.system(size: 16, weight: .semibold))
              .foregroundStyle(Color.relivingBurgundy)
            Spacer()
            Image(systemName: "pencil")
              .foregroundStyle(Color.relivingDarkSage)
          }
          TextEditor(text: $description)
            .font(.system(size: 15))
            .frame(height: 100)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.relivingBeige))
            .onChange(of: description) { _, newValue in
              if newValue.count > descriptionCharacterLimit {
                description = String(newValue.prefix(descriptionCharacterLimit))
              }
            }
          Text("\(description.count)/\(descriptionCharacterLimit)")
            .font(.system(size: 12))
            .foregroundStyle(Color.relivingDarkSage)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }

        if category == .person {
          VoiceMemoriesEditor(audioClips: $audioClips)
        }

        CustomButton(title: "Use", style: .primary, isDisabled: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
          onComplete(
            CapturedMediaItem(
              id: item.id,
              photo: item.photo,
              name: name.trimmingCharacters(in: .whitespacesAndNewlines),
              description: description.trimmingCharacters(in: .whitespacesAndNewlines),
              usdzURL: item.usdzURL,
              audioClips: audioClips
            )
          )
          dismiss()
        }
      }
      .padding(24)
    }
    .background(Color.relivingIvory)
  }

  private func discardGeneratedModel() {
    if let usdzURL = generatedItem?.usdzURL {
      try? FileManager.default.removeItem(at: usdzURL)
    }
    dismiss()
  }

  private func generatedItem(with modelURL: URL, photo: UIImage) -> CapturedMediaItem {
    CapturedMediaItem(
      id: existingItem?.id ?? UUID(),
      photo: photo,
      name: name.trimmingCharacters(in: .whitespacesAndNewlines),
      description: description.trimmingCharacters(in: .whitespacesAndNewlines),
      usdzURL: modelURL
    )
  }

  private func generate() {
    isGenerating = true
    showSuccessCelebration = false
    successScale = 0.65
    successOpacity = 0
    progressMessage = enhancementPrompt == nil ? "Connecting to Meshy…" : "Connecting to OpenAI…"
    Task {
      do {
        let finalImage: UIImage
        if let enhancementPrompt {
          finalImage = try await OpenAIImageClient.shared.enhance(
            image: image,
            prompt: enhancementPrompt,
            onStageChange: { stage in
              Task { @MainActor in
                progressMessage = message(for: stage)
              }
            }
          )
          await MainActor.run {
            progressMessage = "Connecting to Meshy…"
          }
        } else {
          finalImage = image
        }

        let modelURL = try await MeshyClient.shared.generate3DModel(
          image: finalImage,
          onStageChange: { stage in
            Task { @MainActor in
              progressMessage = message(for: stage)
            }
          }
        )
        let completedItem = generatedItem(with: modelURL, photo: finalImage)
        await MainActor.run {
          isGenerating = false
          showSuccessCelebration = true
          withAnimation(.spring(response: 0.55, dampingFraction: 0.62)) {
            successScale = 1
            successOpacity = 1
          }
        }
        try await Task.sleep(nanoseconds: 1_250_000_000)
        await MainActor.run {
          generatedItem = completedItem
          showSuccessCelebration = false
        }
      } catch {
        await MainActor.run {
          isGenerating = false
          errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
          showError = true
        }
      }
    }
  }

  private func message(for stage: GenerationStage) -> String {
    switch stage {
    case .connecting:
      return "Connecting to Meshy…"
    case .rendering:
      return category == .object ? "Rendering your 3D object…" : "Rendering your 3D persona…"
    }
  }

  private func message(for stage: ImageEnhancementStage) -> String {
    switch stage {
    case .connecting:
      return "Connecting to OpenAI…"
    case .recoloring:
      return "Recoloring with OpenAI…"
    }
  }
}

private struct LoopingLoadingVideoView: UIViewRepresentable {
  func makeUIView(context: Context) -> LoopingVideoUIView {
    LoopingVideoUIView()
  }

  func updateUIView(_ uiView: LoopingVideoUIView, context: Context) {}
}

private final class LoopingVideoUIView: UIView {
  private let player = AVQueuePlayer()
  private var looper: AVPlayerLooper?

  override class var layerClass: AnyClass { AVPlayerLayer.self }

  private var playerLayer: AVPlayerLayer {
    layer as! AVPlayerLayer
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = UIColor(red: 234 / 255, green: 224 / 255, blue: 208 / 255, alpha: 1)
    playerLayer.player = player
    playerLayer.videoGravity = .resizeAspect

    if let videoURL = Bundle.main.url(forResource: "RemiLoading", withExtension: "mp4") {
      let item = AVPlayerItem(url: videoURL)
      looper = AVPlayerLooper(player: player, templateItem: item)
      player.isMuted = true
      player.play()
    }
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window == nil {
      player.pause()
    } else {
      player.play()
    }
  }
}

enum OpenAIImageError: LocalizedError {
  case missingAPIKey
  case invalidImage
  case invalidResponse
  case requestFailed(String)

  var errorDescription: String? {
    switch self {
    case .missingAPIKey:
      return "Missing OpenAI API key. Add OPENAI_API_KEY to Secrets.xcconfig."
    case .invalidImage:
      return "Couldn't process the selected photo."
    case .invalidResponse:
      return "OpenAI didn't return an enhanced image."
    case .requestFailed(let message):
      return message
    }
  }
}

final class OpenAIImageClient {
  static let shared = OpenAIImageClient()

  private let editsURL = URL(string: "https://api.openai.com/v1/images/edits")!

  private var apiKey: String? {
    Bundle.main.object(forInfoDictionaryKey: "OpenAIAPIKey") as? String
  }

  func enhance(
    image: UIImage,
    prompt: String,
    onStageChange: @escaping (ImageEnhancementStage) -> Void
  ) async throws -> UIImage {
    onStageChange(.connecting)
    guard let apiKey, !apiKey.isEmpty else {
      throw OpenAIImageError.missingAPIKey
    }
    guard let imageData = image.pngData() else {
      throw OpenAIImageError.invalidImage
    }

    let boundary = "Boundary-\(UUID().uuidString)"
    var request = URLRequest(url: editsURL, timeoutInterval: 180)
    request.httpMethod = "POST"
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.httpBody = multipartBody(
      boundary: boundary,
      imageData: imageData,
      prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    )

    let data: Data
    let response: URLResponse
    do {
      onStageChange(.recoloring)
      (data, response) = try await URLSession.shared.data(for: request)
    } catch {
      throw OpenAIImageError.requestFailed("Couldn't connect to OpenAI. Check your internet connection and try again.")
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      throw OpenAIImageError.invalidResponse
    }
    guard (200...299).contains(httpResponse.statusCode) else {
      let apiError = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data)
      throw OpenAIImageError.requestFailed(apiError?.error.message ?? "OpenAI couldn't enhance this image.")
    }

    let result = try JSONDecoder().decode(OpenAIImageResponse.self, from: data)
    guard
      let encodedImage = result.data.first?.b64JSON,
      let enhancedData = Data(base64Encoded: encodedImage),
      let enhancedImage = UIImage(data: enhancedData)
    else {
      throw OpenAIImageError.invalidResponse
    }
    return enhancedImage
  }

  private func multipartBody(boundary: String, imageData: Data, prompt: String) -> Data {
    var body = Data()

    func appendField(name: String, value: String) {
      body.append(Data("--\(boundary)\r\n".utf8))
      body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
      body.append(Data("\(value)\r\n".utf8))
    }

    appendField(name: "model", value: "gpt-image-1.5")
    appendField(name: "quality", value: "medium")
    appendField(name: "output_format", value: "png")
    appendField(name: "prompt", value: prompt)
    body.append(Data("--\(boundary)\r\n".utf8))
    body.append(Data("Content-Disposition: form-data; name=\"image[]\"; filename=\"source.png\"\r\n".utf8))
    body.append(Data("Content-Type: image/png\r\n\r\n".utf8))
    body.append(imageData)
    body.append(Data("\r\n--\(boundary)--\r\n".utf8))
    return body
  }
}

private struct OpenAIImageResponse: Decodable {
  let data: [ImageData]

  struct ImageData: Decodable {
    let b64JSON: String?

    enum CodingKeys: String, CodingKey {
      case b64JSON = "b64_json"
    }
  }
}

private struct OpenAIErrorResponse: Decodable {
  let error: APIError

  struct APIError: Decodable {
    let message: String
  }
}

/// Inline USDZ viewer backed by QuickLook, supporting pan/zoom/rotate gestures.
struct USDZPreviewView: UIViewControllerRepresentable {
  let url: URL

  func makeUIViewController(context: Context) -> QLPreviewController {
    let controller = QLPreviewController()
    controller.dataSource = context.coordinator
    return controller
  }

  func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
    uiViewController.reloadData()
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(url: url)
  }

  final class Coordinator: NSObject, QLPreviewControllerDataSource {
    let url: URL

    init(url: URL) {
      self.url = url
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
      url as NSURL
    }
  }
}

enum MeshyError: LocalizedError {
  case missingAPIKey
  case invalidImage
  case invalidResponse
  case connectionFailed
  case taskFailed(String)

  var errorDescription: String? {
    switch self {
    case .missingAPIKey:
      return "Missing Meshy API key. Add MESHY_3D_RENDERING_API_KEY to Secrets.xcconfig."
    case .invalidImage:
      return "Couldn't process the selected photo."
    case .invalidResponse:
      return "Unexpected response from Meshy."
    case .connectionFailed:
      return "Couldn't connect to Meshy. Check your internet connection and try again."
    case .taskFailed(let message):
      return message
    }
  }
}

/// Client for Meshy's Image to 3D API. See https://docs.meshy.ai/en/api/image-to-3d
final class MeshyClient {
  static let shared = MeshyClient()

  private let baseURL = URL(string: "https://api.meshy.ai/openapi/v1/image-to-3d")!
  private let pollInterval: UInt64 = 3_000_000_000

  private var apiKey: String? {
    Bundle.main.object(forInfoDictionaryKey: "Meshy3DRenderingAPIKey") as? String
  }

  /// Sends the photo to Meshy, waits for completion, and downloads the resulting USDZ
  /// into the app's "3D-modelled-objects" folder.
  func generate3DModel(image: UIImage, onStageChange: @escaping (GenerationStage) -> Void) async throws -> URL {
    guard let apiKey, !apiKey.isEmpty else {
      throw MeshyError.missingAPIKey
    }
    guard let imageData = image.jpegData(compressionQuality: 0.85) else {
      throw MeshyError.invalidImage
    }

    let body: [String: Any] = [
      "image_url": "data:image/jpeg;base64,\(imageData.base64EncodedString())",
      "target_formats": ["usdz"],
      "should_texture": true,
      "image_enhancement": true,
    ]

    onStageChange(.connecting)
    let taskId = try await createTask(body: body, apiKey: apiKey)
    onStageChange(.rendering)
    let usdzURLString = try await pollUntilComplete(taskId: taskId, apiKey: apiKey)
    return try await downloadModel(from: usdzURLString, taskId: taskId)
  }

  private func createTask(body: [String: Any], apiKey: String) async throws -> String {
    var request = URLRequest(url: baseURL)
    request.httpMethod = "POST"
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await performRequest(request)
    guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
      throw MeshyError.invalidResponse
    }
    return try JSONDecoder().decode(CreateTaskResponse.self, from: data).result
  }

  private func pollUntilComplete(taskId: String, apiKey: String) async throws -> String {
    let statusURL = baseURL.appendingPathComponent(taskId)
    while true {
      var request = URLRequest(url: statusURL)
      request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

      let (data, response) = try await performRequest(request)
      guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
        throw MeshyError.invalidResponse
      }
      let task = try JSONDecoder().decode(TaskStatusResponse.self, from: data)

      switch task.status {
      case "SUCCEEDED":
        guard let usdzURL = task.modelUrls?.usdz else { throw MeshyError.invalidResponse }
        return usdzURL
      case "FAILED", "CANCELED":
        throw MeshyError.taskFailed(task.taskError?.message ?? "Generation failed")
      default:
        try await Task.sleep(nanoseconds: pollInterval)
      }
    }
  }

  private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
    do {
      return try await URLSession.shared.data(for: request)
    } catch {
      throw MeshyError.connectionFailed
    }
  }

  private func downloadModel(from urlString: String, taskId: String) async throws -> URL {
    guard let remoteURL = URL(string: urlString) else { throw MeshyError.invalidResponse }
    let tempURL: URL
    do {
      (tempURL, _) = try await URLSession.shared.download(from: remoteURL)
    } catch {
      throw MeshyError.connectionFailed
    }

    let folder = try modelsFolder()
    let destination = folder.appendingPathComponent("\(taskId).usdz")
    if FileManager.default.fileExists(atPath: destination.path) {
      try FileManager.default.removeItem(at: destination)
    }
    try FileManager.default.moveItem(at: tempURL, to: destination)
    return destination
  }

  /// The "3D-modelled-objects" folder inside the app's Documents directory.
  private func modelsFolder() throws -> URL {
    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let folder = documents.appendingPathComponent("3D-modelled-objects", isDirectory: true)
    if !FileManager.default.fileExists(atPath: folder.path) {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    return folder
  }
}

private struct CreateTaskResponse: Decodable {
  let result: String
}

private struct TaskStatusResponse: Decodable {
  let status: String
  let modelUrls: ModelURLs?
  let taskError: TaskError?

  enum CodingKeys: String, CodingKey {
    case status
    case modelUrls = "model_urls"
    case taskError = "task_error"
  }

  struct ModelURLs: Decodable {
    let usdz: String?
  }

  struct TaskError: Decodable {
    let message: String?
  }
}
