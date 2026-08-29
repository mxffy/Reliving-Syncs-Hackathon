/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// 3D_object_rendering.swift
//
// Media capture for the Objects/People categories on the Settings screen.
// Currently just captures and displays photos per category; 3D rendering logic to come later.
//

import CoreImage
import SwiftUI
import UIKit

// Vintage instant-film / photo-album palette. Kept as the same token names other screens already
// depend on, but retuned to a richer, warmer set of hues (deep wine, warm parchment, kraft tan,
// sage green, warm charcoal ink) instead of the previous flatter sage/gray combo — note `relivingBeige`
// used to be an exact duplicate of `relivingLightSage`, which was part of why things read as flat.
extension Color {
  /// Deep wine — primary accent, headlines, active states.
  static let relivingBurgundy = Color(red: 0.42, green: 0.20, blue: 0.24)
  /// Muted sage green — secondary accent (echoes the Remi mascot's shell).
  static let relivingLightSage = Color(red: 0.69, green: 0.71, blue: 0.63)
  /// Warm parchment — primary background.
  static let relivingIvory = Color(red: 0.969, green: 0.925, blue: 0.847)
  /// Kraft-paper tan — card/chip fills. Deliberately distinct from `relivingLightSage` now.
  static let relivingBeige = Color(red: 0.80, green: 0.74, blue: 0.62)
  /// Warm near-black ink — body text on light backgrounds (replaces the old cold gray).
  static let relivingDarkSage = Color(red: 0.24, green: 0.19, blue: 0.17)
}

/// Which recognition category a captured photo belongs to.
enum MediaCategoryKind {
  case object
  case person

  var title: String {
    switch self {
    case .object: return "Object"
    case .person: return "Person"
    }
  }

  /// Placeholder guidance shown in the description field on the Rendering Description screen.
  var descriptionPlaceholder: String {
    switch self {
    case .object:
      return "Describe the object’s appearance, including colour, material, patterns, style, and unique features."
    case .person:
      return "Describe the person’s appearance, include clothing, hairstyle, approximate age, accessories, pose, and any distinctive visual details."
    }
  }
}

/// A real recorded memory clip belonging to a persona. Never synthesized — only authentic uploaded
/// or recorded audio is ever played back. `embedding` is the precomputed sentence embedding of
/// `transcript`, used for semantic retrieval against live speech.
struct MemoryAudioClip: Identifiable, Equatable {
  let id: UUID
  var audioURL: URL
  var transcript: String
  var embedding: [Float]?
  var title: String?
  /// Optional word that, when heard aloud while this clip's object is in view, plays this
  /// clip directly (independent of the semantic transcript-similarity retrieval).
  var triggerWord: String?

  init(
    id: UUID = UUID(),
    audioURL: URL,
    transcript: String,
    embedding: [Float]? = nil,
    title: String? = nil,
    triggerWord: String? = nil
  ) {
    self.id = id
    self.audioURL = audioURL
    self.transcript = transcript
    self.embedding = embedding
    self.title = title
    self.triggerWord = triggerWord
  }
}

/// A captured photo plus its generated 3D model, once available.
struct CapturedMediaItem: Identifiable {
  let id: UUID
  let photo: UIImage
  var name: String
  var description: String
  var usdzURL: URL?
  var isDefault = false
  var audioClips: [MemoryAudioClip] = []
}

/// Holds captured photos for each recognition category.
/// Shared singleton so items persist across Settings being dismissed and reopened.
@Observable
final class MediaCategoryStore {
  static let shared = MediaCategoryStore()

  var objectItems: [CapturedMediaItem]
  var peopleItems: [CapturedMediaItem]

  private init(bundle: Bundle = .main) {
    objectItems = [Self.telephoneItem(bundle: bundle), Self.vaseItem(bundle: bundle)].compactMap { $0 }
    peopleItems = [Self.davidItem(bundle: bundle), Self.aliceItem(bundle: bundle)].compactMap { $0 }
  }

  private static func telephoneItem(bundle: Bundle) -> CapturedMediaItem? {
    guard
      let modelURL = bundle.url(forResource: "Telephone", withExtension: "usdz"),
      let photoURL = bundle.url(forResource: "Telephone", withExtension: "png"),
      let thumbnail = UIImage(contentsOfFile: photoURL.path)
    else {
      return nil
    }
    return CapturedMediaItem(
      id: UUID(uuidString: "4E4A786B-7911-44B7-95D6-997B6AD2DD35")!,
      photo: thumbnail,
      name: "Telephone",
      description: "Dusty vintage rotary telephone",
      usdzURL: modelURL,
      isDefault: true,
      audioClips: defaultTriggerAudioClip(bundle: bundle, resource: "telephone", title: "Telephone memory", triggerWord: "Mark")
    )
  }

  private static func vaseItem(bundle: Bundle) -> CapturedMediaItem? {
    guard
      let modelURL = bundle.url(forResource: "VASE_VICTORIAN_ERA", withExtension: "usdz"),
      let photoURL = bundle.url(forResource: "VASE_VICTORIAN_ERA", withExtension: "png"),
      let thumbnail = UIImage(contentsOfFile: photoURL.path)
    else {
      return nil
    }
    return CapturedMediaItem(
      id: UUID(uuidString: "9D3C7C7B-6A3F-4B3E-9C8F-2B8E5A6C1D2E")!,
      photo: thumbnail,
      name: "Vase",
      description: "Ornate Victorian-era porcelain vase",
      usdzURL: modelURL,
      isDefault: true,
      audioClips: defaultTriggerAudioClip(bundle: bundle, resource: "vase", title: "Vase memory", triggerWord: "Mark")
    )
  }

  /// A single bundled clip identified purely by its trigger word, with no transcript/embedding needed.
  private static func defaultTriggerAudioClip(bundle: Bundle, resource: String, title: String, triggerWord: String) -> [MemoryAudioClip] {
    guard let audioURL = bundle.url(forResource: resource, withExtension: "mp3") else { return [] }
    return [MemoryAudioClip(audioURL: audioURL, transcript: "", title: title, triggerWord: triggerWord)]
  }

  private static func davidItem(bundle: Bundle) -> CapturedMediaItem? {
    guard
      let modelURL = bundle.url(forResource: "Old_man_Spice_animated", withExtension: "usdz"),
      let photoURL = bundle.url(forResource: "david_photograph", withExtension: "png"),
      let photo = UIImage(contentsOfFile: photoURL.path)
    else {
      return nil
    }
    return CapturedMediaItem(
      id: UUID(uuidString: "47B3D36C-B18D-41DA-B58D-03B6285DC656")!,
      photo: photo,
      name: "David",
      description: "David",
      usdzURL: modelURL,
      isDefault: true,
      audioClips: defaultDavidAudioClips(bundle: bundle)
    )
  }

  /// Sample voice memories bundled for the David persona, with embeddings precomputed once at launch.
  private static func defaultDavidAudioClips(bundle: Bundle) -> [MemoryAudioClip] {
    let transcriptsByResource: [(resource: String, transcript: String, title: String)] = [
      ("telephone", "That telephone has been gathering dust for a bit now, I better dust it off", "The old telephone"),
      ("golf", "Oh I've had quite a long day out playing golf with Jerred and his brother", "Golf day"),
    ]
    return transcriptsByResource.compactMap { entry in
      guard let audioURL = bundle.url(forResource: entry.resource, withExtension: "mp3") else { return nil }
      let embedding = SentenceEmbeddingService.shared.embed(entry.transcript)
      return MemoryAudioClip(
        audioURL: audioURL,
        transcript: entry.transcript,
        embedding: embedding,
        title: entry.title
      )
    }
  }

  private static func aliceItem(bundle: Bundle) -> CapturedMediaItem? {
    guard
      let modelURL = bundle.url(forResource: "Angelica", withExtension: "usdz"),
      let photoURL = bundle.url(forResource: "alice_new", withExtension: "png"),
      let photo = UIImage(contentsOfFile: photoURL.path)
    else {
      return nil
    }
    return CapturedMediaItem(
      id: UUID(uuidString: "C1A11CE0-2A1D-4B7E-9F0A-6D1E9B8C2F3A")!,
      photo: photo,
      name: "Alice",
      description: "Alice",
      usdzURL: modelURL,
      isDefault: true,
      audioClips: defaultAliceAudioClips(bundle: bundle)
    )
  }

  /// Sample voice memories bundled for the Alice persona, with embeddings precomputed once at launch.
  private static func defaultAliceAudioClips(bundle: Bundle) -> [MemoryAudioClip] {
    let transcriptsByResource: [(resource: String, transcript: String, title: String)] = [
      ("uni", "Hi Grandma! Uni's been really busy lately, but I'm doing well. I can't wait to tell you all about it when I visit.", "Busy at uni"),
      ("garden", "Grandma, I was thinking about your garden today. I still remember helping you water the roses when I was little.", "Your garden"),
    ]
    return transcriptsByResource.compactMap { entry in
      guard let audioURL = bundle.url(forResource: entry.resource, withExtension: "mp3") else { return nil }
      let embedding = SentenceEmbeddingService.shared.embed(entry.transcript)
      return MemoryAudioClip(
        audioURL: audioURL,
        transcript: entry.transcript,
        embedding: embedding,
        title: entry.title
      )
    }
  }
}

/// UIImagePickerController bridge supporting either the camera or the photo library.
struct CategoryImagePickerView: UIViewControllerRepresentable {
  let sourceType: UIImagePickerController.SourceType
  let onImagePicked: (UIImage) -> Void

  func makeUIViewController(context: Context) -> UIImagePickerController {
    let picker = UIImagePickerController()
    picker.delegate = context.coordinator
    picker.sourceType = sourceType
    picker.mediaTypes = ["public.image"]
    return picker
  }

  func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    let parent: CategoryImagePickerView

    init(_ parent: CategoryImagePickerView) {
      self.parent = parent
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
      if let image = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage {
        parent.onImagePicked(image)
      }
      picker.dismiss(animated: true)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
      picker.dismiss(animated: true)
    }
  }
}

/// A category section (Objects or People) shown as a horizontal, old-film-style filmstrip of
/// polaroid photos, with a dashed "add" card always visible as the first item so it's never
/// hidden behind a scroll.
struct CategorySectionView: View {
  let title: String
  let category: MediaCategoryKind
  @Binding var items: [CapturedMediaItem]

  @State private var showSourceOptions = false
  @State private var activePickerSource: UIImagePickerController.SourceType?
  @State private var pendingImage: UIImage?
  @State private var selectedItem: CapturedMediaItem?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(.system(size: 19, weight: .semibold, design: .rounded))
        .foregroundStyle(Color.relivingBurgundy)

      VStack(spacing: 4) {
        FilmSprocketStrip(tint: .relivingBurgundy)

        ScrollView(.horizontal, showsIndicators: false) {
          HStack(alignment: .top, spacing: 16) {
            Button {
              showSourceOptions = true
            } label: {
              PolaroidAddCard()
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Add \(title.lowercased()) photo")

            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
              Button {
                selectedItem = item
              } label: {
                PolaroidThumbnail(
                  image: item.photo,
                  caption: item.name,
                  rotationDegrees: index.isMultiple(of: 2) ? -3.5 : 3.5
                )
              }
              .buttonStyle(.pressable)
            }
          }
          .padding(.horizontal, 4)
          .padding(.vertical, 10)
        }

        FilmSprocketStrip(tint: .relivingBurgundy)
      }
      .padding(.vertical, 6)
      .background(Color.relivingBeige.opacity(0.35), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    .confirmationDialog("Add photo", isPresented: $showSourceOptions, titleVisibility: .visible) {
      if UIImagePickerController.isSourceTypeAvailable(.camera) {
        Button("Take Photo") {
          activePickerSource = .camera
        }
      }
      Button("Choose from Photos") {
        activePickerSource = .photoLibrary
      }
      Button("Cancel", role: .cancel) {}
    }
    .sheet(item: $activePickerSource) { source in
      CategoryImagePickerView(sourceType: source) { image in
        activePickerSource = nil
        // Objects photographed with the camera are captured in black and white.
        pendingImage = category == .object && source == .camera ? monochromeImage(from: image) : image
      }
      .ignoresSafeArea()
    }
    .sheet(isPresented: Binding(
      get: { pendingImage != nil },
      set: { isPresented in
        if !isPresented { pendingImage = nil }
      }
    )) {
      if let pendingImage {
        ImagePreparationFlow(image: pendingImage, category: category) { item in
          items.append(item)
        }
      }
    }
    .sheet(item: $selectedItem) { item in
      CapturedItemDetailView(
        item: item,
        category: category,
        onUpdate: { updateItem($0) },
        onDelete: item.isDefault ? nil : { deleteItem(item) }
      )
    }
  }

  private func updateItem(_ updatedItem: CapturedMediaItem) {
    guard let index = items.firstIndex(where: { $0.id == updatedItem.id }) else { return }
    items[index] = updatedItem
    selectedItem = updatedItem
  }

  private func monochromeImage(from image: UIImage) -> UIImage {
    guard
      let ciImage = CIImage(image: image),
      let filter = CIFilter(name: "CIPhotoEffectMono")
    else {
      return image
    }
    filter.setValue(ciImage, forKey: kCIInputImageKey)
    guard
      let outputImage = filter.outputImage,
      let cgImage = CIContext().createCGImage(outputImage, from: outputImage.extent)
    else {
      return image
    }
    return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
  }

  private func deleteItem(_ item: CapturedMediaItem) {
    if let usdzURL = item.usdzURL {
      try? FileManager.default.removeItem(at: usdzURL)
    }
    items.removeAll { $0.id == item.id }
  }
}

/// Detail screen for a captured item: the original photo, its 3D model preview, and a delete action.
struct CapturedItemDetailView: View {
  @State var item: CapturedMediaItem
  let category: MediaCategoryKind
  let onUpdate: (CapturedMediaItem) -> Void
  let onDelete: (() -> Void)?

  @Environment(\.dismiss) private var dismiss
  @State private var showDeleteConfirmation = false
  @State private var showEditor = false
  @State private var contentVisible = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 22) {
          VStack(spacing: 8) {
            Image(uiImage: item.photo)
              .resizable()
              .aspectRatio(contentMode: .fit)
              .frame(maxHeight: 220)
              .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
          }
          .padding(10)
          .padding(.bottom, 18)
          .background(Color.relivingCream, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
          .shadow(color: Color.relivingInk.opacity(0.28), radius: 10, x: 0, y: 6)
          .rotationEffect(.degrees(-1.5))

          if let usdzURL = item.usdzURL {
            USDZPreviewView(url: usdzURL)
              .frame(height: 320)
              .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
              .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                  .stroke(Color.relivingBeige, lineWidth: 1.5)
              }
          } else {
            Text("3D model unavailable")
              .font(.system(size: 15))
              .foregroundStyle(Color.relivingDarkSage.opacity(0.6))
          }

          VStack(alignment: .leading, spacing: 10) {
            HStack {
              VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                  .font(.system(size: 21, weight: .semibold, design: .rounded))
                  .foregroundStyle(Color.relivingBurgundy)
                Text(item.description.isEmpty ? "No description" : item.description)
                  .font(.system(size: 15))
                  .foregroundStyle(Color.relivingDarkSage.opacity(0.7))
              }
              Spacer()
              if !item.isDefault {
                Button {
                  showEditor = true
                } label: {
                  Image(systemName: "pencil")
                    .foregroundStyle(Color.relivingBurgundy)
                    .frame(width: 44, height: 44)
                    .background(Color.relivingCream, in: Circle())
                    .shadow(color: Color.relivingInk.opacity(0.2), radius: 4, y: 2)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Edit and regenerate")
              }
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(16)
          .background(Color.relivingCream.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

          VoiceMemoriesEditor(audioClips: $item.audioClips)
            .onChange(of: item.audioClips) { _, _ in
              onUpdate(item)
            }
        }
        .padding(24)
        .opacity(contentVisible ? 1 : 0)
        .offset(y: contentVisible ? 0 : 12)
        .animation(.easeOut(duration: 0.4), value: contentVisible)
      }
      .background(Color.relivingPaperGradient)
      .navigationTitle("Details")
      .navigationBarTitleDisplayMode(.inline)
      .onAppear {
        withAnimation { contentVisible = true }
      }
      .toolbar {
        ToolbarItem(placement: .navigationBarLeading) {
          Button {
            dismiss()
          } label: {
            Image(systemName: "chevron.left")
              .font(.system(size: 18, weight: .semibold))
          }
        }
        if onDelete != nil {
          ToolbarItem(placement: .navigationBarTrailing) {
            Button(role: .destructive) {
              showDeleteConfirmation = true
            } label: {
              Image(systemName: "trash")
            }
          }
        }
      }
      .tint(Color.relivingBurgundy)
      .confirmationDialog("Delete this item?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
        Button("Delete", role: .destructive) {
          onDelete?()
          dismiss()
        }
        Button("Cancel", role: .cancel) {}
      }
      .sheet(isPresented: $showEditor) {
        ImagePreparationFlow(image: item.photo, category: category, existingItem: item) { updatedItem in
          if let oldURL = item.usdzURL, oldURL != updatedItem.usdzURL {
            try? FileManager.default.removeItem(at: oldURL)
          }
          item = updatedItem
          onUpdate(updatedItem)
          showEditor = false
        }
      }
    }
  }
}

private enum ImagePreparationStep {
  case choice
  case prompt
  case render(String?)
}

struct ImagePreparationFlow: View {
  let image: UIImage
  let category: MediaCategoryKind
  let existingItem: CapturedMediaItem?
  let onComplete: (CapturedMediaItem) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var step: ImagePreparationStep = .choice
  @State private var enhancementPrompt = ""

  init(
    image: UIImage,
    category: MediaCategoryKind,
    existingItem: CapturedMediaItem? = nil,
    onComplete: @escaping (CapturedMediaItem) -> Void
  ) {
    self.image = image
    self.category = category
    self.existingItem = existingItem
    self.onComplete = onComplete
  }

  var body: some View {
    switch step {
    case .choice:
      NavigationStack {
        VStack(spacing: 24) {
          Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxHeight: 320)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(8)
            .background(Color.relivingBeige, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

          Text("Would you like to recolour or improve this image?")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(Color.relivingBurgundy)
            .multilineTextAlignment(.center)

          VStack(spacing: 12) {
            CustomButton(title: "Yes", style: .primary, isDisabled: false) {
              step = .prompt
            }
            Button {
              step = .render(nil)
            } label: {
              Text("No")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.relivingBurgundy)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Color.relivingLightSage, in: Capsule())
            }
          }

          Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.relivingIvory)
        .navigationTitle(existingItem == nil ? "New \(category.title)" : "Regenerate")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .navigationBarLeading) {
            Button {
              dismiss()
            } label: {
              Image(systemName: "xmark")
            }
          }
        }
        .tint(Color.relivingBurgundy)
      }

    case .prompt:
      NavigationStack {
        VStack(alignment: .leading, spacing: 20) {
          Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: 240)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(8)
            .background(Color.relivingBeige, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

          Text("How should this image be improved?")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(Color.relivingBurgundy)

          VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
              if enhancementPrompt.isEmpty {
                Text("Recolour this so bike is teal and image is less blurry")
                  .font(.system(size: 15))
                  .foregroundStyle(.gray)
                  .padding(.horizontal, 4)
                  .padding(.vertical, 8)
                  .allowsHitTesting(false)
              }
              TextEditor(text: $enhancementPrompt)
                .font(.system(size: 15))
                .frame(height: 120)
                .scrollContentBackground(.hidden)
                .onChange(of: enhancementPrompt) { _, newValue in
                  if newValue.count > 200 {
                    enhancementPrompt = String(newValue.prefix(200))
                  }
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.relivingBeige))

            Text("\(enhancementPrompt.count)/200")
              .font(.system(size: 12))
              .foregroundStyle(Color.relivingDarkSage)
              .frame(maxWidth: .infinity, alignment: .trailing)
          }

          Spacer()

          CustomButton(
            title: "Continue",
            style: .primary,
            isDisabled: enhancementPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          ) {
            step = .render(enhancementPrompt)
          }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.relivingIvory)
        .navigationTitle("Improve Image")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .navigationBarLeading) {
            Button {
              step = .choice
            } label: {
              Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .semibold))
            }
          }
        }
        .tint(Color.relivingBurgundy)
      }

    case .render(let prompt):
      RenderingDescriptionView(
        image: image,
        category: category,
        existingItem: existingItem,
        enhancementPrompt: prompt,
        onComplete: onComplete
      )
    }
  }
}

extension UIImagePickerController.SourceType: @retroactive Identifiable {
  public var id: Int { rawValue }
}
