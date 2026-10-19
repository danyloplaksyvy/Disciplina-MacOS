# Disciplina V1 — Final Product & Engineering Specification

Scope approved

Specification v1.0 · October 19, 2026

Product: Disciplina Platform: macOS Initial audience: Personal use, with future public distribution Product philosophy: Minimal friction, native experience, scalable engineering

## 1. Executive summary

Disciplina V1 will be a native macOS task manager focused on capturing tasks quickly and completing them with minimal disruption.

The product will have three entry points:

Menu Bar Popover

Quickly view, add, and complete tasks while working in other applications.

Main Application Window

Manage the full task list, edit tasks, review completed work, and access settings.

Global Quick Capture

Press a configurable keyboard shortcut from another application, type a task, press Enter, and return to work.

All three interfaces will operate on the same local task database and share application state.

### V1 success criteria

| KPI                    | Target                                      |
| ---------------------- | ------------------------------------------- |
| Quick capture          | One shortcut, type, Enter                   |
| Task completion        | One click                                   |
| Local data persistence | Survives app and system restart             |
| Task synchronization   | Immediate between all open Disciplina views |
| Login                  | No account required                         |
| Internet               | Entire app works offline                    |
| Development            | Maintainable, testable, and easy to extend  |

The key validation question is: Does Disciplina make task capture sufficiently effortless that you use it throughout the day?

## 2. Product requirements

### 2.1 Features included in V1

| ID    | Feature                            | Priority |
| ----- | ---------------------------------- | -------- |
| FR-01 | Create a task                      | P0       |
| FR-02 | Complete and reopen a task         | P0       |
| FR-03 | Edit a task title                  | P0       |
| FR-04 | Delete a task                      | P0       |
| FR-05 | Active and completed sections      | P0       |
| FR-06 | Persistent local database          | P0       |
| FR-07 | macOS menu bar popover             | P0       |
| FR-08 | Main application window            | P0       |
| FR-09 | Global quick-capture shortcut      | P0       |
| FR-10 | Configurable shortcut              | P0       |
| FR-11 | Shared state across all interfaces | P0       |
| FR-12 | Keyboard interactions              | P0       |
| FR-13 | Launch at login option             | P1       |
| FR-14 | Native dark/light mode             | P1       |
| FR-15 | Accessibility and UI polish        | P1       |

P0 means required before using the first version daily. P1 means required before calling the personal beta polished and complete.

### 2.2 Task behavior specification

| Action             | Expected behavior                                     |
| ------------------ | ----------------------------------------------------- |
| Add                | Trim whitespace, save task, display in Active         |
| Complete           | Move to Completed and record completion time          |
| Reopen             | Move back to Active and clear current completion time |
| Edit               | Update title and modification timestamp               |
| Delete             | Ask for confirmation, then permanently remove         |
| Empty title        | Reject without creating a task                        |
| Duplicate titles   | Allowed                                               |
| Maximum title      | 200 characters                                        |
| Active ordering    | Newest creation first                                 |
| Completed ordering | Most recently completed first                         |

Tasks will contain a single-line title. No descriptions, dates, priorities, projects, or subtasks in V1.

An empty list should have a friendly message and an obvious task-creation action rather than an empty screen.

## 3. Screens and interaction details

A. Menu bar popover

Suggested width: 340–380 pt

Primary daily interface

## Disciplina

Add a task...

Active

3

Finish SwiftUI setup

Implement persistence

Test global shortcut

Completed

2

Open full app

⌘ O

Behavior: the input receives focus when the popover opens. Enter creates a task and keeps the input ready. The Completed section starts collapsed. For long lists, the popover uses a bounded scroll area, with the full window available for reviewing everything.

B. Main application window

Suggested initial size: 860 × 600 pt

## My Tasks

Add a task...

Active tasks

3 remaining

Finish SwiftUI setup

Implement persistence

Test global shortcut

Completed tasks

Define V1 requirements

Choose architecture

5 tasks in total

Local storage

Behavior: show the full list, support inline editing and contextual delete actions. The window is resizable, supports keyboard navigation, and can be reopened without creating duplicate windows.

C. Global quick-capture panel

Quick Capture

Esc

What needs to get done?

↵ Save task

Esc Cancel

Behavior: a temporary centered panel appears over the current workspace. The text field is automatically focused. Enter saves and dismisses it; Escape dismisses without saving. It is never permanently floating.

I recommend implementing this quick-capture panel with AppKit's `NSPanel`, embedding the input UI in SwiftUI. Panel focus, Spaces, and full-screen application behavior will require real-device testing.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://developer.apple.com\&sz=32)

Apple Developer Documentation



### Keyboard interactions

| Shortcut                     | Action                                     |
| ---------------------------- | ------------------------------------------ |
| Configurable global shortcut | Open quick capture                         |
| `Enter`                      | Save task                                  |
| `Esc`                        | Cancel editing or dismiss temporary UI     |
| `⌘N`                         | Focus new-task input in main window        |
| `⌘,`                         | Open settings                              |
| `⌘O`                         | Open main task window                      |
| `Space`                      | Toggle selected task (when list has focus) |

Global shortcut recommendation: Start with `⌃⌥Space` for your personal build, but let the user change it. During public onboarding, users should choose their own shortcut to minimize conflicts with existing applications.

### Application lifecycle

- Launching Disciplina manually opens the main window and installs its menu bar icon.
- Closing the main window keeps Disciplina running in the menu bar.
- Clicking the menu bar icon opens the task popover.
- The global shortcut works while Disciplina is running, even when another application is active.
- Launch at login is optional and disabled by default; when enabled, it starts quietly without forcing the main window to appear.
- Quit is available through the app menu and popover.

The Dock icon remains visible in V1. A menu-bar-only mode can be considered later.

## 4. Explicitly excluded from V1

We should not implement goals, time tracking, screen capture, AI analysis, accounts, cloud synchronization, recurring tasks, subtasks, reminders, priorities, projects, or deadlines yet.

One additional decision: do not show a “Today's productivity” score in V1. Since tasks have no scheduling or time-tracking context, that metric could be misleading. Active and completed counts are sufficient for the first release.

## 5. Technology stack — Final decision

| Area              | Technology                         | Rationale                             |
| ----------------- | ---------------------------------- | ------------------------------------- |
| Language          | Swift                              | Native macOS development              |
| UI                | SwiftUI                            | Declarative UI, reusable components   |
| macOS-specific UI | AppKit                             | Quick-capture panel and focus control |
| Menu bar          | `MenuBarExtra`                     | Native menu bar integration           |
| Main window       | SwiftUI `Window`                   | Single-instance window                |
| Local database    | SwiftData                          | Native persistent storage             |
| Architecture      | MVVM + Repository + Domain service | Testability and extensibility         |
| State management  | Swift Observation (`@Observable`)  | Shared reactive application state     |
| Shortcut handling | KeyboardShortcuts package          | Configurable global shortcuts         |
| Settings          | `UserDefaults` / `@AppStorage`     | Lightweight preference storage        |
| Testing           | Swift Testing + XCUITest           | Unit and UI tests                     |
| Minimum target    | macOS 14                           | Modern SwiftUI and SwiftData support  |

Apple supports `MenuBarExtra` with a popover-like window style and a separate main application window. SwiftUI's `Window` scene provides a unique window, while `openWindow(id:)` can bring an existing window forward.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://developer.apple.com\&sz=32)

Apple Developer Documentation

+2



For global shortcuts, I recommend the [KeyboardShortcuts Swift package](https://github.com/sindresorhus/KeyboardShortcuts?utm_source=chatgpt.com). It supports configurable hotkeys, a native recording UI, sandboxed apps, and does not require a system permission dialog for its standard hotkey functionality.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://github.com\&sz=32)

GitHub



This is the only third-party package I would introduce initially.

## 6. Architecture specification

### 6.1 Architectural principles

The application should follow five rules:

1. UI never directly modifies persistence models.
2. Business rules should not depend on SwiftUI or SwiftData.
3. All task interfaces use a shared state owner.
4. Platform-specific functionality is isolated behind services.
5. Complexity is introduced when a feature requires it, not in anticipation of every possible future feature.

Presentation

MenuBarView · MainWindowView · QuickCaptureView

TaskStore — Shared Observable State

Active tasks · Completed tasks · UI actions · Error state

Domain

TodoItem · TaskService · TaskRepository protocol

Data

SwiftDataTaskRepository → SwiftData → Local Database

Platform Services

WindowCoordinator

HotkeyService

LoginItemService

Independent of task business logic

### 6.2 Layer responsibilities

| Layer                   | Responsibility                                               |
| ----------------------- | ------------------------------------------------------------ |
| Views                   | Render state, collect user actions, manage local input focus |
| TaskStore               | Expose shared application state and coordinate actions       |
| TaskService             | Validate titles and enforce task state transitions           |
| TaskRepository          | Define operations for reading and modifying tasks            |
| SwiftDataTaskRepository | Implement persistence operations                             |
| Platform services       | Control windows, shortcuts, and login behavior               |

Important: For V1, `TaskStore` can fulfill the ViewModel responsibility for all three interfaces. We do not need three independent ViewModels holding duplicate copies of the task list.

When feature complexity grows, dedicated ViewModels can be introduced without replacing the repository or domain model.

### 6.3 Project structure

```
Disciplina/
│
├── App/
│   ├── DisciplinaApp.swift
│   ├── AppDependencies.swift
│   └── AppCoordinator.swift
│
├── Features/
│   ├── Tasks/
│   │   ├── Views/
│   │   │   ├── MainTaskWindowView.swift
│   │   │   ├── MenuBarTaskView.swift
│   │   │   ├── TaskListView.swift
│   │   │   ├── TaskRowView.swift
│   │   │   └── TaskInputView.swift
│   │   └── TaskStore.swift
│   │
│   ├── QuickCapture/
│   │   ├── QuickCaptureView.swift
│   │   └── QuickCapturePanel.swift
│   │
│   └── Settings/
│       └── SettingsView.swift
│
├── Domain/
│   ├── Models/
│   │   └── TodoItem.swift
│   ├── Repositories/
│   │   └── TaskRepository.swift
│   └── Services/
│       └── TaskService.swift
│
├── Data/
│   ├── Models/
│   │   └── TaskRecord.swift
│   ├── Persistence/
│   │   └── PersistenceController.swift
│   └── Repositories/
│       └── SwiftDataTaskRepository.swift
│
├── Platform/
│   ├── HotkeyService.swift
│   ├── WindowCoordinator.swift
│   └── LoginItemService.swift
│
├── Shared/
│   ├── DesignSystem/
│   └── Extensions/
│
├── Resources/
│
├── DisciplinaTests/
│
└── DisciplinaUITests/
```

Keep everything in one Xcode application target for now. Folders are architectural boundaries, not separate Swift packages.

## 7. Data model

I recommend calling the domain entity `TodoItem`, avoiding ambiguity with Swift's concurrency `Task` type.

### Domain entity

```

struct TodoItem: Identifiable, Equatable, Sendable {
    let id: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var completedAt: Date?

    var isCompleted: Bool {
        completedAt != nil
    }
}

```

Notice that `isCompleted` is computed from `completedAt`.

This avoids invalid states such as:

- `isCompleted == true`
- `completedAt == nil`

### Persistence entity

The SwiftData model should be a separate class named `TaskRecord`, containing the same persisted attributes. Mapping between `TaskRecord` and `TodoItem` happens inside the Data layer.

### TaskRecord — V1 schema

| `id`          | `UUID`   |
| ------------- | -------- |
| `title`       | `String` |
| `createdAt`   | `Date`   |
| `updatedAt`   | `Date`   |
| `completedAt` | `Date?`  |

No goal identifiers, activity records, projects, or AI-specific fields yet.

For persistence, use one shared `ModelContainer` and its main-actor `ModelContext` for V1. Explicitly save critical mutations and propagate failures to the UI instead of silently reporting success. SwiftData supports both persistent containers and migrations as schemas evolve.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://developer.apple.com\&sz=32)

Apple Developer Documentation

+1



### Repository contract

```

@MainActor
protocol TaskRepository {
    func fetchAll() throws -> [TodoItem]

    func create(title: String) throws -> TodoItem

    func rename(
        id: UUID,
        title: String
    ) throws

    func setCompleted(
        id: UUID,
        isCompleted: Bool
    ) throws

    func delete(id: UUID) throws
}

```

The `TaskService` will handle validation and call this interface.

For example, when completing a task, it sets `completedAt` to the current timestamp. Reopening clears that timestamp. Renaming updates `updatedAt`.

### State synchronization

There should be one source of truth per running app process:

```
User completes a task
          ↓
TaskStore receives the action
          ↓
TaskService validates transition
          ↓
TaskRepository updates SwiftData
          ↓
TaskStore publishes updated tasks
          ↓
Menu bar + Main window refresh
```

Use `@MainActor` for the initial store and repository. This keeps SwiftData's main context isolated correctly and avoids unnecessary concurrency complexity for a small local task list.

The initial implementation can explicitly reload task state after each successful mutation. If performance profiling later justifies it, we can introduce more granular updates.

### Future analytics compatibility

V1 timestamps give us basic historical information about task creation and current completion.

However, they do not preserve every completion/reopening event or measure actual work duration. When analytics becomes part of the product, introduce a dedicated event-history model instead of trying to reconstruct information that was never recorded.

This gives us a clean foundation without prematurely building an analytics pipeline.

## 8. Development backlog

This is the recommended implementation order. Each item represents a task that can become a GitHub issue.

Effort uses relative story points: 1 = very small, 2 = small, 3 = moderate, 5 = substantial, 8 = complex or uncertain.

## V1 Development Tracker

Interactive checklist · Progress is local to this response

## 0/19

Tasks completed

0 / 74 story points

Reset

M1 — Foundation0/4

M2 — Task management0/4

M3 — Native interfaces0/3

M4 — Global quick capture0/3

M5 — Quality and release0/5

&#x20;Copy backlog as Markdown

### Critical path

The most important sequence is:

`APP-02 → DATA-01 → TASK-01 → TASK-03 → UI-03 → HOT-02`

This sequence delivers the basic application architecture, persistent tasks, shared UI state, and the defining quick-capture experience.

The highest-risk item is `HOT-02`, because reliably presenting and focusing a transient panel across macOS Spaces and other applications requires careful native behavior.

## 9. Testing and release requirements

### Automated testing

| Test group        | Required scenarios                                            |
| ----------------- | ------------------------------------------------------------- |
| Domain tests      | Blank titles, whitespace, title length, completion, reopening |
| Repository tests  | CRUD, data mapping, persistence errors                        |
| Persistence tests | Save, reload, delete, schema compatibility                    |
| State tests       | Active/completed sorting, updates after mutations             |
| UI tests          | Task creation, editing, completion and deletion               |
| Integration tests | Main window and popover reflect identical task state          |

Repository tests should use a separate in-memory SwiftData container, avoiding modifications to real user data.

### Manual macOS acceptance tests

Personal beta readiness

0/12 passed

Close the main window; confirm the menu bar app keeps running.

Create a task in the popover; verify it appears in the main window.

Edit and complete a task; verify the updated state survives restart.

Invoke global capture while another application is focused.

Test capture while an application is in full-screen mode.

Test capture across multiple monitors and macOS Spaces.

Verify Escape does not accidentally create a task.

Test unavailable or conflicting keyboard shortcuts.

Test light mode, dark mode, keyboard navigation, and VoiceOver.

Test with at least 1,000 tasks, including completed tasks.

Verify launch-at-login behavior and explicit Quit.

Confirm persistence failures are shown instead of losing input silently.

### Non-functional acceptance targets

These are engineering targets to validate on actual hardware, not promised benchmark results.

| Category        | Target                                                              |
| --------------- | ------------------------------------------------------------------- |
| Performance     | Warm quick capture ready for input in approximately 300 ms or less  |
| Responsiveness  | Task interaction feels immediate, without visible UI blocking       |
| Reliability     | No silent data loss during normal operations                        |
| Privacy         | No account, telemetry, remote API, or screen-monitoring permissions |
| Accessibility   | Standard keyboard control and VoiceOver labels                      |
| Maintainability | Domain logic covered by tests and independent of SwiftData          |
| Platform        | Reliable on the supported macOS versions                            |

For launch at login, use Apple's `SMAppService.mainApp` registration rather than manually managing a background daemon. The preference UI should report registration failures and respect system approval.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://developer.apple.com\&sz=32)

Apple Developer Documentation



## 10. Important architectural decisions to preserve

These decisions form the baseline for future development.

| Decision                              | Reason                                                           |
| ------------------------------------- | ---------------------------------------------------------------- |
| Native SwiftUI first                  | Best integration with macOS workflows                            |
| AppKit only where necessary           | Avoids unnecessary platform-specific complexity                  |
| Local-first storage                   | Fast, private, independent of the internet                       |
| No backend in V1                      | Reduces cost, authentication complexity, and deployment overhead |
| Shared task store                     | Avoids inconsistent UI state                                     |
| Repository abstraction                | Provides testability and storage flexibility                     |
| Task timestamps from day one          | Supports basic future progress analysis                          |
| No speculative feature modules        | Prevents premature overengineering                               |
| Explicit SwiftData migration strategy | Helps protect user data during future releases                   |

I would also defer making the application menu-bar-only or removing the Dock icon until we have validated the daily workflow. Both UX directions remain possible.

## 11. Definition of Done

Disciplina V1 is complete when a user can install it, launch it, and reliably manage their tasks entirely offline; create tasks through the menu bar, full window, or global keyboard shortcut; edit, complete, reopen, and delete tasks; and close and relaunch the application without losing saved data.

Every P0 backlog item must pass its acceptance criteria, the manual macOS checklist must pass, and critical data-persistence issues must be resolved before the personal beta is considered complete.

## 12. Recommended first implementation step

Start with APP-01 and APP-02: the native macOS application shell.

The first deliverable should be a working, initially empty application that supports:

- A menu bar icon that opens a SwiftUI popover.
- A separate main window that can be closed and reopened.
- Shared dependency injection across both interfaces.
- Correct application lifecycle behavior.

Do not build the task database or quick-capture panel until this native application shell is reliable.

This specification is now a reasonable baseline for Disciplina V1. The scope is intentionally small, but its architecture is structured to evolve toward the original vision: a goal-achievement platform that combines task management, productivity tracking, and AI-driven insights.