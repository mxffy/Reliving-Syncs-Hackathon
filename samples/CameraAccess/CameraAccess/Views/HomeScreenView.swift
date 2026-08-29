/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// HomeScreenView.swift
//
// Welcome screen that guides users through the DAT SDK registration process.
// This view is displayed when the app is not yet registered.
//

import MWDATCore
import SwiftUI

struct HomeScreenView: View {
  var viewModel: WearablesViewModel
  @State private var showSettings = false
  @State private var mediaStore = MediaCategoryStore.shared

  // Entrance choreography state — "stepping into the world of polaroids".
  @State private var curtainsOpen = false
  @State private var hasEntered = false
  @State private var iconScale: CGFloat = 0.5
  @State private var iconRotation: Double = -8
  @State private var tipsVisible = false
  @State private var footerVisible = false

  var body: some View {
    ZStack {
      Color.relivingPaperGradient.ignoresSafeArea()

      // A slow-spinning ring of every object/person photo, tinted like old sepia film —
      // "the home page" is now a living carousel instead of a static screen.
      PolaroidCarouselBackdrop(images: (mediaStore.objectItems + mediaStore.peopleItems).map(\.photo))
        .ignoresSafeArea()

      // Soft radial vignette so the foreground column stays legible over the busy carousel.
      RadialGradient(
        colors: [Color.relivingIvory.opacity(0.92), Color.relivingIvory.opacity(0.2)],
        center: .center,
        startRadius: 10,
        endRadius: 340
      )
      .ignoresSafeArea()
      .allowsHitTesting(false)

      VStack {
        HStack {
          Button {
            showSettings = true
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
        }
        .padding(.horizontal, 12)
        .opacity(hasEntered ? 1 : 0)
        .animation(.easeOut(duration: 0.5).delay(0.5), value: hasEntered)

        Spacer()
      }

      VStack(spacing: 12) {
        Spacer()

        Image(.cameraAccessIcon)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(width: 120)
          .padding(18)
          .background(Color.relivingCream.opacity(0.85), in: Circle())
          .shadow(color: Color.relivingInk.opacity(0.25), radius: 16, y: 8)
          .scaleEffect(iconScale)
          .rotationEffect(.degrees(iconRotation))

        VStack(spacing: 12) {
          HomeTipItemView(
            resource: .smartGlassesIcon,
            title: "Video Capture",
            text: "Record videos directly from your glasses, from your point of view."
          )
          .offset(y: tipsVisible ? 0 : 18)
          .opacity(tipsVisible ? 1 : 0)
          .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.05), value: tipsVisible)

          HomeTipItemView(
            resource: .soundIcon,
            title: "Open-Ear Audio",
            text: "Hear notifications while keeping your ears open to the world around you."
          )
          .offset(y: tipsVisible ? 0 : 18)
          .opacity(tipsVisible ? 1 : 0)
          .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.16), value: tipsVisible)

          HomeTipItemView(
            resource: .walkingIcon,
            title: "Enjoy On-the-Go",
            text: "Stay hands-free while you move through your day. Move freely, stay connected."
          )
          .offset(y: tipsVisible ? 0 : 18)
          .opacity(tipsVisible ? 1 : 0)
          .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.27), value: tipsVisible)
        }

        Spacer()

        VStack(spacing: 20) {
          Text("You'll be redirected to the Meta AI app to confirm your connection.")
            .font(.system(size: 14))
            .foregroundStyle(Color.relivingDarkSage.opacity(0.7))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)

          CustomButton(
            title: viewModel.registrationState == .registering ? "Connecting..." : "Connect my glasses",
            style: .primary,
            isDisabled: viewModel.registrationState == .registering
          ) {
            viewModel.connectGlasses()
          }
        }
        .opacity(footerVisible ? 1 : 0)
        .offset(y: footerVisible ? 0 : 14)
        .animation(.easeOut(duration: 0.5).delay(0.45), value: footerVisible)
      }
      .padding(.all, 24)

      // Curtain-opening entrance: velvet panels slide apart like stepping into an old film
      // booth right as the show starts, revealing the spinning carousel and content beneath.
      CurtainRevealOverlay(isOpen: curtainsOpen)
    }
    .onAppear {
      OrientationManager.shared.restrictToPortrait()
      guard !hasEntered else { return }
      hasEntered = true
      withAnimation(.easeInOut(duration: 0.9)) {
        curtainsOpen = true
      }
      withAnimation(.spring(response: 0.55, dampingFraction: 0.62).delay(0.35)) {
        iconScale = 1
        iconRotation = 0
      }
      withAnimation(.easeOut(duration: 0.5).delay(0.55)) { tipsVisible = true }
      withAnimation(.easeOut(duration: 0.5).delay(0.75)) { footerVisible = true }
    }
    .fullScreenCover(isPresented: $showSettings) {
      SettingsView()
    }
  }

}

struct HomeTipItemView: View {
  let resource: ImageResource
  let title: String
  let text: String

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(resource)
        .resizable()
        .renderingMode(.template)
        .foregroundStyle(Color.relivingBurgundy)
        .aspectRatio(contentMode: .fit)
        .frame(width: 20)
        .frame(width: 36, height: 36)
        .background(Color.relivingBeige.opacity(0.4), in: Circle())

      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.system(size: 17, weight: .semibold, design: .rounded))
          .foregroundStyle(Color.relivingBurgundy)

        Text(text)
          .font(.system(size: 14))
          .foregroundStyle(Color.relivingDarkSage.opacity(0.75))
      }
      Spacer()
    }
    .padding(12)
    .background(Color.relivingCream.opacity(0.7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }
}
