import Foundation
import Observation

struct TimeSample {
    let awake: Double
    let continuous: Double
    let date: Date
}

@MainActor
final class TimeSource {
    private let awakeOrigin = SuspendingClock.now
    private let continuousOrigin = ContinuousClock.now
    func sample() -> TimeSample {
        func seconds(_ duration: Duration) -> Double {
            let parts = duration.components
            return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
        }
        return TimeSample(awake: seconds(awakeOrigin.duration(to: .now)),
                          continuous: seconds(continuousOrigin.duration(to: .now)), date: Date())
    }
}

@MainActor @Observable
final class TimerCoordinator {
    private let repository: any TaskRepository
    private let sample: () -> TimeSample
    private let makeID: () -> UUID
    private let calendar: () -> Calendar
    private var trusted: TimeSample?
    private var trustedCalendar: Calendar?
    private(set) var running: WorkSession?
    private(set) var elapsedMilliseconds: Int64 = 0
    private(set) var failure: String?
    var onCommit: (() -> Void)?
    var watchdogSeconds: Double = 15

    init(repository: any TaskRepository, sample: (() -> TimeSample)? = nil,
         makeID: @escaping () -> UUID = UUID.init, calendar: @escaping () -> Calendar = { LocalDay.calendar() }) {
        self.repository = repository
        let source = TimeSource()
        self.sample = sample ?? { source.sample() }
        self.makeID = makeID
        self.calendar = calendar
    }

    var pendingActivity: [LocalDay: Int64] {
        guard failure == nil, let running, let trusted, let trustedCalendar else { return [:] }
        let delta = max(0, elapsedMilliseconds - running.accumulatedMilliseconds)
        var overlay = running; overlay.allocations = []
        do { try overlay.allocate(milliseconds: delta, from: trusted.date, calendar: trustedCalendar, makeID: { running.id }) }
        catch { return [:] }
        var days: [LocalDay: Int64] = [:]
        for value in overlay.allocations ?? [] { days[value.day, default: 0] += value.milliseconds }
        return days
    }

    func recover() throws {
        do {
        var state = try repository.snapshot()
        try state.validate()
        let before = state
        for i in state.sessions.indices where state.sessions[i].allocations == nil && state.sessions[i].legacyDay == nil {
            state.sessions[i].legacyDay = LocalDay(state.sessions[i].startedAt, calendar: calendar())
        }
        if state.sessions.contains(where: { $0.endedAt == nil }) {
            state.closeInterrupted()
        }
        if state != before { try repository.commit(state) }
        running = nil; trusted = nil; elapsedMilliseconds = 0; failure = nil
        } catch { freeze(error); throw error }
    }

    private func duration(at now: TimeSample) throws -> Int64 {
        guard let running, let trusted else { return 0 }
        let awake = now.awake - trusted.awake
        let continuous = now.continuous - trusted.continuous
        guard awake >= 0, continuous >= 0, continuous <= watchdogSeconds,
              continuous - awake < 1, abs(now.date.timeIntervalSince(trusted.date) - awake) <= 1 else { throw DataError.timerUnavailable }
        let delta = awake * 1000
        guard delta.isFinite, delta < Double(Int64.max) else { throw DataError.invalidSnapshot }
        let sum = running.accumulatedMilliseconds.addingReportingOverflow(Int64(delta))
        guard !sum.overflow else { throw DataError.invalidSnapshot }
        return sum.partialValue
    }

    /// One presentation tick. Only checkpoint boundaries write to disk.
    func tick() {
        guard running != nil, failure == nil else { return }
        let now = sample()
        do {
            elapsedMilliseconds = try duration(at: now)
            if let trusted, now.continuous - trusted.continuous >= 5 {
                try checkpoint(at: now)
                onCommit?()
            }
        } catch {
            if (error as? DataError) != nil {
                do { try interrupt() } catch { freeze(error) }
            } else { freeze(error) }
        }
    }

    private func freeze(_ error: Error) {
        elapsedMilliseconds = running?.accumulatedMilliseconds ?? 0
        failure = "Timing stopped. \(error.localizedDescription)"
    }

    private func interrupt() throws {
        var state = try repository.snapshot()
        state.closeInterrupted()
        try repository.commit(state)
        running = nil; trusted = nil; elapsedMilliseconds = 0
        onCommit?()
    }

    private func accrue(_ session: inout WorkSession, at now: TimeSample) throws {
        let total = try duration(at: now)
        guard let trusted, let trustedCalendar else { throw DataError.timerUnavailable }
        // A changed zone without an observed boundary cannot safely assign this interval.
        guard trustedCalendar.timeZone == calendar().timeZone else { throw DataError.timerUnavailable }
        try session.allocate(milliseconds: total - session.accumulatedMilliseconds, from: trusted.date, calendar: trustedCalendar, makeID: makeID)
        session.accumulatedMilliseconds = total
    }
    func timeEnvironmentChanged() {
        guard running != nil else { return }
        do { try interrupt() } catch { freeze(error) }
    }

    private func checkpoint(at now: TimeSample) throws {
        guard let running else { return }
        var state = try repository.snapshot()
        guard let index = state.sessions.firstIndex(where: { $0.id == running.id }) else { throw DataError.invalidSnapshot }
        try accrue(&state.sessions[index], at: now)
        state.sessions[index].lastCheckpointAt = now.date
        try repository.commit(state)
        self.running = state.sessions[index]; trusted = now; trustedCalendar = calendar()
    }

    /// Includes closure of the current interval in the same transaction as the command.
    private func transition(reason: SessionEndReason, change: (inout TaskSnapshot, TimeSample) throws -> UUID?) throws {
        guard failure == nil else { throw DataError.timerUnavailable }
        let now = sample()
        var state = try repository.snapshot()
        if let running, let index = state.sessions.firstIndex(where: { $0.id == running.id }) {
            do {
                try accrue(&state.sessions[index], at: now)
                state.sessions[index].lastCheckpointAt = now.date
                state.sessions[index].endedAt = now.date
                state.sessions[index].endReason = reason
            } catch {
                // An untrusted gap contributes no additional duration.
                state.sessions[index].endedAt = state.sessions[index].lastCheckpointAt ?? running.startedAt
                state.sessions[index].endReason = .interrupted
            }
        }
        if let taskID = running?.taskID, let index = state.tasks.firstIndex(where: { $0.id == taskID }) {
            state.tasks[index].updatedAt = now.date
        }
        let nextID = try change(&state, now)
        try state.validate()
        try repository.commit(state)
        running = nextID.flatMap { id in state.sessions.first { $0.id == id } }
        trusted = running == nil ? nil : now
        trustedCalendar = running == nil ? nil : calendar()
        elapsedMilliseconds = running?.accumulatedMilliseconds ?? 0
    }

    func start(taskID: UUID) throws {
        guard running?.taskID != taskID else { return }
        try transition(reason: .switchedTask) { state, now in
            guard let index = state.tasks.firstIndex(where: { $0.id == taskID && $0.deletedAt == nil }),
                  state.tasks[index].status != .completed else { throw TaskError.notFound }
            state.tasks[index].status = .inProgress
            state.tasks[index].updatedAt = now.date
            let id = makeID()
            state.sessions.append(WorkSession(id: id, taskID: taskID, startedAt: now.date, lastCheckpointAt: now.date, goalIDAtStart: state.tasks[index].goalID, allocations: []))
            return id
        }
    }

    func pause(reason: SessionEndReason = .paused) throws {
        guard running != nil else { return }
        do { try transition(reason: reason) { _, _ in nil } }
        catch {
            if reason == .systemSleep || reason == .appQuit { freeze(error) }
            throw error
        }
    }

    func setStatus(id: UUID, status: TaskStatus) throws {
        guard failure == nil else { throw DataError.timerUnavailable }
        var state = try repository.snapshot()
        guard let index = state.tasks.firstIndex(where: { $0.id == id && $0.deletedAt == nil }) else { throw TaskError.notFound }
        guard state.tasks[index].status != status else { return }
        let change: (inout TaskSnapshot, TimeSample) throws -> UUID? = { state, now in
            try state.recurrenceStatusChanged(taskIndex: index, status: status, now: now.date, calendar: self.calendar(), makeID: self.makeID)
            state.tasks[index].status = status
            state.tasks[index].completedAt = status == .completed ? now.date : nil
            state.tasks[index].updatedAt = now.date
            return nil
        }
        if running?.taskID == id {
            try transition(reason: status == .completed ? .completed : .movedToTodo, change: change)
        } else {
            _ = try change(&state, sample()); try repository.commit(state)
        }
    }

    @discardableResult func delete(id: UUID, disposition: RecurringDeletion = .stop) throws -> (before: RecurrenceSeries, after: UUID)? {
        guard failure == nil else { throw DataError.timerUnavailable }
        var state = try repository.snapshot()
        guard let index = state.tasks.firstIndex(where: { $0.id == id && $0.deletedAt == nil }) else { throw TaskError.notFound }
        var receipt: (before: RecurrenceSeries, after: UUID)?
        let change: (inout TaskSnapshot, TimeSample) throws -> UUID? = { state, now in
            let previous = state.series.first { $0.currentTaskID == id }
            if let seriesID = state.tasks[index].seriesID,
               let s = state.series.firstIndex(where: { $0.id == seriesID && $0.enabled && $0.currentTaskID == id }),
               !state.tasks[index].isCompleted {
                if disposition == .skip {
                    try state.schedule(seriesIndex: s, after: LocalDay(now.date, calendar: self.calendar()), calendar: self.calendar(), makeID: self.makeID)
                } else { state.stopSeries(at: s, revision: self.makeID()) }
            }
            state.tasks[index].deletedAt = now.date; state.tasks[index].updatedAt = now.date
            if let previous, let after = state.series.first(where: { $0.id == previous.id }) {
                receipt = (previous, after.revision)
            }
            return nil
        }
        if running?.taskID == id { try transition(reason: .deleted, change: change) }
        else { _ = try change(&state, sample()); try repository.commit(state) }
        return receipt
    }

    func assignGoal(taskID: UUID, goalID: UUID?) throws {
        guard failure == nil else { throw DataError.timerUnavailable }
        guard running?.taskID != taskID else { throw GoalError.running }
        var state = try repository.snapshot()
        guard let index = state.tasks.firstIndex(where: { $0.id == taskID && $0.deletedAt == nil }) else { throw TaskError.notFound }
        guard goalID == nil || state.goals.contains(where: { $0.id == goalID }) else { throw GoalError.missing }
        guard state.tasks[index].goalID != goalID else { return }
        state.tasks[index].goalID = goalID; state.tasks[index].updatedAt = sample().date
        if let seriesID = state.tasks[index].seriesID,
           let s = state.series.firstIndex(where: { $0.id == seriesID && $0.enabled && $0.currentTaskID == taskID }) {
            state.series[s].futureGoalID = goalID; state.series[s].revision = makeID()
        }
        try repository.commit(state)
    }

    func setRepeat(taskID: UUID, weekdays: [Int]) throws {
        guard failure == nil else { throw DataError.timerUnavailable }
        var state = try repository.snapshot()
        guard let t = state.tasks.firstIndex(where: { $0.id == taskID && !$0.isCompleted && $0.deletedAt == nil }) else { throw TaskError.notFound }
        if let id = state.tasks[t].seriesID,
           let s = state.series.firstIndex(where: { $0.id == id && $0.currentTaskID == taskID && $0.enabled }) {
            if weekdays.isEmpty { state.stopSeries(at: s, revision: makeID()) }
            else { state.series[s].weekdays = weekdays.sorted(); state.series[s].revision = makeID() }
        } else if !weekdays.isEmpty {
            state.detachTask(at: t)
            let id = makeID()
            state.tasks[t].seriesID = id
            state.series.append(RecurrenceSeries(id: id, title: state.tasks[t].title, weekdays: weekdays.sorted(), currentTaskID: taskID, revision: makeID(), futureGoalID: state.tasks[t].goalID, futureAppearance: state.tasks[t].appearance))
        }
        state.tasks[t].updatedAt = sample().date
        try state.validate(); try repository.commit(state)
    }

    func changeSeries(id: UUID, weekdays: [Int]?) throws {
        guard failure == nil else { throw DataError.timerUnavailable }
        var state = try repository.snapshot()
        guard let s = state.series.firstIndex(where: { $0.id == id && $0.enabled }) else { throw TaskError.notFound }
        if let weekdays {
            state.series[s].weekdays = weekdays.sorted(); state.series[s].revision = makeID()
            if state.series[s].pendingTaskID != nil, let trigger = state.series[s].lastTriggerDay {
                state.series[s].pendingDay = try trigger.next(weekdays: weekdays, calendar: calendar())
                _ = state.materializeDue(now: sample().date, calendar: calendar(), makeID: makeID)
            }
        } else { state.stopSeries(at: s, revision: makeID()) }
        try state.validate(); try repository.commit(state)
    }

    func reconcileRecurrence() throws {
        guard failure == nil else { throw DataError.timerUnavailable }
        var state = try repository.snapshot()
        if state.materializeDue(now: sample().date, calendar: calendar(), makeID: makeID) {
            try state.validate(); try repository.commit(state)
        }
    }

    private func changeSessions(taskID: UUID, change: (inout TaskSnapshot, Date) throws -> Void) throws {
        guard failure == nil else { throw DataError.timerUnavailable }
        guard running?.taskID != taskID else { throw SessionEditError.running }
        var state = try repository.snapshot()
        guard let task = state.tasks.firstIndex(where: { $0.id == taskID && $0.deletedAt == nil }) else { throw SessionEditError.missing }
        let date = sample().date
        try change(&state, date)
        state.tasks[task].updatedAt = date
        try state.validate()
        try repository.commit(state)
    }

    func addSession(taskID: UUID, date: Date, milliseconds: Int64) throws {
        guard milliseconds > 0, date.timeIntervalSince1970.isFinite else { throw SessionEditError.invalidDuration }
        try changeSessions(taskID: taskID) { state, _ in
            let id = makeID(), cal = calendar()
            let allocation = DailyAllocation(id: makeID(), sessionID: id, day: LocalDay(date, calendar: cal), timeZoneID: cal.timeZone.identifier, milliseconds: milliseconds, provenance: .manual)
            state.sessions.append(WorkSession(id: id, taskID: taskID, startedAt: date, endedAt: date,
                accumulatedMilliseconds: milliseconds, lastCheckpointAt: date, endReason: .manuallyAdded, origin: .manual, goalIDAtStart: state.tasks.first { $0.id == taskID }?.goalID, allocations: [allocation]))
        }
    }
    func editSession(taskID: UUID, sessionID: UUID, milliseconds: Int64) throws {
        guard milliseconds >= 0 else { throw SessionEditError.invalidDuration }
        let existing = try repository.snapshot().sessions.first { $0.id == sessionID && $0.taskID == taskID }
        guard let existing, existing.endedAt != nil else { throw SessionEditError.missing }
        if existing.accumulatedMilliseconds == milliseconds { return }
        try changeSessions(taskID: taskID) { state, date in
            guard let index = state.sessions.firstIndex(where: { $0.id == sessionID && $0.taskID == taskID && $0.endedAt != nil }) else { throw SessionEditError.missing }
            if let values = state.sessions[index].allocations {
                guard values.count <= 1 else { throw SessionEditError.invalidDuration }
                if values.isEmpty {
                    let cal = self.calendar()
                    state.sessions[index].allocations = [DailyAllocation(id: self.makeID(), sessionID: sessionID, day: LocalDay(existing.startedAt, calendar: cal), timeZoneID: cal.timeZone.identifier, milliseconds: milliseconds, provenance: .corrected)]
                } else { state.sessions[index].allocations![0].milliseconds = milliseconds; state.sessions[index].allocations![0].provenance = .corrected }
            }
            state.sessions[index].accumulatedMilliseconds = milliseconds
            state.sessions[index].durationEditedAt = date
        }
    }
    func editDailySession(taskID: UUID, sessionID: UUID, amounts: [UUID: Int64]) throws {
        guard failure == nil else { throw DataError.timerUnavailable }
        guard running?.taskID != taskID else { throw SessionEditError.running }
        let state = try repository.snapshot()
        guard let existing = state.sessions.first(where: { $0.id == sessionID && $0.taskID == taskID && $0.endedAt != nil }),
              let allocations = existing.allocations, Set(amounts.keys) == Set(allocations.map(\.id)) else { throw SessionEditError.missing }
        if allocations.allSatisfy({ amounts[$0.id] == $0.milliseconds }) { return }
        try changeSessions(taskID: taskID) { state, date in
            guard let i = state.sessions.firstIndex(where: { $0.id == sessionID && $0.taskID == taskID && $0.endedAt != nil }),
                  var values = state.sessions[i].allocations, Set(amounts.keys) == Set(values.map(\.id)) else { throw SessionEditError.missing }
            var total: Int64 = 0, changed = false
            for j in values.indices {
                let value = amounts[values[j].id]!
                let sum = total.addingReportingOverflow(value)
                guard value >= 0, !sum.overflow else { throw SessionEditError.invalidDuration }; total = sum.partialValue
                if value != values[j].milliseconds { values[j].milliseconds = value; values[j].provenance = .corrected; changed = true }
            }
            guard changed else { return }
            state.sessions[i].allocations = values; state.sessions[i].accumulatedMilliseconds = total; state.sessions[i].durationEditedAt = date
        }
    }
    func setAppearance(taskID: UUID, appearance: TaskAppearance?) throws {
        guard failure == nil else { throw DataError.timerUnavailable }
        var state = try repository.snapshot()
        guard let i = state.tasks.firstIndex(where: { $0.id == taskID && $0.deletedAt == nil }) else { throw TaskError.notFound }
        let value = appearance?.normalized
        guard state.tasks[i].appearance != value else { return }
        state.tasks[i].appearance = value; state.tasks[i].updatedAt = sample().date
        if let s = state.series.firstIndex(where: { $0.currentTaskID == taskID && $0.enabled }) {
            state.series[s].futureAppearance = value; state.series[s].revision = makeID()
        }
        try repository.commit(state)
    }

    func deleteSession(taskID: UUID, sessionID: UUID) throws {
        try changeSessions(taskID: taskID) { state, _ in
            guard state.sessions.contains(where: { $0.id == sessionID && $0.taskID == taskID && $0.endedAt != nil }) else { throw SessionEditError.missing }
            state.sessions.removeAll { $0.id == sessionID }
        }
    }

}
