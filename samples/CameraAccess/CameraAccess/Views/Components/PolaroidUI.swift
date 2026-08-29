/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// PolaroidUI.swift
//
// Shared "vintage instant film" design-system pieces used across the Home screen, Settings,
// the Objects/People filmstrip carousels, the details screen, and the AR camera's draggable
// object library: extra theme colors, a tactile pressable button style, a reusable
// polaroid-framed thumbnail, a decorative film-sprocket strip, and the polaroid-developing
// loading animation that replaces the old looping mascot video.
//

import SwiftUI
import UIKit

// MARK: - Extra theme colors

/// Supplements the `reliving*` palette declared in `3D_object_rendering.swift` with a couple of
/// extra tones needed for the polaroid/film motif, without touching the existing tokens that many
/// other screens already depend on.
extension Color {
  /// Warm gold accent — "add" affordances, highlights, badges.
  static let relivingAmber = Color(red: 0.80, green: 0.56, blue: 0.25)
  /// Near-white polaroid border/card tone (warmer than pure white).
  static let relivingCream = Color(red: 0.99, green: 0.97, blue: 0.93)
  /// Warm near-black used for soft shadows instead of flat black.
  static let relivingInk = Color(red: 0.16, green: 0.12, blue: 0.10)
  /// Vintage sepia brown — used where a status color needs to read "old photograph" instead of a
  /// flat system tint (e.g. the connected-glasses indicator).
  static let relivingSepia = Color(red: 0.42, green: 0.29, blue: 0.16)

  /// Soft paper-like background gradient used behind full screens.
  static var relivingPaperGradient: LinearGradient {
    LinearGradient(
      colors: [Color.relivingIvory, Color.relivingBeige.opacity(0.45)],
      startPoint: .top,
      endPoint: .bottom
    )
  }
}

// MARK: - Pressable button style

/// Gentle scale + opacity "press" feedback for any button, so interactions feel tactile instead
/// of a flat system default. Applied to `CustomButton`, `CircleButton`, add-cards, and carousel
/// items throughout the app.
struct PressableButtonStyle: ButtonStyle {
  var pressedScale: CGFloat = 0.94

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? pressedScale : 1)
      .opacity(configuration.isPressed ? 0.85 : 1)
      .animation(.spring(response: 0.28, dampingFraction: 0.6), value: configuration.isPressed)
  }
}

extension ButtonStyle where Self == PressableButtonStyle {
  static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

// MARK: - Film sprocket strip

/// Decorative row of small perforation marks evoking a filmstrip edge. Purely cosmetic.
struct FilmSprocketStrip: View {
  var count: Int = 22
  var tint: Color = .relivingCream

  var body: some View {
    HStack(spacing: 9) {
      ForEach(0..<count, id: \.self) { _ in
        RoundedRectangle(cornerRadius: 2, style: .continuous)
          .fill(tint.opacity(0.55))
          .frame(width: 5, height: 8)
      }
    }
    .frame(maxWidth: .infinity)
    .clipped()
  }
}

// MARK: - Polaroid thumbnail

/// A reusable polaroid-framed photo card: thick cream border (extra-thick beneath the photo, like
/// a real instant print), soft warm shadow, optional rotation, and an italic serif caption.
struct PolaroidThumbnail: View {
  let image: UIImage
  var caption: String?
  var hasModel: Bool = false
  var rotationDegrees: Double = 0
  var width: CGFloat = 108
  var photoHeight: CGFloat = 108
  var isDimmed: Bool = false

  var body: some View {
    VStack(spacing: 6) {
      Image(uiImage: image)
        .resizable()
        .aspectRatio(contentMode: .fill)
        .frame(width: width - 16, height: photoHeight)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

      if let caption {
        Text(caption)
          .font(.system(size: 12, weight: .medium, design: .serif))
          .italic()
          .foregroundStyle(Color.relivingInk.opacity(0.72))
          .lineLimit(1)
          .frame(width: width - 16)
      }
    }
    .padding(.top, 8)
    .padding(.horizontal, 8)
    .padding(.bottom, caption == nil ? 8 : 14)
    .frame(width: width)
    .background(Color.relivingCream, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    .overlay(alignment: .bottomTrailing) {
      if hasModel {
        Image(systemName: "cube.fill")
          .font(.system(size: 10, weight: .bold))
          .foregroundStyle(.white)
          .padding(5)
          .background(Color.relivingBurgundy, in: Circle())
          .padding(6)
      }
    }
    .shadow(color: Color.relivingInk.opacity(0.26), radius: 6, x: 0, y: 4)
    .rotationEffect(.degrees(rotationDegrees))
    .opacity(isDimmed ? 0.4 : 1)
  }
}

/// A dashed-border "add new" polaroid card, so the add affordance for each category is always
/// visible as the leading item of a filmstrip carousel rather than hidden behind a scroll.
struct PolaroidAddCard: View {
  var width: CGFloat = 108
  var height: CGFloat = 108

  var body: some View {
    RoundedRectangle(cornerRadius: 6, style: .continuous)
      .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
      .foregroundStyle(Color.relivingAmber)
      .background(Color.relivingCream.opacity(0.55), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
      .frame(width: width, height: height)
      .overlay {
        Image(systemName: "plus")
          .font(.system(size: 24, weight: .bold))
          .foregroundStyle(Color.relivingAmber)
      }
      .shadow(color: Color.relivingInk.opacity(0.16), radius: 5, x: 0, y: 3)
  }
}

// MARK: - Polaroid "developing" loading animation

/// Replaces the old looping mascot video. Shows the user's own captured photo inside a polaroid
/// frame, animating from a desaturated/blurred "undeveloped" state to a clear photo in a gentle
/// repeating loop, with a subtle handheld sway — evoking someone shaking an instant photo to
/// develop it.
struct PolaroidDevelopingView: View {
  let image: UIImage

  @State private var isDeveloped = false
  @State private var isSwaying = false

  var body: some View {
    VStack(spacing: 10) {
      Image(uiImage: image)
        .resizable()
        .aspectRatio(contentMode: .fill)
        .frame(width: 190, height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .saturation(isDeveloped ? 1 : 0.12)
        .brightness(isDeveloped ? 0 : 0.35)
        .blur(radius: isDeveloped ? 0 : 6)

      Capsule()
        .fill(Color.relivingInk.opacity(0.12))
        .frame(width: 130, height: 10)
    }
    .padding(.top, 14)
    .padding(.horizontal, 14)
    .padding(.bottom, 26)
    .background(Color.relivingCream, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    .shadow(color: Color.relivingInk.opacity(0.3), radius: 10, x: 0, y: 6)
    .rotationEffect(.degrees(isSwaying ? 3.5 : -3.5))
    .onAppear {
      withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
        isDeveloped = true
      }
      withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
        isSwaying = true
      }
    }
  }
}

// MARK: - Circular polaroid carousel backdrop

/// A slow-spinning ring of vintage polaroid thumbnails behind the Home screen content — every
/// object/person photo the user has, repeated as needed to fill the ring, tinted like an old
/// sepia-yellow photograph. Purely decorative; positioned behind the foreground UI and never
/// intercepts touches.
struct PolaroidCarouselBackdrop: View {
  let images: [UIImage]
  var minimumCount: Int = 12
  /// Overrides the orbit radius; defaults to filling whatever frame the view is given.
  var ringRadius: CGFloat?
  var thumbnailSize: CGFloat = 76

  @State private var rotationDegrees: Double = 0

  private var displayImages: [UIImage] {
    guard !images.isEmpty else { return [] }
    var result: [UIImage] = []
    var index = 0
    while result.count < minimumCount {
      result.append(images[index % images.count])
      index += 1
    }
    return result
  }

  var body: some View {
    GeometryReader { geometry in
      let radius = ringRadius ?? min(geometry.size.width, geometry.size.height) * 0.62
      let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
      let count = max(displayImages.count, 1)

      ZStack {
        ForEach(Array(displayImages.enumerated()), id: \.offset) { index, image in
          // Each photo orbits the center while staying upright (counter-rotated against the ring).
          let angle = (360.0 / Double(count)) * Double(index) + rotationDegrees
          PolaroidThumbnail(image: image, width: thumbnailSize, photoHeight: thumbnailSize)
            .rotationEffect(.degrees(-angle))
            .position(
              x: center.x + radius * CGFloat(cos(angle * .pi / 180)),
              y: center.y + radius * CGFloat(sin(angle * .pi / 180))
            )
        }
      }
      .frame(width: geometry.size.width, height: geometry.size.height)
    }
    .compositingGroup()
    .saturation(0.6)
    .overlay {
      // Warm sepia/yellow vintage tint over the whole ring. `compositingGroup()` above confines
      // this multiply blend to the photos themselves instead of the whole rectangular frame.
      LinearGradient(
        colors: [
          Color(red: 0.87, green: 0.65, blue: 0.28).opacity(0.3),
          Color(red: 0.72, green: 0.48, blue: 0.16).opacity(0.3),
        ],
        startPoint: .top,
        endPoint: .bottom
      )
      .blendMode(.multiply)
    }
    .opacity(0.55)
    .allowsHitTesting(false)
    .onAppear {
      guard !images.isEmpty else { return }
      withAnimation(.linear(duration: 50).repeatForever(autoreverses: false)) {
        rotationDegrees = 360
      }
    }
  }
}

// MARK: - Curtain-opening reveal

/// A pair of velvet curtain panels with a theater-style top valance that slide open from the
/// center to reveal the screen beneath, like stepping into an old film booth right as the show
/// starts. Drive `isOpen` from `false` to `true` inside a `withAnimation` block to play it once.
struct CurtainRevealOverlay: View {
  var isOpen: Bool

  var body: some View {
    GeometryReader { geometry in
      let panelWidth = geometry.size.width / 2
      ZStack {
        HStack(spacing: 0) {
          CurtainPanel()
            .frame(width: panelWidth)
            .offset(x: isOpen ? -panelWidth - 30 : 0)
          CurtainPanel()
            .frame(width: panelWidth)
            .scaleEffect(x: -1, y: 1)
            .offset(x: isOpen ? panelWidth + 30 : 0)
        }

        VStack {
          Rectangle()
            .fill(Color.relivingInk)
            .frame(height: 30)
            .overlay(alignment: .bottom) {
              Rectangle().fill(Color.relivingAmber).frame(height: 3)
            }
            .opacity(isOpen ? 0 : 1)
          Spacer()
        }
        .ignoresSafeArea(edges: .top)
      }
    }
    .ignoresSafeArea()
    .allowsHitTesting(false)
  }
}

/// A single velvet curtain panel with a repeating fold texture faked via alternating gradient
/// stops (cheaper and simpler than layering many individual fold shapes).
private struct CurtainPanel: View {
  var body: some View {
    LinearGradient(
      stops: (0...10).map { index in
        Gradient.Stop(
          color: index.isMultiple(of: 2) ? Color.relivingBurgundy : Color.relivingInk.opacity(0.88),
          location: Double(index) / 10
        )
      },
      startPoint: .leading,
      endPoint: .trailing
    )
    .overlay(Color.black.opacity(0.1))
    .shadow(color: .black.opacity(0.4), radius: 12)
  }
}
