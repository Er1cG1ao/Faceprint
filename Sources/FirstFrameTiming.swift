import Foundation

// All boundaries use systemUptime. Only consecutive intervals on the camera
// path belong here; model loading runs concurrently with camera startup.
struct CameraStartupTiming {
    let entered: TimeInterval
    let queued: TimeInterval
    let dequeued: TimeInterval
    let deviceReady: TimeInterval
    let startRunningAt: TimeInterval
    let runningAt: TimeInterval
    let reused: Bool

    func phases(trigger: TimeInterval, task: TimeInterval, checked: TimeInterval,
                firstFrame: TimeInterval?) -> [(String, TimeInterval)] {
        var stages = [
            ("Prompt UI and task scheduling", task - trigger),
            ("Revalidate prompt", checked - task),
            ("Dispatch camera task", entered - checked),
            ("Camera access and preparation", queued - entered),
            ("Camera queue wait", dequeued - queued),
            ("Look up camera", deviceReady - dequeued),
            (reused ? "Reuse capture configuration" : "Configure capture session", startRunningAt - deviceReady),
            ("startRunning()", runningAt - startRunningAt)
        ]
        if let firstFrame { stages.append(("Running to first frame callback", firstFrame - runningAt)) }
        return stages
    }
}

/// The camera's first sample timestamp is converted to the host clock. The
/// delay is computed there, so no absolute clock epochs are mixed.
struct FirstCameraFrameTiming {
    let callbackAt: TimeInterval
    let presentationToCallback: TimeInterval?

    func split(after startup: CameraStartupTiming) -> (runningToPresentation: TimeInterval, presentationToCallback: TimeInterval)? {
        guard let delay = presentationToCallback, delay.isFinite, delay >= 0 else { return nil }
        let presentationAt = callbackAt - delay
        guard presentationAt >= startup.startRunningAt else { return nil }
        // A frame can be timestamped before startRunning() returns.
        return (presentationAt - startup.runningAt, delay)
    }
}
