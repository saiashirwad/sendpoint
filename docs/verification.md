# Verification

GitHub Actions **Verify** (`.github/workflows/verify.yml`) is the authoritative automated gate for the reviewed revision. It runs on pull requests, pushes to `main`, and manual dispatch. All three independent jobs must pass; configure branch protection to require `behavior`, `screenshots`, and `packaging` if enforcement is wanted.

The workflow uses standard `macos-26` Apple Silicon runners, explicitly selects `/Applications/Xcode_26.2.app`, and verifies arm64, Swift 6.2, and a macOS runtime of at least 26.4. The [image inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md) currently lists macOS 26.6.2 and Xcode 26.2. Images can change: a missing toolchain or older runtime fails setup rather than silently selecting another version.

## Runtime coverage

The deployment minimum remains macOS 14. Automated runtime coverage is macOS 26.4 or newer, not every supported macOS version. Older-system release compatibility still needs separate acceptance.

[Run 38681575809](https://github.com/saiashirwad/sendpoint/actions/runs/38681575809), revision `904080a`, compiled with Swift 6.2.3 on macOS 15.7.9, then both XCTest processes aborted with an invalid free. Hosted crash reports showed this common path while deallocating `SurfaceCoordinator` and `LatestNoteEditor`:

```text
swift::TaskLocal::StopLookupScope::~StopLookupScope()
swift_task_deinitOnExecutorImpl
swift_task_deinitOnExecutorMainActorBackDeploy
```

This strongly matches [Swift issue #88036](https://github.com/swiftlang/swift/issues/88036) and [runtime fix #85204](https://github.com/swiftlang/swift/pull/85204). The newer runner changes the execution runtime while retaining Swift 6.2; it does not fix or certify shipped binaries on older systems. No per-class empty-deinitializer workarounds were added. A completed passing run and artifact review are still required for acceptance.

## Review a run

Open **Actions → Verify → run**, confirm the revision (PR runs normally test GitHub's merge revision), and review each job and its artifacts:

- `behavior-evidence-<attempt>`: `check.json` stage outcomes/test counts and `check.log` from `./check.sh`, including verification-script tests, Swift build, and behavior tests. Screenshot tests may be skipped here by design; the separate rendering job covers them.
- `screenshots-evidence-<attempt>`: `shots.json`, `shots.log`, and all rendered light/dark PNGs from `./shots.sh`. The fixture captures its visible windows with macOS `screencapture` and composes child windows at their real positions. This requires a runner with a working WindowServer and screen-capture access. AppKit view-cache snapshots omitted native editor text and the card background in hosted artifacts, so that path is not used. Inspect the screens affected by the change, including both appearances. Capture, voice, and latest-note overlays intentionally remain dark in the light pass. This is a fresh render, **not a baseline comparison**: the JSON comparison stage should report skipped because recording was requested. A green render alone does not establish visual correctness.
- `packaging-evidence-<attempt>`: toolchain, build, bundle-validation, linked-library, and signature logs plus `Sendpoint-ci.zip` when assembly and validation succeeded. CI compiles Metal (downloading Apple's Metal toolchain if missing), builds release with `CODESIGN_IDENTITY=-`, validates the plist, executable architecture, resources, Sparkle framework/symlinks, and deep signatures, then uses `ditto` to archive. It extracts and verifies the archive again to check that framework symlinks and signatures survive.

Every job attempts evidence upload even after failure. Behavior and screenshot jobs also collect Sendpoint and XCTest crash reports from the runner when available. Missing evidence or an interrupted/cancelled job is not a pass; cancellation or infrastructure failure can prevent upload. Artifact names end with `github.run_attempt` to avoid immutable-name conflicts on partial reruns. Review each job's latest executed attempt; a successful job skipped by a partial rerun can have an earlier suffix. Artifacts expire after 14 days and can be removed by a full rerun. The app is inside a `ditto` ZIP rather than uploaded as a loose bundle so symlinks and executable metadata are preserved. It is an untrusted CI build, not a published release; do not install or launch it on a developer Mac without explicit approval.

## Rerun remotely

For an unchanged revision, use the run's **Re-run failed jobs** or **Re-run all jobs** menu. For a new revision, push the fix to the PR and review the new run. For manual runs, use **Actions → Verify → Run workflow**, selecting the intended branch; the workflow must first exist on the default branch for manual dispatch to be available in the UI. Confirm the resulting revision rather than treating an older green run as acceptance.

No local build, tests, screenshots, install, or launch is required. Local diagnostics are optional and explicitly requested. CI does not call `install.sh` or `ship.sh` and does not launch the app; packaging success is not a launch-smoke result.

## Manual acceptance and release limits

Deterministic tests and isolated snapshot renders are not full-app end-to-end testing. With explicit approval on a real Mac, relevant changes still need checks of microphone permission and recording, Accessibility grants and selection from other apps, pasted export/focus behavior, actual downloaded-model transcription, and the updater. Report which manual checks were performed and which remain outstanding.

The CI bundle is ad-hoc signed, with no signing secrets, notarization, DMG, Sparkle feed signing, publishing, or release/updater acceptance. Release procedures remain separate (`release.sh`).
