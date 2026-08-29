/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

import MWDATCore
import Observation
import SwiftUI

/// Manages DeviceSession lifecycle with 1:1 device-to-session mapping.
/// Monitors device availability and creates sessions on demand via `getSession()`.
@Observable
@MainActor
final class DeviceSessionManager {
  private(set) var isReady: Bool = false
  private(set) var hasActiveDevice: Bool = false

  private let wearables: WearablesInterface
  private var deviceSelector: AutoDeviceSelector
  private var deviceSession: DeviceSession?
  private var activeDeviceId: DeviceIdentifier?
  private var rejectedDeviceId: DeviceIdentifier?
  private var linkStateListenerToken: AnyListenerToken?
  @ObservationIgnored private var deviceMonitorTask: Task<Void, Never>?
  @ObservationIgnored private var registrationMonitorTask: Task<Void, Never>?
  @ObservationIgnored private var stateObserverTask: Task<Void, Never>?

  init(wearables: WearablesInterface) {
    self.wearables = wearables
    self.deviceSelector = AutoDeviceSelector(wearables: wearables)
    startDeviceMonitoring()
    startRegistrationMonitoring()
  }

  isolated deinit {
    deviceMonitorTask?.cancel()
    registrationMonitorTask?.cancel()
    stateObserverTask?.cancel()
    linkStateListenerToken = nil
    deviceSession?.stop()
  }

  func stopCurrentSession() {
    stateObserverTask?.cancel()
    stateObserverTask = nil
    deviceSession?.stop()
    deviceSession = nil
    isReady = false
  }

  /// Stops the device session and cancels monitoring. Call before releasing.
  func cleanup() {
    deviceMonitorTask?.cancel()
    deviceMonitorTask = nil
    registrationMonitorTask?.cancel()
    registrationMonitorTask = nil
    stateObserverTask?.cancel()
    stateObserverTask = nil
    deviceSession?.stop()
    deviceSession = nil
    isReady = false
    activeDeviceId = nil
    rejectedDeviceId = nil
    linkStateListenerToken = nil
    hasActiveDevice = false
  }

  /// Returns a ready DeviceSession, creating one if needed.
  /// Waits for the session to reach .started state before returning.
  func getSession() async throws(DeviceSessionError) -> DeviceSession {
    if let session = deviceSession, session.state == .started {
      isReady = true
      return session
    }

    if deviceSession?.state == .stopped {
      deviceSession = nil
    }

    // Wait for an in-progress session to finish starting
    if let session = deviceSession {
      // The session may have already transitioned to .started before the
      // for-await loop begins iterating (stateStream doesn't buffer past events).
      if session.state == .started {
        isReady = true
        startStateObserver(for: session)
        return session
      }

      try await waitForSessionStart(
        stateStream: session.stateStream(),
        errorStream: session.errorStream()
      )
      isReady = true
      startStateObserver(for: session)
      return session
    }

    // Create a new session
    do throws(DeviceSessionError) {
      let session = try wearables.createSession(deviceSelector: deviceSelector)
      deviceSession = session

      let stateStream = session.stateStream()
      let errorStream = session.errorStream()
      try session.start()

      // The session may have already transitioned to .started before the
      // for-await loop begins iterating (the state change is delivered on
      // another thread and the stream does not buffer past events).
      if session.state == .started {
        isReady = true
        startStateObserver(for: session)
        return session
      }

      try await waitForSessionStart(stateStream: stateStream, errorStream: errorStream)
      isReady = true
      startStateObserver(for: session)
      return session
    } catch {
      isReady = false
      if error.indicatesUnavailableDevice {
        rejectDevice(deviceSession?.deviceId ?? deviceSelector.activeDevice)
      }
      deviceSession = nil
      throw error
    }
  }

  // MARK: - Private

  private func waitForSessionStart(
    stateStream: AsyncStream<DeviceSessionState>,
    errorStream: AsyncStream<DeviceSessionError>
  ) async throws(DeviceSessionError) {
    do {
      try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
          for await state in stateStream {
            if state == .started {
              return
            }
            if state == .stopped {
              throw DeviceSessionError.unexpectedError(description: "The session failed to start")
            }
          }
          guard !Task.isCancelled else {
            return
          }
          throw DeviceSessionError.unexpectedError(description: "The session failed to start")
        }

        group.addTask {
          for await error in errorStream {
            throw error
          }
          guard !Task.isCancelled else {
            return
          }
          throw DeviceSessionError.unexpectedError(description: "The session failed to start")
        }

        guard try await group.next() != nil else {
          throw DeviceSessionError.unexpectedError(description: "The session failed to start")
        }
        group.cancelAll()
      }
    } catch let error as DeviceSessionError {
      throw error
    } catch {
      throw .unexpectedError(description: error.localizedDescription)
    }
  }

  /// Monitors device availability only — does NOT create sessions.
  /// Session creation is deferred to `getSession()` to avoid races.
  private func startDeviceMonitoring() {
    deviceMonitorTask = Task { [weak self] in
      guard let self else { return }
      for await device in deviceSelector.activeDeviceStream() {
        handleActiveDeviceChange(device)
      }
    }
  }

  private func handleActiveDeviceChange(_ deviceId: DeviceIdentifier?) {
    linkStateListenerToken = nil
    activeDeviceId = deviceId

    guard let deviceId, let device = wearables.deviceForIdentifier(deviceId) else {
      rejectedDeviceId = nil
      hasActiveDevice = false
      return
    }

    if rejectedDeviceId != deviceId {
      rejectedDeviceId = nil
    }
    hasActiveDevice = rejectedDeviceId == nil && device.linkState == .connected

    linkStateListenerToken = device.addLinkStateListener { [weak self] state in
      Task { @MainActor [weak self] in
        self?.handleLinkStateChange(state, for: deviceId)
      }
    }
  }

  private func handleLinkStateChange(_ state: LinkState, for deviceId: DeviceIdentifier) {
    guard activeDeviceId == deviceId else { return }

    if state == .connected {
      rejectedDeviceId = nil
      hasActiveDevice = true
    } else {
      hasActiveDevice = false
    }
  }

  private func rejectDevice(_ deviceId: DeviceIdentifier?) {
    rejectedDeviceId = deviceId
    hasActiveDevice = false
  }

  private func startRegistrationMonitoring() {
    registrationMonitorTask = Task { [weak self] in
      guard let self else { return }
      for await state in wearables.registrationStateStream() {
        if state == .registered {
          deviceMonitorTask?.cancel()
          deviceSelector = AutoDeviceSelector(wearables: wearables)
          startDeviceMonitoring()
        } else {
          stopCurrentSession()
          activeDeviceId = nil
          rejectedDeviceId = nil
          linkStateListenerToken = nil
          hasActiveDevice = false
        }
      }
    }
  }

  private func startStateObserver(for session: DeviceSession) {
    stateObserverTask?.cancel()
    stateObserverTask = Task { [weak self] in
      for await state in session.stateStream() {
        guard let self else { return }
        if state == .started {
          isReady = true
        } else if state == .stopped {
          // DeviceSession.stopped is terminal - clean up
          isReady = false
          deviceSession = nil
          return
        }
      }
    }
  }
}

extension DeviceSessionError {
  var indicatesUnavailableDevice: Bool {
    switch self {
    case .noEligibleDevice, .dwaUnavailable:
      return true
    case .unexpectedError(let description):
      return description.localizedCaseInsensitiveContains("session ended by device")
    default:
      return false
    }
  }
}
