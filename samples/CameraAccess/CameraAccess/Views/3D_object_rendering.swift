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

extension Color {
  static let relivingBurgundy = Color(red: 119 / 255, green: 69 / 255, blue: 74 / 255)
  static let relivingLightSage = Color(red: 177 / 255, green: 182 / 255, blue: 161 / 255)
  static let relivingIvory = Color(red: 234 / 255, green: 224 / 255, blue: 208 / 255)
  static let relivingBeige = Color(red: 177 / 255, green: 182 / 255, blue: 161 / 255)
  static let relivingDarkSage = Color(red: 68 / 255, green: 68 / 255, blue: 68 / 255)
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

  init(
    id: UUID = UUID(),
    audioURL: URL,
    transcript: String,
    embedding: [Float]? = nil,
    title: String? = nil
  ) {
    self.id = id
    self.audioURL = audioURL
    self.transcript = transcript
    self.embedding = embedding
    self.title = title
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
      isDefault: true
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
      isDefault: true
    )
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

/// A category section (Objects or People) with a grid of captured photos and a + button to add more.
struct CategorySectionView: View {
  let title: String
  let category: MediaCategoryKind
  @Binding var items: [CapturedMediaItem]

  @State private var showSourceOptions = false
  @State private var activePickerSource: UIImagePickerController.SourceType?
  @State private var pendingImage: UIImage?
  @State private var selectedItem: CapturedMediaItem?

  private let columns = [GridItem(.adaptive(minimum: 72), spacing: 12)]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title)
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(Color.relivingBurgundy)

      LazyVGrid(columns: columns, spacing: 12) {
        Button {
          showSourceOptions = true
        } label: {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.relivingBeige)
            .frame(width: 72, height: 72)
            .overlay {
              Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.relivingDarkSage)
            }
        }
        .accessibilityLabel("Add \(title.lowercased()) photo")

        ForEach(items) { item in
          Button {
            selectedItem = item
          } label: {
            VStack(spacing: 5) {
              ZStack(alignment: .bottomTrailing) {
                Image(uiImage: item.photo)
                  .resizable()
                  .aspectRatio(contentMode: .fill)
                  .frame(width: 72, height: 72)
                  .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                  .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                      .stroke(Color.relivingBeige, lineWidth: 3)
                  }

                if item.usdzURL != nil {
                  Image(systemName: "cube.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(Circle().fill(Color.relivingBurgundy))
                    .padding(3)
                }
              }

              Text(item.name)
                .font(.system(size: 12))
                .foregroundStyle(Color.relivingDarkSage)
                .lineLimit(1)
                .frame(width: 72)
            }
          }
        }
      }
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

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 20) {
          Image(uiImage: item.photo)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxHeight: 220)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(8)
            .background(Color.relivingBeige, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

          if let usdzURL = item.usdzURL {
            USDZPreviewView(url: usdzURL)
              .frame(height: 320)
              .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
          } else {
            Text("3D model unavailable")
              .font(.system(size: 15))
              .foregroundStyle(.gray)
          }

          VStack(alignment: .leading, spacing: 10) {
            HStack {
              VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                  .font(.system(size: 20, weight: .semibold))
                Text(item.description.isEmpty ? "No description" : item.description)
                  .font(.system(size: 15))
                  .foregroundStyle(.secondary)
              }
              Spacer()
              if !item.isDefault {
                Button {
                  showEditor = true
                } label: {
                  Image(systemName: "pencil")
                    .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Edit and regenerate")
              }
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)

          if category == .person {
            VoiceMemoriesEditor(audioClips: $item.audioClips)
              .onChange(of: item.audioClips) { _, _ in
                onUpdate(item)
              }
          }
        }
        .padding(24)
      }
      .background(Color.relivingIvory)
      .navigationTitle("Details")
      .navigationBarTitleDisplayMode(.inline)
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
