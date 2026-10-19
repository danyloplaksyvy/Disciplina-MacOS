# Validation and personal-beta readiness

**Beta readiness: pending.** Implemented code is not a substitute for the acceptance evidence below.

## Environment

Development host: Apple Silicon macOS, Command Line Tools with Swift 6.3.2, no full Xcode. The initial SwiftUI shell compiled and opened locally. Full app compilation requires missing SwiftUI/SwiftData macro plugins; GitHub Actions supplies Xcode.

## Verified results — October 19, 2026

- Commit `648cd63`: [GitHub Actions run 39226731807](https://github.com/danyloplaksyvy/Disciplina-MacOS/actions/runs/39226731807) passed both jobs on macOS 26 / Xcode 26.6.
- **13 Swift Testing tests passed**: domain rules, observable state, SwiftData CRUD and rollback, temporary-disk persistence, and a 1,000-item state fixture.
- **5 XCUITest tests passed**: create/edit/complete/reopen/delete with confirmation, cancellation, capture save, main/popover sharing, and close/reopen with a unique window.
- Development app archive generated and signature verified locally using `codesign --verify --deep --strict`.
- The CI-built app opened on the development Mac without installing Xcode, with successful local database initialization. The local artifact comes from `f521527`; `648cd63` changes UI tests only, so the application sources are identical.
- A separate in-memory local view harness verified Enter-to-create and Space-to-complete/reopen. This does not establish persistent storage or full-screen/Spaces acceptance on the device.

## Automated checks

- Domain and state: **9 tests passed locally** (including 3 blank-title cases), Swift Testing 1902 / Swift 6.3.2. Run with `bash scripts/test-core.sh`.
- SwiftData CRUD/rollback and temporary-disk reopen: Xcode unit-test target.
- UI create/edit/complete/reopen/delete, edit/capture cancellation, capture save, popover sharing: XCUITest target.
- CI logs and result bundles distinguish compilation errors, assertion failures, and runner UI infrastructure failures. Do not count infrastructure failures as successful tests.
- UI tests use an in-memory store and never change real task data. Repository tests use separate containers; disk tests use temporary directories.

## Device acceptance checklist

Record OS, hardware, build commit, result, and any issue for each item.

- [ ] Close the main window; the app stays running in the menu bar. Dock reopen and Command-O create no duplicate windows.
- [ ] Create in the popover; see the task immediately in the main window. Popover opens with focused input and Completed collapsed.
- [ ] Edit, complete, reopen, and delete tasks; verify state after relaunch.
- [ ] Capture from another focused application; Enter saves and restores focus.
- [ ] Capture above a full-screen application.
- [ ] Capture across Spaces and multiple monitors; repeated hotkeys use one panel.
- [ ] Escape never creates a task; click-away retains draft; invalid/failed save keeps input.
- [ ] Record/unset/change shortcuts and test conflicts, including another app claiming the same chord.
- [ ] Light/dark appearance, keyboard navigation (including Space in list versus typing), VoiceOver and long Unicode titles.
- [ ] At least 1,000 tasks, including completed tasks, remain usable; record warm capture timing against the approximate 300 ms target.
- [ ] Login launch is optional, quiet, and reflects system approval; explicit Quit stops capture and the menu bar item.
- [ ] Failed storage initialization/save is visible without silent data replacement; a post-save refresh failure cannot duplicate a task.

## Compatibility and release gates

Test macOS 14 as well as the current supported OS before asserting minimum-version compatibility. Login behavior and full-screen/Spaces tests require a real interactive session. A downloaded development build is ad-hoc signed and not notarized; no public distribution readiness is claimed.
