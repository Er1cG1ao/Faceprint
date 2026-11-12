# Performance and workflow diagnostics (1.2.0 test build)

These are implementation budgets, not measured end-to-end guarantees. Native AX requests, camera startup, Vision, Core ML scheduling and macOS UI changes can all add latency.

| Stage | 1.1.4 | 1.2.0 |
| --- | --- | --- |
| Discovery scheduling | 400 ms timer, synchronous AX on UI actor | 200 ms timer, one background probe |
| Face gate | 3 distinct matches and 250 ms hold | 2 distinct matches, no fixed hold; same model/thresholds |
| First prediction | loaded on demand | background model loading and blank-input warm-up |
| Camera | rebuild inputs/output each start | reuse configuration for the same device; camera still stops after use |
| Vision with photo checks off | rectangles, quality, landmarks | landmarks detection; quality pass omitted |
| Password transition | 500 ms focus + 750 ms minimum elapsed; up to 7 s | fresh focus/empty sample after 40 ms; up to 3 s |
| Input | Unicode chunks with 12 ms sleeps | whole-field AXValue if supported; keyboard fallback without fixed sleeps |
| Verification | first matching length returns; up to ~800 ms | first matching length returns; up to ~180 ms |
| Island entry/pulse | 160 ms expansion stagger / 600 ms pulse start | 20 ms / 40 ms |
| Failure hold/collapse | 5 s / 700 ms | 1.2 s / 260 ms |

## Component experiment

Run `swift Tests/ModelTiming.swift Resources/ArcFace.mlmodelc`. It uses a blank 112×112 buffer, eight predictions, the model's normal `.all` compute setting, and checks the 512-element output. It never opens a camera, reads a vault or uses a face.

One local tool-sandbox run recorded model load 66.3 ms, first prediction 29.7 ms, warm prediction median 5.6 ms. The sandbox emitted Core ML/IOSurface warnings; the probe used a plain memory pixel buffer. These numbers do not identify a guaranteed compute backend and are not representative of real face recognition or total fill time. They only support moving cold preparation ahead of the request. Repeat outside the tool sandbox when comparing devices.

## Actual workflow timing

Settings **Copy diagnostics** copies only the latest attempt. Timings start at detection of a verified target, not at the moment macOS displayed its window. Phases include camera/model readiness, first frame, first inference, enrolled-face match, password transition/focus, secure-field assignment or keyboard input, length verification and Return.

The report is retained in memory and copied only when the user clicks the button. No password bytes, face images/embeddings, vault data or request/file titles are logged. Hosts and AX role names can explain why a visible dialog was not accepted. The original and replacement card must still satisfy request/signature/window checks; a timing change does not authorize a different prompt.

For a reproducible report, capture the latest attempt before starting another. Report whether photo checks, Touch ID scanning and automatic Return were enabled, and whether the dialog was Settings, Finder, an installer or Passwords AutoFill. The component experiment does not validate real-world recognition accuracy, app focus or native input delivery.
