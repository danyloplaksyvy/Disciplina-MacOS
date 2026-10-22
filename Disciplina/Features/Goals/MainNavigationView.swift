import SwiftUI

struct MainNavigationView: View {
    let store: TaskStore
    let openSettings: () -> Void
    private enum Destination: String, CaseIterable { case tasks = "Tasks", goals = "Goals" }
    @State private var destination: Destination = .tasks
    @State private var visibility: NavigationSplitViewVisibility = .all
    @State private var manuallyHidden = false
    var body: some View {
        GeometryReader { geometry in
            NavigationSplitView(columnVisibility: $visibility) {
                List {
                    ForEach(Destination.allCases, id: \.self) { value in
                        Button { navigate(value) } label: {
                            Label(value.rawValue, systemImage: value == .tasks ? "checklist" : "target")
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                        }.buttonStyle(.plain).listRowBackground(destination == value ? Theme.accent.opacity(0.16) : Color.clear)
                            .accessibilityIdentifier("navigate-\(value.rawValue.lowercased())")
                            .accessibilityAddTraits(destination == value ? .isSelected : [])
                    }
                    Button(action: openSettings) { Label("Settings", systemImage: "gearshape") }.buttonStyle(.plain)
                }.navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 220)
            } detail: {
                VStack(spacing: 0) {
                    HStack {
                        Button {
                            manuallyHidden = visibility != .detailOnly
                            visibility = manuallyHidden || geometry.size.width < 1000 ? .detailOnly : .all
                        } label: { Image(systemName: "sidebar.left") }.help("Toggle sidebar").accessibilityLabel("Toggle sidebar")
                        if visibility == .detailOnly {
                            Menu(destination.rawValue) {
                                Button("Tasks") { navigate(.tasks) }
                                Button("Goals") { navigate(.goals) }
                                Divider(); Button("Settings", action: openSettings)
                            }.accessibilityIdentifier("compact-navigation")
                        }
                        Spacer()
                    }.padding(.horizontal, 24).padding(.top, 8)
                    // Keep both destinations mounted so drafts, selection, scroll and divider state survive navigation.
                    ZStack {
                        MainTaskWindowView(store: store, openSettings: openSettings)
                            .opacity(destination == .tasks ? 1 : 0).allowsHitTesting(destination == .tasks)
                            .accessibilityHidden(destination != .tasks).disabled(destination != .tasks)
                        GoalsView(store: store)
                            .opacity(destination == .goals ? 1 : 0).allowsHitTesting(destination == .goals)
                            .accessibilityHidden(destination != .goals).disabled(destination != .goals)
                    }
                }.frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
            }.navigationSplitViewStyle(.balanced)
                .onChange(of: geometry.size.width, initial: true) { _, width in
                    visibility = width < 1000 || manuallyHidden ? .detailOnly : .all
                }
                .onReceive(NotificationCenter.default.publisher(for: .focusNewTask)) { _ in
                    if destination != .tasks {
                        navigate(.tasks)
                        DispatchQueue.main.async { NotificationCenter.default.post(name: .focusNewTask, object: nil) }
                    }
                }
        }.frame(minWidth: 760, minHeight: 400).tint(Theme.accent)
    }
    private func navigate(_ value: Destination) {
        NSApp.keyWindow?.makeFirstResponder(nil)
        destination = value
    }
}
