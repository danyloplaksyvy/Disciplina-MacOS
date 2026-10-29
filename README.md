# Disciplina for macOS

A native, offline task manager with a main window, menu bar popover, and configurable global quick capture. macOS 14 or later. No accounts, backend, or telemetry.

## Use a development build without Xcode

Open this repository's **Actions → macOS validation**, select a successful run, and download **Disciplina-arm64-development**. Unzip the artifact and the enclosed app archive, then copy Disciplina.app to `/Applications`. This build is for Apple Silicon Macs and is ad-hoc signed, not notarized. macOS may require a deliberate approval in Privacy & Security before opening it. Do not disable Gatekeeper globally.

Launch Disciplina to open its task window. Closing the window leaves the app in the menu bar. Press Control–Option–Space to capture a task; configure another shortcut in Settings. Launch at login is off by default and should be enabled only after placing the app in its permanent location. Quit explicitly from the app menu or popover.

Start a task to track time, pause when you stop working, and resume to create another work session. Only one timer runs at a time. While timing, the menu bar shows a burgundy dot and session time beside the checkmark; otherwise it shows “3 left,” “All clear,” or “—” when state is unavailable. The popover offers quick actions; the main window groups tasks by creation day, with status sections and session history.

Open task details to add missed work, correct session durations, or delete a session after confirmation. Opening a time editor pauses that task’s timer; cancelling leaves it paused. Recorded dates stay unchanged when editing duration. Drag the divider to resize the task list and details, or close details to expand the list.

In v1.0.3, choose Repeat in an unfinished task’s details: daily, weekdays, or selected weekdays. Completing it schedules one new task for the next eligible day. Unfinished tasks do not multiply, and returning after several days creates only one successor. Manage schedules between occurrences in Settings → Recurring Tasks. Login launch starts the menu bar and shortcut without opening the task window.

Deleted tasks remain in Settings → Data & Recovery until explicitly deleted permanently. That section also provides JSON export and replace-from-backup restore. Upgrades and restores retain local backups; timers remain paused after sleep or an interrupted run.

Build artifacts are available only after the build and unit-test job passes. See [validation status](docs/VALIDATION.md) before treating a build as beta-ready.

## Goals and progress — v1.1.0

Open **Goals** in the main window to define an outcome, success criterion, optional target date, and milestones. Milestone completion determines progress; marking a goal achieved is a separate action. Archive preserves all history and can be reversed. Achieved and archived goals remain editable.

Create or link tasks inside a goal, or use **Change Goal…** in task details. Changing a running task’s goal requires pausing; Resume is always manual. Each timer session and manual time entry keeps the goal assigned when recorded. Existing sessions stay unassigned, and reassignment never moves past effort. Recurring successors inherit the current occurrence’s goal. Permanent task/session deletion reduces goal effort; soft deletion preserves it.

Task and milestone deletion share app-level Undo. Text editing retains native Undo. Export format 5 includes goals, milestones and daily activity; formats 1–4 can still be restored.

## Activity and polish — v1.1.1

Open **Activity** for a monthly calendar and Weekly Review. New timer sessions preserve daily work in the time zone where it was recorded. Manual time belongs to its chosen date; multi-day corrections edit each day separately. Legacy timer sessions are explicitly shown as start-date attribution, not an invented daily history. Weekly completion counts reflect currently completed records and can change after reopening.

Deletion feedback includes Undo in the main window and menu bar popover. Dismissing it keeps Command-Z available. Optional task appearance lives in details; current recurring tasks pass their symbol and color to future occurrences.

## Task search — v1.1.2

In **Tasks**, use **Command-F** to search titles, including completed tasks. Combine search with status and goal filters. Matching ignores case and accents; deleted tasks remain in Data & Recovery. **Clear filters** restores the full list and previous day expansion choices.

Filtering keeps open details and unfinished inline title edits. A hidden task's details explain why it is outside the results. Creating a task never inherits filters; a confirmation appears if the new task is hidden. Escape clears search text, then returns focus to the task list. Search/filter choices last for the app session.

## Development

Open `Disciplina.xcodeproj` in Xcode 26 or newer with Swift 6.2 or newer. Select the **Disciplina** scheme and **My Mac**. The project uses ad-hoc signing and requires no paid Apple Developer membership for development builds. KeyboardShortcuts 3.1.0 is the only application dependency; its exact resolution is committed in the Xcode workspace.

```sh
xcodebuild test -project Disciplina.xcodeproj -scheme Disciplina \
  -destination 'platform=macOS,arch=arm64' -only-testing:DisciplinaTests
```

Without Xcode, `bash scripts/test-core.sh` runs the production domain and observable-store tests using Command Line Tools (Swift 6.2+). This harness deliberately excludes SwiftData and UI code, whose compiler plugins require Xcode. It is not a second shipping application or architecture module.

The checked-in Xcode project is generated by a dependency-free Python script. After adding/removing source files, run `python3 scripts/generate_project.py`. CI checks that regeneration produces no diff.

## Architecture

Views send actions through one shared `TaskStore`. `TaskService` validates task edits; `TimerCoordinator` serializes timing and status transitions. `TaskRepository` commits task/session/series/goal/milestone snapshots atomically through SwiftData. Domain values never expose persistence objects. A committed mutation followed by a failed fetch is reported separately and cannot be resubmitted until refreshing succeeds.

One main-actor model context serves all entry points. The versioned schema freezes the V1–V5 layouts and migrates a separate copy to V6 before publishing its store location. Storage initialization failures are surfaced; the app never falls back to a new empty database. Task data remains in the app's local sandbox; no CloudKit container is configured.

See [v1.1.1 engineering notes](docs/V1.1.1-IMPLEMENTATION.md), [v1.1.0 engineering notes](docs/V1.1.0-IMPLEMENTATION.md), [v1.0.3 engineering notes](docs/V1.0.3-IMPLEMENTATION.md), [v1.0.2 engineering notes](docs/V1.0.2-IMPLEMENTATION.md), [v1.0.1 specification](docs/PRD-V1.0.1.md), [v1.0.1 engineering notes](docs/V1.0.1-IMPLEMENTATION.md), [original PRD](docs/PRD.md), [implementation checklist](docs/IMPLEMENTATION.md), and [manual acceptance](docs/VALIDATION.md).

## Distribution and licensing

Personal development builds only. Public signing, notarization, Intel release builds, and App Store distribution are deferred. No open-source license has been selected; public visibility alone does not grant a reuse license.
