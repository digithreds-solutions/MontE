import SwiftUI
import AppKit

// MARK: - Modern Sleek Glowing Status Dot

@MainActor struct GlowingStatusDot: View {
    let color: Color
    var size: CGFloat = 8.0
    var isPulsating: Bool = true
    @State private var isBreathing: Bool = false

    var body: some View {
        ZStack {
            // Layer 1: Diffuse Ambient Halo Glow (Breathing)
            Circle()
                .fill(color.opacity(isBreathing ? 0.60 : 0.25))
                .frame(width: size + (isBreathing ? 8 : 4), height: size + (isBreathing ? 8 : 4))
                .blur(radius: isBreathing ? 4.5 : 2.0)

            // Layer 2: Intense Corona Flare
            Circle()
                .fill(color.opacity(0.85))
                .frame(width: size + 2.5, height: size + 2.5)
                .blur(radius: 1.2)

            // Layer 3: Solid Luminous Core
            Circle()
                .fill(color)
                .frame(width: size, height: size)

            // Layer 4: Specular LED Lens Highlight
            Circle()
                .fill(Color.white.opacity(0.65))
                .frame(width: size * 0.35, height: size * 0.35)
                .offset(x: -size * 0.16, y: -size * 0.16)
        }
        .frame(width: size + 8, height: size + 8)
        .onAppear {
            if isPulsating {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    isBreathing = true
                }
            }
        }
    }
}

// MARK: - System Settings & Diagnostics Shortcuts

enum SystemShortcut {
    static func openBatterySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openStorageSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Storage-Settings.extension") {
            NSWorkspace.shared.open(url)
        } else if let fallback = URL(string: "x-apple.systempreferences:com.apple.settings.Storage") {
            NSWorkspace.shared.open(fallback)
        }
    }

    static func openNetworkSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openActivityMonitor() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
    }

    static func openSystemInformation() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/System Information.app"))
    }
}

// MARK: - Aerated Menu Statistics Grid View (Top of Overflow Menu)

@MainActor struct MenuStatsGridView: View {
    @Bindable var viewModel: MonteViewModel
    var onRefresh: () -> Void
    var onOpenDashboard: () -> Void
    var onOpenStorageInspector: () -> Void
    var onOpenProcessInvestigator: () -> Void
    var onOpenSettings: (SettingsTab) -> Void = { _ in }

    private var h: SystemHealth { viewModel.health }
    private var hud: HUDSettings { viewModel.settings.hud }

    var body: some View {
        VStack(spacing: 12) {
            // Header: App Title, Sleek Glowing Status Dot, Health Label, and Refresh
            HStack(alignment: .center, spacing: 7) {
                Text("Mont-E")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)

                GlowingStatusDot(color: h.overallHealth.color, size: 8.0)

                Text(h.overallHealth.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    onRefresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Refresh metrics (⌘R)")
            }

            // Keep-Awake Remaining Time Banner (Shown when active)
            if viewModel.keepAwake.isActive {
                HStack(spacing: 7) {
                    Image(systemName: "cup.and.saucer")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Text(viewModel.keepAwake.statusSummary)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)

                    Spacer()

                    Button {
                        viewModel.keepAwake.stop(reason: "Keep-Awake disabled manually.", manual: true)
                    } label: {
                        Text("Stop")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(NSColor.controlBackgroundColor))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }

            // Bluetooth Connected Peripherals Cockpit
            if hud.showBluetooth && !h.bluetoothDevices.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(h.bluetoothDevices.prefix(3)) { dev in
                        HStack(spacing: 6) {
                            Image(systemName: dev.category.sfSymbol)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .frame(width: 14)

                            Text(dev.name)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Spacer()

                            Text(dev.primaryBatteryDisplay)
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(
                                    (dev.batteryPercent ?? 100) <= 20
                                        ? Color.red.opacity(0.18)
                                        : Color.green.opacity(0.15)
                                )
                                .foregroundStyle(
                                    (dev.batteryPercent ?? 100) <= 20
                                        ? Color.red
                                        : Color.green
                                )
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Aerated Tiles Layout: Grid vs Compact List
            if hud.layoutMode == .compactList {
                VStack(spacing: 8) {
                    renderedTiles
                }
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    renderedTiles
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 16) // Exact 16pt bottom padding to divider
        .frame(width: hud.layoutMode == .compactList ? 270 : 310)
    }

    private var batteryDotColor: Color {
        if h.isCharging {
            return Color.green
        } else if h.isAcPower {
            return Color.blue
        } else if h.batteryPercent <= 20 {
            return Color.red
        } else if h.batteryPercent <= 40 {
            return Color.orange
        } else {
            return Color.green
        }
    }

    private var batteryStateColor: Color {
        if h.isCharging {
            return Color.green
        } else if h.isAcPower {
            return Color.blue
        } else if h.batteryPercent <= 20 {
            return Color.red
        } else if h.batteryPercent <= 40 {
            return Color.orange
        } else {
            return Color.secondary.opacity(0.8)
        }
    }

    private var batteryStateText: String {
        if h.isCharging {
            if let cap = h.batteryLimit, cap < 100 {
                return "Charging (\(cap)% Cap)"
            }
            return "Charging"
        } else if h.isAcPower {
            if let cap = h.batteryLimit, cap < 100 {
                return "Pass-Through (\(cap)%)"
            }
            return "AC Pass-Through"
        } else if h.batteryPercent <= 20 {
            return "Low Battery / Saver"
        } else {
            return "On Battery"
        }
    }

    @ViewBuilder
    private var renderedTiles: some View {
        // 1. CPU Load (Clickable to open Process Investigator)
        if hud.showCPU {
            Button {
                onOpenProcessInvestigator()
            } label: {
                StatGridCell(
                    symbolName: "cpu",
                    title: "CPU",
                    value: "\(String(format: "%.0f", h.cpuUsagePercent))%",
                    detail: (hud.showCoreGrid && h.processorCores.totalCoreCount > 0)
                        ? "\(String(format: "%.0f", h.processorCores.pCoreAveragePercent))% P • \(String(format: "%.0f", h.processorCores.eCoreAveragePercent))% E"
                        : h.thermalStatus.description
                )
            }
            .buttonStyle(.plain)
            .help("Click to inspect processes by CPU & RAM (⌘P)")
            .contextMenu {
                Button("Inspect Processes (⌘P)") { onOpenProcessInvestigator() }
                Button("Launch Activity Monitor (CPU)...") { SystemShortcut.openActivityMonitor() }
                Button("Open Dashboard...") { onOpenDashboard() }
            }
        }

        // 1b. GPU Load (Clickable to open Dashboard)
        if hud.showGPU && h.gpu.isAvailable {
            Button {
                onOpenDashboard()
            } label: {
                StatGridCell(
                    symbolName: "display",
                    title: "GPU Load",
                    value: "\(String(format: "%.0f", h.gpu.deviceUtilizationPercent))%",
                    detail: "\(String(format: "%.1f", h.gpu.inUseMemoryMb / 1024.0)) GB VRAM"
                )
            }
            .buttonStyle(.plain)
            .help("Click to view GPU & Graphics status")
            .contextMenu {
                Button("Open Dashboard...") { onOpenDashboard() }
                Button("Launch Activity Monitor (GPU)...") { SystemShortcut.openActivityMonitor() }
            }
        }

        // 2. RAM Memory (Clickable to open Process Investigator)
        if hud.showMemory {
            Button {
                onOpenProcessInvestigator()
            } label: {
                StatGridCell(
                    symbolName: "memorychip",
                    title: "Memory",
                    value: "\(String(format: "%.1f", h.ramUsedGb)) GB",
                    detail: "\(String(format: "%.0f", h.ramPercent))% used"
                )
            }
            .buttonStyle(.plain)
            .help("Click to inspect memory usage & terminate safe daemons (⌘P)")
            .contextMenu {
                Button("Inspect Memory & RAM (⌘P)") { onOpenProcessInvestigator() }
                Button("Launch Activity Monitor (Memory)...") { SystemShortcut.openActivityMonitor() }
                Divider()
                Button("Clean Memory & Inactive Caches") {
                    Task { _ = await viewModel.optimizeMemory() }
                }
            }
        }

        // 3. SSD Swap (Clickable to inspect memory & swap)
        if hud.showSwap {
            Button {
                onOpenProcessInvestigator()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "internaldrive")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("SSD Swap")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 4) {
                            Text("\(String(format: "%.1f", h.swapUsedMb / 1024.0)) GB")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.primary)

                            SwapMicroBar(ratio: min(h.swapUsedMb / 6144.0, 1.0), risk: h.swapRisk)
                        }
                        Text(h.swapRisk.label)
                            .font(.system(size: 9))
                            .foregroundStyle(h.swapRisk == .critical ? Color.red : (h.swapRisk == .moderate ? Color.orange : Color.secondary.opacity(0.7)))
                    }
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 52, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .help("Click to inspect SSD swap usage and heavy processes (⌘P)")
            .contextMenu {
                Button("Inspect Swap in Process Investigator (⌘P)") { onOpenProcessInvestigator() }
                Button("Launch Activity Monitor (Memory)...") { SystemShortcut.openActivityMonitor() }
                Button("Open macOS Storage Settings...") { SystemShortcut.openStorageSettings() }
            }
        }

        // 4. Battery & Power with Glowing 8dp Status Dot (3-line layout)
        if hud.showBattery {
            Button {
                SystemShortcut.openBatterySettings()
            } label: {
                HStack(spacing: 8) {
                    GlowingStatusDot(color: batteryDotColor, size: 8.0)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Battery")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)

                        Text("\(h.batteryPercent)%")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)

                        Text(batteryStateText)
                            .font(.system(size: 9))
                            .foregroundStyle(batteryStateColor)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 52, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .help("Click to open macOS Battery Settings")
            .contextMenu {
                Button("Open macOS Battery Settings...") { SystemShortcut.openBatterySettings() }
                Button("Open System Information (Power)...") { SystemShortcut.openSystemInformation() }
                Divider()
                Button(viewModel.health.isBatteryLimiterInstalled ? "Configure Battery Limiter..." : "Setup Battery Limiter...") {
                    onOpenSettings(.battery)
                }
            }
        }

        // 5. APFS Free Disk Space (Clickable to open Storage Inspector)
        if hud.showDiskSpace {
            Button {
                onOpenStorageInspector()
            } label: {
                StatGridCell(
                    symbolName: "internaldrive.fill",
                    title: "APFS Storage",
                    value: "\(String(format: "%.0f", h.diskFreeGb)) GB Free",
                    detail: "\(String(format: "%.0f", h.diskUsedPercent))% of \(Int(h.diskTotalGb))G"
                )
            }
            .buttonStyle(.plain)
            .help("Click to inspect disk storage, cache & build logs")
            .contextMenu {
                Button("Inspect App & Build Caches...") { onOpenStorageInspector() }
                Button("Open macOS Storage Settings...") { SystemShortcut.openStorageSettings() }
            }
        }

        // 6. Top RAM Process (Clickable to open Process Investigator)
        if hud.showTopProcess {
            Button {
                onOpenProcessInvestigator()
            } label: {
                StatGridCell(
                    symbolName: "app.dashed",
                    title: "Top RAM App",
                    value: h.topProcessName.count > 10 ? String(h.topProcessName.prefix(9)) + "…" : h.topProcessName,
                    detail: "\(String(format: "%.0f", h.topProcessRamMb)) MB Resident"
                )
            }
            .buttonStyle(.plain)
            .help("Click to inspect and terminate processes (⌘P)")
            .contextMenu {
                Button("Inspect in Process Investigator (⌘P)") { onOpenProcessInvestigator() }
                Button("Launch Activity Monitor...") { SystemShortcut.openActivityMonitor() }
            }
        }

        // 7. Battery Cycles & Health (Clickable to open Battery Settings / Diagnostics)
        if hud.showBatteryHealth {
            Button {
                onOpenDashboard()
                viewModel.selectedDashboardTab = .battery
            } label: {
                StatGridCell(
                    symbolName: "heart.text.square",
                    title: "Battery Health",
                    value: h.batteryCycles.map { "\($0) Cycles" } ?? "Normal",
                    detail: "\(h.batteryHealthPercent ?? 100)% • \(h.batteryCondition ?? "Normal")"
                )
            }
            .buttonStyle(.plain)
            .help("Click to inspect battery health, capacity & cycle count in Dashboard")
            .contextMenu {
                Button("Open Dashboard Battery Tab") {
                    onOpenDashboard()
                    viewModel.selectedDashboardTab = .battery
                }
                Button("Open macOS Battery Settings...") { SystemShortcut.openBatterySettings() }
                Button("Open System Information (Power)...") { SystemShortcut.openSystemInformation() }
                Divider()
                Button("Copy Battery Diagnostics") {
                    NSPasteboard.general.clearContents()
                    let cycles = h.batteryCycles.map(String.init) ?? "N/A"
                    let health = "\(h.batteryHealthPercent ?? 100)%"
                    let cond = h.batteryCondition ?? "Normal"
                    let pct = "\(h.batteryPercent)%"
                    let powerSource = h.isAcPower ? "AC Power" : "Battery"
                    let temp = h.batteryTemperatureCelsius.map { String(format: "%.1f°C", $0) } ?? "N/A"
                    NSPasteboard.general.setString("Battery: \(pct) (\(powerSource)), Health: \(health), Cycles: \(cycles), Temp: \(temp), Condition: \(cond)", forType: .string)
                }
            }
        }

        // 8. SSD Write Cycles & SMART Health (Clickable to open Dashboard Memory/SSD tab)
        if hud.showSsdHealth {
            Button {
                onOpenDashboard()
                viewModel.selectedDashboardTab = .memory
            } label: {
                StatGridCell(
                    symbolName: "internaldrive.badge.checkmark",
                    title: "SSD Health",
                    value: String(format: "%.1f TB TBW", h.ssdLifetimeBytesWrittenTb ?? (h.ssdBytesWrittenGb / 1024.0)),
                    detail: "\(h.ssdPercentageUsed ?? 0)% Wear • \(h.ssdSmartStatus)"
                )
            }
            .buttonStyle(.plain)
            .help("Click to inspect SSD write cycles, TBW wear and SMART health")
            .contextMenu {
                Button("Open Dashboard Memory & SSD Tab") {
                    onOpenDashboard()
                    viewModel.selectedDashboardTab = .memory
                }
                Button("Open macOS Storage Settings...") { SystemShortcut.openStorageSettings() }
                Divider()
                Button("Copy SSD Diagnostics") {
                    NSPasteboard.general.clearContents()
                    let tbw = String(format: "%.2f TB", h.ssdLifetimeBytesWrittenTb ?? (h.ssdBytesWrittenGb / 1024.0))
                    let tbr = String(format: "%.2f TB", h.ssdLifetimeBytesReadTb ?? (h.ssdBytesReadGb / 1024.0))
                    let wear = "\(h.ssdPercentageUsed ?? 0)% used"
                    let smart = h.ssdSmartStatus
                    let model = h.ssdModelName
                    NSPasteboard.general.setString("SSD: \(model), SMART: \(smart), TBW: \(tbw), TBR: \(tbr), Wear: \(wear)", forType: .string)
                }
            }
        }

        // 8. Network I/O Bandwidth (Clickable to open Network Settings)
        if hud.showNetworkIO {
            Button {
                SystemShortcut.openNetworkSettings()
            } label: {
                StatGridCell(
                    symbolName: "network",
                    title: "Network I/O",
                    value: "↓ \(formatBandwidth(h.networkDownloadKbSec))",
                    detail: "↑ \(formatBandwidth(h.networkUploadKbSec))"
                )
            }
            .buttonStyle(.plain)
            .help("Click to open macOS Network Settings")
            .contextMenu {
                Button("Open macOS Network Settings...") { SystemShortcut.openNetworkSettings() }
                Button("Launch Activity Monitor (Network)...") { SystemShortcut.openActivityMonitor() }
            }
        }

        // 8b. Cooling & Fans
        if hud.showFans {
            Button {
                onOpenDashboard()
                viewModel.selectedDashboardTab = .cpu
            } label: {
                StatGridCell(
                    symbolName: "fanblades",
                    title: "Cooling & Fans",
                    value: h.fans.first?.displaySpeed ?? "Silent",
                    detail: h.fans.count > 1 ? "\(h.fans[1].displaySpeed)" : h.thermalStatus.description
                )
            }
            .buttonStyle(.plain)
            .help("Click to view Fan RPM & Cooling status in Dashboard")
        }

        // 8c. Wi-Fi & Link Diagnostics
        if hud.showWiFi && h.wifi.isConnected {
            Button {
                onOpenDashboard()
                viewModel.selectedDashboardTab = .overview
            } label: {
                StatGridCell(
                    symbolName: "wifi",
                    title: "Wi-Fi Link",
                    value: "\(h.wifi.rssi) dBm",
                    detail: "\(h.wifi.ssid)"
                )
            }
            .buttonStyle(.plain)
            .help("Wi-Fi: \(h.wifi.ssid) • \(h.wifi.rssi) dBm (\(h.wifi.qualityLabel)) on \(h.wifi.interfaceName)")
            .contextMenu {
                Button("Open macOS Network Settings...") { SystemShortcut.openNetworkSettings() }
                Button("Open Dashboard...") { onOpenDashboard() }
            }
        }

        // 8d. Mounted External Volumes
        if hud.showMountedVolumes && !h.mountedVolumes.isEmpty {
            let extVol = h.mountedVolumes.first(where: { $0.isRemovable }) ?? h.mountedVolumes.first!
            Button {
                onOpenDashboard()
                viewModel.selectedDashboardTab = .overview
            } label: {
                StatGridCell(
                    symbolName: extVol.isRemovable ? "externaldrive" : "internaldrive",
                    title: extVol.name,
                    value: String(format: "%.0fG Free", extVol.freeGb),
                    detail: "\(String(format: "%.0f%%", extVol.usedPercent)) used"
                )
            }
            .buttonStyle(.plain)
            .help("Volume: \(extVol.name) at \(extVol.mountPath)")
            .contextMenu {
                Button("Open macOS Storage Settings...") { SystemShortcut.openStorageSettings() }
                Button("Open Dashboard...") { onOpenDashboard() }
            }
        }

        // 9. Xcode DerivedData Cache (Clickable to open storage inspector)
        if hud.showXcodeDerivedData {
            Button {
                onOpenStorageInspector()
            } label: {
                StatGridCell(
                    symbolName: "hammer.fill",
                    title: "DerivedData",
                    value: "\(String(format: "%.1f", h.storage.xcodeDerivedDataGb)) GB",
                    detail: "Clean cache"
                )
            }
            .buttonStyle(.plain)
            .help("Click to clean Xcode DerivedData cache")
            .contextMenu {
                Button("Inspect & Clean DerivedData...") { onOpenStorageInspector() }
                Button("Reveal DerivedData in Finder") {
                    let path = NSString(string: "~/Library/Developer/Xcode/DerivedData").expandingTildeInPath
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
                }
            }
        }

        // 10. Gradle Daemons (Only shown if configured by developer)
        if viewModel.settings.monitorGradle && hud.showGradle {
            HStack(spacing: 8) {
                Image(systemName: "hammer")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Gradle")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)

                        Spacer()

                        if hud.showQuickKillButtons && !h.daemons.isEmpty {
                            Button {
                                Task {
                                    _ = await viewModel.stopGradleDaemons()
                                }
                            } label: {
                                Text("Kill")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(Color(NSColor.controlBackgroundColor))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .help("Stop idle Gradle daemons")
                        }
                    }

                    Text("\(h.daemons.count) Daemon\(h.daemons.count == 1 ? "" : "s")")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(h.daemons.isEmpty ? "Optimized" : "Idle background")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 52, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contextMenu {
                Button("Stop Idle Gradle Daemons") {
                    Task { _ = await viewModel.stopGradleDaemons() }
                }
                Button("Inspect in Process Investigator (⌘P)") { onOpenProcessInvestigator() }
            }
        }

        // 11. Build Logs & Agent Storage (Clickable to open deep inspector)
        if hud.showAgentStorage {
            Button {
                onOpenStorageInspector()
            } label: {
                StatGridCell(
                    symbolName: "folder.badge.gearshape",
                    title: "Agent Storage",
                    value: "\(String(format: "%.0f", h.storage.antigravityBrainMb + h.storage.claudeLogsMb)) MB",
                    detail: "Inspect & clean"
                )
            }
            .buttonStyle(.plain)
            .help("Click to inspect and clean AI Agent brain logs & build caches")
            .contextMenu {
                Button("Inspect Agent Storage & Logs...") { onOpenStorageInspector() }
                Button("Open macOS Storage Settings...") { SystemShortcut.openStorageSettings() }
            }
        }
    }

    private func formatBandwidth(_ kbSec: Double) -> String {
        if kbSec >= 1024.0 {
            return String(format: "%.1f MB/s", kbSec / 1024.0)
        } else {
            return String(format: "%.0f KB/s", kbSec)
        }
    }
}

// MARK: - Reusable Clean Monochrome Stat Cell (Consistent 52pt Height)

@MainActor private struct StatGridCell: View {
    let symbolName: String
    let title: String
    let value: String
    let detail: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbolName)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.secondary.opacity(0.7))
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 52, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Small Vertical Swap Level Bar

@MainActor struct SwapMicroBar: View {
    let ratio: Double
    let risk: SwapRiskLevel

    private var barColor: Color {
        switch risk {
        case .safe:     return Color.secondary.opacity(0.6)
        case .moderate: return Color.orange
        case .critical: return Color.red
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 3.5, height: 12)

            RoundedRectangle(cornerRadius: 1.5)
                .fill(barColor)
                .frame(width: 3.5, height: max(12 * CGFloat(ratio), 2.5))
        }
    }
}
