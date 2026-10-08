import AppKit
import SwiftUI

struct WorkspaceBarView: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    @ObservedObject var clock: ClockViewModel
    @ObservedObject var battery: BatteryViewModel
    @ObservedObject var wifi: WiFiViewModel
    @ObservedObject var bluetooth: BluetoothViewModel
    @ObservedObject var configManager: ConfigManager

    private var theme: ThemeConfig { configManager.config.theme }
    private var dimensions: DimensionsConfig { configManager.config.dimensions }
    private var displayType: WorkspaceDisplayType { configManager.config.workspaces.displayType }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 2) {
                // Far left — themed Apple menu (⌥ alternates like the system menu).
                AppleMenuButton(theme: theme)
                    .padding(.trailing, 6)

                ForEach(viewModel.workspaces) { workspace in
                    workspaceItem(workspace)
                        .animation(
                            .spring(response: 0.28, dampingFraction: 0.78),
                            value: viewModel.transitionToken
                        )
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 2) {
                BluetoothButton(bluetooth: bluetooth, theme: theme)
                WiFiButton(wifi: wifi, theme: theme)
                if battery.isPresent {
                    BatteryButton(battery: battery, theme: theme)
                }
                // Far right — 24h clock; click opens CalendarBar.
                ClockButton(time: clock.timeString, theme: theme)
            }
        }
        .padding(.horizontal, dimensions.paddingHorizontal)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .frame(height: dimensions.height)
        .background(Color.clear)
    }

    // MARK: - Workspaces

    @ViewBuilder
    private func workspaceItem(_ workspace: WorkspaceInfo) -> some View {
        switch displayType {
        case .dots:
            dotItem(workspace)
        case .icons, .pills:
            pillItem(workspace)
        }
    }

    private func pillItem(_ workspace: WorkspaceInfo) -> some View {
        let active = workspace.isCurrent
        let occupied = workspace.isOccupied
        let number = label(for: workspace)

        return Button {
            viewModel.selectWorkspace(workspace.rawName)
        } label: {
            Text(number)
                .font(labelFont(weight: active ? .semibold : .medium))
                .foregroundColor(foreground(active: active, occupied: occupied))
                .monospacedDigit()
                .frame(minWidth: 18, minHeight: 18)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(active ? Color(hex: theme.activeWorkspaceBg) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(
                            active ? Color(hex: theme.accentColor).opacity(0.65) : Color.clear,
                            lineWidth: 1
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .scaleEffect(active ? 1.06 : 1.0)
                .opacity(active ? 1.0 : (occupied ? 1.0 : 0.72))
        }
        .buttonStyle(.plain)
        .help("Workspace \(workspace.rawName)")
    }

    private func dotItem(_ workspace: WorkspaceInfo) -> some View {
        let active = workspace.isCurrent
        let occupied = workspace.isOccupied

        return Button {
            viewModel.selectWorkspace(workspace.rawName)
        } label: {
            Circle()
                .fill(foreground(active: active, occupied: occupied))
                .frame(width: active ? 8 : 6, height: active ? 8 : 6)
                .frame(width: 20, height: 20)
                .opacity(active ? 1.0 : (occupied ? 0.85 : 0.45))
        }
        .buttonStyle(.plain)
        .help("Workspace \(workspace.rawName)")
    }

    private func label(for workspace: WorkspaceInfo) -> String {
        let raw = workspace.rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.isEmpty { return raw }
        let display = workspace.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return display.isEmpty ? "?" : display
    }

    private func foreground(active: Bool, occupied: Bool) -> Color {
        if active {
            return Color(hex: theme.accentColor)
        }
        if occupied {
            return Color(hex: theme.textColor)
        }
        return Color(hex: theme.subtextColor)
    }

    private func labelFont(weight: Font.Weight) -> Font {
        let size = theme.fontSize
        if NSFont(name: theme.fontFamily, size: size) != nil {
            return .custom(theme.fontFamily, size: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: .rounded)
    }
}

// MARK: - Bluetooth

private struct BluetoothButton: View {
    @ObservedObject var bluetooth: BluetoothViewModel
    let theme: ThemeConfig

    var body: some View {
        Button {
            BluetoothMenuController.shared.toggle(
                relativeTo: ButtonScreenFrames.bluetooth.rect,
                theme: theme
            )
        } label: {
            HStack(spacing: 5) {
                Image(systemName: bluetooth.symbolName)
                    .font(.system(size: max(theme.fontSize - 1, 11), weight: .medium))
                Text(bluetooth.statusLabel)
                    .font(labelFont)
                    .lineLimit(1)
            }
            .foregroundColor(
                bluetooth.powerOn && !bluetooth.connectedDevices.isEmpty
                    ? Color(hex: theme.accentColor)
                    : Color(hex: theme.textColor)
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(BarIconButtonStyle(theme: theme))
        .help(bluetooth.helpText)
        .background(
            ScreenFrameReader { frame in
                ButtonScreenFrames.bluetooth.rect = frame
            }
        )
    }

    private var labelFont: Font {
        let size = theme.fontSize
        if NSFont(name: theme.fontFamily, size: size) != nil {
            return .custom(theme.fontFamily, size: size).weight(.medium)
        }
        return .system(size: size, weight: .medium, design: .rounded)
    }
}

// MARK: - Wi-Fi

private struct WiFiButton: View {
    @ObservedObject var wifi: WiFiViewModel
    let theme: ThemeConfig

    var body: some View {
        Button {
            WiFiMenuController.shared.toggle(
                relativeTo: ButtonScreenFrames.wifi.rect,
                theme: theme
            )
        } label: {
            HStack(spacing: 5) {
                Image(systemName: wifi.symbolName)
                    .font(.system(size: max(theme.fontSize - 1, 11), weight: .medium))
                Text(wifi.speedLabel)
                    .font(labelFont)
                    .monospacedDigit()
            }
            .foregroundColor(Color(hex: theme.textColor))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(BarIconButtonStyle(theme: theme))
        .help(wifi.ssid.map { "Wi-Fi: \($0)" } ?? "Wi-Fi")
        .background(
            ScreenFrameReader { frame in
                ButtonScreenFrames.wifi.rect = frame
            }
        )
    }

    private var labelFont: Font {
        let size = theme.fontSize
        if NSFont(name: theme.fontFamily, size: size) != nil {
            return .custom(theme.fontFamily, size: size).weight(.medium)
        }
        return .system(size: size, weight: .medium, design: .rounded)
    }
}

// MARK: - Battery

private struct BatteryButton: View {
    @ObservedObject var battery: BatteryViewModel
    let theme: ThemeConfig

    var body: some View {
        Button {
            SystemActions.openBatterySettings()
        } label: {
            HStack(spacing: 3) {
                if battery.showsBolt {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: max(theme.fontSize - 3, 9), weight: .semibold))
                }
                Text(battery.percentLabel)
                    .font(labelFont)
                    .monospacedDigit()
            }
            .foregroundColor(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(BarIconButtonStyle(theme: theme))
        .help("Battery Settings")
    }

    private var foreground: Color {
        if let percent = battery.percent, percent <= 20, !battery.isCharging {
            return Color(hex: theme.accentColor)
        }
        return Color(hex: theme.textColor)
    }

    private var labelFont: Font {
        let size = theme.fontSize
        if NSFont(name: theme.fontFamily, size: size) != nil {
            return .custom(theme.fontFamily, size: size).weight(.medium)
        }
        return .system(size: size, weight: .medium, design: .rounded)
    }
}

// MARK: - Clock

private struct ClockButton: View {
    let time: String
    let theme: ThemeConfig

    var body: some View {
        Button {
            CalendarBarClient.toggle(anchor: ButtonScreenFrames.clock.rect)
        } label: {
            Text(time)
                .font(clockFont)
                .monospacedDigit()
                .foregroundColor(Color(hex: theme.textColor))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(BarIconButtonStyle(theme: theme))
        .help("Calendar")
        .background(
            ScreenFrameReader { frame in
                ButtonScreenFrames.clock.rect = frame
            }
        )
    }

    private var clockFont: Font {
        let size = theme.fontSize
        if NSFont(name: theme.fontFamily, size: size) != nil {
            return .custom(theme.fontFamily, size: size).weight(.medium)
        }
        return .system(size: size, weight: .medium, design: .rounded)
    }
}

// MARK: - Apple logo button

private struct AppleMenuButton: View {
    let theme: ThemeConfig

    var body: some View {
        Button {
            AppleMenuController.shared.toggle(
                relativeTo: ButtonScreenFrames.apple.rect,
                theme: theme
            )
        } label: {
            Image(systemName: "apple.logo")
                .font(.system(size: max(theme.fontSize + 1, 13), weight: .medium))
                .foregroundColor(Color(hex: theme.textColor))
                .frame(minWidth: 24, minHeight: 24)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(BarIconButtonStyle(theme: theme))
        .help("Apple menu")
        .background(
            ScreenFrameReader { frame in
                ButtonScreenFrames.apple.rect = frame
            }
        )
    }
}

/// Mutable screen rects that outlive SwiftUI body rebuilds.
///
/// Avoid `@State` here: macOS 27 CLT ships SwiftUI's `State` as an external
/// macro (`SwiftUIMacros`) but does not include the plugin binary (Xcode does).
private enum ButtonScreenFrames {
    static let bluetooth = ScreenFrameBox()
    static let wifi = ScreenFrameBox()
    static let clock = ScreenFrameBox()
    static let apple = ScreenFrameBox()
}

private final class ScreenFrameBox {
    var rect: NSRect = .zero
}

/// Reports this view's frame in AppKit screen coordinates.
private struct ScreenFrameReader: NSViewRepresentable {
    var onChange: (NSRect) -> Void

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: ReaderView, context: Context) {
        nsView.onChange = onChange
        nsView.report()
    }

    final class ReaderView: NSView {
        var onChange: ((NSRect) -> Void)?

        override func layout() {
            super.layout()
            report()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            report()
        }

        func report() {
            guard let window else { return }
            let rect = window.convertToScreen(convert(bounds, to: nil))
            onChange?(rect)
        }
    }
}

private struct BarIconButtonStyle: ButtonStyle {
    let theme: ThemeConfig

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
