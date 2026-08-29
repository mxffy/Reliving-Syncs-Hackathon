/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// StreamView.swift
//
// Main UI for video streaming from Meta wearable devices using the DAT SDK.
// This view demonstrates the complete streaming API: video streaming with real-time display, photo capture,
// and error handling.
//

import MWDATCore
import SwiftUI

struct StreamView: View {
  @Bindable var viewModel: StreamSessionViewModel
  var wearablesVM: WearablesViewModel
  @Environment(\.horizontalSizeClass) var horizontalSizeClass
  @Environment(\.verticalSizeClass) var verticalSizeClass
  
  var isLandscape: Bool {
    horizontalSizeClass == .regular && verticalSizeClass == .compact
  }

  var body: some View {
    ZStack {
      // Black background for letterboxing/pillarboxing
      Color.black
        .edgesIgnoringSafeArea(.all)

      // Video backdrop
      if let videoFrame = viewModel.currentVideoFrame, viewModel.hasReceivedFirstFrame {
        GeometryReader { geometry in
          Image(uiImage: videoFrame)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .edgesIgnoringSafeArea(.all)
      } else {
        ProgressView()
          .scaleEffect(1.5)
          .foregroundStyle(.white)
      }

      // Controls layer - positioned based on orientation
      if isLandscape {
        HStack {
          Spacer()
          ControlsView(viewModel: viewModel)
          Spacer()
        }
        .padding(.all, 24)
      } else {
        VStack {
          Spacer()
          ControlsView(viewModel: viewModel)
        }
        .padding(.all, 24)
      }
    }
    .onAppear {
      OrientationManager.shared.allowAllOrientations()
    }
    .onDisappear {
      if viewModel.streamingStatus != .stopped {
        Task { await viewModel.stopSession() }
      }
      OrientationManager.shared.restrictToPortrait()
    }
    // Show captured photos from DAT SDK in a preview sheet
    .sheet(isPresented: $viewModel.showPhotoPreview) {
      if let photo = viewModel.capturedPhoto {
        PhotoPreviewView(
          photo: photo,
          onDismiss: {
            viewModel.dismissPhotoPreview()
          }
        )
      }
    }
  }
}

// Extracted controls for clarity
struct ControlsView: View {
  var viewModel: StreamSessionViewModel

  var body: some View {
    CircleButton(icon: "stop.fill", text: nil, size: 76, iconSize: 22) {
      Task { await viewModel.stopSession() }
    }
    .accessibilityLabel("Stop streaming")
    .accessibilityIdentifier("stop_streaming_button")
  }
}
