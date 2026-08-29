/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// SettingsView.swift
//
// Profile screen showing the current user and the Objects/People recognition categories.
//

import SwiftUI

struct SettingsView: View {
  @Environment(\.dismiss) var dismiss
  @State private var mediaStore = MediaCategoryStore.shared

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 24) {
          VStack(spacing: 12) {
            Image(.grandmaPfp)
              .resizable()
              .aspectRatio(contentMode: .fill)
              .frame(width: 120, height: 120)
              .clipShape(Circle())

            Text("Mary Bernard")
              .font(.system(size: 22, weight: .semibold))
              .foregroundStyle(.black)

            Text("Age: 68")
              .font(.system(size: 16))
              .foregroundStyle(.gray)
          }
          .padding(.top, 12)

          VStack(spacing: 24) {
            CategorySectionView(title: "Objects", photos: $mediaStore.objectPhotos)
            CategorySectionView(title: "People", photos: $mediaStore.peoplePhotos)
          }
        }
        .padding(.all, 24)
      }
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarLeading) {
          Button {
            dismiss()
          } label: {
            Image(systemName: "chevron.left")
              .font(.system(size: 18, weight: .semibold))
          }
          .accessibilityLabel("Back")
        }
      }
    }
  }
}
