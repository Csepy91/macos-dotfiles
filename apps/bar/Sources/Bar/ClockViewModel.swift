import Foundation

/// 24-hour clock for the bar. Updates once a second (cheap; keeps HH:mm crisp).
@MainActor
final class ClockViewModel: ObservableObject {
    @Published private(set) var timeString: String = ClockViewModel.format(Date())

    private var timer: Timer?
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    func start() {
        stop()
        tick()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
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
