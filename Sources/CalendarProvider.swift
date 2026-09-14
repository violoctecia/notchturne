import EventKit
import Combine
import Foundation

final class CalendarProvider: ObservableObject {
    struct Event: Identifiable, Equatable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let allDay: Bool
        var past: Bool { end < Date() }
    }

    enum Access: Equatable { case unknown, denied, granted }

    @Published private(set) var events: [Event] = []

    @Published private(set) var busyDays: Set<Int> = []
    @Published private(set) var access: Access = .unknown

    private let store = EKEventStore()
    private var timer: Timer?

    func start() {
        refreshAccess()
        guard timer == nil else { return }
        let t = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.reload()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in self?.reload() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func requestAccess() {
        store.requestFullAccessToEvents { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.access = granted ? .granted : .denied
                if granted { self?.reload() }
            }
        }
    }

    private func refreshAccess() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            access = .granted
            reload()
        case .denied, .restricted, .writeOnly:
            access = .denied
        default:
            access = .unknown
        }
    }

    private func reload() {
        guard access == .granted else { return }
        reloadToday()
        reloadMonth()
    }

    private func reloadMonth() {
        let calendar = Calendar.current
        let now = Date()
        guard let interval = calendar.dateInterval(of: .month, for: now) else { return }
        let found = store.events(matching: store.predicateForEvents(
            withStart: interval.start, end: interval.end, calendars: nil
        ))
        let days = Set(found.compactMap { event -> Int? in
            guard let date = event.startDate else { return nil }
            return calendar.component(.day, from: date)
        })
        if days != busyDays { busyDays = days }
    }

    private func reloadToday() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return }

        let found = store.events(matching: store.predicateForEvents(
            withStart: start, end: end, calendars: nil
        ))

        let mapped = found
            .sorted { ($0.startDate ?? start) < ($1.startDate ?? start) }
            .map {
                Event(id: $0.eventIdentifier ?? UUID().uuidString,
                      title: $0.title ?? "",
                      start: $0.startDate ?? start,
                      end: $0.endDate ?? start,
                      allDay: $0.isAllDay)
            }

        if mapped != events { events = mapped }
    }
}
