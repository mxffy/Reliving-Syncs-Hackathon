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
  var scale: CGFloat = 5
  var rotation: CGSize = .zero
}

/// Holds all tag-links/placements and their scale/offset/rotation, keyed by tag ID.
/// Shared singleton (like `MediaCategoryStore`) so this survives the camera view closing and reopening.
@Observable
private final class TrackedObjectPlacementStore {
  static let shared = TrackedObjectPlacementStore()
  private init() {}

  var placements: [CameraObjectPlacement] = []
  var objectAssignmentsByTagID: [Int: UUID] = [:]
  var trackedObjectScaleByTagID: [Int: CGFloat] = [:]
  var trackedObjectOffsetByTagID: [Int: CGSize] = [:]
  var trackedObjectRotationByTagID: [Int: CGSize] = [:]
  var personaScaleByID: [UUID: CGFloat] = [:]
  var personaOffsetByID: [UUID: CGSize] = [:]
  var personaRotationByID: [UUID: CGSize] = [:]
}

struct CameraObjectOverlay: View {
  let trackingService: AprilTagTrackingService?

  @State private var mediaStore = MediaCategoryStore.shared
  @State private var placementStore = TrackedObjectPlacementStore.shared
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

  /// Alice's scan is a head/bust only (see `MediaCategoryStore.aliceItem`), unlike David's full-body
  /// model — the shared "crop a full body down to the face" framing below crops a head-only model's
  /// chin/hair instead, so give her a much gentler, near-centered framing tuned for that proportion.
  private static let headOnlyPersonaIDs: Set<UUID> = [UUID(uuidString: "C1A11CE0-2A1D-4B7E-9F0A-6D1E9B8C2F3A")!]

  private func personaFraming(for persona: CapturedMediaItem) -> (distance: Float, horizontal: Float, vertical: Float) {
    if Self.headOnlyPersonaIDs.contains(persona.id) {
      return (distance: 3.2, horizontal: 0, vertical: 0)
    }
    return (distance: 1.7, horizontal: 0.1, vertical: -0.45)
  }

  /// Alice's starting pose before any user gesture: bigger and lower on screen, and turned a
  /// further half-turn since her scan's forward axis doesn't match the shared `baseYaw` flip
  /// tuned for David (a full \u03c0 turn needs no sign-guessing \u2014 it lands the same either way).
  private func personaDefaultTransform(for id: UUID) -> (scale: CGFloat, offset: CGSize, rotationWidth: CGFloat) {
    if Self.headOnlyPersonaIDs.contains(id) {
      return (scale: 1.15, offset: CGSize(width: 0, height: 140), rotationWidth: .pi)
    }
    return (scale: 1, offset: .zero, rotationWidth: 0)
  }

  /// Sidebar-eligible objects: excludes anything currently linked to a tag.
  private var availableObjects: [CapturedMediaItem] {
    allObjects.filter { !placementStore.objectAssignmentsByTagID.values.contains($0.id) }
  }

  /// Placing/linking an object requires a currently-tracked tag with no object linked yet.
  private var hasUnlinkedTrackedTag: Bool {
    trackingService?.trackedTags.contains { objectForTag($0.id) == nil } ?? false
  }

  /// IDs of linked objects currently visible via a tracked AprilTag — feeds the persona service's
  /// hardcoded "Mark" + object voice trigger.
  private var viewedObjectIDs: Set<UUID> {
    Set((trackingService?.trackedTags ?? []).compactMap { objectForTag($0.id)?.id })
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

        ForEach($placementStore.placements) { $placement in
          PlacedCameraObjectView(
            placement: $placement,
            containerSize: geometry.size,
            isEditModeOn: isEditModeOn,
            onDelete: {
              placementStore.placements.removeAll { $0.id == placement.id }
            }
          )
        }

        objectLibrary()
          .padding(.top, max(geometry.safeAreaInsets.top, 12) + 60)
          .padding(.trailing, 16)
          .zIndex(10)

        if let activePersona, let modelURL = activePersona.usdzURL {
          let framing = personaFraming(for: activePersona)
          PersonaOverlayView(
            modelURL: modelURL,
            isEditModeOn: isEditModeOn,
            cameraDistance: framing.distance,
            horizontalFramingOffset: framing.horizontal,
            verticalFramingOffset: framing.vertical,
            scale: personaScaleBinding(forID: activePersona.id),
            offset: personaOffsetBinding(forID: activePersona.id),
            rotation: personaRotationBinding(forID: activePersona.id)
          )
          .frame(width: geometry.size.width, height: geometry.size.height)
          .zIndex(9)
          .transition(.opacity.combined(with: .scale(scale: 0.85)))
        }

        personaStatus(for: personaService.conversationState, transcript: personaService.liveTranscript)
          .padding(.bottom, max(geometry.safeAreaInsets.bottom, 12) + 16)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
          .allowsHitTesting(false)
          .zIndex(11)
      }
      .frame(width: geometry.size.width, height: geometry.size.height)
      .contentShape(Rectangle())
      .animation(.spring(response: 0.35, dampingFraction: 0.8), value: personaService.activePersonaID)
      .animation(.easeInOut(duration: 0.2), value: personaService.conversationState)
      .onAppear {
        personaService.start()
        personaService.currentlyViewedObjectIDs = viewedObjectIDs
      }
      .onDisappear { personaService.stop() }
      .onChange(of: viewedObjectIDs) { _, ids in
        personaService.currentlyViewedObjectIDs = ids
      }
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

  private func objectLibrary() -> some View {
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
      .buttonStyle(.pressable)
      .accessibilityLabel(isEditModeOn ? "Exit edit mode" : "Enter edit mode")

      if isEditModeOn {
        VStack(spacing: 10) {
          Text("Objects")
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(Color.relivingBurgundy)
            .frame(maxWidth: .infinity, alignment: .leading)

          if availableObjects.isEmpty {
            VStack(spacing: 8) {
              Image(systemName: "cube.transparent")
                .font(.system(size: 24))
                .foregroundStyle(Color.relivingDarkSage.opacity(0.6))
              Text("No 3D objects yet")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.relivingDarkSage.opacity(0.6))
                .multilineTextAlignment(.center)
            }
            .frame(width: 92, height: 90)
          } else {
            ScrollView(.vertical, showsIndicators: false) {
              LazyVStack(spacing: 14) {
                ForEach(availableObjects) { item in
                  libraryItem(item)
                }
              }
              .padding(.vertical, 4)
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
    guard let sourceID = placementStore.objectAssignmentsByTagID[tagID] else { return nil }
    return allObjects.first { $0.id == sourceID }
  }

  private func scaleBinding(forTagID tagID: Int) -> Binding<CGFloat> {
    Binding(
      // Default new links to max scale (matches the resize gesture's upper clamp below).
      get: { placementStore.trackedObjectScaleByTagID[tagID] ?? 6 },
      set: { placementStore.trackedObjectScaleByTagID[tagID] = $0 }
    )
  }

  private func offsetBinding(forTagID tagID: Int) -> Binding<CGSize> {
    Binding(
      get: { placementStore.trackedObjectOffsetByTagID[tagID] ?? .zero },
      set: { placementStore.trackedObjectOffsetByTagID[tagID] = $0 }
    )
  }

  private func rotationBinding(forTagID tagID: Int) -> Binding<CGSize> {
    Binding(
      get: { placementStore.trackedObjectRotationByTagID[tagID] ?? .zero },
      set: { placementStore.trackedObjectRotationByTagID[tagID] = $0 }
    )
  }

  private func unlinkObject(fromTagID tagID: Int) {
    placementStore.objectAssignmentsByTagID[tagID] = nil
    placementStore.trackedObjectScaleByTagID[tagID] = nil
    placementStore.trackedObjectOffsetByTagID[tagID] = nil
    placementStore.trackedObjectRotationByTagID[tagID] = nil
  }

  private func personaScaleBinding(forID id: UUID) -> Binding<CGFloat> {
    Binding(
      get: { placementStore.personaScaleByID[id] ?? personaDefaultTransform(for: id).scale },
      set: { placementStore.personaScaleByID[id] = $0 }
    )
  }

  private func personaOffsetBinding(forID id: UUID) -> Binding<CGSize> {
    Binding(
      get: { placementStore.personaOffsetByID[id] ?? personaDefaultTransform(for: id).offset },
      set: { placementStore.personaOffsetByID[id] = $0 }
    )
  }

  private func personaRotationBinding(forID id: UUID) -> Binding<CGSize> {
    Binding(
      get: {
        placementStore.personaRotationByID[id]
          ?? CGSize(width: personaDefaultTransform(for: id).rotationWidth, height: 0)
      },
      set: { placementStore.personaRotationByID[id] = $0 }
    )
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
  private func personaStatus(for state: PersonaConversationState, transcript: String) -> some View {
    if let presentation = personaStatusPresentation(for: state, transcript: transcript) {
      HStack(spacing: 7) {
        Image(systemName: presentation.icon)
          .font(.system(size: 12, weight: .semibold))
        Text(presentation.text)
          .font(.system(size: 12, weight: .semibold))
          .lineLimit(1)
          .truncationMode(.head)
      }
      .foregroundStyle(.white.opacity(0.85))
      .padding(.horizontal, 11)
      .frame(height: 30)
      .frame(maxWidth: 280)
      .background(Color.black.opacity(0.5), in: Capsule())
      .accessibilityLabel(presentation.text)
      .transition(.opacity)
    }
  }

  private func personaStatusPresentation(
    for state: PersonaConversationState,
    transcript: String
  ) -> (icon: String, text: String)? {
    switch state {
    case .idle:
      return nil
    case .listening:
      let heard = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
      if !heard.isEmpty {
        return ("waveform", heard)
      }
      return ("waveform", activePersona == nil ? "Listening for familiar names…" : "Listening…")
    case .matching:
      return ("brain", "Recalling a memory…")
    case .playing:
      return ("speaker.wave.2.fill", "Playing memory…")
    }
  }

  private func libraryItem(_ item: CapturedMediaItem) -> some View {
    let isPlaceable = hasUnlinkedTrackedTag
    return PolaroidThumbnail(
      image: item.photo,
      caption: item.name,
      hasModel: true,
      width: 92,
      photoHeight: 70,
      isDimmed: !isPlaceable
    )
    // Disabled (dimmed, non-interactive) until an unlinked AprilTag is visible to place onto.
    .allowsHitTesting(isPlaceable)
    .onTapGesture {
      tapToPlaceOrLink(item)
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
    placementStore.placements.append(placement)
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
    // Only allowed onto a tag that isn't already linked to another object — never floats freely.
    guard
      let trackedTag = nearestTrackedTag(to: position, in: size, trackingService: trackingService),
      objectForTag(trackedTag.id) == nil
    else {
      return false
    }
    linkObject(item, toTagID: trackedTag.id)
    return true
  }

  /// Links to the first unlinked tracked tag. No-op if none is visible (library item is disabled then).
  private func tapToPlaceOrLink(_ item: CapturedMediaItem) {
    guard let unlinkedTag = trackingService?.trackedTags.first(where: { objectForTag($0.id) == nil }) else {
      return
    }
    linkObject(item, toTagID: unlinkedTag.id)
  }

  private func linkObject(_ item: CapturedMediaItem, toTagID tagID: Int) {
    placementStore.objectAssignmentsByTagID[tagID] = item.id
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
  let isEditModeOn: Bool
  var cameraDistance: Float = 1.7
  var horizontalFramingOffset: Float = 0.1
  var verticalFramingOffset: Float = -0.45
  @Binding var scale: CGFloat
  @Binding var offset: CGSize
  @Binding var rotation: CGSize

  @State private var dragOrigin: CGSize?
  @State private var scaleOrigin: CGFloat?
  @State private var rotationOrigin: CGSize?

  var body: some View {
    // Face the camera dead-on (no generic handheld-object tilt), closer + lower framing
    // so the face fills the screen instead of the legs; dimmed lighting avoids blowing out the face.
    // The model's own forward direction faces away from the camera, so add a half-turn.
    ObjectModelSceneView(
      url: modelURL,
      pitch: Float(rotation.height),
      yaw: Float(rotation.width),
      basePitch: 0,
      baseYaw: .pi,
      cameraDistance: cameraDistance,
      horizontalFramingOffset: horizontalFramingOffset,
      verticalFramingOffset: verticalFramingOffset,
      lightingIntensityMultiplier: 0.4
    )
    .scaleEffect(scale)
    .offset(offset)
    .contentShape(Rectangle())
    .simultaneousGesture(dragGesture, including: isEditModeOn ? .all : .none)
    .simultaneousGesture(resizeGesture, including: isEditModeOn ? .all : .none)
    .simultaneousGesture(rotateGesture, including: isEditModeOn ? .none : .all)
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
        scale = min(max(origin * value, 0.5), 2)
      }
      .onEnded { _ in
        scaleOrigin = nil
      }
  }

  /// Spins the model in place (like a Quick Look preview) without moving it.
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
        scale = min(max(origin * value, 0.4), 6)
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
        placement.scale = min(max(origin * value, 0.45), 5)
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
  /// Base tilt applied before `pitch`/`yaw`; defaults suit handheld tracked objects.
  /// The persona overlay overrides these to face the camera dead-on.
  var basePitch: Float = -0.18
  var baseYaw: Float = 0.5
  var cameraDistance: Float = 4
  var horizontalFramingOffset: Float = 0
  var verticalFramingOffset: Float = 0
  var lightingIntensityMultiplier: Float = 1

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
      SCNVector3(basePitch + pitch, baseYaw + yaw, roll)
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
      -(bounds.min.x + bounds.max.x) / 2 * modelContainer.scale.x + horizontalFramingOffset,
      -(bounds.min.y + bounds.max.y) / 2 * modelContainer.scale.y + verticalFramingOffset,
      -(bounds.min.z + bounds.max.z) / 2 * modelContainer.scale.z
    )
    modelContainer.eulerAngles = SCNVector3(basePitch + pitch, baseYaw + yaw, roll)
    scene.rootNode.addChildNode(modelContainer)

    let cameraNode = SCNNode()
    let camera = SCNCamera()
    camera.usesOrthographicProjection = false
    camera.fieldOfView = 35
    cameraNode.camera = camera
    cameraNode.position = SCNVector3(0, 0, cameraDistance)
    scene.rootNode.addChildNode(cameraNode)

    let keyLight = SCNNode()
    keyLight.light = SCNLight()
    keyLight.light?.type = .omni
    keyLight.light?.intensity = CGFloat(1_200 * lightingIntensityMultiplier)
    keyLight.position = SCNVector3(2, 3, 4)
    scene.rootNode.addChildNode(keyLight)

    // Low-angle fill light from the opposite side to reveal depth/shading the key light misses.
    let fillLight = SCNNode()
    fillLight.light = SCNLight()
    fillLight.light?.type = .omni
    fillLight.light?.intensity = CGFloat(350 * lightingIntensityMultiplier)
    fillLight.position = SCNVector3(-3, -1, 3)
    scene.rootNode.addChildNode(fillLight)

    let ambientLight = SCNNode()
    ambientLight.light = SCNLight()
    ambientLight.light?.type = .ambient
    ambientLight.light?.intensity = CGFloat(450 * lightingIntensityMultiplier)
    scene.rootNode.addChildNode(ambientLight)

    return scene
  }
}

private extension SCNVector3 {
  init(repeating value: Float) {
    self.init(value, value, value)
  }
}
