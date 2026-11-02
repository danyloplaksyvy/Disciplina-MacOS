// swift-tools-version: 6.2
import PackageDescription

// Command-line tests for the exact production domain/store sources, without Xcode-only macros.
// The shipping app and persistence/UI tests live in Disciplina.xcodeproj.
let package = Package(
    name: "DisciplinaCoreTests",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "Disciplina", path: "Disciplina",
                exclude: ["App", "Data", "Platform", "DesignSystem", "Features/QuickCapture", "Features/Settings", "Features/Goals", "Features/Activity", "Features/Tasks/TaskViews.swift", "Features/Tasks/TaskSearchField.swift", "Features/Tasks/SessionEditorView.swift", "Features/Tasks/RepeatEditorView.swift", "Features/Tasks/AppearanceEditorView.swift"],
                sources: ["Domain", "Features/Tasks/TaskStore.swift", "Features/Tasks/MenuBarStatus.swift"]),
        .testTarget(name: "DisciplinaTests", dependencies: ["Disciplina"], path: "DisciplinaTests",
                    exclude: ["PersistenceTests.swift"])
    ],
    swiftLanguageModes: [.v6]
)
