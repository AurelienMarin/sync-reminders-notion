import EventKit
import Foundation

final class EventKitReminderStore: @unchecked Sendable {
    private let store = EKEventStore()

    func requestAccess() async throws {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if status == .fullAccess { return }
        if status == .denied || status == .restricted {
            throw ReminderAccessError.denied
        }
        let granted = try await store.requestFullAccessToReminders()
        if !granted {
            throw ReminderAccessError.denied
        }
    }

    func listNames() async throws -> [String] {
        store.calendars(for: .reminder).map(\.title).sorted()
    }

    func fetchReminders(inListNames names: [String]) async throws -> [ReminderRecord] {
        let wanted = Set(names)
        let calendars = store.calendars(for: .reminder).filter { wanted.contains($0.title) }
        let completed = store.predicateForCompletedReminders(
            withCompletionDateStarting: nil,
            ending: nil,
            calendars: calendars
        )
        let open = store.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: calendars
        )
        let completedRecords = try await fetch(completed)
        let openRecords = try await fetch(open)
        return completedRecords + openRecords
    }

    private func fetch(_ predicate: NSPredicate) async throws -> [ReminderRecord] {
        try await withCheckedThrowingContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = .current
                let records = (reminders ?? []).map { reminder in
                    ReminderRecord(
                        listName: reminder.calendar.title,
                        isCompleted: reminder.isCompleted,
                        completionDate: reminder.completionDate,
                        due: reminder.dueDateComponents.flatMap {
                            ReminderRecord.Due.from(components: $0, calendar: calendar)
                        },
                        title: reminder.title ?? ""
                    )
                }
                continuation.resume(returning: records)
            }
        }
    }
}
