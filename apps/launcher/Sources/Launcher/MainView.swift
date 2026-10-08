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
        .frame(height: idealHeight, alignment: .top)
        .onAppear {
            searchFocused = true
            onHeightChange(idealHeight)
        }
        .onChange(of: idealHeight) { height in
            onHeightChange(height)
        }
        .onChange(of: focusToken) { _ in
            searchFocused = true
        }
        .onExitCommand {
            onRequestClose()
        }
    }

    /// Fixed metrics so window height snaps to whole rows (no half-clipped last line).
    private enum Metrics {
        static let header: CGFloat = 52
        static let divider: CGFloat = 1
        static let listPadding: CGFloat = 16
        static let emptyBody: CGFloat = 52
        static let accessibilityBody: CGFloat = 148
        static let appRow: CGFloat = 48
        static let appRowSpacing: CGFloat = 2
        static let menuSection: CGFloat = 22
        static let menuItem: CGFloat = 30
    }

    /// Window height from content — not GeometryReader (that only sees the panel's current frame).
    private var idealHeight: CGFloat {
        let maxH = CGFloat(configManager.config.dimensions.maxHeight)
        let chrome = Metrics.header + Metrics.divider
        let bodyMax = max(maxH - chrome, 0)

        if viewModel.mode == .menu && !viewModel.accessibilityTrusted {
            return chrome + min(Metrics.accessibilityBody, bodyMax)
        }
        if viewModel.results.isEmpty {
            return chrome + min(Metrics.emptyBody, bodyMax)
        }

        return chrome + fittedListHeight(maxBody: bodyMax)
    }

    /// Largest height ≤ `maxBody` that ends on a whole row boundary.
    private func fittedListHeight(maxBody: CGFloat) -> CGFloat {
        if viewModel.mode == .menu {
            var height = Metrics.listPadding
            var fitted = Metrics.listPadding
            for row in displayRows {
                let rowH: CGFloat
                switch row {
                case .section: rowH = Metrics.menuSection
                case .item: rowH = Metrics.menuItem
                }
                if height + rowH > maxBody { break }
                height += rowH
                fitted = height
            }
            return fitted
        }

        let count = viewModel.results.count
        var fittedCount = 0
        while fittedCount < count {
            let next = Metrics.listPadding
                + CGFloat(fittedCount + 1) * Metrics.appRow
                + CGFloat(fittedCount) * Metrics.appRowSpacing
            if next > maxBody { break }
            fittedCount += 1
        }
        guard fittedCount > 0 else { return min(Metrics.listPadding + Metrics.appRow, maxBody) }
        return Metrics.listPadding
            + CGFloat(fittedCount) * Metrics.appRow
            + CGFloat(fittedCount - 1) * Metrics.appRowSpacing
    }

    private enum DisplayRow: Identifiable {
        case section(String)
        case item(LauncherItem)

        var id: String {
            switch self {
            case .section(let name): return "section:\(name)"
            case .item(let item): return item.id
            }
        }
    }

    /// Apps / clipboard stay flat; menu commands group under their top-level menu title.
    private var displayRows: [DisplayRow] {
        guard viewModel.mode == .menu else {
            return viewModel.results.map { .item($0) }
        }
        var rows: [DisplayRow] = []
        var lastRoot: String?
        for item in viewModel.results {
            guard case .menu(let cmd) = item else {
                rows.append(.item(item))
                continue
            }
            if cmd.rootMenu != lastRoot {
                rows.append(.section(cmd.rootMenu))
                lastRoot = cmd.rootMenu
            }
            rows.append(.item(item))
        }
        return rows
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: headerIcon)
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

    private var headerIcon: String {
        switch viewModel.mode {
        case .apps: return "sparkle.magnifyingglass"
        case .menu: return "menubar.rectangle"
        case .clipboard: return "clipboard"
        }
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
            .help("Tab to cycle modes · : Menu · ; Clipboard")
    }

    private var placeholder: String {
        switch viewModel.mode {
        case .apps: return "Search apps…"
        case .menu: return "Search menu commands…"
        case .clipboard: return "Search clipboard history…"
        }
    }

    private var resultsList: some View {
        let listBody = idealHeight - Metrics.header - Metrics.divider
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: viewModel.mode == .menu ? 0 : Metrics.appRowSpacing) {
                    ForEach(displayRows) { row in
                        switch row {
                        case .section(let name):
                            Text(name)
                                .font(.system(size: max(theme.fontSize - 2, 11), weight: .semibold))
                                .foregroundStyle(Color(hex: theme.subtextColor))
                                .padding(.horizontal, 12)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                                .frame(height: Metrics.menuSection)
                        case .item(let item):
                            ResultRow(
                                item: item,
                                isSelected: viewModel.results.firstIndex(of: item) == viewModel.selectedIndex,
                                theme: theme,
                                indented: viewModel.mode == .menu,
                                height: viewModel.mode == .menu ? Metrics.menuItem : Metrics.appRow
                            )
                            .id(item.id)
                            .onTapGesture {
                                guard let index = viewModel.results.firstIndex(of: item) else { return }
                                viewModel.selectIndex(index)
                                if viewModel.activateSelection() {
                                    onRequestClose()
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, Metrics.listPadding / 2)
            }
            .frame(height: listBody)
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
            switch viewModel.mode {
            case .apps: return "Start typing to filter applications."
            case .menu: return "No menu commands found."
            case .clipboard: return "Clipboard history is empty."
            }
        }
        return "No matches."
    }

    private var accessibilityPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Accessibility required")
                .font(.system(size: theme.fontSize, weight: .semibold))
            Text("macOS isn’t allowing this Launcher build to read the menu bar. If Launcher already appears enabled in Privacy → Accessibility, remove that row, add ~/Applications/Launcher.app again, then toggle it on (rebuilds invalidate old grants).")
                .foregroundStyle(Color(hex: theme.subtextColor))
                .fixedSize(horizontal: false, vertical: true)
            Button("Open System Settings") {
                viewModel.requestAccessibilityAccess()
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
    var indented: Bool = false
    var height: CGFloat = 48

    var body: some View {
        HStack(spacing: indented ? 8 : 12) {
            if !indented {
                icon
                    .frame(width: 28, height: 28)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .foregroundStyle(Color(hex: isSelected ? theme.selectionText : theme.textColor))
                    .lineLimit(1)
                if !indented, !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.system(size: max(theme.fontSize - 2, 11)))
                        .foregroundStyle(Color(hex: theme.subtextColor))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, indented ? 22 : 10)
        .padding(.trailing, 10)
        .frame(height: height)
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
        case .clipboard(let entry):
            if entry.kind == .image,
               let nsImage = ClipboardHistoryStore.shared.image(for: entry)
            {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(hex: isSelected ? theme.selectionText : theme.subtextColor))
                    .frame(width: 28, height: 28)
            }
        }
    }
}

// MARK: - Key handling monitor attached at AppController level

enum LauncherKeyRouter {
    @MainActor
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
            let shift = event.modifierFlags.contains(.shift)
            let ok: Bool
            if shift, viewModel.mode == .clipboard {
                ok = viewModel.pasteSelection()
            } else {
                ok = viewModel.activateSelection()
            }
            if ok {
                onActivate()
            }
            return true
        default:
            return false
        }
    }
}
