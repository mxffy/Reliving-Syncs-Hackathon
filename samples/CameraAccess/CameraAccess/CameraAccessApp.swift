/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// CameraAccessApp.swift
//
// Main entry point for the CameraAccess sample app demonstrating the Meta Wearables DAT SDK.
// This app shows how to connect to wearable devices (like Ray-Ban Meta smart glasses),
// stream live video from their cameras, and capture photos. It provides a complete example
// of DAT SDK integration including device registration, permissions, and media streaming.
//

import Foundation
import MWDATCore
import SwiftUI
import UIKit

#if DEBUG
import MWDATMockDevice
#endif

// Global state for orientation management
class OrientationManager {
  static let shared = OrientationManager()
  var shouldLockOrientation = false
  
  func restrictToPortrait() {
    shouldLockOrientation = true
    AppDelegate.orientationMask = .portrait
    let orientation = UIInterfaceOrientation.portrait.rawValue
    UIDevice.current.setValue(orientation, forKey: "orientation")
    AppDelegate.orientationMask = .portrait
  }
  
  func allowAllOrientations() {
    shouldLockOrientation = false
    AppDelegate.orientationMask = .all
  }
}

class AppDelegate: NSObject, UIApplicationDelegate {
  static var orientationMask = UIInterfaceOrientationMask.portrait
  
  func application(
    _ application: UIApplication,
    supportedInterfaceOrientationsFor window: UIWindow?
  ) -> UIInterfaceOrientationMask {
    return AppDelegate.orientationMask
  }
}

@main
struct CameraAccessApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  var body: some Scene {
    WindowGroup {
      CameraAccessRootView()
    }
  }
}

private struct CameraAccessRootView: View {
  @State private var wearablesViewModel: WearablesViewModel?
  @State private var configurationError: String?

  var body: some View {
    Group {
      if let wearablesViewModel {
        CameraAccessContentView(
          wearables: Wearables.shared,
          viewModel: wearablesViewModel
        )
      } else {
        Color.white
          .ignoresSafeArea()
          .overlay {
            if configurationError == nil {
              ProgressView()
            }
          }
      }
    }
    .task {
      await configureWearables()
    }
    .alert("Error", isPresented: configurationErrorBinding) {
      Button("OK") {
        configurationError = nil
      }
    } message: {
      Text(configurationError ?? "Wearables SDK configuration failed.")
    }
  }

  private var configurationErrorBinding: Binding<Bool> {
    Binding(
      get: { configurationError != nil },
      set: { isPresented in
        if !isPresented {
          configurationError = nil
        }
      }
    )
  }

  private func configureWearables() async {
    guard ProcessInfo.processInfo.environment["XCTestBundlePath"] == nil else { return }
    guard wearablesViewModel == nil, configurationError == nil else { return }

    do {
      try await Task.detached(priority: .userInitiated) {
        try Wearables.configure()
      }.value
    } catch {
      configurationError = error.localizedDescription
      return
    }

    #if DEBUG
    // Start the test server when launched by XCUITests so tests can control
    // mock device setup via HTTP commands from the test process.
    if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
      MockDeviceKit.shared.enable(config: MockDeviceKitConfig(initiallyRegistered: false))

      let portFilePath = ProcessInfo.processInfo.environment["MWDAT_TEST_SERVER_PORT_FILE"]
      Task {
        try await MockDeviceKit.shared.startTestServer(portFilePath: portFilePath)
      }
    }
    #endif

    let wearables = Wearables.shared
    wearablesViewModel = WearablesViewModel(wearables: wearables)
  }
}

private struct CameraAccessContentView: View {
  let wearables: WearablesInterface
  @Bindable var viewModel: WearablesViewModel

  var body: some View {
    Group {
      MainAppView(wearables: wearables, viewModel: viewModel)
        .alert("Error", isPresented: $viewModel.showError) {
          Button("OK") {
            viewModel.dismissError()
          }
        } message: {
          Text(viewModel.errorMessage)
        }

      RegistrationView(viewModel: viewModel)
    }
  }
}
