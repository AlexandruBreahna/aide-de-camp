//
//  HapticsService.swift
//  aide-de-camp
//
//  Created by Alexander Eckhart on 02.09.25.
//

import UIKit

/// Lightweight wrapper around UIFeedbackGenerator for streaming ticks.
/// Apple recommends calling `prepare()` to reduce latency. (HIG + docs)
/// See: UIImpactFeedbackGenerator, UINotificationFeedbackGenerator, UIFeedbackGenerator.prepare().
final class HapticsService {
    static let shared = HapticsService()

    private let impact = UIImpactFeedbackGenerator(style: .medium)
    private let notifier = UINotificationFeedbackGenerator()

    // Throttle so we don't fire too often during token streams.
    private var lastTick: CFTimeInterval = 0
    private let minInterval: CFTimeInterval = 0.12 // ~8 Hz feels good for streaming

    private init() {
        impact.prepare() // Apple: prepare() is optional but recommended.
    }

    /// Call this on each streamed chunk (rate-limited).
    func streamTick(intensity: CGFloat = 0.6) {
        let now = CACurrentMediaTime()
        guard now - lastTick >= minInterval else { return }
        lastTick = now
        impact.impactOccurred(intensity: max(0.0, min(intensity, 1.0)))
        // Keep it prepared for the next tick (docs suggest preparing again if you expect more).
        impact.prepare()
    }

    /// Call this with the current streamed text to emphasize sentence endings.
    /// Keeps the old API (`streamTick(intensity:)`) for compatibility.
    func streamTick(for partial: String, baseIntensity: CGFloat = 0.75) {
        let now = CACurrentMediaTime()
        guard now - lastTick >= minInterval else { return }
        lastTick = now
        let strong: CGFloat = 1.0 // max allowed by Apple
        let intensity: CGFloat
        if let last = partial.trimmingCharacters(in: .whitespacesAndNewlines).last, ".!?;:".contains(last) {
            intensity = strong
        } else {
            intensity = baseIntensity // medium baseline since generator style is .medium
        }
        impact.impactOccurred(intensity: intensity)
        impact.prepare()
    }

    /// Optional: call when streaming begins.
    func streamBegan() {
        impact.prepare()
    }

    /// Optional: success tap when stream completes normally.
    func streamEndedSuccess() {
        notifier.notificationOccurred(.success)
    }

    /// Optional: error tap when stream fails/cancels.
    func streamEndedError() {
        notifier.notificationOccurred(.error)
    }
}
