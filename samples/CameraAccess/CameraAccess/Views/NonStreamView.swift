/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// NonStreamView.swift
//
// Default screen to show getting started tips after app connection
// Initiates streaming
//

import MWDATCore
import SwiftUI

private let updateRequiredBackgroundColor = Color(red: 1.0, green: 0.957, blue: 0.839)
private let updateRequiredForegroundColor = Color(red: 0.541, green: 0.294, blue: 0.0)
private let updateRequiredTitle = "Update required"
private let waitingForActiveDeviceText = "Waiting for an active device"

struct NonStreamView: View {
  var viewModel: StreamSessionViewModel
  @Bindable var wearablesVM: WearablesViewModel
  let onStartPhoneCamera: () -> Void
  @State private var showSettingsMenu: Bool = false
  @State private var showAppSettings: Bool = false
  @State private var mediaStore = MediaCategoryStore.shared

  private var isRegistered: Bool {
    wearablesVM.registrationState == .registered
  }

  private var usesGlasses: Bool {
    isRegistered && viewModel.hasActiveDevice
  }

  private var filmstripItems: [CapturedMediaItem] {
    mediaStore.objectItems + mediaStore.peopleItems
  }

  var body: some View {
    ZStack {
      Color.relivingPaperGradient.ignoresSafeArea()

      // Dismiss overlay when tapping outside the settings menu (placed first so it's behind content)
      if showSettingsMenu {
        Color.clear
          .contentShape(Rectangle())
          .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
              showSettingsMenu = false
            }
          }
          .edgesIgnoringSafeArea(.all)
      }

      VStack {
        HStack(alignment: .center) {
          Button {
            showAppSettings = true
          } label: {
            Image(systemName: "gearshape.fill")
              .font(.system(size: 20, weight: .semibold))
              .foregroundStyle(Color.relivingBurgundy)
              .frame(width: 44, height: 44)
              .background(Color.relivingCream, in: Circle())
              .shadow(color: Color.relivingInk.opacity(0.2), radius: 5, y: 2)
          }
          .buttonStyle(.pressable)
          .accessibilityLabel("Settings")
          .accessibilityIdentifier("settings_button")

          Spacer()

          Image("brownLogo")
            .resizable()
            .scaledToFit()
            .frame(width: 150, height: 46)
            .accessibilityHidden(true)

          Spacer()

          if isRegistered {
            Button {
              withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                showSettingsMenu.toggle()
              }
            } label: {
              Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color.relivingSepia)
                .frame(width: 48, height: 48)
                .background(Color.relivingCream, in: Circle())
                .shadow(color: Color.relivingInk.opacity(0.2), radius: 5, y: 2)
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Glasses connected")
            .accessibilityIdentifier("connected_glasses_button")
            .overlay(alignment: .trailing) {
              if showSettingsMenu {
                CustomButton(
                  title: "Disconnect",
                  style: .destructive,
                  isDisabled: false
                ) {
                  wearablesVM.disconnectGlasses()
                  withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showSettingsMenu = false
                  }
                }
                .frame(width: 120)
                .transition(.scale(scale: 0.01, anchor: .trailing).combined(with: .opacity))
              }
            }
          } else {
            Button {
              wearablesVM.connectGlasses()
            } label: {
              Image(systemName: "xmark.circle.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.red)
                .frame(width: 48, height: 48)
                .background(Color.relivingCream, in: Circle())
                .shadow(color: Color.relivingInk.opacity(0.2), radius: 5, y: 2)
            }
            .buttonStyle(.pressable)
            .disabled(wearablesVM.registrationState == .registering)
            .accessibilityLabel("Glasses not connected")
            .accessibilityIdentifier("disconnected_glasses_button")
          }
        }

        Spacer()

        Button(action: handlePrimaryAction) {
          ZStack {
            Circle()
              .fill(
                LinearGradient(
                  colors: [Color.relivingBurgundy, Color.relivingInk],
                  startPoint: .top,
                  endPoint: .bottom
                )
              )
              .frame(width: 112, height: 112)
              .overlay {
                Circle()
                  .stroke(Color.relivingCream.opacity(0.85), lineWidth: 4)
                  .padding(6)
              }
              .shadow(color: Color.relivingInk.opacity(0.35), radius: 14, y: 8)

            if usesGlasses {
              Image(.smartGlassesIcon)
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(.white)
                .aspectRatio(contentMode: .fit)
                .frame(width: 58, height: 58)
            } else {
              Image(systemName: "camera.fill")
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(.white)
            }
          }
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(usesGlasses ? "Start glasses streaming" : "Open iPhone camera")
        .accessibilityIdentifier("primary_camera_button")

        Spacer()

        if !filmstripItems.isEmpty {
          VStack(spacing: 4) {
            FilmSprocketStrip(tint: .relivingBurgundy)

            ScrollView(.horizontal, showsIndicators: false) {
              HStack(alignment: .top, spacing: 16) {
                ForEach(Array(filmstripItems.enumerated()), id: \.element.id) { index, item in
                  PolaroidThumbnail(
                    image: item.photo,
                    caption: item.name,
                    rotationDegrees: index.isMultiple(of: 2) ? -3.5 : 3.5,
                    width: 92,
                    photoHeight: 92
                  )
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
      }
      .padding(.all, 24)
    }
    .onAppear {
      OrientationManager.shared.restrictToPortrait()
    }
    .fullScreenCover(isPresented: $showAppSettings) {
      SettingsView()
    }
  }

  private func handlePrimaryAction() {
    guard usesGlasses else {
      onStartPhoneCamera()
      return
    }

    Task {
      if wearablesVM.requiresFirmwareUpdate {
        await wearablesVM.openFirmwareUpdate()
      } else if viewModel.requiresDATAppUpdate {
        await wearablesVM.openDATGlassesAppUpdate()
      } else {
        await viewModel.handleStartStreaming()
      }
    }
  }
}

struct UpdateRequiredMessage: View {
  let showFirmwareUpdate: Bool
  let showDATAppUpdate: Bool

  private var message: String {
    if showFirmwareUpdate && showDATAppUpdate {
      return "Your glasses firmware and app need updates before Camera Access can start."
    }
    if showFirmwareUpdate {
      return "Your glasses firmware needs an update before Camera Access can start."
    }
    return "The app on your glasses needs an update before Camera Access can start."
  }

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: "exclamationmark.triangle.fill")
        .resizable()
        .aspectRatio(contentMode: .fit)
        .foregroundStyle(updateRequiredForegroundColor)
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 4) {
        Text(updateRequiredTitle)
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(updateRequiredForegroundColor)

        Text(message)
          .font(.system(size: 15))
          .foregroundStyle(updateRequiredForegroundColor)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 0)
    }
    .padding(.all, 16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(updateRequiredBackgroundColor)
    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
  }
}

struct GettingStartedSheetView: View {
  @Environment(\.dismiss) var dismiss
  @Binding var height: CGFloat

  var body: some View {
    VStack(spacing: 24) {
      Text("Getting started")
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(.primary)

      VStack(spacing: 12) {
        TipItemView(
          resource: .videoIcon,
          text: "First, Camera Access needs permission to use your glasses camera."
        )
        TipItemView(
          resource: .tapIcon,
          text: "Capture photos by tapping the camera button."
        )
        TipItemView(
          resource: .smartGlassesIcon,
          text: "The capture LED lets others know when you're capturing content or going live."
        )
      }
      .padding(.bottom, 16)

      CustomButton(
        title: "Continue",
        style: .primary,
        isDisabled: false
      ) {
        dismiss()
      }
    }
    .padding(.all, 24)
    .background(
      GeometryReader { geo -> Color in
        DispatchQueue.main.async {
          height = geo.size.height
        }
        return Color.clear
      }
    )
  }
}

struct TipItemView: View {
  let resource: ImageResource
  let text: String

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(resource)
        .resizable()
        .renderingMode(.template)
        .foregroundStyle(.primary)
        .aspectRatio(contentMode: .fit)
        .frame(width: 24)
        .padding(.leading, 4)
        .padding(.top, 4)

      Text(text)
        .font(.system(size: 15))
        .foregroundStyle(.primary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
