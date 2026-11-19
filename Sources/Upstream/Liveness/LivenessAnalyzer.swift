//
//  LivenessAnalyzer.swift
//  glance
//
//  Rolling-window driver for the liveness cues. Takes `LivenessFrame`, not
//  `FaceRecognitionResult`, keeping this file's dependency graph shallow enough
//  to compile standalone in `tools/liveness_selftest.swift`.
//

import Foundation

@MainActor
final class LivenessAnalyzer {
    private let windowDuration: TimeInterval

    /// Read fresh on every `observe()`, not captured at init, so a mid-scan Settings change takes effect immediately.
    var modeProvider: () -> LivenessMode = { .light }
    var tuningProvider: () -> LivenessTuning = { .default }
    /// Face Lab can switch individual cues off to isolate one; the unlock
    /// path leaves this at "all enabled."
    var enabledCuesProvider: () -> Set<LivenessCue> = { Set(LivenessCue.allCases) }

    private var frames: [LivenessFrame] = []
    private var evaluator = LivenessEvaluator()
    init(windowDuration: TimeInterval = 2.0) {
        self.windowDuration = windowDuration
    }

    func reset() {
        frames.removeAll()
        evaluator.reset()
    }

    /// Call once per frame with a detected face, regardless of whether it matched an identity,
    /// so liveness stays an independent gate. The window is time-pruned (~2s) but the evaluator's
    /// fire counts are not — they accumulate across the whole scan, so a spoof tell can't be waited out.
    @discardableResult
    func observe(_ frame: LivenessFrame) -> LivenessSnapshot {
        frames.append(frame)
        frames.removeAll { frame.timestamp.timeIntervalSince($0.timestamp) > windowDuration }

        evaluator.mode = modeProvider()
        evaluator.tuning = tuningProvider()
        evaluator.enabledCues = enabledCuesProvider()

        let geometry = GeometryLiveness.evaluate(frames)

        let readings = LivenessCues.readings(window: frames, geometry: geometry)
        return evaluator.observe(readings)
    }
}

