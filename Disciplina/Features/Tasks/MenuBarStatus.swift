/// A presentation value: nil means the current count cannot be trusted.
struct MenuBarStatus: Equatable {
    let activeCount: Int?

    var text: String {
        guard let activeCount else { return "—" }
        return activeCount == 0 ? "All clear" : "\(activeCount) left"
    }

    var accessibilityLabel: String {
        guard let activeCount else { return "Disciplina: Task count unavailable" }
        guard activeCount != 0 else { return "Disciplina: All clear" }
        return "Disciplina: \(activeCount) active \(activeCount == 1 ? "task" : "tasks")"
    }
}
