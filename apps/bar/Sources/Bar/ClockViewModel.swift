import AppKit
import Foundation

/// 24-hour clock for the bar. Fires once per minute (plus on start / wake),
/// not every second — the display is `HH:mm`.
@MainActor
final class ClockViewModel: ObservableObject {
    @Published private(set) var timeString: String = ClockViewModel.format(Date())

    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    func start() {
        stop()
        tick()
        scheduleNextMinuteTick()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
                self?.scheduleNextMinuteTick()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }

    private func scheduleNextMinuteTick() {
        timer?.invalidate()

        let now = Date()
        let calendar = Calendar.current
        let nextMinute = calendar.nextDate(
            after: now,
            matching: DateComponents(second: 0),
            matchingPolicy: .nextTime
        ) ?? now.addingTimeInterval(60)
        let interval = max(nextMinute.timeIntervalSince(now), 0.05)

        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
                self?.scheduleNextMinuteTick()
            }
        }
        timer.tolerance = min(2.0, interval * 0.25)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let next = Self.format(Date())
        if next != timeString {
            timeString = next
        }
    }

    private static func format(_ date: Date) -> String {
        formatter.string(from: date)
    }
}
