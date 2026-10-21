import Foundation

struct TaskDayGroup: Identifiable, Equatable {
    var id: LocalDay
    var title: String
    var inProgress: [TodoItem]
    var todo: [TodoItem]
    var completed: [TodoItem]

    static func make(inProgress: [TodoItem], todo: [TodoItem], completed: [TodoItem], now: Date, calendar: Calendar) -> [Self] {
        let today = LocalDay(now, calendar: calendar)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now).map { LocalDay($0, calendar: calendar) }
        let days = Set((inProgress + todo + completed).map { LocalDay($0.createdAt, calendar: calendar) })
        let formatter = DateFormatter(); formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("yMMMd")
        return days.sorted(by: >).map { day in
            let label = day == today ? "Today" : day == yesterday ? "Yesterday" : (try? formatter.string(from: day.date(calendar: calendar))) ?? ""
            return Self(id: day, title: label,
                        inProgress: inProgress.filter { LocalDay($0.createdAt, calendar: calendar) == day },
                        todo: todo.filter { LocalDay($0.createdAt, calendar: calendar) == day },
                        completed: completed.filter { LocalDay($0.createdAt, calendar: calendar) == day })
        }
    }
}
