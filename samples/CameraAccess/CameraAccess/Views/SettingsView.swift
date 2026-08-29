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
  @State private var headerVisible = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 28) {
          VStack(spacing: 12) {
            Image(.grandmaPfp)
              .resizable()
              .aspectRatio(contentMode: .fill)
              .frame(width: 120, height: 120)
              .clipShape(Circle())
              .overlay {
                Circle().stroke(Color.relivingCream, lineWidth: 5)
              }
              .overlay {
                Circle().stroke(Color.relivingBurgundy.opacity(0.6), lineWidth: 1.5)
              }
              .shadow(color: Color.relivingInk.opacity(0.25), radius: 10, y: 5)

            Text("Mary Bernard")
              .font(.system(size: 22, weight: .semibold, design: .rounded))
              .foregroundStyle(Color.relivingBurgundy)

            Text("Age: 68")
              .font(.system(size: 15))
              .foregroundStyle(Color.relivingDarkSage.opacity(0.7))
          }
          .padding(.top, 12)
          .opacity(headerVisible ? 1 : 0)
          .offset(y: headerVisible ? 0 : 10)
          .animation(.easeOut(duration: 0.45), value: headerVisible)

          VStack(spacing: 28) {
            CategorySectionView(title: "Objects", category: .object, items: $mediaStore.objectItems)
            CategorySectionView(title: "People", category: .person, items: $mediaStore.peopleItems)
          }
        }
        .padding(.all, 24)
      }
      .background(Color.relivingPaperGradient)
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
      .tint(Color.relivingBurgundy)
      .onAppear {
        withAnimation { headerVisible = true }
      }
    }
  }
}
