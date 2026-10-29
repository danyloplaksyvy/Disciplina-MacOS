# Validation and personal-beta readiness

**Beta readiness: pending.** Implemented code is not a substitute for the acceptance evidence below.

## Environment

Development host: Apple Silicon macOS. Earlier milestones used Command Line Tools with Swift 6.3.2 and GitHub Actions for full builds. Xcode 27.1 became available locally on October 26; local full builds and 74 unit/persistence tests pass. CI continues validating with Xcode 26.6. Local English-title UI automation requires an English keyboard input source; a run with RussianWin injected only spaces and is not counted as a functional pass.

## v1.1.2 verification — October 29, 2026

- PR #1 and PR #2 were integrated into main using merge commits. PR #2 was retargeted and revalidated against main in [run 40886407224](https://github.com/danyloplaksyvy/Disciplina-MacOS/actions/runs/40886407224) before merging. Source branches and previous development artifacts were retained. Implementation is in PR #3.
- Final application/test source: `eeb69372e2ec7c31337b80854e3654295aa3c569`. Local command-line suite: **69 tests passed**. Xcode 27.1: **82 unit/persistence tests passed**, and both test bundles compiled. Search tests cover Unicode/diacritics, whitespace, combined filters, deleted/completed tasks, goal rename/reassignment, recurrence, failed saves and reload-only recovery. Schema V6 and JSON 5 are unchanged.
- Focused local UI checks passed for combined filters/hidden creation, collapsed-day restoration, navigation/window reopening, and filtered-out details with preserved title drafts. The draft test exposed list Space handling intercepting text editing; list Space/Return commands now yield to editable native text responders. The corrected test passed with the complete draft preserved. The 100-goal/10,000-task navigation/search scenario also passed.
- Performance on **Apple M4, macOS 26.6.2 (25G83), Xcode 27.1 (27A9275)**: pure search projection averaged approximately **15 ms** across 20 projections of 10,000 tasks. Eight Debug UI input-to-result-draw-pass samples had **139.2 ms median / 192.3 ms maximum**. The **150 ms target is not met consistently**. These are an instrumented draw-pass proxy, not physical-screen latency; Release excludes the instrumentation. No history scan is driven by visual stopwatch ticks.
- The packaged Release binary migrated a fresh disposable copy of the previously saved private V5 snapshot: **19 tasks and 18 sessions validated**, schema 6 activated, and the original generation plus a backup retained. No personal task contents were uploaded or committed.
- [GitHub Actions run 40890836325](https://github.com/danyloplaksyvy/Disciplina-MacOS/actions/runs/40890836325) passed: **82 unit/persistence tests and 29 UI tests in each appearance, zero failures**. Both appearances include compact-window search/detail sizing, filtered deletion Undo, draft preservation, Command-F/Escape, day expansion restoration, and existing goals, Activity, capture, simulated login, popover, timer, recurrence and session-editing regressions. CI also produced a separate clean development artifact with its merge-source commit recorded.
- Clean local Release archive: `build/v1.1.2/final/Disciplina-arm64-development.zip`, **1.1.2, build 7**, arm64, ad-hoc signed. Strict deep signature verification passed; no XCTest framework is bundled. Source is recorded above and in adjacent `BUILD-INFO.txt`. SHA-256: `aca3a03eeffe557f0b149700b58f3b60ab674d2bfd51ea424909d073203b702a`.

### Remaining v1.1.2 acceptance checks

- [ ] Consistent <=150 ms visible search results with 100 goals and 10,000 tasks; the measured Debug maximum exceeds the target.
- [ ] Real login, macOS 14 runtime, secondary monitors, other Spaces and native full-screen device matrix.
- [ ] Physical sleep/wake, capture focus/latency and timer recovery on the installed app.
- [ ] VoiceOver, increased contrast, Reduce Motion, inactive selection and larger text device checks.
- [ ] Installed-app minimum/default/maximized layouts and native file-dialog export/restore using disposable data.

Version **1.1.2**, build **7** remains a development build pending device acceptance. Live user data was not replaced for these tests.

## v1.1.1 verification — October 27, 2026

- Application/test source `9b44065b791558012907135bae5e203d56d960a8` passed [GitHub Actions run 40461638739](https://github.com/danyloplaksyvy/Disciplina-MacOS/actions/runs/40461638739): **74 unit/persistence tests and 25 UI tests in each appearance**, with zero failures. Coverage includes Activity task/return navigation and Weekly Review, full-row sidebar clicks, appearance editing, persistent popover Undo, and existing goals, capture, login, timer, recurrence and session-editing regressions. The 100-goal/10,000-task UI scenario passed in both appearances.
- Local Command Line Tools: **61 domain/store tests passed**. Local Xcode 27.1 independently passed **74 unit/persistence tests** and built the final Release source. Coverage includes atomic midnight allocation, DST/year boundaries, millisecond conservation, multi-day corrections and rollback, travel interruption, JSON 1–5 compatibility, malformed allocations, appearance inheritance and deletion feedback. Visual timer ticks do not write persistence or rebuild historical aggregates.
- Persistence tests cover staged V1–V5 upgrades, WAL snapshots, preserved records and failed activation. The exact downloaded CI app also migrated a fresh private consistent copy of the installed V5 database: **19 tasks, 18 sessions**. Validation succeeded, schema 6 was activated, and the original generation and backup were retained. The live database was untouched; no personal records were committed or uploaded.
- UI investigation found retained inactive native views interfering with navigation/scrolling. Destinations now retain their SwiftUI state in native hosts that are hidden when inactive. The final Activity test scrolls to a session task, opens details, returns, and switches to Weekly Review. The window host preserves minimum sizing without intrinsic-size resizing; automatic window cascading is disabled after initial centering. Earlier local off-screen-window and non-English-input failures are not counted as passes.
- Local native inspection used a separate in-memory preview app to check task details, selected-row contrast, calendar/manual-work presentation, Weekly Review labels and goal totals, task return navigation and the appearance editor. Final full UI acceptance was run in CI; local preview checks do not establish installed-app/device acceptance.
- The clean CI archive at `build/v1.1.1/final/Disciplina-arm64-development.zip` passed `codesign --verify --deep --strict`. It is ad-hoc signed, arm64, **1.1.1, build 6**, with no XCTest framework. Recorded PR merge source: `5075cbec8be1d769a33091fd3baaae64bf956b89`; branch source: `9b44065b791558012907135bae5e203d56d960a8`. SHA-256: `2230227f48987b856a7c669f28b912a38eb4a54e39c5ed27ba45addcce7f923f`. Source metadata and checksum are also in the adjacent `BUILD-INFO.txt`. Earlier candidates are superseded.

### Remaining v1.1.1 device checks

- [ ] Real login, macOS 14 runtime/migration, secondary monitors and other Spaces.
- [ ] Physical sleep/wake, clock/time-zone changes during live timing, native focus matrix and capture latency.
- [ ] VoiceOver, increased contrast, Reduce Motion, inactive-window selection and larger text.
- [ ] Installed-app minimum/maximized layouts, multi-day correction interaction, and native file-dialog export/restore.

Version **1.1.1**, build **6** remains a development build pending device acceptance.

## v1.1.0 verification — October 23, 2026

- Local Command Line Tools: **54 domain/store tests passed**. Coverage includes goal validation/lifecycle, milestone ordering and deletion Undo, running-task reassignment and failure recovery, immutable timer/manual attribution, recurrence inheritance, duration overflow, and a 100-goal/10,000-task fixture with no persistence writes on visual ticks.
- Final application/test source `4ac851edc14abb4b904fac663e5fce3af7ead886` passed [GitHub Actions run 39913241870](https://github.com/danyloplaksyvy/Disciplina-MacOS/actions/runs/39913241870): **66 unit/persistence tests and 22 UI tests in each appearance**, with zero failures. Native coverage includes goal/milestone lifecycle and Undo, task assignment and pause confirmation, attributed work, navigation state, and existing capture/popover/login/timer/recurrence regressions.
- The 100-goal/10,000-task UI scenario passed in both appearances, including opening a goal, starting/pausing a linked task and returning to Tasks. Total automated scenario duration was 80 seconds dark / 88 seconds light, including fixture setup and accessibility queries; these are not input-latency measurements. An earlier light run timed out retrieving the accessibility tree. Targeted first-match queries resolved that test timeout without reducing fixture size or changing application behavior.
- Migration tests cover V1–V4 to V5, WAL snapshots, preserved records, failed activation and JSON 1–4 compatibility. A private consistent copy of the installed V4 database also passed migration with the packaged app: **16 tasks, 17 sessions**. The original store was untouched; no personal records were committed or uploaded.
- The development archive at `build/v1.1.0/Disciplina-arm64-development.zip` passed `codesign --verify --deep --strict`; metadata is **1.1.0, build 5**, arm64. Its recorded PR merge source is `b0e9f20353896e418b654297c8e7cf6289aef171`, corresponding to application commit `87ece351c16641425a8b0dd8f84652b657a8712d`. The subsequent commit changes UI queries only. SHA-256: `0180915a985b4f03dc91ee830030c32bdb696e4592e7b06aca3941fdf09bf689`.
- Native inspection checked compact Tasks/Goals navigation and identified an empty-state alignment problem, corrected in the packaged source. CI screenshots inspected earlier show readable goal details, milestone progress and attributed work. Full device layout/appearance acceptance remains pending.

### Remaining device checks

- [ ] Real login, macOS 14 runtime/migration, secondary monitors and other Spaces.
- [ ] Physical sleep/wake, native capture focus matrix and warm capture latency.
- [ ] VoiceOver, increased contrast, Reduce Motion and inactive-window selection.
- [ ] Minimum/default/maximized navigation sizing, divider preservation and native file-dialog export/restore on the installed app.

Version **1.1.0**, build **5** remains a development build pending device acceptance.

## v1.0.3 verification — October 21, 2026

- Local Command Line Tools: **44 domain/store tests passed**. Recurrence coverage includes incomplete tasks spanning days, one late successor, repeated completion/checks, atomic timer-completion failure, restart, rename, schedule changes, skip/stop, guarded deletion Undo, independent restoration, historical reopening, post-commit refresh failure, JSON 1/2 compatibility and format 3 round-trip. Calendar coverage includes DST, midnight, time-zone regrouping and year boundaries.
- Migration validation passed on a private SQLite snapshot of the installed V3 database using the final CI-built executable from `e60e29c`. Only the disposable copy was upgraded; no personal task/session records were committed or uploaded.
- Final application/test source `e60e29c253b8e5a1bd00bdd05c0aaaafe39a467b` passed [GitHub Actions run 39648812844](https://github.com/danyloplaksyvy/Disciplina-MacOS/actions/runs/39648812844): **54 unit/persistence tests and 18 UI tests in each of light and dark appearance**, with zero failures. Native coverage includes quiet simulated login, startup-error recovery retaining one icon, unique-window reopening, recurrence editing and Settings management, collapsible day groups, session editors, native text Undo, task Undo, Finder capture, and the full-screen popover.
- Persistence tests cover WAL-backed V1/V2/V3→V4 migrations, unchanged source records, failure before activation, series rollback, disk reopen and staged restore. Recurrence Undo retains its transaction receipt across post-commit refresh failures.
- Inspected light/dark screenshots confirm contrasting selected-row titles, metadata, timer controls and actions; the default 860 × 600 content size and readable side-by-side details are preserved.
- The downloaded clean Release app passed `codesign --verify --deep --strict`. Metadata confirms **1.0.3, build 4**, an ad-hoc signature, arm64 architecture, the source commit above, and no XCTest frameworks. Archive: `build/v1.0.3/Disciplina-arm64-development.zip` (ignored output), SHA-256 `3438081a283d56d01a62762c7fec1c554fc891ba5151056a0af5c8267473e6bb`.

### Remaining device checks

- [ ] Real logout/login through `SMAppService`, including focus ownership and shortcut readiness.
- [ ] macOS 14 runtime, rendering and migration.
- [ ] Secondary monitors, multiple Spaces and other applications in native full screen.
- [ ] VoiceOver, increased contrast, inactive-window selection and Reduce Motion on a physical device.
- [ ] Physical sleep/wake, 1,000-task interactive performance and warm capture latency.

Version **1.0.3**, build **4** remains a development build pending these device checks.

## v1.0.2 verification — October 21, 2026

- Local Command Line Tools: **35 domain/store tests passed**. Added coverage includes duration parsing and overflow, manual session provenance, status and identity preservation, session deletion, automatic pause, failed writes, post-pause refresh failure, legacy JSON import, format 2 round-trip, and structural animation revisions.
- Final application/test commit `484475f`: [GitHub Actions run 39595614400](https://github.com/danyloplaksyvy/Disciplina-MacOS/actions/runs/39595614400) passed all jobs: **43 unit/persistence tests and 14 UI tests in each of light and dark appearance**, with zero failures. Persistence coverage includes WAL-backed V1→V3 and manifested V2→V3 migrations, a simulated failure before manifest publication, source preservation, and persistence of edited/manual sessions across reopen.
- Inspected light/dark screenshots confirm readable list/detail proportions, two-line row titles, visible controls, full titles in details, and the Close details action. The final full-screen screenshot confirms the popover is above the task window and its capture field owns visible keyboard focus.
- Native UI coverage includes session addition/editing/cancellation/deletion, pause-on-editor-open, existing task CRUD and Undo, capture from Finder, popover typing without clicking the input, Escape dismissal, and capture through the popover above the app’s native full-screen window after revealing the auto-hidden menu bar.
- The downloaded Release app was verified locally using `codesign --verify --deep --strict`; metadata confirms version 1.0.2, build 3, source `484475f7c52965e0a3c4f6cee4c4c36cb5a8c7b7`, and no XCTest framework. Local archive: `build/v1.0.2/Disciplina-arm64-development.zip` (ignored output).
- Schema V2 is frozen; V3 upgrades occur on a consistent snapshot before atomically selecting the validated generation. JSON exports now use format 2; format 1 imports remain supported.

### Remaining device checks

- [ ] macOS 14 runtime and rendering.
- [ ] Popover presentation over other apps in native full screen, across Spaces and secondary monitors.
- [ ] Divider dragging and minimum-size behavior with accessibility text settings.
- [ ] Physical-device Reduce Motion, VoiceOver, increased contrast, and rapid task-action animation review.
- [ ] Previously pending physical sleep/wake, login launch, 1,000-task interactive performance, and warm capture latency checks.

Version **1.0.2**, build **3** remains a development build pending these device checks.

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
