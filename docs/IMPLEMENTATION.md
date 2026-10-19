# V1 implementation checklist

The PRD's pasted tracker omitted individual backlog entries. These are reconstructed work items, not recovered estimates. Implementation does not imply acceptance: see VALIDATION.md.

| Milestone | Work item | Implementation |
| --- | --- | --- |
| M1 | APP-01 repository/project/docs | Public repository, generated Xcode project, PRD, README |
| M1 | APP-02 dependency composition | One AppDependencies and shared TaskStore |
| M1 | APP-03 native lifecycle | Unique SwiftUI Window, MenuBarExtra, app delegate |
| M1 | CI-01 macOS pipeline | Build, unit tests, UI tests, development artifact |
| M2 | DATA-01 schema/repository | Versioned SwiftData schema; transactional rollback |
| M2 | TASK-01 domain rules | Title validation, timestamps, injected clock/IDs |
| M2 | TASK-02 observable store | Stable sorting, commit/refresh error distinction |
| M2 | TASK-03 CRUD interface | Create, rename, complete/reopen, confirmed deletion |
| M3 | UI-01 main window | Full lists, inline edit, task counts |
| M3 | UI-02 popover | Bounded list, collapsed Completed, task input |
| M3 | UI-03 keyboard/focus | Command-N/O, Enter/Escape, list Space |
| M4 | HOT-01 hotkey service | KeyboardShortcuts recorder; Control-Option-Space default |
| M4 | HOT-02 transient panel | Reusable nonactivating NSPanel, active screen positioning |
| M4 | HOT-03 capture integration | Saved-only dismissal, retained failed drafts, cancellation |
| M5 | SYS-01 login option | SMAppService status, registration errors and approval |
| M5 | QA-01 accessibility/appearance | Native controls, semantic colors, VoiceOver labels |
| M5 | QA-02 automated tests | Domain/store, repository, disk persistence, UI flows |
| M5 | QA-03 manual/performance | Checklist pending device evidence |
| M5 | REL-01 personal build | CI ad-hoc development app; installation instructions |

## Decisions

- TaskRepository uses fetchAll, insert, update, delete. TaskService owns complete domain values.
- Title limit counts extended grapheme clusters (Swift Character); internal newlines are rejected.
- Active tasks sort by descending creation time; completed by descending completion time; UUID breaks ties.
- Idempotent completion/rename calls leave timestamps unchanged.
- Persistence save failure rolls back the shared context. Refresh failure after commit blocks mutations until a successful reload, preventing duplicate creates.
- Capture click-away retains its draft; Escape clears it. Successful save clears it and returns focus.
- Settings read actual SMAppService status rather than keeping a contradictory Boolean preference.
- No license is selected and no public release is published.
