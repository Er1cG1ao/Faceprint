# Third-party notices

## Glance

Faceprint is built on Glance and includes substantial direct reuse of its source code and visual assets. Glance is created by Jonathan Zhou. The upstream revision used here is `b97f521397ec1197ba17768ba797cae1e628848d`.

Reused components include ArcFace Core ML inference, face detection and alignment, embedding math, liveness measurements, nine-view enrollment definitions and visuals, camera-preview rendering, Dynamic Island geometry, animation state, scan images, and success/failure videos. Faceprint adapts these components to password-prompt filling, adds verified input and optional Return, and uses its own local encrypted session storage.

Glance code and media are provided under its MIT license. The complete original copyright and license notice is retained in LICENSE-Glance.txt and included in the app bundle. Upstream repository and license follow below.

- https://github.com/jonnyoo/glance
- https://github.com/jonnyoo/glance/blob/b97f521397ec1197ba17768ba797cae1e628848d/LICENSE

## InsightFace pretrained model

The ArcFace recognition weights are InsightFace's `w600k_mbf`, from the `buffalo_s` model pack, converted to Core ML by Glance. InsightFace states separate non-commercial research terms for its pretrained models. The MIT code license does not grant additional rights to these weights. Faceprint does not claim ownership of them or change their license.

The source repository imports the model from an operator's local Glance installation. The experimental beta app contains that compiled model. Review the original model terms before using or redistributing it, and obtain the appropriate model authorization for a different use.

- https://github.com/deepinsight/insightface#license
- https://github.com/deepinsight/insightface/tree/master/model_zoo
- https://github.com/jonnyoo/glance/blob/b97f521397ec1197ba17768ba797cae1e628848d/tools/README.md

The settings window layout and measured floating-tab capsule/label transitions also adapt Glance’s SettingsMetrics, SettingsTabBar, SessionLockButton and native unified-titlebar configuration (jonnyoo/glance, revision b97f521397ec1197ba17768ba797cae1e628848d). Copyright and MIT terms are retained in LICENSE-Glance.txt.

Faceprint 1.4.0 also adapts Glance’s YourFaceSettingsPage identity-card layout, FaceEnrollmentStore quality bands, GlanceToggle small native control sizing, and UnlockAnimationPicker/SettingsOptionTile visuals from the same revision. Faceprint stores its identity collection in its existing encrypted vault.

Faceprint 1.5.0 adapts Glance’s NameStepView and SettingsMenuPickerPill layout from the same pinned MIT source. The GitHub updater and installer are Faceprint code.

Faceprint 1.5.1 reuses Glance’s ProgressiveHeaderBlur layered gradient-masked material implementation (same pinned MIT revision), retaining its attribution in Sources/ProgressiveHeaderBlur.swift.
