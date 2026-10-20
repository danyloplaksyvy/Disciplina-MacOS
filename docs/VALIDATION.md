# Validation and personal-beta readiness

**Beta readiness: pending.** Implemented code is not a substitute for the acceptance evidence below.

## Environment

Development host: Apple Silicon macOS, Command Line Tools with Swift 6.3.2, no full Xcode. The initial SwiftUI shell compiled and opened locally. Full app compilation requires missing SwiftUI/SwiftData macro plugins; GitHub Actions supplies Xcode.

## v1.0.1 verification — October 20, 2026

- Final application commit `1a05a12`: [GitHub Actions run 39467805516](https://github.com/danyloplaksyvy/Disciplina-MacOS/actions/runs/39467805516) passed on macOS 26 / Xcode 26.6: **34 unit tests and 10 UI tests in each of light and dark appearance**, with zero failures.
- The local Command Line Tools suite passed **27 tests**. Timing coverage includes injected clocks, checkpoint failure, untrusted gaps, restart recovery, atomic switching, deletion/restoration, duration overflow, and committed mutations followed by refresh failure.
- Persistence coverage includes real V1-schema fixtures (empty, two tasks, and 1,000 tasks), WAL-backed snapshots, field preservation, rollback, disk reopen, malformed snapshots, and failure before replacement-store publication.
- A private SQLite snapshot of the installed V1 database was migrated and validated locally using the CI-built `f4dfa39` executable: **3 tasks, 0 sessions**. Only the private copy was upgraded. No personal records were committed or uploaded; the original store was not migrated or replaced.
- UI coverage includes task CRUD, immediate deletion Undo and Command-Z, native text Undo without restoring deleted tasks, capture without clicking, capture from Finder, repeated shortcuts preserving drafts, unique-window reopening, shared surfaces, closed-popover count updates, and timer/pause count restoration.
- Inspected CI screenshots show correct light/dark burgundy dots, timer digits before the checkmark, selected status-item appearance, and the grouped main window. These checks do not establish VoiceOver or increased-contrast acceptance.
- UI tests use in-memory data and isolated temporary recovery locations; restoring in test mode cannot select the live application's store or enable its production shortcut listener.
- Release packaging uses a separate Release build, verifies its ad-hoc signature, excludes XCTest, and records the source commit. Version is **1.0.1**, build **2**. The downloaded artifact was independently verified locally with `codesign --verify --deep --strict`, matching version/build/source metadata and no XCTest framework. Local archive: `build/v1.0.1/Disciplina-arm64-development.zip` (ignored output).

### Remaining v1.0.1 release gates

- [ ] Run on macOS 14; the deployment target alone is not runtime evidence.
- [ ] Verify capture from full-screen apps, other Spaces, secondary monitors, and an open popover; measure warm focus latency against 300 ms.
- [ ] Verify physical sleep/wake and graceful-quit failure choices on the device.
- [ ] Check VoiceOver, increased contrast, larger text, and keyboard focus throughout recovery and task details.
- [ ] Profile interactive performance with 1,000 tasks. Automated fixture coverage is not a performance measurement.
- [ ] Exercise login launch and native file-dialog export/restore end to end on the installed app.

The development build is suitable for these acceptance checks; beta readiness remains pending.

## Verified results — October 19, 2026

- Commit `648cd63`: [GitHub Actions run 39226731807](https://github.com/danyloplaksyvy/Disciplina-MacOS/actions/runs/39226731807) passed both jobs on macOS 26 / Xcode 26.6.
- **13 Swift Testing tests passed**: domain rules, observable state, SwiftData CRUD and rollback, temporary-disk persistence, and a 1,000-item state fixture.
- **5 XCUITest tests passed**: create/edit/complete/reopen/delete with confirmation, cancellation, capture save, main/popover sharing, and close/reopen with a unique window.
- Development app archive generated and signature verified locally using `codesign --verify --deep --strict`.
- The CI-built app opened on the development Mac without installing Xcode, with successful local database initialization. The local artifact comes from `f521527`; `648cd63` changes UI tests only, so the application sources are identical.
- A separate in-memory local view harness verified Enter-to-create and Space-to-complete/reopen. This does not establish persistent storage or full-screen/Spaces acceptance on the device.

## Dynamic menu bar count — October 19, 2026

- Commit `f4d0f75`: [GitHub Actions run 39229850302](https://github.com/danyloplaksyvy/Disciplina-MacOS/actions/runs/39229850302) passed both jobs on macOS 26 / Xcode 26.6: **18 unit tests and 6 UI tests**, with no failures.
- The local Command Line Tools suite passed **14 tests**. Coverage includes unavailable/zero/singular/plural labels, exact counts through 1,000, all task mutations, failed saves retaining a valid count, failed refreshes hiding stale counts, and successful refresh recovery.
- UI tests verify status updates with the popover closed, creation/completion/reopening/deletion, unchanged counts after renaming, the 9 → 10 transition, and opening the existing popover.
- Inspected CI screenshots confirm text-before-checkmark ordering, alignment, full labels, and selected appearance for All clear, 1 left, 9 left, and 10 left in light mode. The native bridge reordered separate Text/Image views, so the reusable label renders a template NSImage while retaining MenuBarExtra.
- Exact 99 → 100 and 999 → 1,000 transitions are covered by state tests. Local rendering samples include these widths; native menu bar checks at these larger counts remain manual.
- **Pending device checks:** dark appearance, VoiceOver/tooltip interaction, and macOS 14 rendering. Compiling with a macOS 14 deployment target does not establish runtime compatibility.
- Current development archive: `build/menu-bar-update/Disciplina-arm64-development.zip` (ignored local output), from the successful run above.

## Original V1 automated checks (historical)

- Domain and state: **14 tests passed locally** (including 3 blank-title cases), Swift Testing 1902 / Swift 6.3.2. Run with `bash scripts/test-core.sh`.
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
