import Foundation

@main
enum FaceprintSelfTest {
    static func main() throws {
        for unlocked in [false, true] {
            for face in [false, true] {
                for password in [false, true] {
                    for busy in [false, true] {
                        let expected = unlocked && face && password && !busy
                        precondition(InputActionPolicy.canEnable(sessionUnlocked: unlocked, hasFace: face, hasPassword: password, busy: busy) == expected)
                    }
                }
            }
        }
        for enabled in [false, true] {
            for verified in [false, true] {
                precondition(InputActionPolicy.shouldPressReturn(enabled: enabled, verified: verified) == (enabled && verified))
            }
        }
        print("PASS filling requires an unlocked session, a face, a password, and idle state; Return requires opt-in and verified input")

        let poses: [(EnrollmentPose, Float, Float)] = [
            (.center, 0, 0), (.left, 0.3, 0), (.topLeft, 0.3, -0.22),
            (.top, 0, -0.22), (.topRight, -0.3, -0.22), (.right, -0.3, 0),
            (.bottomRight, -0.3, 0.22), (.bottom, 0, 0.22), (.bottomLeft, 0.3, 0.22)
        ]
        precondition(poses.map { $0.0 } == EnrollmentPose.allCases)
        for (pose, yaw, pitch) in poses {
            precondition(EnrollmentPoseMatcher.matches(yaw: yaw, pitch: pitch, pose: pose, widened: false))
            precondition(!EnrollmentPoseMatcher.matches(yaw: 0.7, pitch: 0.6, pose: pose, widened: true))
        }
        precondition(!EnrollmentPoseMatcher.matches(yaw: 0.22, pitch: 0, pose: .center, widened: false))
        precondition(EnrollmentPoseMatcher.matches(yaw: 0.22, pitch: 0, pose: .center, widened: true))
        print("PASS nine-pose order, capture bands, overshoot rejection, and stall widening")

        var vector = [Float](repeating: 0, count: 512)
        vector[0] = 1
        let legacy = try JSONSerialization.data(withJSONObject: [
            "modelIdentifier": "arcface-w600k_mbf-v1",
            "samples": Array(repeating: vector, count: 24)
        ])
        let decoded = try JSONDecoder().decode(FaceTemplate.self, from: legacy)
        precondition(decoded.poses == nil && decoded.matches(vector))
        let names = poses.flatMap { [$0.0.name, $0.0.name] }
        let template = FaceTemplate(modelIdentifier: "arcface-w600k_mbf-v1", samples: Array(repeating: vector, count: 18), poses: names)
        let restored = try JSONDecoder().decode(FaceTemplate.self, from: JSONEncoder().encode(template))
        precondition(restored.matches(vector) && restored.poses == names)
        print("PASS legacy face templates and nine-view serialization")

        for text in ["x", "abc123!", "A😀Bé", String(repeating: "z", count: 21) + "😀👩‍💻"] {
            for limit in [1, 20] {
                let chunks = KeyboardText.batches(text, maximumUTF16Units: limit)
                precondition(chunks.flatMap { $0 } == Array(text.utf16))
                precondition(chunks.allSatisfy { !($0.last.map { (0xD800...0xDBFF).contains($0) } ?? false) })
            }
        }
        print("PASS Unicode input chunks preserve surrogate pairs")

        let prompt = ["AutoFill for “Example Browser”", "Enter the password for the user “Test User” to continue with Passwords.", "OK", "Cancel"]
        precondition(PromptPolicy.autofillContext(in: prompt, accountNames: ["Test User"]) == "autofill:example browser")
        precondition(PromptPolicy.autofillContext(in: prompt, accountNames: ["Another User"]) == nil)
        precondition(PromptPolicy.autofillContext(in: ["Open your Faceprint session", "OK", "Cancel"], accountNames: ["Test User"]) == nil)
        print("PASS native AutoFill context, wrong-account rejection, and session-prompt exclusion")
    }
}
