import AppKit
import SwiftUI

struct MainView: View {
    @ObservedObject var viewModel: LauncherViewModel
    @ObservedObject var configManager: ConfigManager
    var onHeightChange: (CGFloat) -> Void
    var onRequestClose: () -> Void
    var focusToken: UUID

    @FocusState private var searchFocused: Bool

    private var theme: ThemeConfig { configManager.config.theme }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
                .overlay(Color(hex: theme.borderColor).opacity(0.35))

            if viewModel.mode == .menu && !viewModel.accessibilityTrusted {
                accessibilityPrompt
            } else if viewModel.results.isEmpty {
                emptyState
            } else {
                resultsList
            }
        }
        .font(theme.swiftUIFont)
        .foregroundStyle(Color(hex: theme.textColor))
        .background(Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous))
        .background(
            GeometryReader { geo in
                Color.clear
                    .preference(key: PanelHeightKey.self, value: geo.size.height)
            }
        )
        .onPreferenceChange(PanelHeightKey.self) { height in
            onHeightChange(height)
        }
        .onAppear {
            searchFocused = true
        }
        .onChange(of: focusToken) { _ in
            searchFocused = true
        }
        .onExitCommand {
            onRequestClose()
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: viewModel.mode == .apps ? "sparkle.magnifyingglass" : "menubar.rectangle")
                .foregroundStyle(Color(hex: theme.subtextColor))
                .frame(width: 18)

            TextField(placeholder, text: $viewModel.query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .font(theme.swiftUIFont)
                .foregroundStyle(Color(hex: theme.textColor))
                .onSubmit {
                    if viewModel.activateSelection() {
                        onRequestClose()
                    }
                }

            modeBadge
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var modeBadge: some View {
        Text(viewModel.mode.rawValue.uppercased())
            .font(.system(size: max(theme.fontSize - 3, 10), weight: .semibold, design: .rounded))
            .tracking(0.6)
            .foregroundStyle(Color(hex: theme.selectionText))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(hex: theme.selectionBackground))
            )
            .help("Tab or type : to switch modes")
    }

    private var placeholder: String {
        switch viewModel.mode {
        case .apps: return "Search apps…"
        case .menu: return "Search menu commands…"
        }
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(viewModel.results.enumerated()), id: \.element.id) { index, item in
                        ResultRow(
                            item: item,
                            isSelected: index == viewModel.selectedIndex,
                            theme: theme
                        )
                        .id(item.id)
                        .onTapGesture {
                            viewModel.selectIndex(index)
                            if viewModel.activateSelection() {
                                onRequestClose()
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .frame(maxHeight: configManager.config.dimensions.maxHeight - 64)
            .onChange(of: viewModel.selectedIndex) { idx in
                guard viewModel.results.indices.contains(idx) else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(viewModel.results[idx].id, anchor: .center)
                }
            }
        }
    }

    private var emptyState: some View {
        Text(emptyMessage)
            .foregroundStyle(Color(hex: theme.subtextColor))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
    }

    private var emptyMessage: String {
        if viewModel.query.isEmpty {
            return viewModel.mode == .apps ? "Start typing to filter applications." : "No menu commands found."
        }
        return "No matches."
    }

    private var accessibilityPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Accessibility required")
                .font(.system(size: theme.fontSize, weight: .semibold))
            Text("Grant Accessibility access so Launcher can read and activate the frontmost app’s menu bar.")
                .foregroundStyle(Color(hex: theme.subtextColor))
                .fixedSize(horizontal: false, vertical: true)
            Button("Open System Settings") {
                _ = MenuBarScanner.isTrusted(prompt: true)
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(hex: theme.selectionText))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Row

private struct ResultRow: View {
    let item: LauncherItem
    let isSelected: Bool
    let theme: ThemeConfig

    var body: some View {
        HStack(spacing: 12) {
            icon
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .foregroundStyle(Color(hex: isSelected ? theme.selectionText : theme.textColor))
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.system(size: max(theme.fontSize - 2, 11)))
                    .foregroundStyle(Color(hex: theme.subtextColor))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: max(theme.cornerRadius - 4, 6), style: .continuous)
                .fill(isSelected ? Color(hex: theme.selectionBackground) : Color.clear)
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var icon: some View {
        switch item {
        case .app(let app):
            Image(nsImage: app.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 28, height: 28)
        case .menu:
            Image(systemName: "command")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(hex: isSelected ? theme.selectionText : theme.subtextColor))
                .frame(width: 28, height: 28)
        }
    }
}

// MARK: - Preference

private struct PanelHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 120
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Key handling monitor attached at AppController level

enum LauncherKeyRouter {
    static func handle(
        event: NSEvent,
        viewModel: LauncherViewModel,
        onClose: () -> Void,
        onActivate: () -> Void
    ) -> Bool {
        switch event.keyCode {
        case 53: // escape
            onClose()
            return true
        case 126: // up
            viewModel.moveSelection(by: -1)
            return true
        case 125: // down
            viewModel.moveSelection(by: 1)
            return true
        case 48: // tab
            viewModel.toggleMode()
            return true
        case 36, 76: // return / keypad enter
            if viewModel.activateSelection() {
                onActivate()
            }
            return true
        default:
            return false
        }
    }
}
