import Foundation

struct SessionDuration: Equatable {
    var hours: String
    var minutes: String
    var seconds: String
    init(milliseconds: Int64 = 0) {
        let seconds = milliseconds / 1000
        hours = String(seconds / 3600)
        minutes = String(seconds / 60 % 60)
        self.seconds = String(seconds % 60)
    }
    func milliseconds() throws -> Int64 {
        func number(_ text: String) throws -> Int64 {
            guard !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }), let value = Int64(text) else { throw SessionEditError.invalidDuration }
            return value
        }
        let h = try number(hours), m = try number(minutes), s = try number(seconds)
        guard m < 60, s < 60 else { throw SessionEditError.invalidDuration }
        let hours = h.multipliedReportingOverflow(by: 3_600_000)
        let total = hours.partialValue.addingReportingOverflow(m * 60_000 + s * 1000)
        guard !hours.overflow, !total.overflow else { throw SessionEditError.invalidDuration }
        return total.partialValue
    }
}

enum SessionEditError: LocalizedError {
    case invalidDuration, running, missing
    var errorDescription: String? {
        switch self {
        case .invalidDuration: "Enter valid hours, minutes (0–59), and seconds (0–59). The duration must fit the supported range."
        case .running: "Pause this task before changing its work sessions."
        case .missing: "This task or session is no longer available. Reload and try again."
        }
    }
}
