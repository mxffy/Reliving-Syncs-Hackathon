import Foundation
import Observation
import SwiftAprilTag
import UIKit

struct AprilTagObservation: Identifiable, Equatable, Sendable {
    let id: Int
    let imageSize: CGSize
    let corners: [CGPoint]

    init?(id: Int, imageSize: CGSize, corners: [CGPoint]) {
        guard
            imageSize.width > 0,
            imageSize.height > 0,
            corners.count == 4,
            corners.allSatisfy({ $0.x.isFinite && $0.y.isFinite })
        else {
            return nil
        }
        self.id = id
        self.imageSize = imageSize
        self.corners = corners
    }

    func projected(in viewportSize: CGSize) -> AprilTagViewportTransform? {
        guard viewportSize.width > 0, viewportSize.height > 0 else { return nil }

        let aspectFillScale = max(
            viewportSize.width / imageSize.width,
            viewportSize.height / imageSize.height
        )
        let offset = CGPoint(
            x: (viewportSize.width - imageSize.width * aspectFillScale) / 2,
            y: (viewportSize.height - imageSize.height * aspectFillScale) / 2
        )
        let projectedCorners = corners.map {
            CGPoint(
                x: $0.x * aspectFillScale + offset.x,
                y: $0.y * aspectFillScale + offset.y
            )
        }

        let center = projectedCorners.reduce(CGPoint.zero) { partial, point in
            CGPoint(x: partial.x + point.x / 4, y: partial.y + point.y / 4)
        }
        let bottomWidth = distance(projectedCorners[0], projectedCorners[1])
        let rightHeight = distance(projectedCorners[1], projectedCorners[2])
        let topWidth = distance(projectedCorners[2], projectedCorners[3])
        let leftHeight = distance(projectedCorners[3], projectedCorners[0])
        let markerSize = (bottomWidth + rightHeight + topWidth + leftHeight) / 4
        guard markerSize.isFinite, markerSize > 0 else { return nil }

        let horizontalVector = CGPoint(
            x: (projectedCorners[1].x - projectedCorners[0].x + projectedCorners[2].x - projectedCorners[3].x) / 2,
            y: (projectedCorners[1].y - projectedCorners[0].y + projectedCorners[2].y - projectedCorners[3].y) / 2
        )
        let rotation = atan2(horizontalVector.y, horizontalVector.x)
        let yaw = clampedPerspective((leftHeight - rightHeight) / max(leftHeight + rightHeight, 1))
        let pitch = clampedPerspective((topWidth - bottomWidth) / max(topWidth + bottomWidth, 1))

        return AprilTagViewportTransform(
            tagID: id,
            center: center,
            markerSize: markerSize,
            rotation: rotation,
            pitch: pitch,
            yaw: yaw
        )
    }

    private func distance(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
        hypot(second.x - first.x, second.y - first.y)
    }

    private func clampedPerspective(_ value: CGFloat) -> CGFloat {
        min(max(value * 1.5, -0.65), 0.65)
    }
}

struct AprilTagViewportTransform: Equatable, Sendable {
    let tagID: Int
    let center: CGPoint
    let markerSize: CGFloat
    let rotation: CGFloat
    let pitch: CGFloat
    let yaw: CGFloat
}

@Observable
@MainActor
final class AprilTagTrackingService {
    enum Status: Equatable {
        case searching
        case tracking
        case trackingLost
    }

    private(set) var status: Status = .searching
    private(set) var trackedTags: [AprilTagObservation] = []

    private let minimumFrameInterval: TimeInterval = 0.125
    private let lostTrackingGracePeriod: TimeInterval = 0.75
    private let workerQueue = DispatchQueue(
        label: "com.reliving.apriltag-detection",
        qos: .utility
    )
    private nonisolated(unsafe) let detector: Detector? = {
        guard let detector = try? Detector(families: [.tag36h11]) else { return nil }
        detector.threadCount = 2
        detector.quadDecimate = 2.0
        detector.refineEdges = true
        return detector
    }()

    private var trackedTagsByID: [Int: AprilTagObservation] = [:]
    private var lastSeenAt: [Int: Date] = [:]
    private var lastSubmittedAt: Date?
    private var isDetectionInFlight = false
    private var hasTrackedTag = false
    private var expirationTask: Task<Void, Never>?
    private var generation = 0

    func submit(_ image: UIImage, now: Date = Date()) {
        guard !isDetectionInFlight else { return }
        if let lastSubmittedAt,
             now.timeIntervalSince(lastSubmittedAt) < minimumFrameInterval {
            return
        }

        lastSubmittedAt = now
        isDetectionInFlight = true
        let submissionGeneration = generation

        workerQueue.async { [weak self] in
            guard let self, let detector = self.detector else {
                Task { @MainActor [weak self] in
                    self?.completeDetection([], generation: submissionGeneration)
                }
                return
            }

            let preparedImage = Self.normalizedImage(image)
            let imageSize: CGSize
            if let cgImage = preparedImage.cgImage {
                imageSize = CGSize(width: cgImage.width, height: cgImage.height)
            } else {
                imageSize = .zero
            }
            let detections = (try? detector.detect(uiImage: preparedImage)) ?? []
            let observations = detections.compactMap {
                AprilTagObservation(id: $0.id, imageSize: imageSize, corners: $0.corners)
            }

            Task { @MainActor [weak self] in
                self?.completeDetection(observations, generation: submissionGeneration)
            }
        }
    }

    func reset() {
        generation += 1
        expirationTask?.cancel()
        expirationTask = nil
        trackedTagsByID.removeAll()
        lastSeenAt.removeAll()
        trackedTags = []
        lastSubmittedAt = nil
        isDetectionInFlight = false
        hasTrackedTag = false
        status = .searching
    }

    private func completeDetection(_ observations: [AprilTagObservation], generation: Int) {
        guard generation == self.generation else { return }
        isDetectionInFlight = false
        let now = Date()

        for observation in observations {
            if let current = trackedTagsByID[observation.id],
                 current.imageSize == observation.imageSize,
                 current.corners == observation.corners {
                lastSeenAt[observation.id] = now
                continue
            }
            trackedTagsByID[observation.id] = observation
            lastSeenAt[observation.id] = now
            hasTrackedTag = true
        }

        expireStaleTags(at: now)
        publishTrackingState()
        scheduleNextExpiration()
    }

    private func expireStaleTags(at date: Date) {
        let expiredIDs = lastSeenAt.compactMap { id, lastSeenDate in
            date.timeIntervalSince(lastSeenDate) >= lostTrackingGracePeriod ? id : nil
        }
        for id in expiredIDs {
            lastSeenAt[id] = nil
            trackedTagsByID[id] = nil
        }
    }

    private func publishTrackingState() {
        trackedTags = trackedTagsByID.values.sorted { $0.id < $1.id }
        if !trackedTags.isEmpty {
            status = .tracking
        } else {
            status = hasTrackedTag ? .trackingLost : .searching
        }
    }

    private func scheduleNextExpiration() {
        expirationTask?.cancel()
        guard let nextExpiration = lastSeenAt.values
            .map({ $0.addingTimeInterval(lostTrackingGracePeriod) })
            .min()
        else {
            expirationTask = nil
            return
        }

        let delay = max(nextExpiration.timeIntervalSinceNow, 0)
        expirationTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.expireStaleTags(at: Date())
            self.publishTrackingState()
            self.scheduleNextExpiration()
        }
    }

    private nonisolated static func normalizedImage(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let pixelSize = CGSize(
            width: image.size.width * image.scale,
            height: image.size.height * image.scale
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: pixelSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: pixelSize))
        }
    }
}