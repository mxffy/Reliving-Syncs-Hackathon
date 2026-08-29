/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// CircleButton.swift
//
// Reusable circular button component used in streaming controls and UI actions.
//

import SwiftUI

struct CircleButton: View {
  let icon: String
  let text: String?
  var size: CGFloat = 56
  var iconSize: CGFloat = 16
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      if let text {
        VStack(spacing: 2) {
          Image(systemName: icon)
            .font(.system(size: 14))
          Text(text)
            .font(.system(size: 10, weight: .medium))
        }
      } else {
        Image(systemName: icon)
          .font(.system(size: iconSize))
      }
    }
    .foregroundStyle(.black)
    .frame(width: size, height: size)
    .background(.white)
    .clipShape(Circle())
  }
}
