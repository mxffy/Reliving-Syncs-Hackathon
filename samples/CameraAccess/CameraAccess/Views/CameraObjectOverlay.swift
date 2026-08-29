/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

import SceneKit
import SwiftUI

private struct CameraObjectPlacement: Identifiable {
  let id = UUID()
  let sourceID: UUID
  let name: String
  let modelURL: URL
  var position: CGPoint
  var scale: CGFloat = 1
  var rotation: CGSize = .zero
}

struct CameraObjectOverlay: View {
  let trackingService: AprilTagTrackingService?

  @State private var mediaStore = MediaCategoryStore.shared
  @State private var placements: [CameraObjectPlacement] = []
  @State private var objectAssignmentsByTagID: [Int: UUID] = [:]
  @State private var trackedObjectScaleByTagID: [Int: CGFloat] = [:]
  @State private var trackedObjectOffsetByTagID: [Int: CGSize] = [:]
  @State private var trackedObjectRotationByTagID: [Int: CGSize] = [:]
  @State private var isEditModeOn = false
  @State private var personaService = PersonaConversationService()

  /// All 3D objects, linked or not. Use this (not `availableObjects`) to look up an already-linked item.
  private var allObjects: [CapturedMediaItem] {
    mediaStore.objectItems.filter { $0.usdzURL != nil }
  }

  /// The person just named aloud, if any — not tag-linked, so it stays with the user rather than a marker.
  private var activePersona: CapturedMediaItem? {
    guard let id = personaService.activePersonaID else { return nil }
    return mediaStore.peopleItems.first { $0.id == id && $0.usdzURL != nil }
  }

  /// Sidebar-eligible objects: excludes anything currently linked to a tag.
  private var availableObjects: [CapturedMediaItem] {
    allObjects.filter { !objectAssignmentsByTagID.values.contains($0.id) }
  }

  init(trackingService: AprilTagTrackingService? = nil) {
    self.trackingService = trackingService
  }

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .topTrailing) {
        Color.clear
          .contentShape(Rectangle())

        if let trackingService {
          ForEach(trackingService.trackedTags) { trackedTag in
            if let transform = trackedTag.projected(in: geometry.size) {
              AprilTagDetectionIndicator(
                transform: transform,
                linkedObjectName: objectForTag(trackedTag.id)?.name
              )

              if
                let item = objectForTag(trackedTag.id),
                let modelURL = item.usdzURL
              {
                TrackedCameraObjectView(
                  name: item.name,
                  modelURL: modelURL,
                  transform: transform,
                  isEditModeOn: isEditModeOn,
                  scale: scaleBinding(forTagID: trackedTag.id),
                  offset: offsetBinding(forTagID: trackedTag.id),
                  rotation: rotationBinding(forTagID: trackedTag.id),
                  onDelete: { unlinkObject(fromTagID: trackedTag.id) }
                )
              }
            }
          }

          trackingStatus(for: trackingService)
            .padding(.top, max(geometry.safeAreaInsets.top, 12) + 60)
            .padding(.leading, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .allowsHitTesting(false)
            .zIndex(11)
        }

        ForEach($placements) { $placement in
          PlacedCameraObjectView(
            placement: $placement,
            containerSize: geometry.size,
            isEditModeOn: isEditModeOn,
            onDelete: {
              placements.removeAll { $0.id == placement.id }
            }
          )
        }

        objectLibrary(containerSize: geometry.size)
          .padding(.top, max(geometry.safeAreaInsets.top, 12) + 60)
          .padding(.trailing, 16)
          .zIndex(10)

        if let activePersona, let modelURL = activePersona.usdzURL {
          PersonaOverlayView(modelURL: modelURL)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .allowsHitTesting(false)
            .zIndex(9)
            .transition(.opacity.combined(with: .scale(scale: 0.85)))
        }

        personaStatus(for: personaService.conversationState)
          .padding(.bottom, max(geometry.safeAreaInsets.bottom, 12) + 16)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
          .allowsHitTesting(false)
          .zIndex(11)
      }
      .frame(width: geometry.size.width, height: geometry.size.height)
      .contentShape(Rectangle())
      .animation(.spring(response: 0.35, dampingFraction: 0.8), value: personaService.activePersonaID)
      .animation(.easeInOut(duration: 0.2), value: personaService.conversationState)
      .onAppear { personaService.start() }
      .onDisappear { personaService.stop() }
      .dropDestination(for: String.self) { identifiers, location in
        guard
          let identifier = identifiers.first,
          let sourceID = UUID(uuidString: identifier),
          let item = allObjects.first(where: { $0.id == sourceID })
        else {
          return false
        }
        return placeOrLinkObject(
          item,
          at: location,
          in: geometry.size,
          trackingService: trackingService
        )
      }
    }
    .ignoresSafeArea()
  }

  private func objectLibrary(containerSize: CGSize) -> some View {
    VStack(alignment: .trailing, spacing: 10) {
      Button {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
          isEditModeOn.toggle()
        }
      } label: {
        Image(systemName: "pencil")
          .font(.system(size: 20, weight: .semibold))
          .foregroundStyle(.white)
          .frame(width: 48, height: 48)
          .background(Color.relivingBurgundy, in: Circle())
          .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
      }
      .accessibilityLabel(isEditModeOn ? "Exit edit mode" : "Enter edit mode")

      if isEditModeOn {
        VStack(spacing: 10) {
          Text("Objects")
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(Color.relivingBurgundy)
            .frame(maxWidth: .infinity, alignment: .leading)

          if availableObjects.isEmpty {
            VStack(spacing: 8) {
              Image(systemName: "cube.transparent")
                .font(.system(size: 24))
                .foregroundStyle(Color.relivingDarkSage)
              Text("No 3D objects yet")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.relivingDarkSage)
                .multilineTextAlignment(.center)
            }
            .frame(width: 92, height: 90)
          } else {
            ScrollView(.vertical, showsIndicators: false) {
              LazyVStack(spacing: 12) {
                ForEach(availableObjects) { item in
                  libraryItem(item, containerSize: containerSize)
                }
              }
            }
            .frame(maxHeight: 380)
          }
        }
        .padding(12)
        .frame(width: 126)
        .background(Color.relivingIvory.opacity(0.97), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(Color.relivingBeige, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
        .transition(.move(edge: .trailing).combined(with: .opacity))
      }
    }
  }

  private func objectForTag(_ tagID: Int) -> CapturedMediaItem? {
    guard let sourceID = objectAssignmentsByTagID[tagID] else { return nil }
    return allObjects.first { $0.id == sourceID }
  }

  private func scaleBinding(forTagID tagID: Int) -> Binding<CGFloat> {
    Binding(
      get: { trackedObjectScaleByTagID[tagID] ?? 1 },
      set: { trackedObjectScaleByTagID[tagID] = $0 }
    )
  }

  private func offsetBinding(forTagID tagID: Int) -> Binding<CGSize> {
    Binding(
      get: { trackedObjectOffsetByTagID[tagID] ?? .zero },
      set: { trackedObjectOffsetByTagID[tagID] = $0 }
    )
  }

  private func rotationBinding(forTagID tagID: Int) -> Binding<CGSize> {
    Binding(
      get: { trackedObjectRotationByTagID[tagID] ?? .zero },
      set: { trackedObjectRotationByTagID[tagID] = $0 }
    )
  }

  private func unlinkObject(fromTagID tagID: Int) {
    objectAssignmentsByTagID[tagID] = nil
    trackedObjectScaleByTagID[tagID] = nil
    trackedObjectOffsetByTagID[tagID] = nil
    trackedObjectRotationByTagID[tagID] = nil
  }

  private func trackingStatus(for service: AprilTagTrackingService) -> some View {
    let presentation = trackingStatusPresentation(for: service)
    return HStack(spacing: 7) {
      Image(systemName: presentation.icon)
        .font(.system(size: 13, weight: .semibold))
      Text(presentation.text)
        .font(.system(size: 13, weight: .semibold))
        .lineLimit(1)
    }
    .foregroundStyle(presentation.foreground)
    .padding(.horizontal, 11)
    .frame(height: 34)
    .background(Color.black.opacity(0.58), in: Capsule())
    .accessibilityLabel(presentation.text)
  }

  private func trackingStatusPresentation(
    for service: AprilTagTrackingService
  ) -> (icon: String, text: String, foreground: Color) {
    switch service.status {
    case .searching:
      return ("viewfinder", "Searching for AprilTags", .white.opacity(0.82))
    case .tracking:
      let linkedTags = service.trackedTags.filter { objectForTag($0.id) != nil }
      if service.trackedTags.count == 1, let tag = service.trackedTags.first {
        if let item = objectForTag(tag.id) {
          return ("link", "Tag \(tag.id) detected: \(item.name) linked", Color.relivingLightSage)
        }
        return ("scope", "Tag \(tag.id) detected: unlinked", Color.relivingIvory)
      }
      return (
        "scope",
        "\(service.trackedTags.count) tags detected: \(linkedTags.count) linked",
        linkedTags.isEmpty ? Color.relivingIvory : Color.relivingLightSage
      )
    case .trackingLost:
      return ("exclamationmark.circle", "Tracking lost", Color.relivingIvory)
    }
  }

  @ViewBuilder
  private func personaStatus(for state: PersonaConversationState) -> some View {
    if let presentation = personaStatusPresentation(for: state) {
      HStack(spacing: 7) {
        Image(systemName: presentation.icon)
          .font(.system(size: 12, weight: .semibold))
        Text(presentation.text)
          .font(.system(size: 12, weight: .semibold))
          .lineLimit(1)
      }
      .foregroundStyle(.white.opacity(0.85))
      .padding(.horizontal, 11)
      .frame(height: 30)
      .background(Color.black.opacity(0.5), in: Capsule())
      .accessibilityLabel(presentation.text)
      .transition(.opacity)
    }
  }

  private func personaStatusPresentation(
    for state: PersonaConversationState
  ) -> (icon: String, text: String)? {
    switch state {
    case .idle:
      return nil
    case .listening:
      return ("waveform", activePersona == nil ? "Listening for familiar names…" : "Listening…")
    case .matching:
      return ("brain", "Recalling a memory…")
    case .playing:
      return ("speaker.wave.2.fill", "Playing memory…")
    }
  }

  private func libraryItem(_ item: CapturedMediaItem, containerSize: CGSize) -> some View {
    VStack(spacing: 5) {
      Image(uiImage: item.photo)
        .resizable()
        .aspectRatio(contentMode: .fill)
        .frame(width: 84, height: 74)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
          Image(systemName: "cube.fill")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(5)
            .background(Color.relivingBurgundy, in: Circle())
            .padding(4)
        }

      Text(item.name)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Color.relivingBurgundy)
        .lineLimit(1)
    }
    .frame(width: 92)
    .padding(.vertical, 6)
    .background(Color.relivingBeige, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    .onTapGesture {
      tapToPlaceOrLink(item, containerSize: containerSize)
    }
    .draggable(item.id.uuidString) {
      Image(uiImage: item.photo)
        .resizable()
        .aspectRatio(contentMode: .fill)
        .frame(width: 92, height: 92)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
  }

  private func placeObject(_ item: CapturedMediaItem, at position: CGPoint, in size: CGSize) -> Bool {
    guard let modelURL = item.usdzURL else { return false }
    let placement = CameraObjectPlacement(
      sourceID: item.id,
      name: item.name,
      modelURL: modelURL,
      position: clampedPosition(position, in: size)
    )
    placements.append(placement)
    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
      isEditModeOn = false
    }
    return true
  }

  private func placeOrLinkObject(
    _ item: CapturedMediaItem,
    at position: CGPoint,
    in size: CGSize,
    trackingService: AprilTagTrackingService?
  ) -> Bool {
    if
      let trackedTag = nearestTrackedTag(
        to: position,
        in: size,
        trackingService: trackingService
      )
    {
      linkObject(item, toTagID: trackedTag.id)
      return true
    }
    return placeObject(item, at: position, in: size)
  }

  /// Tapping (rather than dragging to a specific tag) links to whichever tag is currently visible.
  private func tapToPlaceOrLink(_ item: CapturedMediaItem, containerSize: CGSize) {
    if let firstTrackedTag = trackingService?.trackedTags.first {
      linkObject(item, toTagID: firstTrackedTag.id)
      return
    }
    _ = placeObject(
      item,
      at: CGPoint(x: containerSize.width / 2, y: containerSize.height / 2),
      in: containerSize
    )
  }

  private func linkObject(_ item: CapturedMediaItem, toTagID tagID: Int) {
    objectAssignmentsByTagID[tagID] = item.id
    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
      isEditModeOn = false
    }
  }

  private func nearestTrackedTag(
    to position: CGPoint,
    in size: CGSize,
    trackingService: AprilTagTrackingService?
  ) -> AprilTagObservation? {
    trackingService?.trackedTags
      .compactMap { observation -> (AprilTagObservation, CGFloat)? in
        guard let transform = observation.projected(in: size) else { return nil }
        let distance = hypot(position.x - transform.center.x, position.y - transform.center.y)
        let linkRadius = max(transform.markerSize, 80)
        return distance <= linkRadius ? (observation, distance) : nil
      }
      .min { $0.1 < $1.1 }?
      .0
  }

  private func clampedPosition(_ position: CGPoint, in size: CGSize) -> CGPoint {
    CGPoint(
      x: min(max(position.x, 70), max(size.width - 70, 70)),
      y: min(max(position.y, 100), max(size.height - 100, 100))
    )
  }
}

private struct AprilTagDetectionIndicator: View {
  let transform: AprilTagViewportTransform
  let linkedObjectName: String?

  private var color: Color {
    linkedObjectName == nil ? Color.relivingIvory : Color.relivingLightSage
  }

  var body: some View {
    RoundedRectangle(cornerRadius: 4)
      .stroke(color, style: StrokeStyle(lineWidth: 2, dash: linkedObjectName == nil ? [6, 4] : []))
      .frame(
        width: max(transform.markerSize, 36),
        height: max(transform.markerSize, 36)
      )
      .overlay(alignment: .top) {
        Text(label)
          .font(.system(size: 10, weight: .bold))
          .foregroundStyle(.black)
          .padding(.horizontal, 6)
          .frame(height: 20)
          .background(color, in: Capsule())
          .fixedSize()
          .offset(y: -25)
      }
      .rotationEffect(.radians(transform.rotation))
      .position(transform.center)
      .allowsHitTesting(false)
      .accessibilityLabel(label)
  }

  private var label: String {
    guard let linkedObjectName else { return "TAG \(transform.tagID) | UNLINKED" }
    return "TAG \(transform.tagID) | \(linkedObjectName.uppercased())"
  }
}

/// Shown when a person's name is heard aloud. Anchored to the viewport (not a tag), so it stays
/// fixed in front of the camera — as the device moves, the persona moves with it, always in view.
private struct PersonaOverlayView: View {
  let modelURL: URL

  var body: some View {
    ObjectModelSceneView(url: modelURL, pitch: 0, yaw: 0)
  }
}

private struct TrackedCameraObjectView: View {
  let name: String
  let modelURL: URL
  let transform: AprilTagViewportTransform
  let isEditModeOn: Bool
  @Binding var scale: CGFloat
  @Binding var offset: CGSize
  @Binding var rotation: CGSize
  let onDelete: () -> Void

  @State private var dragOrigin: CGSize?
  @State private var scaleOrigin: CGFloat?
  @State private var rotationOrigin: CGSize?

  private let baseSize: CGFloat = 170

  var body: some View {
    ZStack(alignment: .topTrailing) {
      // Default upright pose plus any user-driven spin; position/scale follow the tag.
      ObjectModelSceneView(url: modelURL, pitch: Float(rotation.height), yaw: Float(rotation.width))
        .frame(width: baseSize, height: baseSize)

      if isEditModeOn {
        Button(action: onDelete) {
          Image(systemName: "xmark")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(Color.relivingBurgundy, in: Circle())
        }
        .offset(x: 8, y: -8)
        .accessibilityLabel("Unlink \(name)")
      }
    }
    .scaleEffect(min(max(transform.markerSize / 90, 0.35), 3.2) * scale)
    .position(x: transform.center.x + offset.width, y: transform.center.y + offset.height)
    .contentShape(Rectangle())
    .simultaneousGesture(dragGesture, including: isEditModeOn ? .all : .none)
    .simultaneousGesture(resizeGesture, including: isEditModeOn ? .all : .none)
    .simultaneousGesture(rotateGesture, including: isEditModeOn ? .none : .all)
    .accessibilityLabel("\(name), tracked by tag \(transform.tagID)")
  }

  private var dragGesture: some Gesture {
    DragGesture(minimumDistance: 1)
      .onChanged { value in
        let origin = dragOrigin ?? offset
        dragOrigin = origin
        offset = CGSize(
          width: origin.width + value.translation.width,
          height: origin.height + value.translation.height
        )
      }
      .onEnded { _ in
        dragOrigin = nil
      }
  }

  private var resizeGesture: some Gesture {
    MagnificationGesture()
      .onChanged { value in
        let origin = scaleOrigin ?? scale
        scaleOrigin = origin
        scale = min(max(origin * value, 0.4), 3)
      }
      .onEnded { _ in
        scaleOrigin = nil
      }
  }

  /// Spins the model in place (like a Quick Look preview) without moving it off the tag.
  private var rotateGesture: some Gesture {
    DragGesture(minimumDistance: 1)
      .onChanged { value in
        let origin = rotationOrigin ?? rotation
        rotationOrigin = origin
        rotation = CGSize(
          width: origin.width + value.translation.width / 60,
          height: min(max(origin.height + value.translation.height / 60, -1.4), 1.4)
        )
      }
      .onEnded { _ in
        rotationOrigin = nil
      }
  }
}

private struct PlacedCameraObjectView: View {
  @Binding var placement: CameraObjectPlacement
  let containerSize: CGSize
  let isEditModeOn: Bool
  let onDelete: () -> Void

  @State private var dragOrigin: CGPoint?
  @State private var scaleOrigin: CGFloat?
  @State private var rotationOrigin: CGSize?

  private let baseSize: CGFloat = 170

  var body: some View {
    ZStack(alignment: .topTrailing) {
      ObjectModelSceneView(
        url: placement.modelURL,
        pitch: Float(placement.rotation.height),
        yaw: Float(placement.rotation.width)
      )
      .frame(width: baseSize, height: baseSize)

      if isEditModeOn {
        Button(action: onDelete) {
          Image(systemName: "xmark")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(Color.relivingBurgundy, in: Circle())
        }
        .offset(x: 8, y: -8)
        .accessibilityLabel("Remove \(placement.name)")
      }
    }
    .scaleEffect(placement.scale)
    .position(placement.position)
    .contentShape(Rectangle())
    .simultaneousGesture(dragGesture, including: isEditModeOn ? .all : .none)
    .simultaneousGesture(resizeGesture, including: isEditModeOn ? .all : .none)
    .simultaneousGesture(rotateGesture, including: isEditModeOn ? .none : .all)
    .accessibilityLabel(placement.name)
  }

  private var dragGesture: some Gesture {
    DragGesture(minimumDistance: 1)
      .onChanged { value in
        let origin = dragOrigin ?? placement.position
        dragOrigin = origin
        placement.position = clampedPosition(
          CGPoint(
            x: origin.x + value.translation.width,
            y: origin.y + value.translation.height
          )
        )
      }
      .onEnded { _ in
        dragOrigin = nil
      }
  }

  private var resizeGesture: some Gesture {
    MagnificationGesture()
      .onChanged { value in
        let origin = scaleOrigin ?? placement.scale
        scaleOrigin = origin
        placement.scale = min(max(origin * value, 0.45), 2.5)
        placement.position = clampedPosition(placement.position)
      }
      .onEnded { _ in
        scaleOrigin = nil
      }
  }

  /// Spins the model in place (like a Quick Look preview) without moving its position.
  private var rotateGesture: some Gesture {
    DragGesture(minimumDistance: 1)
      .onChanged { value in
        let origin = rotationOrigin ?? placement.rotation
        rotationOrigin = origin
        placement.rotation = CGSize(
          width: origin.width + value.translation.width / 60,
          height: min(max(origin.height + value.translation.height / 60, -1.4), 1.4)
        )
      }
      .onEnded { _ in
        rotationOrigin = nil
      }
  }

  private func clampedPosition(_ position: CGPoint) -> CGPoint {
    let halfSize = baseSize * placement.scale / 2
    let minimumX = min(halfSize, containerSize.width / 2)
    let maximumX = max(containerSize.width - halfSize, containerSize.width / 2)
    let minimumY = min(halfSize, containerSize.height / 2)
    let maximumY = max(containerSize.height - halfSize, containerSize.height / 2)
    return CGPoint(
      x: min(max(position.x, minimumX), maximumX),
      y: min(max(position.y, minimumY), maximumY)
    )
  }
}

private struct ObjectModelSceneView: UIViewRepresentable {
  let url: URL
  var pitch: Float = 0
  var yaw: Float = 0
  var roll: Float = 0

  func makeUIView(context: Context) -> SCNView {
    let sceneView = SCNView()
    sceneView.backgroundColor = .clear
    sceneView.isOpaque = false
    sceneView.isUserInteractionEnabled = false
    sceneView.antialiasingMode = .multisampling4X
    sceneView.scene = makeScene()
    return sceneView
  }

  func updateUIView(_ uiView: SCNView, context: Context) {
    uiView.scene?.rootNode.childNode(withName: "cameraObjectModel", recursively: false)?.eulerAngles =
      SCNVector3(-0.18 + pitch, 0.5 + yaw, roll)
  }

  private func makeScene() -> SCNScene {
    let scene = SCNScene()
    guard let modelScene = try? SCNScene(url: url, options: nil) else {
      return scene
    }

    let modelContainer = SCNNode()
    modelContainer.name = "cameraObjectModel"
    for child in modelScene.rootNode.childNodes {
      modelContainer.addChildNode(child.clone())
    }

    let bounds = modelContainer.boundingBox
    let width = bounds.max.x - bounds.min.x
    let height = bounds.max.y - bounds.min.y
    let depth = bounds.max.z - bounds.min.z
    let largestDimension = max(width, height, depth)
    if largestDimension > 0 {
      modelContainer.scale = SCNVector3(repeating: 1.7 / largestDimension)
    }
    modelContainer.position = SCNVector3(
      -(bounds.min.x + bounds.max.x) / 2 * modelContainer.scale.x,
      -(bounds.min.y + bounds.max.y) / 2 * modelContainer.scale.y,
      -(bounds.min.z + bounds.max.z) / 2 * modelContainer.scale.z
    )
    modelContainer.eulerAngles = SCNVector3(-0.18 + pitch, 0.5 + yaw, roll)
    scene.rootNode.addChildNode(modelContainer)

    let cameraNode = SCNNode()
    let camera = SCNCamera()
    camera.usesOrthographicProjection = false
    camera.fieldOfView = 35
    cameraNode.camera = camera
    cameraNode.position = SCNVector3(0, 0, 4)
    scene.rootNode.addChildNode(cameraNode)

    let keyLight = SCNNode()
    keyLight.light = SCNLight()
    keyLight.light?.type = .omni
    keyLight.light?.intensity = 1_200
    keyLight.position = SCNVector3(2, 3, 4)
    scene.rootNode.addChildNode(keyLight)

    // Low-angle fill light from the opposite side to reveal depth/shading the key light misses.
    let fillLight = SCNNode()
    fillLight.light = SCNLight()
    fillLight.light?.type = .omni
    fillLight.light?.intensity = 350
    fillLight.position = SCNVector3(-3, -1, 3)
    scene.rootNode.addChildNode(fillLight)

    let ambientLight = SCNNode()
    ambientLight.light = SCNLight()
    ambientLight.light?.type = .ambient
    ambientLight.light?.intensity = 450
    scene.rootNode.addChildNode(ambientLight)

    return scene
  }
}

private extension SCNVector3 {
  init(repeating value: Float) {
    self.init(value, value, value)
  }
}
