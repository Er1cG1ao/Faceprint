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
    let calledStartRunning: Bool

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
            (calledStartRunning ? "startRunning()" : "Session already running", runningAt - startRunningAt)
        ]
        if let firstFrame { stages.append(("Running to first frame callback", firstFrame - runningAt)) }
        return stages
    }
}
