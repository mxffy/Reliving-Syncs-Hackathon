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

import SwiftUI
import UIKit

/// Holds captured photos for each recognition category. Will feed the 3D rendering pipeline later.
/// Shared singleton so photos persist across Settings being dismissed and reopened.
@Observable
final class MediaCategoryStore {
  static let shared = MediaCategoryStore()

  var objectPhotos: [UIImage] = []
  var peoplePhotos: [UIImage] = []
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
  @Binding var photos: [UIImage]

  @State private var showSourceOptions = false
  @State private var activePickerSource: UIImagePickerController.SourceType?

  private let columns = [GridItem(.adaptive(minimum: 72), spacing: 12)]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title)
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(.black)

      LazyVGrid(columns: columns, spacing: 12) {
        Button {
          showSourceOptions = true
        } label: {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.gray.opacity(0.15))
            .frame(width: 72, height: 72)
            .overlay {
              Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.gray)
            }
        }
        .accessibilityLabel("Add \(title.lowercased()) photo")

        ForEach(Array(photos.enumerated()), id: \.offset) { _, photo in
          Image(uiImage: photo)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        photos.append(image)
      }
      .ignoresSafeArea()
    }
  }
}

extension UIImagePickerController.SourceType: @retroactive Identifiable {
  public var id: Int { rawValue }
}
