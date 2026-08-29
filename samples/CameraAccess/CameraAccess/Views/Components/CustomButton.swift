/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// CustomButton.swift
//
// Reusable button component used throughout the CameraAccess app for consistent styling.
//

import SwiftUI

struct CustomButton: View {
  let title: String
  let style: ButtonStyle
  let isDisabled: Bool
  let action: () -> Void

  enum ButtonStyle {
    case primary, destructive

    var backgroundGradientColors: [Color] {
      switch self {
      case .primary:
        return [Color.relivingBurgundy, Color.relivingBurgundy.opacity(0.82)]
      case .destructive:
        return [.destructiveBackground, .destructiveBackground]
      }
    }

    var foregroundColor: Color {
      switch self {
      case .primary:
        return .white
      case .destructive:
        return .destructiveForeground
      }
    }

    var shadowColor: Color {
      switch self {
      case .primary:
        return .relivingBurgundy
      case .destructive:
        return .black
      }
    }
  }

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 16, weight: .semibold, design: .rounded))
        .foregroundStyle(style.foregroundColor)
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .background(
          LinearGradient(colors: style.backgroundGradientColors, startPoint: .top, endPoint: .bottom),
          in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay {
          RoundedRectangle(cornerRadius: 28, style: .continuous)
            .stroke(Color.white.opacity(style == .primary ? 0.18 : 0), lineWidth: 1)
        }
        .shadow(color: style.shadowColor.opacity(0.28), radius: 10, x: 0, y: 5)
    }
    .buttonStyle(.pressable)
    .disabled(isDisabled)
    .opacity(isDisabled ? 0.55 : 1.0)
  }
}
