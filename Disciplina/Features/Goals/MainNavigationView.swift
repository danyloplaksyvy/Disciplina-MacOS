import SwiftUI

struct MainNavigationView: View {
    let store: TaskStore
    let openSettings: () -> Void
    private enum Destination: String, CaseIterable { case tasks = "Tasks", goals = "Goals", activity = "Activity" }
    @State private var destination: Destination = .tasks
    @State private var visibility: NavigationSplitViewVisibility = .all
    @State private var manuallyHidden = false
    var body: some View {
        GeometryReader { geometry in
            NavigationSplitView(columnVisibility: $visibility) {
                List {
                    ForEach(Destination.allCases, id: \.self) { value in
                        Button { navigate(value) } label: {
                            Label(value.rawValue, systemImage: value == .tasks ? "checklist" : value == .goals ? "target" : "calendar")
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5).contentShape(Rectangle())
                        }.buttonStyle(.plain).listRowBackground(destination == value ? Theme.accent.opacity(0.16) : Color.clear)
                            .accessibilityIdentifier("navigate-\(value.rawValue.lowercased())")
                            .accessibilityAddTraits(destination == value ? .isSelected : [])
                    }
                    Button(action: openSettings) { Label("Settings", systemImage: "gearshape").frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5).contentShape(Rectangle()) }.buttonStyle(.plain)
                }.navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 220)
            } detail: {
                VStack(spacing: 0) {
                    if visibility == .detailOnly {
                        HStack {
                            Menu(destination.rawValue) {
                                Button("Tasks") { navigate(.tasks) }
                                Button("Goals") { navigate(.goals) }
                                Button("Activity") { navigate(.activity) }
                                Divider(); Button("Settings", action: openSettings)
                            }.accessibilityIdentifier("compact-navigation")
                            Spacer()
                        }.padding(.horizontal, 24).padding(.top, 8)
                    }
                    if let notice = store.notice {
                        HStack {
                            Text(notice).font(.callout).foregroundStyle(.secondary)
                            Spacer()
                            Button { store.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Dismiss status message")
                        }.padding(.horizontal, 24).padding(.top, 8)
                    }
                    DeletionNoticeView(store: store).padding(.horizontal, 24)
                    // Each destination keeps its SwiftUI state in a retained native host.
                    // Native hiding also removes embedded scroll views from hit testing.
                    ZStack {
                        RetainedDestination(isVisible: destination == .tasks) {
                            MainTaskWindowView(store: store, openSettings: openSettings).tint(Theme.accent)
                        }
                        RetainedDestination(isVisible: destination == .activity) {
                            ActivityView(store: store, isVisible: destination == .activity).tint(Theme.accent)
                        }
                        RetainedDestination(isVisible: destination == .goals) {
                            GoalsView(store: store).tint(Theme.accent)
                        }
                    }
                }.frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
            }.navigationSplitViewStyle(.balanced)
                .onChange(of: geometry.size.width, initial: true) { _, width in
                    visibility = width < 1000 || manuallyHidden ? .detailOnly : .all
                }
                .onChange(of: visibility) { _, value in
                    if geometry.size.width >= 1000 { manuallyHidden = value == .detailOnly }
                    else if value != .detailOnly { visibility = .detailOnly }
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

/// Opacity alone leaves AppKit-backed descendants participating in native events.
/// Keep the host and its state alive, but hide the entire native subtree.
private struct RetainedDestination<Content: View>: NSViewRepresentable {
    let isVisible: Bool
    @ViewBuilder var content: () -> Content

    func makeNSView(context: Context) -> NSHostingView<Content> {
        let view = NSHostingView(rootView: content())
        view.sizingOptions = []
        view.isHidden = !isVisible
        return view
    }

    func updateNSView(_ view: NSHostingView<Content>, context: Context) {
        view.rootView = content()
        view.isHidden = !isVisible
    }
}
