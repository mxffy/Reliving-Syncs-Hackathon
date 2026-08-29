/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

import AVFoundation
import Observation
import SwiftUI
import UIKit

@Observable
final class PhoneCameraViewModel {
  let session = AVCaptureSession()
  let aprilTagTrackingService: AprilTagTrackingService
  var capturedPhoto: UIImage?
  var showPhotoPreview = false
  var showError = false
  var errorMessage = ""
  var isReady = false

  @ObservationIgnored private let sessionQueue = DispatchQueue(label: "com.meta.CameraAccess.phone-camera")
  @ObservationIgnored private let photoOutput = AVCapturePhotoOutput()
  @ObservationIgnored private let videoOutput = AVCaptureVideoDataOutput()
  @ObservationIgnored private let videoOutputQueue = DispatchQueue(label: "com.meta.CameraAccess.phone-camera-frames", qos: .utility)
  @ObservationIgnored private var photoProcessor: PhonePhotoProcessor?
  @ObservationIgnored private var frameProcessor: PhoneVideoFrameProcessor?
  @ObservationIgnored private var isConfigured = false

  // AprilTagTrackingService's init is main-actor isolated; callers construct this view model on the main actor.
  @MainActor
  init() {
    aprilTagTrackingService = AprilTagTrackingService()
  }

  func start() {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      configureAndStart()
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
        if granted {
          self?.configureAndStart()
        } else {
          self?.presentError("Camera access is required to use the iPhone camera.")
        }
      }
    case .denied, .restricted:
      presentError("Camera access is disabled. Enable it in Settings to use the iPhone camera.")
    @unknown default:
      presentError("The iPhone camera is unavailable.")
    }
  }

  func stop() {
    sessionQueue.async { [weak self] in
      guard let self, self.session.isRunning else { return }
      self.session.stopRunning()
    }
    Task { @MainActor in
      aprilTagTrackingService.reset()
    }
  }

  func capturePhoto() {
    sessionQueue.async { [weak self] in
      guard let self, self.isConfigured, self.session.isRunning else {
        self?.presentError("The iPhone camera is not ready yet.")
        return
      }

      let processor = PhonePhotoProcessor { [weak self] image in
        DispatchQueue.main.async {
          guard let self else { return }
          self.photoProcessor = nil
          guard let image else {
            self.presentError("The photo could not be captured.")
            return
          }
          self.capturedPhoto = image
          self.showPhotoPreview = true
        }
      }
      self.photoProcessor = processor
      self.photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: processor)
    }
  }

  func dismissPhotoPreview() {
    showPhotoPreview = false
    capturedPhoto = nil
  }

  private func configureAndStart() {
    sessionQueue.async { [weak self] in
      guard let self else { return }

      if !self.isConfigured {
        do {
          try self.configureSession()
          self.isConfigured = true
        } catch {
          self.presentError(error.localizedDescription)
          return
        }
      }

      guard !self.session.isRunning else { return }
      self.session.startRunning()
      DispatchQueue.main.async {
        self.isReady = true
      }
    }
  }

  private func configureSession() throws {
    session.beginConfiguration()
    defer { session.commitConfiguration() }
    session.sessionPreset = .photo

    guard
      let camera = AVCaptureDevice.default(
        .builtInWideAngleCamera,
        for: .video,
        position: .back
      )
    else {
      throw PhoneCameraError.cameraUnavailable
    }

    let input = try AVCaptureDeviceInput(device: camera)
    guard
      session.canAddInput(input),
      session.canAddOutput(photoOutput),
      session.canAddOutput(videoOutput)
    else {
      throw PhoneCameraError.configurationFailed
    }

    session.addInput(input)
    session.addOutput(photoOutput)

    videoOutput.alwaysDiscardsLateVideoFrames = true
    let processor = PhoneVideoFrameProcessor { [weak self] image in
      Task { @MainActor in
        self?.aprilTagTrackingService.submit(image)
      }
    }
    frameProcessor = processor
    videoOutput.setSampleBufferDelegate(processor, queue: videoOutputQueue)
    session.addOutput(videoOutput)

    // The view is locked to portrait, so the sensor's landscape-right buffers need a fixed rotation.
    if let connection = videoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
      connection.videoRotationAngle = 90
    }
  }

  private func presentError(_ message: String) {
    DispatchQueue.main.async {
      self.errorMessage = message
      self.showError = true
      self.isReady = false
    }
  }
}

private enum PhoneCameraError: LocalizedError {
  case cameraUnavailable
  case configurationFailed

  var errorDescription: String? {
    switch self {
    case .cameraUnavailable:
      return "The rear iPhone camera is unavailable."
    case .configurationFailed:
      return "The iPhone camera could not be configured."
    }
  }
}

private final class PhonePhotoProcessor: NSObject, AVCapturePhotoCaptureDelegate {
  private let completion: (UIImage?) -> Void

  init(completion: @escaping (UIImage?) -> Void) {
    self.completion = completion
  }

  func photoOutput(
    _ output: AVCapturePhotoOutput,
    didFinishProcessingPhoto photo: AVCapturePhoto,
    error: Error?
  ) {
    guard error == nil, let data = photo.fileDataRepresentation() else {
      completion(nil)
      return
    }
    completion(UIImage(data: data))
  }
}

private final class PhoneVideoFrameProcessor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
  private let context = CIContext()
  private let minimumFrameInterval: TimeInterval = 0.1
  private var lastFrameAt: TimeInterval = 0
  private let onFrame: (UIImage) -> Void

  init(onFrame: @escaping (UIImage) -> Void) {
    self.onFrame = onFrame
  }

  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    let now = CACurrentMediaTime()
    guard now - lastFrameAt >= minimumFrameInterval else { return }
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    lastFrameAt = now

    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
    guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
    onFrame(UIImage(cgImage: cgImage))
  }
}

private final class CameraPreviewUIView: UIView {
  override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

  var previewLayer: AVCaptureVideoPreviewLayer {
    layer as! AVCaptureVideoPreviewLayer
  }
}

private struct PhoneCameraPreview: UIViewRepresentable {
  let session: AVCaptureSession

  func makeUIView(context: Context) -> CameraPreviewUIView {
    let view = CameraPreviewUIView()
    view.previewLayer.session = session
    view.previewLayer.videoGravity = .resizeAspectFill
    return view
  }

  func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
    uiView.previewLayer.session = session
  }
}

struct PhoneCameraView: View {
  let onClose: () -> Void
  @State private var viewModel = PhoneCameraViewModel()

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      PhoneCameraPreview(session: viewModel.session)
        .ignoresSafeArea()

      CameraObjectOverlay(trackingService: viewModel.aprilTagTrackingService)

      if !viewModel.isReady {
        ProgressView()
          .tint(.white)
          .scaleEffect(1.5)
      }

      VStack {
        Spacer()
        CircleButton(icon: "stop.fill", text: nil, size: 76, iconSize: 22) {
          onClose()
        }
        .accessibilityLabel("Stop camera")
        .accessibilityIdentifier("stop_phone_camera_button")
      }
      .padding(.all, 24)
    }
    .onAppear {
      viewModel.start()
      OrientationManager.shared.restrictToPortrait()
    }
    .onDisappear {
      viewModel.stop()
    }
    .sheet(isPresented: $viewModel.showPhotoPreview) {
      if let photo = viewModel.capturedPhoto {
        PhotoPreviewView(photo: photo) {
          viewModel.dismissPhotoPreview()
        }
      }
    }
    .alert("Camera unavailable", isPresented: $viewModel.showError) {
      Button("Close", action: onClose)
    } message: {
      Text(viewModel.errorMessage)
    }
  }
}