import Combine
import EventKit
import Foundation

struct CalendarDay: Identifiable, Equatable {
    let date: Date
    let dayNumber: Int
    let isInDisplayedMonth: Bool
    let isToday: Bool
    let hasEvents: Bool

    var id: TimeInterval { date.timeIntervalSince1970 }
}

struct CalendarEventItem: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let calendarColor: String
}

enum CalendarAuthState: Equatable {
    case unknown
    case authorized
    case denied
    case restricted
}

@MainActor
final class CalendarViewModel: ObservableObject {
    @Published private(set) var displayedMonth: Date
    @Published var selectedDate: Date
    @Published private(set) var days: [CalendarDay] = []
    @Published private(set) var events: [CalendarEventItem] = []
    @Published private(set) var monthEventDays: Set<String> = []
    @Published private(set) var authState: CalendarAuthState = .unknown
    @Published var isVisible = false

    private let store = EKEventStore()
    private let calendar = Calendar.current
    private let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = .current
        f.locale = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init() {
        let now = Date()
        displayedMonth = calendar.startOfDay(for: calendar.date(from: calendar.dateComponents([.year, .month], from: now))!)
        selectedDate = calendar.startOfDay(for: now)
        rebuildGrid()
    }

    func prepareForShow(showEvents: Bool) {
        let now = Date()
        selectedDate = calendar.startOfDay(for: now)
        displayedMonth = calendar.startOfDay(for: calendar.date(from: calendar.dateComponents([.year, .month], from: now))!)
        rebuildGrid()
        applyShowEvents(showEvents)
    }

    /// Refresh or clear EventKit data without resetting the selected month/day.
    func applyShowEvents(_ showEvents: Bool) {
        if showEvents {
            Task { await refreshAuthorizationAndEvents() }
        } else {
            events = []
            monthEventDays = []
            rebuildGrid()
        }
    }

    func goToPreviousMonth() {
        guard let previous = calendar.date(byAdding: .month, value: -1, to: displayedMonth) else { return }
        displayedMonth = previous
        rebuildGrid()
        Task { await loadMonthMarkersAndSelectedEvents() }
    }

    func goToNextMonth() {
        guard let next = calendar.date(byAdding: .month, value: 1, to: displayedMonth) else { return }
        displayedMonth = next
        rebuildGrid()
        Task { await loadMonthMarkersAndSelectedEvents() }
    }

    func select(_ date: Date) {
        selectedDate = calendar.startOfDay(for: date)
        if !calendar.isDate(selectedDate, equalTo: displayedMonth, toGranularity: .month) {
            displayedMonth = calendar.startOfDay(
                for: calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate))!
            )
            rebuildGrid()
        }
        Task { await loadEvents(for: selectedDate) }
    }

    func moveSelection(byDays delta: Int) {
        guard let next = calendar.date(byAdding: .day, value: delta, to: selectedDate) else { return }
        select(next)
    }

    var monthTitle: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter.string(from: displayedMonth)
    }

    var selectedDayTitle: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("EEEE, MMM d")
        return formatter.string(from: selectedDate)
    }

    var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...]) + Array(symbols[..<first])
    }

    // MARK: - EventKit

    func refreshAuthorizationAndEvents() async {
        syncAuthState()
        switch authState {
        case .authorized:
            await loadMonthMarkersAndSelectedEvents()
        case .unknown:
            await requestAccess()
        case .denied, .restricted:
            events = []
            monthEventDays = []
        }
    }

    private func requestAccess() async {
        let granted: Bool
        do {
            if #available(macOS 14.0, *) {
                granted = try await store.requestFullAccessToEvents()
            } else {
                granted = try await withCheckedThrowingContinuation { continuation in
                    store.requestAccess(to: .event) { ok, error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: ok)
                        }
                    }
                }
            }
        } catch {
            NSLog("[CalendarBar] EventKit access error: \(error)")
            granted = false
        }
        syncAuthState()
        if granted || authState == .authorized {
            await loadMonthMarkersAndSelectedEvents()
        } else {
            events = []
            monthEventDays = []
        }
    }

    private func syncAuthState() {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess, .authorized:
            authState = .authorized
        case .writeOnly, .denied:
            authState = .denied
        case .restricted:
            authState = .restricted
        case .notDetermined:
            authState = .unknown
        @unknown default:
            authState = .unknown
        }
    }

    private func loadMonthMarkersAndSelectedEvents() async {
        guard authState == .authorized else { return }
        await loadMonthMarkers()
        await loadEvents(for: selectedDate)
        rebuildGrid()
    }

    private func loadMonthMarkers() async {
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth)),
              let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart)
        else {
            monthEventDays = []
            return
        }

        let endOfLastDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: monthEnd) ?? monthEnd
        let predicate = store.predicateForEvents(withStart: monthStart, end: endOfLastDay, calendars: nil)
        let ekEvents = store.events(matching: predicate)

        var keys = Set<String>()
        // Cap day walks so a pathological multi-year event cannot hitch the main actor.
        let maxSpanDays = 62
        for event in ekEvents {
            var cursor = calendar.startOfDay(for: event.startDate)
            let last = calendar.startOfDay(for: event.endDate)
            guard cursor <= last else { continue }
            var steps = 0
            while cursor <= last, steps < maxSpanDays {
                keys.insert(dayKeyFormatter.string(from: cursor))
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
                steps += 1
            }
        }
        monthEventDays = keys
    }

    private func loadEvents(for date: Date) async {
        guard authState == .authorized else {
            events = []
            return
        }

        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            events = []
            return
        }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let ekEvents = store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }

        events = ekEvents.map { event in
            CalendarEventItem(
                id: event.eventIdentifier ?? UUID().uuidString,
                title: event.title ?? "(No title)",
                start: event.startDate,
                end: event.endDate,
                isAllDay: event.isAllDay,
                calendarColor: hexColor(from: event.calendar.cgColor)
            )
        }
    }

    // MARK: - Grid

    private func rebuildGrid() {
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth)) else {
            days = []
            return
        }

        let weekdayOfFirst = calendar.component(.weekday, from: monthStart)
        let leading = (weekdayOfFirst - calendar.firstWeekday + 7) % 7
        guard let gridStart = calendar.date(byAdding: .day, value: -leading, to: monthStart) else {
            days = []
            return
        }

        let today = calendar.startOfDay(for: Date())
        var built: [CalendarDay] = []
        built.reserveCapacity(42)

        for offset in 0..<42 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: gridStart) else { continue }
            let dayStart = calendar.startOfDay(for: date)
            let key = dayKeyFormatter.string(from: dayStart)
            built.append(
                CalendarDay(
                    date: dayStart,
                    dayNumber: calendar.component(.day, from: dayStart),
                    isInDisplayedMonth: calendar.isDate(dayStart, equalTo: monthStart, toGranularity: .month),
                    isToday: calendar.isDate(dayStart, inSameDayAs: today),
                    hasEvents: monthEventDays.contains(key)
                )
            )
        }
        days = built
    }

    private func hexColor(from cgColor: CGColor?) -> String {
        guard let comps = cgColor?.components else { return "#8aadf4" }
        let r: CGFloat
        let g: CGFloat
        let b: CGFloat
        if comps.count >= 3 {
            r = comps[0]
            g = comps[1]
            b = comps[2]
        } else if comps.count >= 1 {
            r = comps[0]
            g = comps[0]
            b = comps[0]
        } else {
            return "#8aadf4"
        }
        return String(
            format: "#%02X%02X%02X",
            Int(min(max(r, 0), 1) * 255),
            Int(min(max(g, 0), 1) * 255),
            Int(min(max(b, 0), 1) * 255)
        )
    }
}
