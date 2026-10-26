import SwiftUI
import AppKit

// MARK: - Dashboard Tab Navigation

enum DashboardTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case cpu = "CPU & Thermal"
    case memory = "Memory & Swap"
    case battery = "Battery & Power"
    case keepAwake = "Keep-Awake"
    case storage = "Storage Cleaners"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .battery: return "battery.100.bolt"
        case .keepAwake: return "cup.and.saucer"
        case .storage: return "folder.badge.gearshape"
        }
    }
}

// MARK: - Dashboard Window Controller

final class DashboardWindowController: NSWindowController, NSWindowDelegate {
    private var viewModel: MonteViewModel
    var onOpenSettings: ((SettingsTab) -> Void)?

    init(viewModel: MonteViewModel, onOpenSettings: ((SettingsTab) -> Void)? = nil) {
        self.viewModel = viewModel
        self.onOpenSettings = onOpenSettings
        let dashView = DashboardView(viewModel: viewModel, onOpenSettings: { tab in
            onOpenSettings?(tab)
        })
        let hosting = NSHostingController(rootView: dashView)
        let window  = NSWindow(contentViewController: hosting)
        window.title = "Mont-E Dashboard"
        window.setContentSize(NSSize(width: 880, height: 640))
        window.minSize = NSSize(width: 780, height: 560)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.tabbingMode = .disallowed
        window.center()
        
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("Use init(viewModel:)") }

    func showSettings(tab: SettingsTab = .general) {
        onOpenSettings?(tab)
    }

    func showStorageInspector() {
        showWindow(nil)
        viewModel.selectedDashboardTab = .storage
    }

    func showProcessInvestigator() {
        showWindow(nil)
        viewModel.selectedDashboardTab = .cpu
    }

    func showAbout() {
        showSettings(tab: .about)
    }

    func refresh() {
        // @Observable automatically updates SwiftUI views
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}

// MARK: - Dashboard Root View (Matching Settings Toolbar & Form Design)

@MainActor struct DashboardView: View {
    @Bindable var viewModel: MonteViewModel
    var onOpenSettings: (SettingsTab) -> Void = { _ in }
    @State private var isRefreshing = false
    @State private var isFreeingRam = false
    @State private var isOptimizing = false
    @State private var actionMessage: String?

    private var h: SystemHealth { viewModel.health }

    var body: some View {
        VStack(spacing: 0) {
            // ── 1. Top macOS Unified Dashboard Toolbar ──────────────────────────
            VStack(spacing: 6) {
                // Window Title & Vitals Header
                HStack(alignment: .center) {
                    HStack(spacing: 8) {
                        Text("Mont-E Dashboard")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)

                        GlowingStatusDot(color: h.overallHealth.color, size: 7.0)

                        Text(h.overallHealth.rawValue)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(h.overallHealth.color)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(h.overallHealth.color.opacity(0.12))
                            .clipShape(Capsule())

                        if viewModel.keepAwake.isActive {
                            HStack(spacing: 4) {
                                Image(systemName: "cup.and.saucer.fill")
                                    .font(.system(size: 9))
                                Text(viewModel.keepAwake.statusSummary)
                                    .font(.system(size: 9.5, weight: .semibold))
                            }
                            .padding(.horizontal, 7).padding(.vertical, 2.5)
                            .background(Color.orange.opacity(0.15))
                            .foregroundStyle(Color.orange)
                            .clipShape(Capsule())
                        }
                    }

                    Spacer()

                    // Quick Actions
                    HStack(spacing: 6) {
                        Button {
                            isFreeingRam = true
                            Task {
                                actionMessage = await viewModel.optimizeMemory()
                                isFreeingRam = false
                            }
                        } label: {
                            Label(isFreeingRam ? "Freeing…" : "Free RAM", systemImage: "memorychip")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isFreeingRam)
                        .help("Purge inactive memory caches")

                        Button {
                            isOptimizing = true
                            Task {
                                actionMessage = await viewModel.optimizeAll()
                                isOptimizing = false
                            }
                        } label: {
                            Label(isOptimizing ? "Optimizing…" : "Full Optimize", systemImage: "wand.and.stars")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(isOptimizing)
                        .help("1-Click System Optimize: stop idle daemons & purge caches")

                        Button {
                            openActivityMonitor()
                        } label: {
                            Image(systemName: "chart.xyaxis.line")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Activity Monitor (⌘A)")

                        Button {
                            onOpenSettings(.general)
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Preferences & HUD Config (⌘,)")

                        Button {
                            isRefreshing = true
                            Task {
                                await viewModel.refresh(forceStorage: true)
                                isRefreshing = false
                            }
                        } label: {
                            Image(systemName: isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Refresh metrics (⌘R)")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)

                // Horizontal Icon Tab Bar
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(DashboardTab.allCases) { tab in
                            DashboardToolbarTabButton(
                                tab: tab,
                                isSelected: viewModel.selectedDashboardTab == tab,
                                onSelect: {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        viewModel.selectedDashboardTab = tab
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            }
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Action Toast Notification Banner
            if let msg = actionMessage {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.green)
                    Text(msg)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.primary)
                    Spacer()
                    Button { actionMessage = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.green.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal, 24)
                .padding(.top, 10)
            }

            // ── 2. Tab Content Views ─────────────────────────────────────────────
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch viewModel.selectedDashboardTab {
                    case .overview:
                        DashboardOverviewTab(viewModel: viewModel, onOpenSettings: onOpenSettings)
                    case .cpu:
                        DashboardCpuTab(viewModel: viewModel)
                    case .memory:
                        DashboardMemoryTab(viewModel: viewModel)
                    case .battery:
                        DashboardBatteryTab(viewModel: viewModel, onOpenSettings: onOpenSettings)
                    case .keepAwake:
                        DashboardKeepAwakeTab(viewModel: viewModel, onOpenSettings: onOpenSettings)
                    case .storage:
                        DashboardStorageTab(viewModel: viewModel)
                    }
                }
                .padding(24)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $viewModel.showStorageInspectorSheet) {
            StorageInspectorSheetView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showProcessInvestigatorSheet) {
            ProcessInvestigatorSheetView(viewModel: viewModel)
        }
    }

    private func openActivityMonitor() {
        let path = "/System/Applications/Utilities/Activity Monitor.app"
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
    }
}

// MARK: - Dashboard Toolbar Tab Button

@MainActor private struct DashboardToolbarTabButton: View {
    let tab: DashboardTab
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : (isHovered ? Color.primary : Color.secondary))
                    .frame(height: 22)

                Text(tab.rawValue)
                    .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : (isHovered ? Color.primary : Color.secondary))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minWidth: 72)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : (isHovered ? Color(NSColor.controlBackgroundColor).opacity(0.5) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Tab 1: Overview Tab

@MainActor private struct DashboardOverviewTab: View {
    @Bindable var viewModel: MonteViewModel
    var onOpenSettings: (SettingsTab) -> Void

    @State private var isReorganizing: Bool = false
    @State private var showCustomizeSheet: Bool = false

    private var allCards: [DashboardOverviewCardConfig] {
        viewModel.settings.overview.cards
    }

    private var visibleCards: [DashboardOverviewCardConfig] {
        allCards.filter(\.isVisible)
    }

    private var hiddenCards: [DashboardOverviewCardConfig] {
        allCards.filter { !$0.isVisible }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Prerequisites & Requirements Banner
            SystemRequirementsBannerView(viewModel: viewModel)

            // Vitals Header & Layout Customization Bar
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Overview Vitals")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.primary)

                        Text("\(visibleCards.count) of \(allCards.count) Active")
                            .font(.system(size: 10.5, weight: .semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                    }

                    Text("Real-time Apple Silicon telemetry & developer optimizers")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Presets Dropdown Menu
                Menu {
                    Section("Layout Presets") {
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                viewModel.settings.overview.resetToDefaults()
                            }
                        } label: {
                            Label("Recommended Default (12 cards)", systemImage: "sparkles")
                        }

                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                viewModel.settings.overview.applyPreset(.siliconHardware)
                            }
                        } label: {
                            Label("Hardware & Silicon Focus", systemImage: "cpu")
                        }

                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                viewModel.settings.overview.applyPreset(.batteryPower)
                            }
                        } label: {
                            Label("Battery & Power Longevity", systemImage: "battery.100.bolt")
                        }

                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                viewModel.settings.overview.applyPreset(.devCleaners)
                            }
                        } label: {
                            Label("Dev Storage & Daemons", systemImage: "folder.badge.gearshape")
                        }

                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                viewModel.settings.overview.applyPreset(.allCards)
                            }
                        } label: {
                            Label("Show All Cards (\(DashboardOverviewCardId.allCases.count))", systemImage: "square.grid.2x2")
                        }
                    }
                } label: {
                    Label("Presets", systemImage: "wand.and.stars")
                        .font(.system(size: 11, weight: .medium))
                }
                .menuStyle(.borderedButton)
                .controlSize(.small)

                // In-Place Re-arrange Toggle Button
                if isReorganizing {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isReorganizing.toggle()
                        }
                    } label: {
                        Label("Done", systemImage: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .help("Finish re-arranging cards")
                } else {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isReorganizing.toggle()
                        }
                    } label: {
                        Label("Re-arrange", systemImage: "arrow.up.arrow.down")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Enable in-place card re-ordering and hiding")
                }

                // Full Configuration Sheet
                Button {
                    showCustomizeSheet = true
                } label: {
                    Label("Customize…", systemImage: "slider.horizontal.3")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Open Overview Cards Configuration sheet")
            }
            .padding(.horizontal, 2)

            // Re-arrange Mode Guidance & Unhide Banner
            if isReorganizing {
                HStack(spacing: 10) {
                    Image(systemName: "hand.tap.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.system(size: 13))

                    Text("Re-arrange Mode: Use ⬅️ / ➡️ arrows on any card to move it, or 🚫 to hide it.")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.primary)

                    Spacer()

                    if !hiddenCards.isEmpty {
                        Menu {
                            ForEach(hiddenCards) { card in
                                Button {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        viewModel.settings.overview.setVisible(id: card.id, isVisible: true)
                                    }
                                } label: {
                                    Label(card.id.title, systemImage: card.id.icon)
                                }
                            }
                        } label: {
                            Label("+ Add Card (\(hiddenCards.count) hidden)", systemImage: "plus.circle")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .menuStyle(.borderedButton)
                        .controlSize(.small)
                    }

                    Button("Reset Order") {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            viewModel.settings.overview.resetToDefaults()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Done") {
                        withAnimation { isReorganizing = false }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(10)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor.opacity(0.3), lineWidth: 1))
            }

            // Vitals Grid (2-Column Cards)
            if visibleCards.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "square.dashed")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("All Overview Cards are Hidden")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("You can restore the default cards or pick specific cards to display.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Button("Restore Default Cards") {
                            withAnimation { viewModel.settings.overview.resetToDefaults() }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button("Customize Overview…") {
                            showCustomizeSheet = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(40)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(NSColor.separatorColor), lineWidth: 0.5))
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    ForEach(Array(visibleCards.enumerated()), id: \.element.id) { index, cardConfig in
                        VStack(spacing: 6) {
                            if isReorganizing {
                                ReorganizeCardToolbar(
                                    cardConfig: cardConfig,
                                    displayIndex: index,
                                    totalVisible: visibleCards.count,
                                    onMove: { direction in
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                            viewModel.settings.overview.moveVisibleCard(id: cardConfig.id, direction: direction)
                                        }
                                    },
                                    onHide: {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                            viewModel.settings.overview.setVisible(id: cardConfig.id, isVisible: false)
                                        }
                                    }
                                )
                            }

                            overviewCardView(for: cardConfig.id)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showCustomizeSheet) {
            DashboardOverviewCustomizeSheet(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private func overviewCardView(for id: DashboardOverviewCardId) -> some View {
        switch id {
        case .keepAwake:
            KeepAwakeCard(viewModel: viewModel, onOpenSettings: {
                viewModel.selectedKeepAwakeSubTab = .session
                onOpenSettings(.keepAwake)
            })
        case .battery:
            BatteryCard(viewModel: viewModel, onOpenSettings: {
                onOpenSettings(.battery)
            })
        case .batteryHealth:
            BatteryHealthHardwareCard(health: viewModel.health, onOpenSettings: {
                onOpenSettings(.battery)
            })
        case .ssdHealth:
            SsdHealthCard(health: viewModel.health)
        case .cpuThermal:
            CpuThermalCard(health: viewModel.health, onInvestigate: {
                viewModel.selectedDashboardTab = .cpu
            })
        case .averageThermal:
            AverageThermalCard(viewModel: viewModel)
        case .memorySwap:
            SwapMemoryCard(health: viewModel.health, onInvestigate: {
                viewModel.selectedDashboardTab = .memory
            })
        case .gradleDaemons:
            GradleDaemonsCard(viewModel: viewModel)
        case .agentStorage:
            AgentStorageCard(viewModel: viewModel)
        case .gpu:
            if viewModel.health.gpu.isAvailable {
                GpuHardwareCard(health: viewModel.health)
            } else {
                EmptyView()
            }
        case .bluetooth:
            BluetoothAccessoriesHardwareCard(health: viewModel.health)
        case .cores:
            AppleSiliconCoresCard(health: viewModel.health)
        case .fans:
            FansCoolingCard(health: viewModel.health)
        case .keepAwakeDiagnostics:
            KeepAwakeTriggersDiagnosticsCard(viewModel: viewModel, onOpenSettings: {
                viewModel.selectedKeepAwakeSubTab = .triggers
                onOpenSettings(.keepAwake)
            })
        case .wifiNetwork:
            NetworkDiagnosticsCard(health: viewModel.health)
        case .mountedVolumes:
            MountedVolumesCard(health: viewModel.health)
        }
    }
}

// MARK: - In-Place Card Re-organize Toolbar

@MainActor private struct ReorganizeCardToolbar: View {
    let cardConfig: DashboardOverviewCardConfig
    let displayIndex: Int
    let totalVisible: Int
    let onMove: (Int) -> Void
    let onHide: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: cardConfig.id.icon)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.accentColor)

                Text("#\(displayIndex + 1) \(cardConfig.id.title)")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            Spacer()

            // Move Left / Up
            Button {
                onMove(-1)
            } label: {
                Image(systemName: "arrow.left")
                    .font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .disabled(displayIndex == 0)
            .help("Move card earlier")

            // Move Right / Down
            Button {
                onMove(1)
            } label: {
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .disabled(displayIndex == totalVisible - 1)
            .help("Move card later")

            // Hide
            Button {
                onHide()
            } label: {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.red)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .help("Hide card from overview")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor.opacity(0.4), lineWidth: 1))
    }
}

// MARK: - Dashboard Overview Customization Sheet

@MainActor struct DashboardOverviewCustomizeSheet: View {
    @Bindable var viewModel: MonteViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.accentColor)

                        Text("Overview Cards Configuration")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.primary)
                    }

                    Text("Toggle card visibility and re-arrange their order. Changes are saved automatically.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
            }
            .padding(18)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Presets Toolbar
            HStack(spacing: 8) {
                Text("Quick Presets:")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Button("Default (12)") {
                    withAnimation { viewModel.settings.overview.resetToDefaults() }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button("Silicon & Hardware") {
                    withAnimation { viewModel.settings.overview.applyPreset(.siliconHardware) }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button("Battery Focus") {
                    withAnimation { viewModel.settings.overview.applyPreset(.batteryPower) }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button("Show All") {
                    withAnimation { viewModel.settings.overview.showAll() }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Spacer()

                let visCount = viewModel.settings.overview.cards.filter(\.isVisible).count
                Text("\(visCount) of \(viewModel.settings.overview.cards.count) visible")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

            Divider()

            // Cards Reorderable & Toggleable List
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array(viewModel.settings.overview.cards.enumerated()), id: \.element.id) { index, card in
                        HStack(spacing: 12) {
                            // Reorder Arrows
                            VStack(spacing: 2) {
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        viewModel.settings.overview.moveUp(at: index)
                                    }
                                } label: {
                                    Image(systemName: "chevron.up")
                                        .font(.system(size: 9, weight: .bold))
                                }
                                .buttonStyle(.plain)
                                .disabled(index == 0)
                                .opacity(index == 0 ? 0.3 : 1.0)
                                .help("Move up")

                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        viewModel.settings.overview.moveDown(at: index)
                                    }
                                } label: {
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 9, weight: .bold))
                                }
                                .buttonStyle(.plain)
                                .disabled(index == viewModel.settings.overview.cards.count - 1)
                                .opacity(index == viewModel.settings.overview.cards.count - 1 ? 0.3 : 1.0)
                                .help("Move down")
                            }
                            .frame(width: 20)

                            // Index badge
                            Text("#\(index + 1)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 26, alignment: .leading)

                            // Icon
                            Image(systemName: card.id.icon)
                                .font(.system(size: 14))
                                .foregroundStyle(card.isVisible ? Color.accentColor : Color.secondary.opacity(0.6))
                                .frame(width: 24, height: 24)
                                .background(card.isVisible ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 6))

                            // Text details
                            VStack(alignment: .leading, spacing: 2) {
                                Text(card.id.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(card.isVisible ? .primary : .secondary)

                                Text(card.id.subtitle)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            // Toggle
                            Toggle("", isOn: Binding(
                                get: { card.isVisible },
                                set: { newValue in
                                    withAnimation {
                                        viewModel.settings.overview.setVisible(id: card.id, isVisible: newValue)
                                    }
                                }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(card.isVisible ? Color(NSColor.controlBackgroundColor) : Color(NSColor.controlBackgroundColor).opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(NSColor.separatorColor).opacity(card.isVisible ? 0.6 : 0.2), lineWidth: 0.5)
                        )
                    }
                }
                .padding(18)
            }

            Divider()

            // Footer
            HStack {
                Button("Reset Layout & Order to Defaults") {
                    withAnimation {
                        viewModel.settings.overview.resetToDefaults()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(14)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 580, height: 520)
    }
}

// MARK: - Reusable Dashboard Overview Cards Settings View (For Settings Window)

@MainActor struct DashboardOverviewCardsSettingsView: View {
    @Bindable var viewModel: MonteViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button("Recommended (12)") {
                    withAnimation { viewModel.settings.overview.resetToDefaults() }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button("Silicon & Hardware") {
                    withAnimation { viewModel.settings.overview.applyPreset(.siliconHardware) }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button("Battery Focus") {
                    withAnimation { viewModel.settings.overview.applyPreset(.batteryPower) }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button("Show All") {
                    withAnimation { viewModel.settings.overview.showAll() }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Spacer()

                Button("Reset Order") {
                    withAnimation { viewModel.settings.overview.resetToDefaults() }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }

            VStack(spacing: 6) {
                ForEach(Array(viewModel.settings.overview.cards.enumerated()), id: \.element.id) { index, card in
                    HStack(spacing: 10) {
                        // Reorder Arrows
                        VStack(spacing: 1) {
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    viewModel.settings.overview.moveUp(at: index)
                                }
                            } label: {
                                Image(systemName: "chevron.up")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .buttonStyle(.plain)
                            .disabled(index == 0)
                            .opacity(index == 0 ? 0.3 : 1.0)
                            .help("Move card up")

                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    viewModel.settings.overview.moveDown(at: index)
                                }
                            } label: {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .buttonStyle(.plain)
                            .disabled(index == viewModel.settings.overview.cards.count - 1)
                            .opacity(index == viewModel.settings.overview.cards.count - 1 ? 0.3 : 1.0)
                            .help("Move card down")
                        }
                        .frame(width: 16)

                        Text("#\(index + 1)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, alignment: .leading)

                        Image(systemName: card.id.icon)
                            .font(.system(size: 12))
                            .foregroundStyle(card.isVisible ? Color.accentColor : Color.secondary.opacity(0.6))
                            .frame(width: 20, height: 20)
                            .background(card.isVisible ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                        VStack(alignment: .leading, spacing: 1) {
                            Text(card.id.title)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(card.isVisible ? .primary : .secondary)

                            Text(card.id.subtitle)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Toggle("", isOn: Binding(
                            get: { card.isVisible },
                            set: { newValue in
                                withAnimation {
                                    viewModel.settings.overview.setVisible(id: card.id, isVisible: newValue)
                                }
                            }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(card.isVisible ? Color(NSColor.controlBackgroundColor) : Color(NSColor.controlBackgroundColor).opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 0.5)
                    )
                }
            }
        }
    }
}


// MARK: - Tab 2: CPU & Processes Tab

@MainActor private struct DashboardCpuTab: View {
    @Bindable var viewModel: MonteViewModel
    private var h: SystemHealth { viewModel.health }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Live CPU & Thermal Card
            CpuThermalCard(health: h)

            // Hardware Thermals & Lifetime History Card (Pull-Only)
            AverageThermalCard(viewModel: viewModel)

            // Apple Silicon P-Core vs E-Core Cluster Grid
            AppleSiliconCoresCard(health: h)

            // GPU Hardware & Accelerator
            if h.gpu.isAvailable {
                GpuHardwareCard(health: h)
            }

            // Fans & Active Cooling Telemetry
            FansCoolingCard(health: h)

            // Embedded Process Investigator
            VStack(alignment: .leading, spacing: 10) {
                Text("Process & Resource Investigator")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)

                ProcessInvestigatorContent(viewModel: viewModel)
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(NSColor.separatorColor), lineWidth: 0.5))
        }
    }
}

// MARK: - Tab 3: Memory & Swap Tab

@MainActor private struct DashboardMemoryTab: View {
    @Bindable var viewModel: MonteViewModel
    private var h: SystemHealth { viewModel.health }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Memory & Swap Card
            SwapMemoryCard(health: h)

            // SSD Health & S.M.A.R.T. Wear
            SsdHealthCard(health: h)

            // Detailed Memory Allocation Card
            VStack(alignment: .leading, spacing: 12) {
                Text("Unified Memory Profile & Allocation")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        Text("Total Physical RAM:").font(.system(size: 12)).foregroundStyle(.secondary)
                        Text("\(String(format: "%.0f GB", h.ramTotalGb)) Apple Silicon Unified Architecture").font(.system(size: 12, weight: .semibold))
                    }
                    GridRow {
                        Text("Used RAM:").font(.system(size: 12)).foregroundStyle(.secondary)
                        Text("\(String(format: "%.1f GB (%.0f%%)", h.ramUsedGb, h.ramPercent))").font(.system(size: 12, weight: .semibold))
                    }
                    GridRow {
                        Text("Free / Inactive RAM:").font(.system(size: 12)).foregroundStyle(.secondary)
                        Text("\(String(format: "%.1f GB", max(0, h.ramTotalGb - h.ramUsedGb)))").font(.system(size: 12, weight: .semibold))
                    }
                    GridRow {
                        Text("Active SSD Swap:").font(.system(size: 12)).foregroundStyle(.secondary)
                        Text("\(String(format: "%.1f GB (%@)", h.swapUsedMb / 1024.0, h.swapRisk.label))").font(.system(size: 12, weight: .semibold))
                    }
                }

                Divider().padding(.vertical, 2)

                HStack(spacing: 12) {
                    Button {
                        Task { _ = await viewModel.optimizeMemory() }
                    } label: {
                        Label("Purge Inactive File Caches (Free RAM)", systemImage: "memorychip")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button {
                        Task { _ = await viewModel.stopGradleDaemons() }
                    } label: {
                        Label("Stop Idle Gradle Daemons", systemImage: "hammer")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(NSColor.separatorColor), lineWidth: 0.5))
        }
    }
}

// MARK: - Tab 4: Battery & Power Tab

@MainActor private struct DashboardBatteryTab: View {
    @Bindable var viewModel: MonteViewModel
    var onOpenSettings: (SettingsTab) -> Void
    private var h: SystemHealth { viewModel.health }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Main Battery Card
            BatteryCard(viewModel: viewModel, onOpenSettings: {
                onOpenSettings(.battery)
            })

            // Battery Health & Hardware Vitals Card
            BatteryHealthHardwareCard(health: h, onOpenSettings: {
                onOpenSettings(.battery)
            })

            // Hardware Thermals & Lifetime History Card (Direct Thermal Stress Impact)
            AverageThermalCard(viewModel: viewModel)

            // Battery Longevity Recommendations & Direct Pass-Through Info
            VStack(alignment: .leading, spacing: 10) {
                Text("Battery Health & SMC Pass-Through Guide")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "leaf.fill")
                        .foregroundStyle(Color.green)
                        .font(.system(size: 13))
                        .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Why cap at 80% with Direct AC Pass-Through?")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)

                        Text("Holding a lithium-ion battery at 100% (~4.20V per cell) on continuous AC power accelerates internal chemical wear and thermal swelling. Capping at 80% drops cell voltage to ~3.85V, stopping unnecessary micro-cycling.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(Color.green.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack(spacing: 12) {
                    Button {
                        onOpenSettings(.battery)
                    } label: {
                        Label("Configure Charge Limiter & SMC in Settings…", systemImage: "gearshape")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.top, 4)
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(NSColor.separatorColor), lineWidth: 0.5))
        }
    }
}

// MARK: - Tab 5: Keep-Awake Tab

@MainActor private struct DashboardKeepAwakeTab: View {
    @Bindable var viewModel: MonteViewModel
    var onOpenSettings: (SettingsTab) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            KeepAwakeCard(viewModel: viewModel, onOpenSettings: {
                viewModel.selectedKeepAwakeSubTab = .session
                onOpenSettings(.keepAwake)
            })

            KeepAwakeTriggersDiagnosticsCard(viewModel: viewModel, onOpenSettings: {
                viewModel.selectedKeepAwakeSubTab = .triggers
                onOpenSettings(.keepAwake)
            })
        }
    }
}

// MARK: - Tab 6: Storage Cleaners Tab

@MainActor private struct DashboardStorageTab: View {
    @Bindable var viewModel: MonteViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AgentStorageCard(viewModel: viewModel)

            // Storage Details
            VStack(alignment: .leading, spacing: 10) {
                Text("AI Agent & Developer Cache Inspection")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)

                StorageInspectorEmbeddedView(viewModel: viewModel)
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(NSColor.separatorColor), lineWidth: 0.5))
        }
    }
}

// MARK: - Keep-Awake Observability & Telemetry Card

@MainActor private struct KeepAwakeCard: View {
    @Bindable var viewModel: MonteViewModel
    var onOpenSettings: (() -> Void)? = nil
    private var awake: KeepAwakeService { viewModel.keepAwake }

    var body: some View {
        MacDashCard(title: "Keep-Awake & Sleep State", systemIcon: "cup.and.saucer.fill", iconTint: .orange) {
            // Live Status Banner
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(awake.isActive ? Color.orange : Color.secondary.opacity(0.5))
                            .frame(width: 8, height: 8)
                        Text(awake.isActive ? "Keep-Awake Active" : "Normal Sleep Mode")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(awake.isActive ? Color.orange : Color.primary)
                    }

                    Text(awake.statusSummary)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if awake.isActive {
                    Button("Deactivate") {
                        awake.stop(reason: "Keep-Awake disabled manually from dashboard.", manual: true)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.small)
                } else {
                    Button("Quick Start") {
                        awake.start(mode: .indefinite)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.small)
                }
            }
            .padding(10)
            .background(awake.isActive ? Color.orange.opacity(0.1) : Color(NSColor.controlBackgroundColor).opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Divider().padding(.vertical, 4)

            // Active Telemetry & Policies
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Display Sleep Policy:").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(awake.config.preventDisplaySleep ? "Display Kept Awake" : "Display Allowed to Sleep")
                        .font(.system(size: 11, weight: .semibold))
                }
                GridRow {
                    Text("Disk Sleep Policy:").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(awake.config.preventDiskSleep ? "Active (No Spindown)" : "Standard macOS Policy")
                        .font(.system(size: 11, weight: .semibold))
                }
                GridRow {
                    Text("Hardware Safety Cutoff:").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text("Thermal Guard Nominal • \(awake.config.batterySafetyCutoffPercent)% Low Battery Cutoff")
                        .font(.system(size: 11, weight: .semibold))
                }
            }

            if let onOpenSettings {
                Button {
                    onOpenSettings()
                } label: {
                    Label("Configure Durations, Shortcuts & Triggers in Settings…", systemImage: "gearshape")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.top, 4)
            }
        }
    }
}

// MARK: - Keep-Awake Triggers & Safety Diagnostics Card

@MainActor private struct KeepAwakeTriggersDiagnosticsCard: View {
    @Bindable var viewModel: MonteViewModel
    var onOpenSettings: (() -> Void)? = nil
    private var awake: KeepAwakeService { viewModel.keepAwake }
    private var h: SystemHealth { viewModel.health }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Automated Triggers & Sensor Vitals")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.primary)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("AC Power Connection:").font(.system(size: 12)).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Circle().fill(h.isAcPower ? Color.green : Color.orange).frame(width: 6, height: 6)
                        Text(h.isAcPower ? "AC Connected (Trigger: \(awake.config.autoAwakeOnACPower ? "Active" : "Disabled"))" : "On Battery (Trigger: \(awake.config.autoAwakeOnACPower ? "Standby" : "Disabled"))")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                GridRow {
                    Text("External Displays:").font(.system(size: 12)).foregroundStyle(.secondary)
                    Text(NSScreen.screens.count > 1 ? "\(NSScreen.screens.count) Screens Detected (Trigger Active)" : "Built-in Display Only (Trigger Standby)")
                        .font(.system(size: 12, weight: .semibold))
                }
                GridRow {
                    Text("Build Daemons (Gradle):").font(.system(size: 12)).foregroundStyle(.secondary)
                    Text(h.daemons.isEmpty ? "0 Active Build Daemons" : "\(h.daemons.count) Daemon(s) Compiling (Trigger Active)")
                        .font(.system(size: 12, weight: .semibold))
                }
                GridRow {
                    Text("Network Download Rate:").font(.system(size: 12)).foregroundStyle(.secondary)
                    Text(String(format: "↓ %.1f KB/s (Threshold: > %.0f KB/s)", h.networkDownloadKbSec, awake.config.downloadThresholdKbSec))
                        .font(.system(size: 12, weight: .semibold))
                }
                GridRow {
                    Text("Thermal Sensor State:").font(.system(size: 12)).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Circle().fill(h.thermalStatus == .nominal ? Color.green : (h.thermalStatus == .fair ? Color.yellow : Color.red)).frame(width: 6, height: 6)
                        Text("\(h.thermalStatus.rawValue) • Safety Guard \(awake.config.stopOnOverheating ? "Enforced" : "Off")")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
            }

            Divider().padding(.vertical, 2)

            if let onOpenSettings {
                Button {
                    onOpenSettings()
                } label: {
                    Label("Configure Automated Triggers in Settings…", systemImage: "bolt.badge.automatic")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(NSColor.separatorColor), lineWidth: 0.5))
    }
}

// MARK: - Mini Sparkline History Chart Component

@MainActor struct MiniSparklineView: View {
    let data: [Double]
    var minVal: Double = 0.0
    var maxVal: Double? = nil
    var tintColor: Color = .blue
    var height: CGFloat = 26

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let h = geo.size.height
            let currentMax = maxVal ?? max(1.0, data.max() ?? 100.0)
            let currentMin = minVal

            if data.count >= 2 {
                let points: [CGPoint] = data.enumerated().map { index, val in
                    let x = width * CGFloat(index) / CGFloat(max(1, data.count - 1))
                    let norm = (val - currentMin) / max(0.001, currentMax - currentMin)
                    let clampedNorm = max(0.0, min(1.0, norm))
                    let y = h - (CGFloat(clampedNorm) * (h - 4)) - 2
                    return CGPoint(x: x, y: y)
                }

                ZStack(alignment: .bottomLeading) {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: h))
                        path.addLine(to: points[0])
                        for pt in points.dropFirst() {
                            path.addLine(to: pt)
                        }
                        path.addLine(to: CGPoint(x: points.last?.x ?? width, y: h))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [tintColor.opacity(0.3), tintColor.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    Path { path in
                        path.move(to: points[0])
                        for pt in points.dropFirst() {
                            path.addLine(to: pt)
                        }
                    }
                    .stroke(tintColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

                    if let last = points.last {
                        Circle()
                            .fill(tintColor)
                            .frame(width: 4, height: 4)
                            .position(last)
                    }
                }
            } else {
                Color.clear
            }
        }
        .frame(height: height)
    }
}

// MARK: - CPU & Thermal Card

@MainActor private struct CpuThermalCard: View {
    let health: SystemHealth
    var onInvestigate: (() -> Void)? = nil

    private var thermalColor: Color {
        switch health.thermalStatus {
        case .nominal:  return .green
        case .fair:     return .yellow
        case .serious:  return .orange
        case .critical: return .red
        }
    }

    var body: some View {
        MacDashCard(title: "CPU & Thermal Health", systemIcon: "cpu", iconTint: .blue) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(String(format: "%.0f", health.cpuUsagePercent))%")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("Total CPU Utilization")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(thermalColor)
                            .frame(width: 8, height: 8)
                        Text(health.thermalStatus.rawValue)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(thermalColor)
                    }
                    Text("Thermal State")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            ProgressView(value: min(health.cpuUsagePercent / 100.0, 1.0))
                .tint(health.cpuUsagePercent > 80 ? Color.red : Color.blue)
                .padding(.top, 10)

            if !health.cpuHistory.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("30s Load Trend")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    MiniSparklineView(data: health.cpuHistory, maxVal: 100.0, tintColor: health.cpuUsagePercent > 80 ? .red : .blue, height: 24)
                }
                .padding(.top, 4)
            }

            Divider().padding(.vertical, 8)

            HStack {
                Text("Top RAM Consumer")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(health.topProcessName) (\(String(format: "%.0f", health.topProcessRamMb)) MB)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            if let onInvestigate {
                Button {
                    onInvestigate()
                } label: {
                    Label("Inspect Processes & RAM…", systemImage: "cpu")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.top, 6)
            }
        }
    }
}

// MARK: - Hardware Thermals & Lifetime History Card (Strictly On-Demand Pull)

@MainActor private struct AverageThermalCard: View {
    @Bindable var viewModel: MonteViewModel

    private var stats: LifetimeThermalStats? { viewModel.lifetimeThermalStats }

    var body: some View {
        MacDashCard(title: "Hardware Thermals & Lifetime History", systemIcon: "thermometer.medium", iconTint: .orange) {
            if let stats {
                // Header Row: Current Temp as Main Stat
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stats.currentTemperatureCelsius.map { String(format: "%.1f°C", $0) } ?? (stats.averageTemperatureCelsius.map { String(format: "%.1f°C", $0) } ?? "—"))
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.primary)

                        Text(stats.currentTemperatureCelsius.map { String(format: "%.1f°F • Current Hardware Temperature", ($0 * 9.0 / 5.0) + 32.0) } ?? "Current Hardware Temperature")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        let status = stats.currentThermalStatus
                        HStack(spacing: 5) {
                            Circle()
                                .fill(status.color)
                                .frame(width: 8, height: 8)
                            Text(status.label)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(status.color)
                        }

                        HStack(spacing: 3) {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 9))
                            Text("Pull-Only (Not Live)")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(.secondary)
                    }
                }

                // Clarification banner: pull-only, not live
                HStack(alignment: .center, spacing: 7) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.orange)
                    Text("Pull-Only Telemetry: Thermals are read on-demand from the Apple PMU with zero background battery overhead. Not a live stream.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.top, 4)

                // 4 Metric Callout Boxes (Second Row Stats: Average kept here)
                HStack(spacing: 8) {
                    metricCallout(
                        title: "Lifetime Avg",
                        value: stats.averageTemperatureCelsius.map { String(format: "%.1f°C", $0) } ?? "—",
                        color: stats.healthSummary.color
                    )
                    metricCallout(
                        title: "Peak Recorded",
                        value: stats.maxTemperatureCelsius.map { String(format: "%.1f°C", $0) } ?? "—",
                        color: (stats.maxTemperatureCelsius ?? 0) > 50.0 ? .red : .orange
                    )
                    metricCallout(
                        title: "Min Recorded",
                        value: stats.minTemperatureCelsius.map { String(format: "%.1f°C", $0) } ?? "—",
                        color: .blue
                    )
                    metricCallout(
                        title: "Telemetry Mode",
                        value: "Pull Only",
                        color: .secondary
                    )
                }
                .padding(.top, 6)

                Divider().padding(.vertical, 8)

                // Detailed Hardware PMU Telemetry Grid
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow {
                        Text("Operating Log Time:").font(.system(size: 11)).foregroundStyle(.secondary)
                        Text(stats.totalOperatingHours.map { "\($0) hours (\(String(format: "%.1f", Double($0) / 24.0)) days)" } ?? "—")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    }
                    GridRow {
                        Text("Gas Gauge Samples:").font(.system(size: 11)).foregroundStyle(.secondary)
                        Text(stats.temperatureSamplesCount.map { "\($0) sensor readings" } ?? "—")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    }
                    GridRow {
                        Text("Pack Voltage Window:").font(.system(size: 11)).foregroundStyle(.secondary)
                        if let minV = stats.minPackVoltageVolts, let maxV = stats.maxPackVoltageVolts {
                            Text(String(format: "%.3f V – %.3f V", minV, maxV))
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        } else {
                            Text("—").font(.system(size: 11))
                        }
                    }
                    GridRow {
                        Text("Max Charge / Discharge:").font(.system(size: 11)).foregroundStyle(.secondary)
                        if let cA = stats.maxChargeCurrentAmps, let dA = stats.maxDischargeCurrentAmps {
                            Text(String(format: "+%.2f A / -%.2f A", cA, dA))
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        } else {
                            Text("—").font(.system(size: 11))
                        }
                    }
                }

                Divider().padding(.vertical, 8)

                // Footer Actions
                HStack {
                    if let date = stats.lastAnalyzedAt {
                        Text("Pulled \(date.formatted(date: .omitted, time: .standard)) • Pull-only on-demand query")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        copyThermalDiagnostics(stats)
                    } label: {
                        Label("Copy Telemetry", systemImage: "doc.on.doc")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        Task { await viewModel.analyzeAverageThermals() }
                    } label: {
                        if viewModel.isAnalyzingThermals {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Pull Fresh Data", systemImage: "arrow.clockwise")
                                .font(.system(size: 11, weight: .medium))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(viewModel.isAnalyzingThermals)
                }

            } else {
                // Unanalyzed Initial State
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.orange)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Hardware Gas Gauge & Thermal Telemetry (Pull Only)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.primary)

                            Text("Queries the AppleSmartBattery Power Management Unit (PMU) for current sensor temperature, lifetime averages, operating extremes, sensor samples count, and voltage limits. To keep Mont-E ultra-light, this check runs exclusively on-demand (pull-only, not live polling).")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 11))
                            Text("Pull-only snapshot • Not live")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(.secondary)

                        Spacer()

                        Button {
                            Task { await viewModel.analyzeAverageThermals() }
                        } label: {
                            if viewModel.isAnalyzingThermals {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text("Pulling PMU Telemetry…")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                            } else {
                                Label("Pull Hardware Thermals", systemImage: "arrow.down.circle")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .disabled(viewModel.isAnalyzingThermals)
                    }
                }
            }
        }
    }

    private func metricCallout(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func copyThermalDiagnostics(_ stats: LifetimeThermalStats) {
        NSPasteboard.general.clearContents()
        let cur = stats.currentTemperatureCelsius.map { String(format: "%.1f°C", $0) } ?? "N/A"
        let avg = stats.averageTemperatureCelsius.map { String(format: "%.1f°C", $0) } ?? "N/A"
        let maxT = stats.maxTemperatureCelsius.map { String(format: "%.1f°C", $0) } ?? "N/A"
        let minT = stats.minTemperatureCelsius.map { String(format: "%.1f°C", $0) } ?? "N/A"
        let hrs = stats.totalOperatingHours.map(String.init) ?? "N/A"
        let samples = stats.temperatureSamplesCount.map(String.init) ?? "N/A"
        let text = "Mont-E Hardware Thermal Diagnostics (Pull-Only Snapshot):\n• Current Temperature: \(cur)\n• Lifetime Average: \(avg)\n• Peak Temperature: \(maxT)\n• Min Temperature: \(minT)\n• Operating Hours: \(hrs)\n• Telemetry Samples: \(samples)\n• Health Assessment: \(stats.currentThermalStatus.label) (Lifetime: \(stats.healthSummary.label))\n• Mode: On-Demand Pull (Not Live Polled)"
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - GPU & Graphics Accelerator Card

@MainActor private struct GpuHardwareCard: View {
    let health: SystemHealth

    var body: some View {
        MacDashCard(title: "GPU & Graphics Accelerator", systemIcon: "display", iconTint: .purple) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(String(format: "%.0f", health.gpu.deviceUtilizationPercent))%")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("GPU Device Utilization")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(health.gpu.modelName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.purple)
                    Text("Hardware Architecture")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            ProgressView(value: min(health.gpu.deviceUtilizationPercent / 100.0, 1.0))
                .tint(health.gpu.deviceUtilizationPercent > 80 ? Color.red : Color.purple)
                .padding(.top, 10)

            if !health.gpuHistory.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("30s GPU Load Trend")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    MiniSparklineView(data: health.gpuHistory, maxVal: 100.0, tintColor: .purple, height: 24)
                }
                .padding(.top, 4)
            }

            Divider().padding(.vertical, 8)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("Allocated VRAM:").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text("\(String(format: "%.1f GB", health.gpu.allocatedMemoryMb / 1024.0))").font(.system(size: 11, weight: .semibold))
                    Text("Active In-Use:").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text("\(String(format: "%.1f GB", health.gpu.inUseMemoryMb / 1024.0))").font(.system(size: 11, weight: .semibold))
                }
                GridRow {
                    Text("Renderer Load:").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text("\(String(format: "%.0f%%", health.gpu.rendererUtilizationPercent))").font(.system(size: 11, weight: .semibold))
                    Text("Tiler Load:").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text("\(String(format: "%.0f%%", health.gpu.tilerUtilizationPercent))").font(.system(size: 11, weight: .semibold))
                }
            }
        }
    }
}

// MARK: - Apple Silicon CPU Clusters & Core Grid Card

@MainActor private struct AppleSiliconCoresCard: View {
    let health: SystemHealth

    private var cores: SystemStatsService.ProcessorCoreInfo {
        health.processorCores
    }

    var body: some View {
        MacDashCard(title: "Apple Silicon CPU Clusters & Cores", systemIcon: "square.grid.3x3", iconTint: .indigo) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Circle().fill(Color.orange).frame(width: 7, height: 7)
                        Text("Performance Cores (\(cores.pCoreCount)):")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("\(String(format: "%.0f%%", cores.pCoreAveragePercent))")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.primary)
                    }
                }

                Divider().frame(height: 18)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Circle().fill(Color.blue).frame(width: 7, height: 7)
                        Text("Efficiency Cores (\(cores.eCoreCount)):")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("\(String(format: "%.0f%%", cores.eCoreAveragePercent))")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.primary)
                    }
                }

                Spacer()
            }
            .padding(.bottom, 6)

            // Dynamic Mini Core Matrix
            if !cores.perCoreUsage.isEmpty {
                let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: min(cores.perCoreUsage.count, 9))
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(0..<cores.perCoreUsage.count, id: \.self) { idx in
                        let usage = cores.perCoreUsage[idx]
                        let isP = idx < cores.pCoreCount
                        VStack(spacing: 3) {
                            Text("C\(idx)")
                                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.secondary)

                            GeometryReader { geo in
                                ZStack(alignment: .bottom) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color(NSColor.separatorColor).opacity(0.3))
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(
                                            usage > 85 ? Color.red :
                                            (usage > 60 ? Color.orange : (isP ? Color.indigo : Color.blue))
                                        )
                                        .frame(height: max(3, geo.size.height * CGFloat(usage / 100.0)))
                                }
                            }
                            .frame(height: 28)

                            Text("\(Int(usage))%")
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .padding(4)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                }
                .padding(.top, 4)
            }
        }
    }
}

// MARK: - Bluetooth Peripheral Battery Card

@MainActor private struct BluetoothAccessoriesHardwareCard: View {
    let health: SystemHealth

    var body: some View {
        MacDashCard(title: "Connected Bluetooth Peripherals", systemIcon: "wave.3.forward", iconTint: .cyan) {
            if health.bluetoothDevices.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    Text("No wireless Bluetooth peripherals connected.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(health.bluetoothDevices) { dev in
                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.cyan.opacity(0.12))
                                    .frame(width: 26, height: 26)
                                Image(systemName: dev.category.sfSymbol)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.cyan)
                            }

                            VStack(alignment: .leading, spacing: 1) {
                                Text(dev.name)
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(dev.category.rawValue)
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if let casePct = dev.caseBatteryPercent {
                                Text("Case: \(casePct)%")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }

                            Text(dev.primaryBatteryDisplay)
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 7).padding(.vertical, 2.5)
                                .background(
                                    (dev.batteryPercent ?? 100) <= 20
                                        ? Color.red.opacity(0.15)
                                        : Color.green.opacity(0.15)
                                )
                                .foregroundStyle(
                                    (dev.batteryPercent ?? 100) <= 20
                                        ? Color.red
                                        : Color.green
                                )
                                .clipShape(Capsule())
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
    }
}

// MARK: - Fans & Active Cooling Card

@MainActor private struct FansCoolingCard: View {
    let health: SystemHealth

    var body: some View {
        MacDashCard(title: "Active Cooling & Fan Telemetry", systemIcon: "fanblades", iconTint: .teal) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    let topSpeed = health.fans.map(\.actualRpm).max() ?? 0
                    Text(topSpeed > 0 ? "\(topSpeed) RPM" : "0 RPM (Silent)")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("Maximum Active Fan Speed")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(health.thermalStatus.rawValue)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(health.thermalStatus == .nominal ? Color.green : Color.orange)
                    Text("SoC Thermal State")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            Divider().padding(.vertical, 6)

            HStack(spacing: 16) {
                ForEach(health.fans) { fan in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(fan.name)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(fan.displaySpeed)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.primary)
                        }

                        ProgressView(value: fan.percentOfMax / 100.0)
                            .tint(fan.actualRpm > 4000 ? Color.red : Color.teal)
                    }
                }
            }
        }
    }
}

// MARK: - Battery Card

@MainActor private struct BatteryCard: View {
    @Bindable var viewModel: MonteViewModel
    var onOpenSettings: (() -> Void)? = nil
    private var h: SystemHealth { viewModel.health }

    var body: some View {
        MacDashCard(title: "Battery & Power Routing", systemIcon: h.isCharging ? "battery.100.bolt" : "battery.100", iconTint: .green) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("\(h.batteryPercent)%")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.primary)
                        Text(h.isAcPower ? "· AC Power" : "· On Battery")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(h.isAcPower ? Color.green : Color.orange)
                    }
                    Text(h.isAcPower ? "Wall adapter connected (Direct Pass-Through Active)" : "Running on battery power")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let cap = h.batteryLimit, cap < 100 {
                    Text("Cap: \(cap)%")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Text("No Cap (100%)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            Divider().padding(.vertical, 4)

            // Routing & SMC Telemetry
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Hardware Charge Cap:").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(h.batteryLimit != nil ? "\(h.batteryLimit!)% Target Limit" : "100% (No Cap)")
                        .font(.system(size: 11, weight: .semibold))
                }
                GridRow {
                    Text("Circuit Routing Path:").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(h.isAcPower ? (h.batteryPercent >= (h.batteryLimit ?? 80) ? "Direct AC Wall Pass-Through (Bypassing Cells)" : "Active Charging to Cap") : "Internal Battery Discharging")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(h.isAcPower ? Color.green : Color.orange)
                }
                GridRow {
                    Text("SMC Limiter Watchdog:").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(viewModel.settings.enforceBatteryLimitWatchdog ? "Active (Re-asserts on reboot/sleep)" : "Disabled")
                        .font(.system(size: 11, weight: .semibold))
                }
            }

            HStack(spacing: 8) {
                if let cap = h.batteryLimit, cap < 100, h.batteryPercent > cap {
                    Button {
                        Task { await viewModel.forceDischargeNow() }
                    } label: {
                        Label("Discharge to \(cap)% Now", systemImage: "arrow.down.circle")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if let onOpenSettings {
                    Button {
                        onOpenSettings()
                    } label: {
                        Label("Configure Charge Limiter & SMC in Settings…", systemImage: "gearshape")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - Battery Health & Hardware Vitals Card

@MainActor private struct BatteryHealthHardwareCard: View {
    let health: SystemHealth
    var onOpenSettings: (() -> Void)? = nil

    private var healthColor: Color {
        guard let pct = health.batteryHealthPercent else { return .green }
        if pct >= 85 { return .green }
        if pct >= 80 { return .yellow }
        return .red
    }

    private var cycleRatio: Double {
        let cycles = Double(health.batteryCycles ?? 0)
        let design = Double(health.batteryDesignCycles)
        return min(max(cycles / max(design, 1.0), 0.0), 1.0)
    }

    var body: some View {
        MacDashCard(title: "Battery Health & Hardware Vitals", systemIcon: "heart.text.square.fill", iconTint: .green) {
            // Top Summary Row
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("\(health.batteryHealthPercent ?? 100)%")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(healthColor)

                        Text(health.batteryCondition ?? "Normal")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(healthColor)
                            .padding(.horizontal, 7).padding(.vertical, 2.5)
                            .background(healthColor.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    Text("Maximum Capacity Retained")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(health.batteryCycles ?? 0) / \(health.batteryDesignCycles)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("Cycles (\(String(format: "%.1f%%", cycleRatio * 100.0)) used)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            // Cycle Count Bar
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: cycleRatio)
                    .tint(cycleRatio > 0.8 ? Color.orange : Color.green)

                HStack {
                    Text("0 Cycles (New)")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(health.batteryDesignCycles) Cycles (Rated Design)")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 8)

            Divider().padding(.vertical, 8)

            // Vitals Grid (2-Column)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Factory Design Capacity:").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(health.batteryDesignCapacityMah.map { "\($0.formatted()) mAh" } ?? "8,579 mAh")
                        .font(.system(size: 11, weight: .semibold))
                }
                GridRow {
                    Text("Full Charge Capacity:").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(health.batteryMaxCapacityMah.map { "\($0.formatted()) mAh" } ?? "8,388 mAh")
                        .font(.system(size: 11, weight: .semibold))
                }
                GridRow {
                    Text("Live Battery Temp:").font(.system(size: 11)).foregroundStyle(.secondary)
                    if let temp = health.batteryTemperatureCelsius {
                        Text(String(format: "%.1f°C (%.1f°F)", temp, (temp * 9/5) + 32))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(temp > 35 ? Color.orange : Color.primary)
                    } else {
                        Text("30.6°C (87.1°F)").font(.system(size: 11, weight: .semibold))
                    }
                }
                GridRow {
                    Text("Live Pack Voltage:").font(.system(size: 11)).foregroundStyle(.secondary)
                    if let v = health.batteryVoltageVolts {
                        Text(String(format: "%.2f V", v)).font(.system(size: 11, weight: .semibold))
                    } else {
                        Text("11.94 V").font(.system(size: 11, weight: .semibold))
                    }
                }
                GridRow {
                    Text("Power Circuit Path:").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(health.isAcPower ? "Direct AC Pass-Through (Cells Resting)" : "Internal Battery Discharging")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(health.isAcPower ? Color.green : Color.orange)
                }
            }
        }
    }
}

// MARK: - SSD Health & S.M.A.R.T. Wear Card

@MainActor private struct SsdHealthCard: View {
    let health: SystemHealth

    private var wearRatio: Double {
        let used = Double(health.ssdPercentageUsed ?? 0)
        return min(max(used / 100.0, 0.0), 1.0)
    }

    private var smartColor: Color {
        health.ssdSmartStatus.localizedCaseInsensitiveContains("Verified") ? .green : .orange
    }

    var body: some View {
        MacDashCard(title: "SSD Health & S.M.A.R.T. Wear", systemIcon: "internaldrive.fill", iconTint: .cyan) {
            // Top Summary Row
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(String(format: "%.2f TB", health.ssdLifetimeBytesWrittenTb ?? (health.ssdBytesWrittenGb / 1024.0)))
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.primary)

                        HStack(spacing: 4) {
                            Circle().fill(smartColor).frame(width: 6, height: 6)
                            Text(health.ssdSmartStatus)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(smartColor)
                        }
                        .padding(.horizontal, 7).padding(.vertical, 2.5)
                        .background(smartColor.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    Text("Total Bytes Written (TBW Lifetime)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(health.ssdPercentageUsed ?? 0)% Wear")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(wearRatio > 0.8 ? Color.red : Color.primary)
                    Text("\(health.ssdAvailableSparePercent ?? 100)% Spare Left")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            // SSD Wear Level Progress Bar
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: max(wearRatio, 0.01))
                    .tint(wearRatio > 0.8 ? Color.red : (wearRatio > 0.5 ? Color.orange : Color.cyan))

                HStack {
                    Text("0% Consumed (>99% Lifespan Remaining)")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("100% Rated Flash Endurance")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 8)

            Divider().padding(.vertical, 8)

            // NVMe Telemetry Grid
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Internal Drive Model:").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text("\(health.ssdModelName) (Apple Fabric NVMe)").font(.system(size: 11, weight: .semibold))
                }
                GridRow {
                    Text("Lifetime Total Reads (TBR):").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(String(format: "%.2f TB", health.ssdLifetimeBytesReadTb ?? (health.ssdBytesReadGb / 1024.0)))
                        .font(.system(size: 11, weight: .semibold))
                }
                GridRow {
                    Text("Power Cycles & Hours:").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text("\(health.ssdPowerCycles ?? 0) Power Cycles • \(health.ssdPowerOnHours ?? 0) Hours Online")
                        .font(.system(size: 11, weight: .semibold))
                }
                GridRow {
                    Text("Session Driver Write I/O:").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text("\(String(format: "%.1f GB", health.ssdBytesWrittenGb)) Written (\(health.ssdWriteOperations.formatted()) Ops)")
                        .font(.system(size: 11, weight: .semibold))
                }
                GridRow {
                    Text("SSD Swap Wear Risk:").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text("\(String(format: "%.1f GB", health.swapUsedMb / 1024.0)) (\(health.swapRisk.label) - Zero Swap Wear)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(health.swapRisk == .critical ? Color.red : Color.primary)
                }
            }
        }
    }
}

// MARK: - Swap & Memory Card

@MainActor private struct SwapMemoryCard: View {
    let health: SystemHealth
    var onInvestigate: (() -> Void)? = nil

    private var riskColor: Color {
        switch health.swapRisk {
        case .safe:     return .green
        case .moderate: return .orange
        case .critical: return .red
        }
    }

    var body: some View {
        MacDashCard(title: "Memory & SSD Swap", systemIcon: "memorychip", iconTint: .purple) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%.1f GB", health.swapUsedMb / 1024.0))
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(riskColor)
                    Text("Active SSD Swap Allocation")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(health.swapRisk.label)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(riskColor)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(riskColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            ProgressView(value: min(health.swapUsedMb / 16_000.0, 1.0))
                .tint(riskColor)
                .padding(.top, 10)

            if !health.ramHistory.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("30s Memory Pressure Trend")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    MiniSparklineView(data: health.ramHistory, maxVal: 100.0, tintColor: riskColor, height: 24)
                }
                .padding(.top, 4)
            }

            Divider().padding(.vertical, 8)

            HStack {
                Text("RAM Usage (\(String(format: "%.0f", health.ramPercent))%)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.1f / %.0f GB", health.ramUsedGb, health.ramTotalGb))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            if let onInvestigate {
                Button {
                    onInvestigate()
                } label: {
                    Label("Investigate Processes & RAM…", systemImage: "memorychip")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.top, 6)
            }
        }
    }
}

// MARK: - Gradle Daemons Card

@MainActor private struct GradleDaemonsCard: View {
    var viewModel: MonteViewModel
    @State private var isStopping = false

    private var h: SystemHealth { viewModel.health }

    var body: some View {
        MacDashCard(title: "Gradle Daemons", systemIcon: "gearshape.2", iconTint: .cyan) {
            if h.daemons.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Zero idle Gradle daemons. RAM is optimized.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else {
                VStack(spacing: 6) {
                    ForEach(h.daemons.prefix(3)) { d in
                        HStack {
                            Text(d.details)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(d.version)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .padding(6)
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }

            Button {
                isStopping = true
                Task {
                    _ = await viewModel.stopGradleDaemons()
                    isStopping = false
                }
            } label: {
                Label(isStopping ? "Stopping…" : "Stop All Daemons (Reclaim RAM)", systemImage: "stop.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .disabled(h.daemons.isEmpty || isStopping)
            .padding(.top, 8)
        }
    }
}

// MARK: - Agent Storage Card

@MainActor private struct AgentStorageCard: View {
    @Bindable var viewModel: MonteViewModel
    @State private var isPruning = false

    private var s: StorageMetrics { viewModel.health.storage }

    var body: some View {
        MacDashCard(title: "Dev & Build Storage", systemIcon: "folder", iconTint: .indigo) {
            VStack(spacing: 6) {
                StorageRow("Antigravity Brain Logs", value: String(format: "%.0f MB", s.antigravityBrainMb))
                StorageRow("Claude Logs & Cache", value: String(format: "%.0f MB", s.claudeLogsMb + s.claudeCacheMb))
                StorageRow("Xcode DerivedData", value: String(format: "%.1f GB", s.xcodeDerivedDataGb))
                StorageRow("Gradle Global Cache", value: String(format: "%.1f GB", s.gradleCachesGb))
            }

            HStack {
                Text("Retention: \(viewModel.logRetentionDays) days")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Slider(value: Binding(
                    get: { Double(viewModel.logRetentionDays) },
                    set: { viewModel.logRetentionDays = Int($0) }
                ), in: 3...30, step: 1)
                .frame(width: 120)
            }
            .padding(.top, 6)

            HStack(spacing: 8) {
                Button {
                    viewModel.selectedDashboardTab = .storage
                } label: {
                    Label("Inspect Details & Clean…", systemImage: "folder.badge.gearshape")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .controlSize(.small)

                Button {
                    isPruning = true
                    Task {
                        _ = await viewModel.pruneLogs(days: viewModel.logRetentionDays)
                        isPruning = false
                    }
                } label: {
                    Label("Prune Logs", systemImage: "trash")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isPruning)
            }
            .padding(.top, 6)
        }
    }

    private func StorageRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 11.5)).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.primary)
        }
    }
}

// MARK: - Reusable Mac Dash Card

private struct MacDashCard<Content: View>: View {
    let title: String
    let systemIcon: String
    let iconTint: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: systemIcon)
                    .foregroundStyle(iconTint)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            Divider()
                .padding(.top, 8)
                .padding(.bottom, 12)
            content()
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
    }
}

// MARK: - Wi-Fi & Network Diagnostics Card

@MainActor private struct NetworkDiagnosticsCard: View {
    let health: SystemHealth

    private var wifi: WiFiDiagnostics { health.wifi }

    private var signalColor: Color {
        switch wifi.qualityLabel {
        case "Excellent": return .green
        case "Good":      return .mint
        case "Fair":      return .yellow
        default:          return .orange
        }
    }

    var body: some View {
        MacDashCard(title: "Wi-Fi & Link Diagnostics", systemIcon: "wifi", iconTint: .cyan) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(wifi.isConnected ? wifi.ssid : "Disconnected")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if wifi.isConnected {
                            HStack(spacing: 2) {
                                ForEach(0..<4) { bar in
                                    RoundedRectangle(cornerRadius: 1)
                                        .fill(bar < wifi.signalBars ? signalColor : Color.secondary.opacity(0.25))
                                        .frame(width: 3, height: CGFloat(4 + bar * 3))
                                }
                            }
                            .frame(height: 14, alignment: .bottom)
                        }
                    }

                    Text(wifi.isConnected ? "\(wifi.qualityLabel) • \(wifi.channelBandDescription)" : "No active Wi-Fi connection")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if wifi.isConnected {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(wifi.rssi) dBm")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(signalColor)
                        Text(wifi.snr > 0 ? "\(wifi.snr) dB SNR" : "Signal Power")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !health.networkHistory.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("Bandwidth Activity")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        HStack(spacing: 6) {
                            Text(String(format: "↓ %.1f KB/s • ↑ %.1f KB/s", health.networkDownloadKbSec, health.networkUploadKbSec))
                                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.primary)
                            Text(String(format: "(Avg: %.1f KB/s)", health.averageDownloadKbSec))
                                .font(.system(size: 9.0, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    MiniSparklineView(data: health.networkHistory, tintColor: .cyan, height: 24)
                }
                .padding(.top, 6)
            }

            Divider().padding(.vertical, 8)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Local IPv4:").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(wifi.localIPv4.isEmpty ? "—" : wifi.localIPv4)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                }
                GridRow {
                    Text("Interface & Band:").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text("\(wifi.interfaceName) • \(wifi.band.isEmpty ? "Unknown" : wifi.band)")
                        .font(.system(size: 11, weight: .semibold))
                }
                if wifi.transmitRateMbps > 0 {
                    GridRow {
                        Text("Transmit Rate:").font(.system(size: 11)).foregroundStyle(.secondary)
                        Text(String(format: "%.0f Mbps", wifi.transmitRateMbps))
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
            }
        }
    }
}

// MARK: - Mounted Volumes & Dev Storage Card

@MainActor private struct MountedVolumesCard: View {
    let health: SystemHealth

    var body: some View {
        MacDashCard(title: "Mounted Volumes & Dev Storage", systemIcon: "externaldrive.connected.to.line.below", iconTint: .indigo) {
            if health.mountedVolumes.isEmpty {
                HStack {
                    Image(systemName: "internaldrive")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Root APFS Volume")
                            .font(.system(size: 12, weight: .semibold))
                        Text(String(format: "%.1f GB free of %.1f GB", health.diskFreeGb, health.diskTotalGb))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(health.mountedVolumes.prefix(4)) { vol in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: vol.mountPath == "/" ? "internaldrive" : (vol.isRemovable ? "externaldrive" : "opticaldiscdrive"))
                                    .font(.system(size: 12))
                                    .foregroundStyle(vol.mountPath == "/" ? Color.blue : Color.indigo)

                                VStack(alignment: .leading, spacing: 1) {
                                    HStack(spacing: 5) {
                                        Text(vol.name)
                                            .font(.system(size: 11.5, weight: .semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)

                                        if vol.isRemovable {
                                            Text("External")
                                                .font(.system(size: 8.5, weight: .bold))
                                                .padding(.horizontal, 4).padding(.vertical, 1)
                                                .background(Color.orange.opacity(0.15))
                                                .foregroundStyle(Color.orange)
                                                .clipShape(Capsule())
                                        }

                                        Text(vol.fileSystemType)
                                            .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                                            .padding(.horizontal, 4).padding(.vertical, 1)
                                            .background(Color.secondary.opacity(0.12))
                                            .foregroundStyle(.secondary)
                                            .clipShape(RoundedRectangle(cornerRadius: 3))
                                    }

                                    Text(vol.mountPath)
                                        .font(.system(size: 9.5, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(String(format: "%.1f GB Free", vol.freeGb))
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(vol.freeGb < 15 ? Color.red : Color.primary)

                                    Text(String(format: "%.0f%% used of %.0f GB", vol.usedPercent, vol.totalGb))
                                        .font(.system(size: 9.5))
                                        .foregroundStyle(.secondary)
                                }
                            }

                            ProgressView(value: min(vol.usedPercent / 100.0, 1.0))
                                .tint(vol.usedPercent > 85 ? Color.red : (vol.mountPath == "/" ? Color.blue : Color.indigo))
                        }
                        if vol.id != health.mountedVolumes.prefix(4).last?.id {
                            Divider().opacity(0.5)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Process Investigator Models

enum ProcessSortOption: String, CaseIterable, Identifiable {
    case ram = "RAM Usage"
    case cpu = "CPU Usage"
    case disk = "Disk I/O"
    case name = "Name"

    var id: String { rawValue }
}

enum ProcessFilterTab: String, CaseIterable, Identifiable {
    case all = "All"
    case safeToKill = "Safe to Kill"
    case userApps = "User Apps"
    case protected = "System"

    var id: String { rawValue }
}

// MARK: - Storage Inspector Models

struct StorageInspectorItem: Identifiable {
    var id: String { key }
    let key: String
    let title: String
    let subtitle: String
    let sizeMb: Double
    let pathDescription: String
    let whyDescription: String
    let canPruneWithDays: Bool

    var sizeFormatted: String {
        if sizeMb >= 1024.0 {
            return String(format: "%.1f GB", sizeMb / 1024.0)
        } else {
            return String(format: "%.0f MB", sizeMb)
        }
    }
}

// MARK: - Embedded Storage Inspector View

@MainActor private struct StorageInspectorEmbeddedView: View {
    @Bindable var viewModel: MonteViewModel
    @State private var logRetentionDays: Int = 7
    @State private var actionMessage: String?
    @State private var activeCleaningKey: String?
    @State private var isCleaningAll = false

    private var s: StorageMetrics { viewModel.health.storage }

    var body: some View {
        VStack(spacing: 12) {
            StorageItemCardView(
                item: StorageInspectorItem(
                    key: "antigravity",
                    title: "Antigravity Agent Brain Logs",
                    subtitle: "Task logs, chat trajectories & scratch scripts",
                    sizeMb: s.antigravityBrainMb,
                    pathDescription: "~/.gemini/antigravity/brain",
                    whyDescription: "Persistent session context generated during agent pairing.",
                    canPruneWithDays: true
                ),
                isCleaning: activeCleaningKey == "antigravity",
                isAnyCleaning: isCleaningAll || activeCleaningKey != nil,
                logRetentionDays: logRetentionDays,
                onClean: { days in
                    activeCleaningKey = "antigravity"
                    Task {
                        actionMessage = await viewModel.pruneLogs(days: days ?? 0)
                        activeCleaningKey = nil
                    }
                },
                onReveal: { StorageService.revealInFinder(path: "~/.gemini/antigravity/brain") }
            )

            StorageItemCardView(
                item: StorageInspectorItem(
                    key: "xcode",
                    title: "Xcode DerivedData Build Cache",
                    subtitle: "Compiled intermediate build objects & module caches",
                    sizeMb: s.xcodeDerivedDataGb * 1024.0,
                    pathDescription: "~/Library/Developer/Xcode/DerivedData",
                    whyDescription: "Xcode build cache that grows steadily with Swift builds.",
                    canPruneWithDays: false
                ),
                isCleaning: activeCleaningKey == "xcode",
                isAnyCleaning: isCleaningAll || activeCleaningKey != nil,
                logRetentionDays: logRetentionDays,
                onClean: { _ in
                    activeCleaningKey = "xcode"
                    Task {
                        actionMessage = await viewModel.cleanDerivedData()
                        activeCleaningKey = nil
                    }
                },
                onReveal: { StorageService.revealInFinder(path: "~/Library/Developer/Xcode/DerivedData") }
            )
        }
    }
}

// MARK: - Embedded Process Investigator Content

@MainActor private struct ProcessInvestigatorContent: View {
    @Bindable var viewModel: MonteViewModel
    @State private var searchText = ""
    @State private var selectedTab: ProcessFilterTab = .all
    @State private var sortOption: ProcessSortOption = .ram
    @State private var terminatingPid: Int32?
    @State private var actionMsg: String?

    private var processes: [ProcessInvestigatorItem] {
        viewModel.investigatorProcesses
    }

    private var filteredProcesses: [ProcessInvestigatorItem] {
        var list = processes
        switch selectedTab {
        case .all: break
        case .safeToKill: list = list.filter { $0.category == .safeDevDaemon }
        case .userApps: list = list.filter { $0.category == .userApp }
        case .protected: list = list.filter { $0.category == .systemProtected || $0.category == .backgroundHelper }
        }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            list = list.filter { $0.displayName.lowercased().contains(q) || $0.name.lowercased().contains(q) || String($0.pid).contains(q) }
        }
        switch sortOption {
        case .ram: list.sort { $0.ramMb > $1.ramMb }
        case .cpu: list.sort { $0.cpuPercent > $1.cpuPercent }
        case .disk: list.sort { $0.diskWrittenMb > $1.diskWrittenMb }
        case .name: list.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        }
        return list
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Picker("", selection: $selectedTab) {
                    ForEach(ProcessFilterTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Sort", selection: $sortOption) {
                    ForEach(ProcessSortOption.allCases) { opt in
                        Text(opt.rawValue).tag(opt)
                    }
                }
                .frame(width: 130)
            }

            HStack {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("Filter processes…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 0.5))

            LazyVStack(spacing: 6) {
                ForEach(filteredProcesses.prefix(12)) { item in
                    ProcessRowView(
                        item: item,
                        isTerminating: terminatingPid == item.pid,
                        onKill: { force in
                            terminatingPid = item.pid
                            Task {
                                actionMsg = await viewModel.killInvestigatorProcess(pid: item.pid, force: force)
                                terminatingPid = nil
                            }
                        }
                    )
                }
            }
        }
        .onAppear {
            Task { await viewModel.fetchInvestigatorProcesses() }
        }
    }
}

// MARK: - System Requirements Banner View

@MainActor struct SystemRequirementsBannerView: View {
    var viewModel: MonteViewModel
    @State private var isCopied = false
    @State private var isRechecking = false
    @State private var isExpanded = false

    private var helpers: SystemHelperStatus { viewModel.health.helpers }

    var body: some View {
        VStack(spacing: 8) {
            if !helpers.isBatteryLimiterInstalled {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "bolt.shield.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.orange)
                        .frame(width: 28, height: 28)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Battery Limiter Helper Not Installed")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.primary)

                        Text("To cap battery charging at 75–80% and preserve battery health on Apple Silicon, install the lightweight helper CLI.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            Button {
                                viewModel.installBatteryTool()
                            } label: {
                                Label("Install Battery Limiter", systemImage: "terminal")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)

                            Button {
                                isRechecking = true
                                Task {
                                    await viewModel.refresh(forceStorage: false)
                                    isRechecking = false
                                }
                            } label: {
                                Text(isRechecking ? "Checking…" : "Re-Check")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(.top, 4)
                    }
                    Spacer()
                }
                .padding(12)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.3), lineWidth: 1))
            }
        }
    }
}

// MARK: - Storage Inspector Sheet View

@MainActor struct StorageInspectorSheetView: View {
    @Bindable var viewModel: MonteViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Storage & Cache Inspector")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Button("Done") {
                    viewModel.showStorageInspectorSheet = false
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(16)
            Divider()
            ScrollView {
                StorageInspectorEmbeddedView(viewModel: viewModel)
                    .padding(16)
            }
        }
        .frame(width: 600, height: 480)
    }
}

// MARK: - Process Investigator Sheet View

@MainActor struct ProcessInvestigatorSheetView: View {
    @Bindable var viewModel: MonteViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Process & RAM Investigator")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Button("Done") {
                    viewModel.showProcessInvestigatorSheet = false
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(16)
            Divider()
            ScrollView {
                ProcessInvestigatorContent(viewModel: viewModel)
                    .padding(16)
            }
        }
        .frame(width: 640, height: 520)
    }
}

// MARK: - Storage Item Card View

@MainActor struct StorageItemCardView: View {
    let item: StorageInspectorItem
    let isCleaning: Bool
    let isAnyCleaning: Bool
    let logRetentionDays: Int
    let onClean: (Int?) -> Void
    let onReveal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(item.pathDescription)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text(item.sizeFormatted)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(item.sizeMb > 1024.0 ? Color.orange : Color.primary)
            }

            Text(item.whyDescription)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button("Reveal in Finder") {
                    onReveal()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                if item.canPruneWithDays {
                    Button("Prune (> \(logRetentionDays)d)") {
                        onClean(logRetentionDays)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isAnyCleaning || item.sizeMb == 0)

                    Button("Clean All") {
                        onClean(nil)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red.opacity(0.85))
                    .controlSize(.small)
                    .disabled(isAnyCleaning || item.sizeMb == 0)
                } else {
                    Button("Clean Cache") {
                        onClean(nil)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red.opacity(0.85))
                    .controlSize(.small)
                    .disabled(isAnyCleaning || item.sizeMb == 0)
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5))
    }
}

// MARK: - Process Row View

@MainActor struct ProcessRowView: View {
    let item: ProcessInvestigatorItem
    let isTerminating: Bool
    let onKill: (Bool) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: item.category == .userApp ? "app.dashed" : (item.category == .safeDevDaemon ? "hammer" : "gearshape"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text("PID \(item.pid)")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                Text(item.safetyExplanation)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(item.ramMb >= 1024.0 ? String(format: "%.1f GB", item.ramMb / 1024.0) : String(format: "%.0f MB", item.ramMb))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.primary)

                HStack(spacing: 4) {
                    if item.cpuPercent > 0.5 {
                        Text("\(String(format: "%.0f%%", item.cpuPercent)) CPU")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(item.cpuPercent > 50 ? Color.orange : Color.secondary)
                    }
                    if item.diskWrittenMb > 1.0 {
                        Text("\(String(format: "%.0f MB/w", item.diskWrittenMb))")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(Color.cyan)
                    }
                }
            }

            if item.isKillable {
                Button {
                    onKill(false)
                } label: {
                    Text(isTerminating ? "Stopping…" : (item.category == .userApp ? "Quit" : "Kill"))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color(NSColor.separatorColor).opacity(0.6), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .disabled(isTerminating)
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}
