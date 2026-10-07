import AppKit
import SwiftUI

struct CalendarView: View {
    @ObservedObject var viewModel: CalendarViewModel
    @ObservedObject var configManager: ConfigManager
    var onHeightChange: (CGFloat) -> Void
    var onRequestClose: () -> Void

    private var theme: ThemeConfig { configManager.config.theme }
    private var showEvents: Bool { configManager.config.behavior.showEvents }

    var body: some View {
        VStack(spacing: 0) {
            monthHeader
            weekdayRow
            monthGrid
            if showEvents {
                Divider()
                    .overlay(Color(hex: theme.borderColor).opacity(0.35))
                agendaSection
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .font(theme.swiftUIFont)
        .foregroundStyle(Color(hex: theme.textColor))
        .background(Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous))
        .frame(height: idealHeight, alignment: .top)
        .onAppear {
            onHeightChange(idealHeight)
        }
        .onChange(of: idealHeight) { height in
            onHeightChange(height)
        }
        .onExitCommand {
            onRequestClose()
        }
    }

    private var idealHeight: CGFloat {
        let maxH = CGFloat(configManager.config.dimensions.maxHeight)
        let header: CGFloat = 36
        let weekdays: CGFloat = 22
        let grid: CGFloat = 6 * 34 + 8
        let base = header + weekdays + grid + 24 // padding

        guard showEvents else {
            return min(base, maxH)
        }

        let divider: CGFloat = 1
        let agendaHeader: CGFloat = 28
        let agendaBody: CGFloat = {
            switch viewModel.authState {
            case .denied, .restricted:
                return 56
            case .unknown:
                return 40
            case .authorized:
                if viewModel.events.isEmpty {
                    return 36
                }
                let rows = CGFloat(min(viewModel.events.count, 5))
                return 8 + rows * 40 + max(rows - 1, 0) * 4
            }
        }()
        return min(base + divider + agendaHeader + agendaBody, maxH)
    }

    // MARK: - Month header

    private var monthHeader: some View {
        HStack(spacing: 8) {
            Text(viewModel.monthTitle)
                .font(.custom(theme.fontFamily, size: theme.fontSize + 1.5).weight(.semibold))
                .foregroundStyle(Color(hex: theme.textColor))

            Spacer(minLength: 0)

            navButton(systemName: "chevron.left") {
                viewModel.goToPreviousMonth()
            }
            navButton(systemName: "chevron.right") {
                viewModel.goToNextMonth()
            }
        }
        .frame(height: 36)
    }

    private func navButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: theme.subtextColor))
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(hex: theme.todayBackground).opacity(0.85))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Grid

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(viewModel.weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.custom(theme.fontFamily, size: theme.fontSize - 1.5))
                    .foregroundStyle(Color(hex: theme.subtextColor))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 22)
    }

    private var monthGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
        return LazyVGrid(columns: columns, spacing: 2) {
            ForEach(viewModel.days) { day in
                dayCell(day)
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 4)
    }

    private func dayCell(_ day: CalendarDay) -> some View {
        let isSelected = Calendar.current.isDate(day.date, inSameDayAs: viewModel.selectedDate)
        let textColor: Color = {
            if isSelected { return Color(hex: theme.accentColor) }
            if day.isToday { return Color(hex: theme.accentColor) }
            if day.isInDisplayedMonth { return Color(hex: theme.textColor) }
            return Color(hex: theme.subtextColor).opacity(0.45)
        }()

        return Button {
            viewModel.select(day.date)
        } label: {
            VStack(spacing: 3) {
                Text("\(day.dayNumber)")
                    .font(.custom(theme.fontFamily, size: theme.fontSize).weight(day.isToday || isSelected ? .semibold : .regular))
                    .foregroundStyle(textColor)
                    .frame(width: 28, height: 28)
                    .background(
                        Group {
                            if isSelected {
                                Circle().fill(Color(hex: theme.todayBackground))
                            } else if day.isToday {
                                Circle().stroke(Color(hex: theme.accentColor).opacity(0.7), lineWidth: 1.2)
                            } else {
                                Color.clear
                            }
                        }
                    )

                Circle()
                    .fill(day.hasEvents ? Color(hex: theme.accentColor) : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity, minHeight: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Agenda

    private var agendaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.selectedDayTitle)
                .font(.custom(theme.fontFamily, size: theme.fontSize - 0.5).weight(.medium))
                .foregroundStyle(Color(hex: theme.subtextColor))
                .padding(.top, 10)

            switch viewModel.authState {
            case .denied, .restricted:
                unauthorizedState
            case .unknown:
                Text("Requesting calendar access…")
                    .foregroundStyle(Color(hex: theme.subtextColor))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            case .authorized:
                if viewModel.events.isEmpty {
                    Text("No events")
                        .foregroundStyle(Color(hex: theme.subtextColor))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                } else {
                    VStack(spacing: 4) {
                        ForEach(viewModel.events.prefix(5)) { event in
                            eventRow(event)
                        }
                    }
                }
            }
        }
    }

    private var unauthorizedState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Calendar access needed")
                .font(.custom(theme.fontFamily, size: theme.fontSize).weight(.medium))
            Text("Allow CalendarBar in System Settings → Privacy & Security → Calendars.")
                .font(.custom(theme.fontFamily, size: theme.fontSize - 1.5))
                .foregroundStyle(Color(hex: theme.subtextColor))
                .fixedSize(horizontal: false, vertical: true)

            Button("Open Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(hex: theme.accentColor))
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }

    private func eventRow(_ event: CalendarEventItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color(hex: event.calendarColor))
                .frame(width: 7, height: 7)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .lineLimit(1)
                    .foregroundStyle(Color(hex: theme.textColor))
                Text(timeLabel(for: event))
                    .font(.custom(theme.fontFamily, size: theme.fontSize - 1.5))
                    .foregroundStyle(Color(hex: theme.subtextColor))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(hex: theme.todayBackground).opacity(0.55))
        )
    }

    private func timeLabel(for event: CalendarEventItem) -> String {
        if event.isAllDay { return "All day" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return "\(formatter.string(from: event.start)) – \(formatter.string(from: event.end))"
    }
}

/// Local key routing while the panel is key.
enum CalendarKeyRouter {
    @MainActor
    static func handle(
        event: NSEvent,
        viewModel: CalendarViewModel,
        onClose: () -> Void
    ) -> Bool {
        if event.keyCode == 53 { // Escape
            onClose()
            return true
        }

        switch event.keyCode {
        case 123: // left
            if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option) {
                viewModel.goToPreviousMonth()
            } else {
                viewModel.moveSelection(byDays: -1)
            }
            return true
        case 124: // right
            if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option) {
                viewModel.goToNextMonth()
            } else {
                viewModel.moveSelection(byDays: 1)
            }
            return true
        case 125: // down
            viewModel.moveSelection(byDays: 7)
            return true
        case 126: // up
            viewModel.moveSelection(byDays: -7)
            return true
        default:
            return false
        }
    }
}
