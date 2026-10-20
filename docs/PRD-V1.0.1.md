# Disciplina v1.0.1 — Product Requirements Document

**Document version:** 1.0  
**Release:** Disciplina v1.0.1  
**Date:** October 20, 2026  
**Platform:** macOS  
**Status:** Approved specification for implementation  
**Development approach:** Incremental improvement of the existing V1 application

---

## 1. Executive Summary

Disciplina v1.0.1 improves the existing macOS task manager through five coordinated initiatives:

1. Establish distinct responsibilities for the menu bar and full application.
2. Strengthen reliability, persistence, data recovery, and accessibility.
3. Fix automatic input focus for global Quick Capture.
4. Introduce task statuses, manual time tracking, and work sessions.
5. Establish a consistent visual identity using burgundy `#7A2849`.

### Product objective

Make Disciplina a reliable, keyboard-first task management application that helps users capture tasks, track active work, and understand how much time they spend on individual tasks.

The application must remain lightweight, native to macOS, and fully functional offline.

### Release success criteria

- Task capture works without mouse interaction.
- Menu bar and full application have clearly separated responsibilities.
- All task and timer changes are consistently reflected across interfaces.
- No previously saved V1 tasks are lost during upgrade.
- At most one task has an active timer.
- Recorded time survives application and system restarts.
- Sleep, unexpected termination, and system clock changes do not artificially inflate recorded time.
- Data can be exported and restored locally.
- The interface remains accessible and visually consistent.

---

## 2. Scope

### 2.1 In scope

- Menu bar UX restructuring
- Full application UX restructuring
- Adaptive menu bar popover sizing
- Quick Capture focus and keyboard improvements
- To Do, In Progress, and Completed statuses
- Manual start, pause, resume, and stop timing
- One running timer globally
- Task-specific accumulated work duration
- Read-only work-session history
- Persistence and consistency safeguards
- Safe editing, deletion, and Undo
- Migration of existing V1 tasks
- JSON export and restore
- VoiceOver and keyboard accessibility
- Burgundy semantic design system
- Light and dark appearance

### 2.2 Out of scope

- Automatic screen or application activity monitoring
- AI coaching or productivity analytics
- Pomodoro timers
- Productivity scoring
- Accounts, synchronization, or cloud services
- Notifications and reminders
- Goals, projects, subtasks, or dependencies
- Team collaboration
- Manual editing of recorded session durations
- Automatic detection of whether work is productive

### 2.3 Compatibility

The release must preserve the existing V1 tasks, established workflows, and user preferences wherever technically feasible.

The recommended deployment target remains macOS 14 or later unless the existing app already has a different supported baseline.

---

## 3. Interface Responsibilities

### 3.1 Functional ownership matrix

| Capability | Menu Bar | Full Application |
|---|---|---|
| Quick task creation | Primary | Supported |
| View running timer | Primary | Supported |
| Start/pause/resume | Primary | Supported |
| Complete task | Supported | Supported |
| View relevant active tasks | Primary | Supported |
| View every task | No | Primary |
| Edit task title | No | Primary |
| Delete task | No | Primary |
| Change task status manually | Limited via timer/complete actions | Primary |
| View total time spent | Running task only | All tasks |
| View work-session history | No | Primary |
| Restore deleted task | No | Settings / Data & Recovery |
| Manage settings | Link only | Primary |
| Export / restore data | No | Settings |
| Open full application | Yes | N/A |

**Architectural rule:** Both interfaces call the same application services. The menu bar is a compact operational surface, not a second task-management implementation.

### 3.2 Menu Bar — Quick Actions

The menu bar popover shall contain:

1. **Quick Capture field** at the top.
2. **Current timer area**, showing the active task, elapsed session time, accumulated task time, and pause action.
3. **Relevant tasks**, allowing completion and timer start/resume.
4. **Open Disciplina** action to access the full application.

When no timer is running, the timer area shall show a compact idle state or a resumable paused task, if available.

#### Relevant task selection

- The running task always appears first and is never duplicated in the list.
- Show up to five additional non-completed tasks.
- Prioritize paused In Progress tasks before To Do tasks.
- Within each group, order by most recently updated.
- Completed tasks are hidden from the menu bar list.
- An action to open the full application remains visible.

#### Popover sizing

- Recommended width: 360–400 points.
- Height determined by intrinsic content.
- Minimum height sufficient for Quick Capture and navigation.
- Maximum height: the lesser of 600 points or the available screen height minus safe margins.
- Only the task-list area scrolls where practical.
- Quick Capture, running timer controls, and the application-navigation action remain visible outside the scroll region.
- Empty sections must not reserve unnecessary space.
- All content must remain usable with larger accessibility text settings.

#### Menu bar interaction

- Clicking an incomplete task's completion control marks it Completed.
- Clicking Start begins timing the selected task.
- Clicking Pause closes its active work session.
- Clicking Resume creates a new work session for that task.
- The application must communicate successful transitions and errors without intrusive modal dialogs.
- The popover should dismiss normally when interacting elsewhere, except when the user is completing a temporary confirmation action.

### 3.3 Full Application — Task Management

The full application shall contain three task groups:

- **In Progress**
- **To Do**
- **Completed**

A task's status determines its group, not whether its timer is currently running.

#### Task rows

Each task row shall support:

- Completion checkbox or equivalent accessible control
- Task title
- Current status
- Running or paused indicator where applicable
- Total accumulated work duration
- Start, pause, or resume action where relevant
- Context menu for editing, changing status, opening details, and deleting

The active running task should be visually identifiable without requiring the user to interpret color alone.

#### Task details

Selecting a task opens a lightweight detail presentation.

The details view shall display:

- Title
- Status
- Creation date
- Completion date, if applicable
- Total accumulated duration
- Timer controls
- Chronological work-session history

Session history shall show each recorded session's start time, end time, duration, and ending reason when useful.

Session records are read-only in v1.0.1.

#### Editing and deletion

- Inline or focused title editing is allowed.
- Blank or whitespace-only titles are rejected.
- Invalid input does not overwrite the previous title.
- Editing Escape cancels the draft; Enter commits it.
- Delete uses a recoverable soft-delete mechanism.
- Deletion provides an immediate Undo action.
- A running timer must be safely stopped before its task is deleted.

---

## 4. Task Status and Timer Requirements

### 4.1 Three independent concepts

**Task status** describes the task's workflow state.

**Timer execution state** describes whether active timing is occurring.

**Work session** is a persisted record of one uninterrupted period of manually timed work.

These concepts must not be collapsed into a single boolean or status field.

### 4.2 Task statuses

| Status | Meaning | Timer allowed |
|---|---|---|
| To Do | Work has not currently been started or has been reset | Not while remaining To Do |
| In Progress | Work has started, whether currently active or paused | Yes |
| Completed | Task has been finished | No |

A previously worked task can return to To Do without deleting historical sessions. Consequently, To Do represents current workflow status, not proof that the task has never been worked on.

### 4.3 Timer states

| State | Description |
|---|---|
| Idle | No active session for this task |
| Running | An open session is accumulating time |
| Paused | Task is In Progress but has no active session |

Paused is a derived UI state, not an additional persisted task status.

### 4.4 State-transition rules

| User action | Resulting status | Timing behavior |
|---|---|---|
| Create task | To Do | No session |
| Start To Do task | In Progress | Start new session |
| Start paused In Progress task | In Progress | Start new session |
| Pause running task | In Progress | End current session |
| Resume paused task | In Progress | Start new session |
| Complete To Do task | Completed | No session created |
| Complete paused task | Completed | No timer change |
| Complete running task | Completed | End session atomically |
| Move In Progress to To Do | To Do | End active session, preserve recorded time |
| Reopen Completed to To Do | To Do | Preserve recorded time |
| Reopen Completed to In Progress | In Progress | Remains paused until manually started |
| Delete running task | Hidden/deleted | End session, then soft-delete |
| Restore deleted task | Previous status | Timer remains stopped |

Completing a task updates its completion timestamp. Reopening clears that timestamp.

Repeated completion or pause commands must be safe and must not generate additional work sessions.

### 4.5 Single-timer invariant

**Only one work session may be running across the application at any time.**

Recommended handoff behavior:

1. The user starts timing Task B while Task A is running.
2. Disciplina ends Task A's current session.
3. Task A remains In Progress, paused.
4. Disciplina creates and starts a session for Task B.
5. The UI displays a brief confirmation: “Paused Task A · Started Task B.”

The change must be committed as one logical transaction, avoiding a state where both timers are running or where the old session ends without the new one starting.

No modal confirmation is required because the previous task's time is preserved and its status remains unchanged.

Starting the already-running task is a no-op.

### 4.6 Time display

- Show elapsed time in `HH:MM:SS` while timing.
- For durations exceeding 99 hours, allow hours to expand.
- Show task totals in a concise format such as `2h 14m`, with more precise duration available in details.
- Update the display approximately once per second.
- Do not write to the database for every visual tick.
- Display values should be calculated from authoritative accumulated duration plus the current valid in-memory interval.

---

## 5. Reliable Timing Architecture

### 5.1 Core timing policy

Never calculate work duration using only:

`Date.now - sessionStartDate`

Wall-clock time can change, and elapsed time across an unexpected termination is not verifiable.

Use Swift's `SuspendingClock` for measuring intervals while the machine is awake. Store normal `Date` values separately for session history and presentation.

### 5.2 Session persistence

Each running session maintains:

- Persisted accumulated duration
- Most recently committed checkpoint
- In-memory monotonic checkpoint instant
- Session start timestamp
- Current ownership by the timer coordinator

Recommended persistence cadence: every five seconds while actively running, plus immediately on start, pause, switch, completion, sleep, and graceful application termination.

A checkpoint writes the cumulative session duration, not a new independent time interval. This prevents duplicate counting when an operation is retried.

Use integer milliseconds for stored duration.

### 5.3 Crash recovery

When Disciplina launches:

1. Load the persisted task and session state.
2. Detect sessions left open by a previous application run.
3. Preserve their last committed durations.
4. Close them with an `interrupted` ending reason.
5. Use the last trusted checkpoint as the recovery boundary.
6. Restore their tasks as paused In Progress.
7. Do not automatically resume any timer.

**Never add the time between the final checkpoint and the new application launch.**

This favors conservative recovery over inventing work duration.

A sudden termination may lose up to one normal checkpoint interval, but it must not produce artificial time or double count a previous interval.

### 5.4 System sleep and wake

- Observe macOS sleep and wake notifications.
- Before sleep, commit accumulated valid time and pause the active session.
- After wake, keep the session paused until manually resumed.
- If a sleep notification is missed, do not infer an uninterrupted working interval from wall-clock time.
- Detect abnormal checkpoint gaps and recover from the last trusted checkpoint.

A checkpoint watchdog should flag unexpectedly large gaps, with 15 seconds as an initial configurable engineering threshold. For an untrusted gap, prefer pausing and potential undercounting to fabricating elapsed work time.

### 5.5 Clock adjustments

- Monotonic time determines durations.
- Wall-clock timestamps determine human-readable session dates.
- Forward or backward changes to the system clock must not change accumulated duration.
- If wall-clock changes create unusual session timestamps, retain the authoritative duration and avoid repairing history by adding or subtracting time.
- Wall-clock timestamps must never be used to recreate missing running duration.

### 5.6 Timer engine rules

- One process-wide `TimerCoordinator` owns timing.
- All timer commands are serialized.
- A single source owns the active session identifier.
- No view creates independent stopwatch state.
- No view directly edits session durations.
- Persisted checkpoints are idempotent cumulative updates.
- Database writes must succeed before a transition is reported as completed.

---

## 6. Quick Capture — Automatic Focus

### 6.1 Problem statement

The existing global shortcut opens the menu bar popover, but the input does not automatically receive keyboard focus.

This interrupts capture and requires an unnecessary mouse click.

### 6.2 Required behavior

1. User presses the configured global shortcut.
2. Disciplina presents a key-capable Quick Capture interface.
3. The text input becomes first responder.
4. Keyboard input works immediately.
5. Enter validates and persists the task.
6. Successful creation dismisses the capture interface.
7. Escape dismisses without creating a task.

If saving fails, the input remains visible with its draft text and an accessible error message.

Input focus must work whether the main window is open, hidden, or another application is active.

### 6.3 Recommended implementation

Keep the existing menu bar popover for mouse-driven quick actions, but use a dedicated lightweight AppKit `NSPanel` for shortcut-driven Quick Capture.

Both surfaces should reuse the same SwiftUI capture component and task-creation service.

This eliminates dependence on the menu bar popover's implicit key-window behavior when invoked from an external application.

#### Focus implementation sequence

1. The shortcut handler calls the main-actor capture coordinator.
2. The coordinator creates or reuses one `NSPanel`.
3. The panel is configured to accept key-window status.
4. The panel is presented using `makeKeyAndOrderFront`.
5. The application requests activation through `NSApp.activate()` when appropriate.
6. The coordinator waits for the panel's actual key-window activation event.
7. SwiftUI `@FocusState` targets the task input.
8. If SwiftUI focus alone is insufficient, a narrow AppKit text-field bridge calls `makeFirstResponder` on the actual input view.
9. Focus success is validated through integration testing.

Do not rely on arbitrary delays, repeated timers, or a global keyboard event monitor to make focus work.

Do not use deprecated activation APIs for new implementation.

### 6.4 Repeated shortcut behavior

| Situation | Expected behavior |
|---|---|
| Quick Capture closed | Open and focus input |
| Quick Capture already open | Refocus existing input; do not close |
| Draft already entered | Preserve draft |
| Main application open | Present Quick Capture above it |
| Menu bar popover open | Focus its existing capture field where reliable, or close the popover and open the Quick Capture panel |
| Modal task edit active | Preserve its unsaved data; Quick Capture must not silently discard it |
| Shortcut pressed rapidly | One capture interface only |
| Shortcut registration unavailable | Preserve normal app functionality and expose a configuration warning |

When dismissal follows shortcut-driven capture, restore the previous application's focus only if Disciplina still owns focus and the user has not switched elsewhere.

A native menu bar popover should continue to auto-focus its own input where the system permits. The dedicated panel remains the reliable global-shortcut pathway.

---

## 7. Data Architecture

### 7.1 Recommended architecture

Retain the existing SwiftUI application and introduce or formalize the following boundaries:

```text
Presentation
  MenuBarView
  MainWindowView
  TaskDetailsView
  QuickCaptureView
  SettingsView

Application
  TaskStore
  TaskService
  TimerCoordinator
  QuickCaptureCoordinator
  DataTransferService

Domain
  TodoItem
  TaskStatus
  WorkSession
  TaskRepository
  WorkSessionRepository

Data
  SwiftDataTaskRepository
  SwiftDataWorkSessionRepository
  PersistenceController

Platform
  HotkeyService
  WindowCoordinator
  SleepWakeObserver
  LoginItemService

DesignSystem
  Colors
  Typography
  Components
```

The existing application should be refactored incrementally, not rebuilt.

A single shared `TaskStore` publishes authoritative task and timer state to all interfaces.

Use `@MainActor` for the initial coordinator and repository integration to simplify serialized operations with the main SwiftData context.

Background workers and additional modules are unnecessary until workload or profiling results justify them.

### 7.2 Task model

```swift
enum TaskStatus: String, Codable, Sendable {
    case todo
    case inProgress
    case completed
}

struct TodoItem: Identifiable, Sendable {
    let id: UUID
    var title: String
    var status: TaskStatus

    let createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
    var deletedAt: Date?
}
```

The running state is not stored as a second independent boolean on the task.

Total work duration is derived from the task's sessions.

### 7.3 Work-session model

```swift
enum SessionEndReason: String, Codable, Sendable {
    case paused
    case switchedTask
    case completed
    case movedToTodo
    case deleted
    case systemSleep
    case appQuit
    case interrupted
}

struct WorkSession: Identifiable, Sendable {
    let id: UUID
    let taskID: UUID

    let startedAt: Date
    var endedAt: Date?

    var accumulatedMilliseconds: Int64
    var lastCheckpointAt: Date?

    var endReason: SessionEndReason?
}
```

The session's cumulative duration is authoritative.

`startedAt`, `endedAt`, and `lastCheckpointAt` are presentation and recovery metadata, not substitutes for monotonic elapsed-time measurements.

A session is considered open while `endedAt == nil`.

An open session must never be resumed after a process restart; a new session is created on manual Resume.

### 7.4 Persisted invariants

- Task IDs are unique.
- Work-session IDs are unique.
- Every session references a valid task.
- No task has more than one open session.
- No application store has more than one open session globally.
- To Do and Completed tasks cannot own active timers.
- Completed tasks have completion timestamps.
- Recorded durations are non-negative.
- Deleting a task preserves its sessions for Undo and recovery.
- Restoring a task never automatically starts timing it.

These invariants are enforced through service validation and appropriate persistence constraints where supported.

### 7.5 Synchronization

All interfaces must observe the same application-state owner.

An action follows this sequence:

```text
User action
    ↓
Shared TaskStore / Application command
    ↓
TaskService or TimerCoordinator
    ↓
Repository persistence
    ↓
Successful committed state
    ↓
Shared observable update
    ↓
Menu bar + Main application
```

No view may maintain a separate authoritative task collection or timer value.

UI state updates should be based on committed data or safely reversible pending state.

---

## 8. Data Safety, Migration, and Recovery

### 8.1 Persistent storage

Continue using the existing local persistence engine where practical, preferably SwiftData if already implemented.

- Save significant mutations explicitly.
- Never silently swallow persistence errors.
- Prevent duplicate task creation from repeated Enter presses during the same pending save.
- Use UUIDs as stable identities.
- Preserve stored data independently of application window lifecycle.
- Do not delete the database automatically when loading or migration fails.

### 8.2 Safe editing

- Editing happens against a local draft.
- The original task remains unchanged until Save.
- Cancel and Escape discard the draft.
- Save validation occurs before persistence.
- A failed save preserves the draft and shows an error.

### 8.3 Recoverable deletion

Use soft deletion with a persisted `deletedAt` timestamp.

- Deleted tasks disappear from normal lists.
- Their work sessions are retained.
- The immediate UI offers Undo.
- Standard macOS Undo (`⌘Z`) is supported where the action context permits.
- A Recently Deleted section in Data & Recovery allows later restoration.
- Permanent deletion requires an explicit confirmation.
- Restored tasks return with their previous status and recorded time, but no running timer.

This prevents accidental or interrupted deletion from becoming irreversible.

### 8.4 Migration from V1

Implement explicit versioned schema migration for the actual current V1 data layout.

Suggested mapping:

| Existing V1 task | v1.0.1 result |
|---|---|
| Incomplete | To Do |
| Completed | Completed |
| Existing identifier | Preserve unchanged |
| Existing title | Preserve unchanged |
| Existing creation time | Preserve unchanged |
| Existing completion time | Preserve unchanged |
| Existing ordering | Preserve where available |
| Work sessions | Initially empty |
| Total tracked time | Zero |

Migration requirements:

1. Inspect and freeze the real V1 schema.
2. Create a consistent pre-migration backup before mutation.
3. Apply migration using a versioned schema plan.
4. Validate record counts, identities, and required attributes.
5. Verify referential integrity and timer invariants.
6. Mark migration successful only after validation.
7. On failure, preserve the backup and display a recovery path instead of initializing an empty database.

SQLite-backed database snapshots must be consistent with any journal or write-ahead-log files; naive copying of an open database file is not sufficient.

Migration must be tested against actual copies of the previous release's data, not solely freshly generated v1.0.1 stores.

### 8.5 Data export

Provide **Export Data** in Settings → Data & Recovery.

Recommended format: versioned JSON.

Export includes:

- Format version
- Export timestamp
- Tasks and their identifiers
- Statuses and timestamps
- Work sessions
- Accumulated durations
- Soft-deletion information

No online service is required.

Machine-specific shortcut registration and transient focus/window state are excluded.

The export must represent a consistent snapshot and must not include live, uncommitted timer duration.

### 8.6 Data restore

Restore uses a replace-from-backup workflow in v1.0.1.

1. Read and validate the entire selected file.
2. Reject malformed, unsupported, duplicated, or inconsistent records.
3. Show a confirmation explaining that current data will be replaced.
4. Checkpoint and pause any running timer.
5. Create a backup of current local data.
6. Perform the restore as a single logical transaction or staged atomic store replacement.
7. On success, reload the shared application state.
8. On failure, preserve the original data and display a recoverable error.

No silent partial imports.

All restored tasks with open or interrupted sessions must start in a non-running state.

---

## 9. Design System

### 9.1 Brand foundation

**Primary brand color: Burgundy — `#7A2849`**

The brand color represents deliberate action, focus, and active effort.

Use it sparingly.

Neutral system surfaces and typography remain dominant.

### 9.2 Semantic color tokens

| Token | Usage |
|---|---|
| `brand.primary` | Canonical burgundy `#7A2849` |
| `brand.interactive` | Theme-aware accessible accent |
| `brand.subtleBackground` | Subtle selection/background tint |
| `surface.primary` | Main window background |
| `surface.secondary` | Cards and grouped regions |
| `text.primary` | Primary system text |
| `text.secondary` | Supporting information |
| `border.subtle` | Native separators |
| `state.running` | Brand-accent timer indicator |
| `state.paused` | Neutral paused indicator |
| `state.completed` | Neutral completed indicator |
| `state.error` | System semantic error color |
| `focus.ring` | Accessible native focus indicator |

### 9.3 Light and dark appearance

Use the same burgundy brand identity in both appearances, but not necessarily the identical color value for every interactive element.

Recommended initial values:

| Usage | Light | Dark |
|---|---|---|
| Brand reference | `#7A2849` | `#7A2849` |
| Accessible accent text/icon | `#7A2849` | `#E7A9BE` |
| Primary text | System primary | System primary |
| Secondary text | System secondary | System secondary |
| Background | System background | System background |
| Separator | System separator | System separator |

The lighter dark-mode value is an accessibility adaptation of the same burgundy palette, not an additional brand color.

Use native dynamic system colors for neutral surfaces.

Filled actions must use foreground/background combinations with sufficient contrast.

### 9.4 Task-state visual semantics

- **To Do:** neutral circle and text label where needed.
- **In Progress, running:** burgundy-accent indicator, live time, and Pause control.
- **In Progress, paused:** pause symbol, neutral styling, and Resume control.
- **Completed:** checkmark, reduced emphasis, and Completed label.
- **Error:** native error treatment with explanatory text.

Never rely exclusively on color.

### 9.5 Accessibility requirements

- Keyboard access to every interactive feature.
- Logical Tab and Shift+Tab order.
- Visible keyboard focus indicators.
- VoiceOver labels that include task name and relevant action.
- Accessible timer announcements without announcing every second.
- Adequate hit targets and spacing.
- Support for increased contrast and reduced motion.
- Screen Reader support for status, session duration, and errors.
- Text contrast of at least 4.5:1 for normal text.
- Essential non-text control indicators at least 3:1 contrast against adjacent colors.

---

## 10. Keyboard Interaction Contract

| Context | Shortcut/action | Expected result |
|---|---|---|
| Global | User-configured shortcut | Open/refocus Quick Capture |
| Quick Capture | Enter | Save task |
| Quick Capture | Escape | Dismiss without saving |
| Main window | `⌘N` | Focus Add Task |
| Task editor | Enter | Commit valid changes |
| Task editor | Escape | Cancel changes |
| Task lists | Arrow keys | Navigate task rows |
| Task lists | Space | Toggle selected task completion, when appropriate |
| Task lists | Return | Open selected task details, when list has focus |
| Undo-supported action | `⌘Z` | Undo previous supported action |
| Application | `⌘,` | Open Settings |

Text fields must retain standard macOS text editing behavior, including selection, copy/paste, and their own Undo handling.

A global shortcut must not register multiple independent listeners.

Shortcut configuration failures must not break normal task management.

---

## 11. Reliability and Acceptance Testing

### 11.1 Task integrity

- Existing tasks remain after upgrading.
- New tasks survive application termination and relaunch.
- Invalid edits cannot overwrite valid titles.
- Rapid repeated Save does not create unintended duplicates.
- Deletion and Undo preserve identifiers and recorded durations.
- Task state remains consistent between windows.

### 11.2 Timer correctness

- Start creates exactly one session.
- Pause stores the correct elapsed duration.
- Resume creates another session.
- Switching tasks preserves both session histories.
- Only one session is running at a time.
- Completing a running task stops the timer.
- Reverting status does not erase recorded time.
- Clock changes do not alter duration.
- Sleep does not add unattended hours.
- Force quit and restart do not add unverified time.
- Restart leaves an interrupted timer paused.
- Total duration equals the sum of persisted session durations plus only the current valid uncommitted running interval.

### 11.3 Quick Capture

Test from:

- Finder
- A normal third-party application
- A full-screen application
- Another macOS Space
- A secondary monitor
- An open Disciplina main window
- An already-visible menu bar popover

For each supported configuration, verify that the input receives focus immediately and typing works without a click.

Repeated shortcut activation must not create duplicate windows or discard the current draft.

The release must have zero reproducible focus failures across its defined test matrix.

### 11.4 Migration and recovery

- Upgrade a real V1 database.
- Upgrade an empty V1 database.
- Upgrade a database containing many completed tasks.
- Simulate migration failure.
- Verify backup remains recoverable.
- Test export and restore round-trip.
- Test malformed and duplicated JSON input.
- Test restore while a timer is running.
- Verify that an interrupted restore does not partially overwrite existing data.

### 11.5 Performance targets

These are validation targets, not assumed results:

- Quick Capture warm presentation and focus: target under 300 ms on the reference development Mac.
- Timer display: smooth approximately one-second updates.
- Persistence: no noticeable task-action UI blocking.
- Menu bar: usable with at least 1,000 stored tasks.
- Popover: bounded height and stable scrolling.
- No excessive CPU activity from stopwatch updates.

---

## 12. Prioritized Development Backlog

Story points represent relative complexity rather than guaranteed elapsed development time.

| ID | Development task | Priority | Points |
|---|---|---|---|
| ARCH-01 | Audit existing V1 architecture and schema | P0 | 3 |
| ARCH-02 | Establish shared application-state ownership | P0 | 5 |
| DATA-01 | Introduce status and session schema | P0 | 5 |
| DATA-02 | Implement and test V1 migration | P0 | 8 |
| TIMER-01 | Implement timer coordinator and monotonic timing | P0 | 8 |
| TIMER-02 | Implement session persistence and checkpoints | P0 | 8 |
| TIMER-03 | Implement single-timer handoff and status transitions | P0 | 5 |
| TIMER-04 | Implement sleep, crash, and restart recovery | P0 | 8 |
| FOCUS-01 | Implement key-capable Quick Capture panel | P0 | 8 |
| FOCUS-02 | Implement first-responder coordination | P0 | 5 |
| FOCUS-03 | Resolve repeated shortcuts and window coexistence | P0 | 3 |
| UI-01 | Refactor menu bar to Quick Actions | P0 | 5 |
| UI-02 | Implement adaptive popover sizing and scrolling | P0 | 3 |
| UI-03 | Organize full application by status | P0 | 5 |
| UI-04 | Build task detail and work-session history | P0 | 5 |
| SAFE-01 | Implement recoverable deletion and Undo | P0 | 5 |
| SAFE-02 | Implement JSON export and atomic restore | P0 | 8 |
| DESIGN-01 | Introduce semantic burgundy tokens | P1 | 3 |
| DESIGN-02 | Apply consistent light/dark styling | P1 | 3 |
| ACCESS-01 | Complete keyboard and VoiceOver support | P0 | 5 |
| QA-01 | Automated task, timer, persistence, and migration tests | P0 | 8 |
| QA-02 | macOS integration and release regression testing | P0 | 8 |

### Recommended execution order

**Phase 1 — Data safety and architecture**

Audit the existing implementation, identify the current persistence schema, create migration fixtures, and establish shared state boundaries.

Deliverable: safe foundation for new persisted task and session data.

**Phase 2 — Timing domain**

Implement statuses, session models, timer coordinator, monotonic checkpoints, timer handoff, and interrupted-session recovery.

Deliverable: reliable manual time tracking independent of interface design.

**Phase 3 — Quick Capture reliability**

Introduce the AppKit-controlled capture surface, keyboard-focus coordination, repeated-shortcut handling, and focus tests.

Deliverable: reliable mouse-free task capture.

**Phase 4 — Interface restructuring**

Separate menu bar quick actions from full task management. Add adaptive popover sizing, status sections, total durations, and session history.

Deliverable: consistent, purpose-specific interfaces.

**Phase 5 — Recovery and design**

Implement safe deletion, Undo, export/restore, the semantic brand palette, and accessibility refinements.

Deliverable: durable, consistent, production-ready personal workflow.

**Phase 6 — Regression and release**

Validate previous functionality, migration, timer correctness, Quick Capture behavior, and native macOS accessibility.

Deliverable: verified Disciplina v1.0.1 build.

---

## 13. Release Definition of Done

Disciplina v1.0.1 is complete when all of the following conditions hold:

- [ ] Existing V1 tasks migrate without data loss.
- [ ] Menu bar functions as a compact quick-action interface.
- [ ] Main window functions as the full task-management interface.
- [ ] Global Quick Capture accepts typing without mouse interaction.
- [ ] All three task statuses behave according to the transition specification.
- [ ] Timers start, pause, resume, and switch reliably.
- [ ] No two tasks can accumulate time simultaneously.
- [ ] Work sessions and totals persist across restarts.
- [ ] Sleep, unexpected termination, and clock changes do not inflate time.
- [ ] Deletion is recoverable and Undo is available.
- [ ] JSON export and restore pass round-trip and failure tests.
- [ ] State is synchronized across all application interfaces.
- [ ] Burgundy design tokens are consistently applied.
- [ ] Keyboard navigation and VoiceOver acceptance tests pass.
- [ ] Critical persistence, data-integrity, and focus defects are resolved.

### Final engineering direction

Disciplina v1.0.1 should remain one native, local-first application with a shared task store, a single timer coordinator, and focused platform adapters.

The goal is not to introduce additional architectural layers for their own sake. The goal is to make task handling, timing, and recovery predictable so that future productivity features can be implemented without rewriting the foundation.

**Release principle: reliability and speed of interaction take precedence over feature quantity.**
