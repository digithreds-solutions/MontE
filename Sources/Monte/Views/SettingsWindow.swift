import SwiftUI
import AppKit

// MARK: - Dedicated Native macOS Settings Window Controller

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private var viewModel: MonteViewModel

    init(viewModel: MonteViewModel) {
        self.viewModel = viewModel
        let settingsView = SettingsWindowView(viewModel: viewModel)
        let hosting = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: hosting)
        
        window.title = "Settings"
        window.setContentSize(NSSize(width: 760, height: 560))
        window.minSize = NSSize(width: 720, height: 500)
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.tabbingMode = .disallowed
        window.center()
        
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("Use init(viewModel:)") }

    func showSettings(tab: SettingsTab = .general) {
        viewModel.selectedSettingsTab = tab
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}

// MARK: - Reusable macOS Preference Form Row Components

struct SettingsSectionRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(label)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 175, alignment: .trailing)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

@MainActor struct SettingsSubHint: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 5) {
            Text("└")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 2)
    }
}

// MARK: - Root Settings View (Classic macOS Preferences Toolbar & Form Layout)

@MainActor struct SettingsWindowView: View {
    @Bindable var viewModel: MonteViewModel
    @State private var memoryOptResult: String?
    @State private var isFreeingRam = false
    @State private var showHelpPopover = false
    @State private var statusToast: String?

    var body: some View {
        VStack(spacing: 0) {
            // ── Top Preferences Toolbar ──────────────────────────────────────────
            VStack(spacing: 6) {
                // Window Title
                Text("Settings")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.top, 10)

                // Horizontal Icon Tab Bar
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(SettingsTab.allCases) { tab in
                            SettingsToolbarTabButton(
                                tab: tab,
                                isSelected: viewModel.selectedSettingsTab == tab,
                                onSelect: {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        viewModel.selectedSettingsTab = tab
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

            // ── Main Content Form Area ──────────────────────────────────────────
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch viewModel.selectedSettingsTab {
                        case .general:
                            GeneralSettingsTab(viewModel: viewModel, onResetAll: {
                                viewModel.settings = .default
                                statusToast = "All settings reset to default values."
                            })
                        case .keepAwake:
                            KeepAwakeSettingsTab(viewModel: viewModel)
                        case .battery:
                            BatterySettingsTab(viewModel: viewModel)
                        case .menuBarHud:
                            MenuBarHudSettingsTab(viewModel: viewModel)
                        case .devTools:
                            DevToolsSettingsTab(
                                viewModel: viewModel,
                                memoryOptResult: $memoryOptResult,
                                isFreeingRam: $isFreeingRam
                            )
                        case .about:
                            AboutSettingsTab(viewModel: viewModel)
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 24)
                    .padding(.bottom, 50)
                }

                // Bottom Bar: Help Button & Toast
                HStack(spacing: 12) {
                    if let toast = statusToast {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.green)
                            Text(toast)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.primary)
                            Button { statusToast = nil } label: { Image(systemName: "xmark") }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color(NSColor.separatorColor), lineWidth: 0.5))
                    }

                    Spacer()

                    Button {
                        showHelpPopover.toggle()
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Help & Information about \(viewModel.selectedSettingsTab.rawValue)")
                    .popover(isPresented: $showHelpPopover) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(viewModel.selectedSettingsTab.rawValue)
                                .font(.system(size: 13, weight: .bold))
                            Text(tabHelpText(for: viewModel.selectedSettingsTab))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .frame(width: 260, alignment: .leading)
                        }
                        .padding(14)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 14)
            }
        }
        .frame(minWidth: 720, minHeight: 520)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func tabHelpText(for tab: SettingsTab) -> String {
        switch tab {
        case .general:
            return "Configure startup behavior, auto-start on macOS login, and system helper utilities."
        case .keepAwake:
            return "Configure sleep prevention, session durations, display policies, dev build triggers (Gradle, Python, etc.), and hardware safety."
        case .battery:
            return "Configure Apple Silicon SMC charge limits (e.g. 80%), Direct AC Pass-Through, and auto-discharge."
        case .menuBarHud:
            return "Customize the menu bar tray metrics combination and choose which cards display in the dropdown HUD."
        case .devTools:
            return "1-click RAM cache cleaner, Gradle daemon terminator, and AI agent log storage retention."
        case .about:
            return "Native Swift 6 / Apple Silicon system architecture specifications and version information."
        }
    }
}

// MARK: - Toolbar Tab Button (Icon on top, label below, rounded highlight when active)

@MainActor private struct SettingsToolbarTabButton: View {
    let tab: SettingsTab
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

// MARK: - Enabled Keep-Awake Rules & Triggers Model & Section

struct ActiveKeepAwakeItem: Identifiable {
    let id: String
    let title: String
    let category: String
    let icon: String
    let iconColor: Color
    let detail: String
    let turnOff: () -> Void
}

@MainActor struct EnabledKeepAwakeSection: View {
    @Bindable var viewModel: MonteViewModel
    var showGoToKeepAwakeButton: Bool = true
    @State private var toastMessage: String? = nil

    private var awake: KeepAwakeService { viewModel.keepAwake }

    private var activeItems: [ActiveKeepAwakeItem] {
        var items: [ActiveKeepAwakeItem] = []

        // 1. Live Session (if active)
        if awake.isActive {
            items.append(ActiveKeepAwakeItem(
                id: "live_session",
                title: "Active Session: \(awake.activeMode.displayName)",
                category: "Live Session",
                icon: "cup.and.saucer.fill",
                iconColor: .orange,
                detail: awake.statusSummary,
                turnOff: {
                    awake.stop(reason: "Stopped from Settings", manual: true)
                }
            ))
        }

        // 2. Developer Build Triggers
        if awake.config.autoAwakeOnGradle {
            items.append(ActiveKeepAwakeItem(
                id: "autoAwakeOnGradle",
                title: "Gradle Daemon Trigger",
                category: "Build Trigger",
                icon: "hammer.fill",
                iconColor: .orange,
                detail: "Keeps Mac awake while Gradle builds or background daemons run",
                turnOff: {
                    awake.config.autoAwakeOnGradle = false
                    awake.applyConfigChanges()
                }
            ))
        }
        if awake.config.autoAwakeOnPython {
            items.append(ActiveKeepAwakeItem(
                id: "autoAwakeOnPython",
                title: "Python Script Trigger",
                category: "Build Trigger",
                icon: "chevron.left.forwardslash.chevron.right",
                iconColor: .yellow,
                detail: "Keeps Mac awake while python, pytest, or uv scripts execute",
                turnOff: {
                    awake.config.autoAwakeOnPython = false
                    awake.applyConfigChanges()
                }
            ))
        }
        if awake.config.autoAwakeOnXcode {
            items.append(ActiveKeepAwakeItem(
                id: "autoAwakeOnXcode",
                title: "Xcode / Swift Trigger",
                category: "Build Trigger",
                icon: "hammer.circle.fill",
                iconColor: .blue,
                detail: "Keeps Mac awake while xcodebuild or swift compiles",
                turnOff: {
                    awake.config.autoAwakeOnXcode = false
                    awake.applyConfigChanges()
                }
            ))
        }
        if awake.config.autoAwakeOnNode {
            items.append(ActiveKeepAwakeItem(
                id: "autoAwakeOnNode",
                title: "Node.js Build Trigger",
                category: "Build Trigger",
                icon: "globe",
                iconColor: .green,
                detail: "Keeps Mac awake while npm, vite, or webpack run",
                turnOff: {
                    awake.config.autoAwakeOnNode = false
                    awake.applyConfigChanges()
                }
            ))
        }
        if awake.config.autoAwakeOnCargo {
            items.append(ActiveKeepAwakeItem(
                id: "autoAwakeOnCargo",
                title: "Cargo / Rust Trigger",
                category: "Build Trigger",
                icon: "gearshape.2.fill",
                iconColor: .orange,
                detail: "Keeps Mac awake while cargo or rustc compiles",
                turnOff: {
                    awake.config.autoAwakeOnCargo = false
                    awake.applyConfigChanges()
                }
            ))
        }
        if awake.config.autoAwakeOnDocker {
            items.append(ActiveKeepAwakeItem(
                id: "autoAwakeOnDocker",
                title: "Docker Engine Trigger",
                category: "Build Trigger",
                icon: "shippingbox.fill",
                iconColor: .cyan,
                detail: "Keeps Mac awake while Docker daemon or containers run",
                turnOff: {
                    awake.config.autoAwakeOnDocker = false
                    awake.applyConfigChanges()
                }
            ))
        }
        if awake.config.autoAwakeOnMake {
            items.append(ActiveKeepAwakeItem(
                id: "autoAwakeOnMake",
                title: "Make / CMake Trigger",
                category: "Build Trigger",
                icon: "wrench.and.screwdriver.fill",
                iconColor: .purple,
                detail: "Keeps Mac awake while make or cmake compiles",
                turnOff: {
                    awake.config.autoAwakeOnMake = false
                    awake.applyConfigChanges()
                }
            ))
        }

        // 3. Hardware & Environmental Triggers
        if awake.config.autoAwakeOnACPower {
            items.append(ActiveKeepAwakeItem(
                id: "autoAwakeOnACPower",
                title: "AC Power Auto-Awake",
                category: "Hardware Trigger",
                icon: "bolt.fill",
                iconColor: .green,
                detail: "Auto-starts keep-awake whenever connected to power adapter",
                turnOff: {
                    awake.config.autoAwakeOnACPower = false
                    awake.applyConfigChanges()
                }
            ))
        }
        if awake.config.autoAwakeOnExternalDisplay {
            items.append(ActiveKeepAwakeItem(
                id: "autoAwakeOnExternalDisplay",
                title: "External Display Trigger",
                category: "Hardware Trigger",
                icon: "display",
                iconColor: .blue,
                detail: "Auto-starts keep-awake whenever external monitor is attached",
                turnOff: {
                    awake.config.autoAwakeOnExternalDisplay = false
                    awake.applyConfigChanges()
                }
            ))
        }
        if awake.config.autoAwakeOnWiFi {
            let ssid = awake.config.targetWiFiSSID.isEmpty ? "Configured Network" : awake.config.targetWiFiSSID
            items.append(ActiveKeepAwakeItem(
                id: "autoAwakeOnWiFi",
                title: "Wi-Fi Trigger (\(ssid))",
                category: "Network Trigger",
                icon: "wifi",
                iconColor: .teal,
                detail: "Auto-starts keep-awake when connected to \(ssid)",
                turnOff: {
                    awake.config.autoAwakeOnWiFi = false
                    awake.applyConfigChanges()
                }
            ))
        }
        if awake.config.autoAwakeOnAudio {
            items.append(ActiveKeepAwakeItem(
                id: "autoAwakeOnAudio",
                title: "Audio Playback Trigger",
                category: "System Trigger",
                icon: "speaker.wave.2.fill",
                iconColor: .indigo,
                detail: "Keeps Mac awake while system audio is actively playing",
                turnOff: {
                    awake.config.autoAwakeOnAudio = false
                    awake.applyConfigChanges()
                }
            ))
        }
        if awake.config.autoAwakeOnDownload {
            items.append(ActiveKeepAwakeItem(
                id: "autoAwakeOnDownload",
                title: "Network Download Trigger",
                category: "Network Trigger",
                icon: "arrow.down.circle.fill",
                iconColor: .blue,
                detail: "Keeps Mac awake while download > \(Int(awake.config.downloadThresholdKbSec)) KB/s",
                turnOff: {
                    awake.config.autoAwakeOnDownload = false
                    awake.applyConfigChanges()
                }
            ))
        }
        if awake.config.autoAwakeOnSchedule {
            let start = String(format: "%02d:%02d", awake.config.scheduleStartHour, awake.config.scheduleStartMinute)
            let end = String(format: "%02d:%02d", awake.config.scheduleEndHour, awake.config.scheduleEndMinute)
            items.append(ActiveKeepAwakeItem(
                id: "autoAwakeOnSchedule",
                title: "Scheduled Hours Trigger",
                category: "Schedule Trigger",
                icon: "calendar.badge.clock",
                iconColor: .orange,
                detail: "Auto-starts session during scheduled hours (\(start) – \(end))",
                turnOff: {
                    awake.config.autoAwakeOnSchedule = false
                    awake.applyConfigChanges()
                }
            ))
        }
        if awake.config.autoAwakeOnWatchedApps {
            items.append(ActiveKeepAwakeItem(
                id: "autoAwakeOnWatchedApps",
                title: "Watched Applications Trigger",
                category: "App Trigger",
                icon: "app.badge.checkmark",
                iconColor: .purple,
                detail: "Auto-starts session while configured developer applications run",
                turnOff: {
                    awake.config.autoAwakeOnWatchedApps = false
                    awake.applyConfigChanges()
                }
            ))
        }

        // 4. Sleep & Display Assertions
        if awake.config.preventDisplaySleep {
            items.append(ActiveKeepAwakeItem(
                id: "preventDisplaySleep",
                title: "Prevent Display Sleep",
                category: "Display Setting",
                icon: "display",
                iconColor: .orange,
                detail: "Prevents screen from turning off or dimming during sessions",
                turnOff: {
                    awake.config.preventDisplaySleep = false
                    awake.applyConfigChanges()
                }
            ))
        }
        if awake.config.dimDisplayWhileAwake {
            items.append(ActiveKeepAwakeItem(
                id: "dimDisplayWhileAwake",
                title: "Dim Display While Awake",
                category: "Display Setting",
                icon: "sun.min.fill",
                iconColor: .secondary,
                detail: "Allows display to dim to save energy while CPU is kept awake",
                turnOff: {
                    awake.config.dimDisplayWhileAwake = false
                    awake.applyConfigChanges()
                }
            ))
        }
        if awake.config.preventDiskSleep {
            items.append(ActiveKeepAwakeItem(
                id: "preventDiskSleep",
                title: "Prevent Idle Disk Sleep",
                category: "Hardware Setting",
                icon: "internaldrive",
                iconColor: .teal,
                detail: "Prevents external storage drives and APFS disks from idle spindown",
                turnOff: {
                    awake.config.preventDiskSleep = false
                    awake.applyConfigChanges()
                }
            ))
        }
        if awake.config.allowScreenSaver {
            items.append(ActiveKeepAwakeItem(
                id: "allowScreenSaver",
                title: "Allow Screen Saver",
                category: "Display Setting",
                icon: "sparkles",
                iconColor: .purple,
                detail: "Allows macOS screensaver while keeping system awake",
                turnOff: {
                    awake.config.allowScreenSaver = false
                    awake.applyConfigChanges()
                }
            ))
        }
        if awake.config.lockScreenOnSessionEnd {
            items.append(ActiveKeepAwakeItem(
                id: "lockScreenOnSessionEnd",
                title: "Lock Screen on Session End",
                category: "Security Setting",
                icon: "lock.fill",
                iconColor: .red,
                detail: "Locks macOS screen immediately when session concludes",
                turnOff: {
                    awake.config.lockScreenOnSessionEnd = false
                    awake.applyConfigChanges()
                }
            ))
        }

        // 5. Hardware Safety & Policies
        if awake.config.onlyOnACPower {
            items.append(ActiveKeepAwakeItem(
                id: "onlyOnACPower",
                title: "AC-Power Only Policy",
                category: "Power Policy",
                icon: "bolt.badge.clock.fill",
                iconColor: .green,
                detail: "Immediately stops keep-awake when operating on battery",
                turnOff: {
                    awake.config.onlyOnACPower = false
                    awake.applyConfigChanges()
                }
            ))
        }
        if awake.config.stopOnOverheating {
            items.append(ActiveKeepAwakeItem(
                id: "stopOnOverheating",
                title: "Thermal Safety Guard",
                category: "Hardware Safety",
                icon: "flame.fill",
                iconColor: .red,
                detail: "Stops keep-awake session if thermal state reaches Critical/Serious",
                turnOff: {
                    awake.config.stopOnOverheating = false
                    awake.applyConfigChanges()
                }
            ))
        }
        if awake.config.stopOnHighBatteryTemperature {
            items.append(ActiveKeepAwakeItem(
                id: "stopOnHighBatteryTemperature",
                title: "Battery Overheat Guard",
                category: "Hardware Safety",
                icon: "thermometer.sun.fill",
                iconColor: .red,
                detail: "Stops keep-awake session if battery temp exceeds \(Int(awake.config.maxBatteryTemperatureCelsius))°C",
                turnOff: {
                    awake.config.stopOnHighBatteryTemperature = false
                    awake.applyConfigChanges()
                }
            ))
        }

        return items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "bolt.badge.automatic")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.orange)

                Text("Enabled Keep-Awake Triggers & Settings")
                    .font(.system(size: 13, weight: .bold))

                Spacer()

                if !activeItems.isEmpty {
                    Text("\(activeItems.count) Enabled")
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.orange.opacity(0.12))
                        .foregroundStyle(Color.orange)
                        .clipShape(Capsule())
                }

                if showGoToKeepAwakeButton {
                    Button {
                        viewModel.selectedSettingsTab = .keepAwake
                    } label: {
                        HStack(spacing: 3) {
                            Text("Configure All")
                            Image(systemName: "chevron.right")
                        }
                        .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.link)
                }
            }

            if let msg = toastMessage {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.green)
                    Text(msg)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.green.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            if activeItems.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No Keep-Awake Triggers or Overrides Active")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("Mac follows standard macOS sleep timers. No background triggers or sleep assertions are keeping the system awake.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if showGoToKeepAwakeButton {
                        Button("Manage Triggers…") {
                            viewModel.selectedSettingsTab = .keepAwake
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(NSColor.separatorColor).opacity(0.6), lineWidth: 0.5)
                )
            } else {
                VStack(spacing: 6) {
                    ForEach(activeItems) { item in
                        HStack(spacing: 10) {
                            // Icon
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(item.iconColor.opacity(0.12))
                                    .frame(width: 28, height: 28)
                                Image(systemName: item.icon)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(item.iconColor)
                            }

                            // Title & Detail
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(item.title)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.primary)
                                    Text(item.category)
                                        .font(.system(size: 9.5, weight: .medium))
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(Color.secondary.opacity(0.12))
                                        .foregroundStyle(.secondary)
                                        .clipShape(Capsule())
                                }

                                Text(item.detail)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            // Turn Off Button
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    item.turnOff()
                                    toastMessage = "Turned off \(item.title) ✓"
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "power")
                                        .font(.system(size: 9.5, weight: .bold))
                                    Text("Turn Off")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.red.opacity(0.10))
                                .foregroundStyle(Color.red)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.red.opacity(0.25), lineWidth: 0.5)
                                )
                            }
                            .buttonStyle(.plain)
                            .help("Turn off this trigger/setting and remove it from active rules")
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                        )
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.95)),
                            removal: .opacity.combined(with: .scale(scale: 0.95))
                        ))
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.8)
        )
    }
}

// MARK: - Tab 1: General Settings

@MainActor struct GeneralSettingsTab: View {
    @Bindable var viewModel: MonteViewModel
    var onResetAll: () -> Void = {}
    @State private var showResetDialog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // 0. Active Keep-Awake Triggers & Settings Overview
            EnabledKeepAwakeSection(viewModel: viewModel, showGoToKeepAwakeButton: true)

            Divider()

            // 1. Launch and Wake Behavior
            SettingsSectionRow(label: "Launch and Wake Behavior:") {
                Toggle("Launch Mont-E automatically at login", isOn: Binding(
                    get: { LaunchAtLoginService.isEnabled },
                    set: { LaunchAtLoginService.isEnabled = $0 }
                ))
                .font(.system(size: 12))

                SettingsSubHint(text: "Runs silently as a native menu bar background agent without Dock clutter")

                Toggle("Continuous SMC watchdog on startup", isOn: $viewModel.settings.enforceBatteryLimitWatchdog)
                    .font(.system(size: 12))

                SettingsSubHint(text: "Re-asserts target battery charge limit immediately on reboot/login")
            }

            Divider()

            // 1b. Proactive Watchdog Alerts
            SettingsSectionRow(label: "Proactive Watchdogs:") {
                Toggle("Enable background resource threshold notifications", isOn: $viewModel.settings.watchdog.alertsEnabled)
                    .font(.system(size: 12, weight: .semibold))

                if viewModel.settings.watchdog.alertsEnabled {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                        GridRow {
                            Toggle("Low Free Disk (< \(viewModel.settings.watchdog.lowDiskThresholdGb) GB)", isOn: $viewModel.settings.watchdog.lowDiskAlert)
                            Toggle("Heavy SSD Swap (> 2 GB)", isOn: $viewModel.settings.watchdog.highSwapAlert)
                        }
                        GridRow {
                            Toggle("Thermal Throttling Alert", isOn: $viewModel.settings.watchdog.highThermalAlert)
                            Toggle("Bluetooth Accessory Low Battery (≤ 20%)", isOn: $viewModel.settings.watchdog.peripheralLowBatteryAlert)
                        }
                    }
                    .font(.system(size: 11.5))
                    .padding(.top, 2)

                    SettingsSubHint(text: "Dispatches native macOS alerts with a 30-minute cooldown to prevent notification fatigue")
                }
            }

            Divider()

            // 2. System Helpers & Integration
            SettingsSectionRow(label: "System Helpers:") {
                SystemRequirementsBannerView(viewModel: viewModel)
            }

            Divider()

            // 3. Maintenance & Settings Actions
            SettingsSectionRow(label: "Maintenance:") {
                VStack(alignment: .leading, spacing: 8) {
                    Button("Reset warnings and dialogs") {
                        // Resets dialog dismiss states
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Reset all settings to default…") {
                        showResetDialog = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .confirmationDialog("Reset all Mont-E settings to their default values?", isPresented: $showResetDialog) {
                        Button("Reset All Settings", role: .destructive) {
                            onResetAll()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will restore default menu bar combinations, HUD cards, and Keep-Awake thresholds.")
                    }
                }
            }
        }
    }
}

// MARK: - Tab 2: Keep-Awake Settings

@MainActor struct KeepAwakeSettingsTab: View {
    @Bindable var viewModel: MonteViewModel
    private var awake: KeepAwakeService { viewModel.keepAwake }
    @State private var customMinutesText: String = "45"
    @State private var untilTimeSelection: Date = Date().addingTimeInterval(3600)
    @State private var selectedNewAppBundle: String = ""
    @State private var applyToastText: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // ── Top Hero Card: Live Status & Quick Action ────────────────────────
            KeepAwakeLiveStatusHeaderCard(viewModel: viewModel)

            // ── Enabled Triggers & Settings Quick-Control ────────────────────────
            EnabledKeepAwakeSection(viewModel: viewModel, showGoToKeepAwakeButton: false)

            // ── Segmented Navigation Picker ──────────────────────────────────────
            Picker("", selection: $viewModel.selectedKeepAwakeSubTab) {
                ForEach(KeepAwakeSettingsSubTab.allCases) { subTab in
                    Label(subTab.rawValue, systemImage: subTab.icon).tag(subTab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 4)

            // ── Sub-Tab Content ──────────────────────────────────────────────────
            switch viewModel.selectedKeepAwakeSubTab {
            case .session:
                KeepAwakeSessionSubView(
                    viewModel: viewModel,
                    customMinutesText: $customMinutesText,
                    untilTimeSelection: $untilTimeSelection
                )
            case .display:
                KeepAwakeDisplaySubView(viewModel: viewModel)
            case .builds:
                KeepAwakeBuildsSubView(viewModel: viewModel)
            case .triggers:
                KeepAwakeTriggersSubView(
                    viewModel: viewModel,
                    selectedNewAppBundle: $selectedNewAppBundle
                )
            case .safety:
                KeepAwakeSafetySubView(viewModel: viewModel)
            }

            Divider()
                .padding(.top, 8)

            // ── Bottom Action & Confirmation Bar ────────────────────────────────
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.green)
                    Text("Settings auto-apply in real-time")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let toast = applyToastText {
                    Text(toast)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.green)
                }

                Button {
                    awake.resumeAutoTriggers()
                    awake.applyConfigChanges()
                    Task {
                        await viewModel.refresh(forceStorage: false)
                        withAnimation {
                            applyToastText = "Settings Applied & Triggers Re-evaluated ✓"
                        }
                    }
                } label: {
                    Label("Apply Settings Now", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.top, 2)
        }
    }
}

// MARK: - Keep-Awake Live Status Header Card

@MainActor private struct KeepAwakeLiveStatusHeaderCard: View {
    @Bindable var viewModel: MonteViewModel
    private var awake: KeepAwakeService { viewModel.keepAwake }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            // Coffee Cup Indicator
            ZStack {
                Circle()
                    .fill(awake.isActive ? Color.orange.opacity(0.16) : Color(NSColor.controlBackgroundColor))
                    .frame(width: 44, height: 44)

                Image(systemName: awake.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(awake.isActive ? Color.orange : Color.secondary)
            }

            // Status Description
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(awake.isActive ? "Keep-Awake Active" : "Normal System Sleep Mode")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(awake.isActive ? Color.orange : Color.primary)

                    Text(awake.isActive ? "☕ ON" : (awake.isManuallyStopped ? "⏸ STANDBY" : "💤 OFF"))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(awake.isActive ? Color.orange.opacity(0.14) : Color.secondary.opacity(0.12))
                        .foregroundStyle(awake.isActive ? Color.orange : Color.secondary)
                        .clipShape(Capsule())
                }

                Text(awake.statusSummary)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Session Quick Action Button
            if awake.isActive {
                Button(role: .destructive) {
                    awake.stop(reason: "Manually stopped from Settings.", manual: true)
                } label: {
                    Label("Stop Session", systemImage: "stop.fill")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
            } else {
                HStack(spacing: 8) {
                    if awake.isManuallyStopped {
                        Button {
                            awake.resumeAutoTriggers()
                            Task { await viewModel.refresh(forceStorage: false) }
                        } label: {
                            Label("Resume Triggers", systemImage: "bolt.fill")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Button {
                        awake.start(mode: .indefinite)
                    } label: {
                        Label("Start Keep-Awake", systemImage: "play.fill")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.small)
                }
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(awake.isActive ? Color.orange.opacity(0.3) : Color(NSColor.separatorColor), lineWidth: 1)
        )
    }
}

// MARK: - Sub-View 1: Sessions & Durations

@MainActor private struct KeepAwakeSessionSubView: View {
    @Bindable var viewModel: MonteViewModel
    @Binding var customMinutesText: String
    @Binding var untilTimeSelection: Date
    private var awake: KeepAwakeService { viewModel.keepAwake }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Quick-Start Mode
            SettingsSectionRow(label: "Default Duration:") {
                Picker("", selection: Binding(
                    get: {
                        switch awake.activeMode {
                        case .indefinite: return 0
                        case .timed(let s): return Int(s)
                        default: return 0
                        }
                    },
                    set: { secs in
                        if secs == 0 {
                            awake.start(mode: .indefinite)
                        } else {
                            awake.start(mode: .timed(TimeInterval(secs)))
                        }
                    }
                )) {
                    Text("Indefinitely (Until Stopped)").tag(0)
                    Text("15 Minutes").tag(15 * 60)
                    Text("30 Minutes").tag(30 * 60)
                    Text("45 Minutes").tag(45 * 60)
                    Text("1 Hour").tag(60 * 60)
                    Text("2 Hours").tag(2 * 3600)
                    Text("4 Hours").tag(4 * 3600)
                    Text("8 Hours").tag(8 * 3600)
                    Text("12 Hours").tag(12 * 3600)
                    Text("24 Hours").tag(24 * 3600)
                }
                .frame(width: 240)

                SettingsSubHint(text: "Duration activated when triggering Keep-Awake via keyboard hotkey or menu bar click")
            }

            Divider()

            // Custom Duration & Until Time
            SettingsSectionRow(label: "Until Specific Time:") {
                HStack(spacing: 10) {
                    DatePicker("", selection: $untilTimeSelection, displayedComponents: [.hourAndMinute])
                        .labelsHidden()
                        .frame(width: 120)

                    Button("Start Until Selected Time") {
                        let now = Date()
                        var target = untilTimeSelection
                        if target <= now {
                            // Target time is for tomorrow if earlier than now
                            target = Calendar.current.date(byAdding: .day, value: 1, to: target) ?? target
                        }
                        awake.start(mode: .untilTime(target))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                SettingsSubHint(text: "Keeps Mac awake continuously until the target clock time of day")
            }

            Divider()

            // Global Hotkey
            SettingsSectionRow(label: "Global Shortcut:") {
                HStack(spacing: 8) {
                    Text("⌥⌘K")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(NSColor.textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(NSColor.separatorColor), lineWidth: 0.5))

                    Text("Press Option + Command + K anywhere in macOS to toggle Keep-Awake on/off")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Security Policy
            SettingsSectionRow(label: "Workstation Security:") {
                Toggle("Lock macOS screen immediately on session end", isOn: Binding(
                    get: { awake.config.lockScreenOnSessionEnd },
                    set: { awake.config.lockScreenOnSessionEnd = $0 }
                ))
                .font(.system(size: 12))

                SettingsSubHint(text: "Secures your workstation automatically when a timed session or build concludes")
            }

            Divider()

            // Sound Effects & Periodic Chimes
            SettingsSectionRow(label: "Audio Feedback:") {
                Toggle("Play subtle audio chime on session start & stop", isOn: Binding(
                    get: { awake.config.playSoundEffects },
                    set: { awake.config.playSoundEffects = $0 }
                ))
                .font(.system(size: 12))

                HStack {
                    Text("Periodic Reminder Chime:")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    Picker("", selection: Binding(
                        get: { awake.config.periodicChimeIntervalMinutes },
                        set: { awake.config.periodicChimeIntervalMinutes = $0 }
                    )) {
                        Text("Off").tag(0)
                        Text("Every 15 Minutes").tag(15)
                        Text("Every 30 Minutes").tag(30)
                        Text("Hourly (Every 60m)").tag(60)
                    }
                    .frame(width: 170)
                }
                .padding(.top, 2)

                SettingsSubHint(text: "Plays periodic sound to notify you that your Mac is currently keeping itself awake")
            }
        }
    }
}

// MARK: - Sub-View 2: Display & Sleep Policies

@MainActor private struct KeepAwakeDisplaySubView: View {
    @Bindable var viewModel: MonteViewModel
    private var awake: KeepAwakeService { viewModel.keepAwake }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Display Sleep
            SettingsSectionRow(label: "Display Backlight:") {
                Toggle("Prevent display from sleeping (Keep screen awake)", isOn: Binding(
                    get: { awake.config.preventDisplaySleep },
                    set: {
                        awake.config.preventDisplaySleep = $0
                        awake.reapplyPolicies()
                    }
                ))
                .font(.system(size: 12))

                SettingsSubHint(text: "Keeps display backlight active. When disabled, display powers off while CPU remains 100% awake")

                Toggle("Dim display to save energy while awake", isOn: Binding(
                    get: { awake.config.dimDisplayWhileAwake },
                    set: {
                        awake.config.dimDisplayWhileAwake = $0
                        awake.reapplyPolicies()
                    }
                ))
                .font(.system(size: 12))

                SettingsSubHint(text: "Lowers screen brightness to minimum while preventing CPU idle sleep and allowing tasks to run")

                Toggle("Allow screen saver to run while keeping system awake", isOn: Binding(
                    get: { awake.config.allowScreenSaver },
                    set: {
                        awake.config.allowScreenSaver = $0
                        awake.reapplyPolicies()
                    }
                ))
                .font(.system(size: 12))

                SettingsSubHint(text: "Allows macOS screen saver to kick in while system CPU remains fully awake in background")
            }

            Divider()

            // Storage & Disks
            SettingsSectionRow(label: "Storage & Disks:") {
                Toggle("Prevent external drive spindown (Disk sleep)", isOn: Binding(
                    get: { awake.config.preventDiskSleep },
                    set: {
                        awake.config.preventDiskSleep = $0
                        awake.reapplyPolicies()
                    }
                ))
                .font(.system(size: 12))

                SettingsSubHint(text: "Prevents USB & Thunderbolt external drives from going to sleep during long builds or transfers")
            }

            Divider()

            // Clamshell Mode
            SettingsSectionRow(label: "Clamshell Mode:") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Closed-Display (Clamshell) Sleep Policy:")
                        .font(.system(size: 12, weight: .semibold))
                    Text("When an external display and AC power adapter are connected, macOS allows closing your MacBook lid without sleeping. Keep-Awake ensures background builds and scripts continue running without interruption.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

// MARK: - Sub-View 3: Dev Builds & Daemons (Granular Build Controls)

@MainActor private struct KeepAwakeBuildsSubView: View {
    @Bindable var viewModel: MonteViewModel
    private var awake: KeepAwakeService { viewModel.keepAwake }
    private var builds: ActiveBuildStatus { awake.activeBuilds }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Live Status Banner
            HStack(spacing: 8) {
                Image(systemName: builds.anyBuildActive ? "hammer.circle.fill" : "hammer.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(builds.anyBuildActive ? Color.cyan : Color.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Live Dev Processes:")
                        .font(.system(size: 11, weight: .bold))
                    Text(builds.activeSummary)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(builds.anyBuildActive ? Color.cyan : Color.secondary)
                }

                Spacer()

                if builds.anyBuildActive {
                    Text("MONITORED")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.cyan.opacity(0.15))
                        .foregroundStyle(Color.cyan)
                        .clipShape(Capsule())
                }
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Build Toggles Group
            SettingsSectionRow(label: "Build Automations:") {
                Text("Toggle individual build systems below to enable or DISABLE them from keeping your Mac awake:")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 2)

                // 1. Gradle Builds
                BuildTriggerRow(
                    title: "Gradle Builds & Daemons",
                    description: "GradleDaemon, gradlew, and Java compile workers",
                    isActive: builds.isGradleActive,
                    activeCount: builds.gradleCount,
                    isOn: Binding(
                        get: { awake.config.autoAwakeOnGradle },
                        set: { awake.config.autoAwakeOnGradle = $0 }
                    )
                )

                // 2. Python Scripts & Builds
                BuildTriggerRow(
                    title: "Python Scripts & Builds",
                    description: "python, python3, pytest, uv, and data processing scripts",
                    isActive: builds.isPythonActive,
                    activeCount: builds.pythonCount,
                    isOn: Binding(
                        get: { awake.config.autoAwakeOnPython },
                        set: { awake.config.autoAwakeOnPython = $0 }
                    )
                )

                // 3. Xcode & Swift Compilation
                BuildTriggerRow(
                    title: "Xcode & Swift Compilation",
                    description: "xcodebuild, swift-frontend, and SwiftPM compilation passes",
                    isActive: builds.isXcodeActive,
                    activeCount: builds.xcodeCount,
                    isOn: Binding(
                        get: { awake.config.autoAwakeOnXcode },
                        set: { awake.config.autoAwakeOnXcode = $0 }
                    )
                )

                // 4. Node.js & Web Builds
                BuildTriggerRow(
                    title: "Node.js & Web Dev Builds",
                    description: "node, npm, pnpm, yarn, bun, and next-server compilation",
                    isActive: builds.isNodeActive,
                    activeCount: builds.nodeCount,
                    isOn: Binding(
                        get: { awake.config.autoAwakeOnNode },
                        set: { awake.config.autoAwakeOnNode = $0 }
                    )
                )

                // 5. Rust / Cargo Compilation
                BuildTriggerRow(
                    title: "Cargo & Rust Compilation",
                    description: "cargo build, cargo test, and rustc compiler passes",
                    isActive: builds.isCargoActive,
                    activeCount: builds.cargoCount,
                    isOn: Binding(
                        get: { awake.config.autoAwakeOnCargo },
                        set: { awake.config.autoAwakeOnCargo = $0 }
                    )
                )

                // 6. Docker Engine & Containers
                BuildTriggerRow(
                    title: "Docker Engine & Containers",
                    description: "dockerd, com.docker backend, and active container runtimes",
                    isActive: builds.isDockerActive,
                    activeCount: builds.dockerCount,
                    isOn: Binding(
                        get: { awake.config.autoAwakeOnDocker },
                        set: { awake.config.autoAwakeOnDocker = $0 }
                    )
                )

                // 7. Make & C/C++ Compilers
                BuildTriggerRow(
                    title: "Make, CMake & Ninja Builds",
                    description: "make, cmake, ninja, and clang compiler processes",
                    isActive: builds.isMakeActive,
                    activeCount: builds.makeCount,
                    isOn: Binding(
                        get: { awake.config.autoAwakeOnMake },
                        set: { awake.config.autoAwakeOnMake = $0 }
                    )
                )
            }
        }
    }
}

// Reusable Build Trigger Row Component
@MainActor private struct BuildTriggerRow: View {
    let title: String
    let description: String
    let isActive: Bool
    let activeCount: Int
    @Binding var isOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Toggle(title, isOn: $isOn)
                    .font(.system(size: 12, weight: .medium))

                Spacer()

                if isActive {
                    Text(activeCount > 0 ? "RUNNING (\(activeCount))" : "RUNNING")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.green.opacity(0.15))
                        .foregroundStyle(Color.green)
                        .clipShape(Capsule())
                } else {
                    Text("IDLE")
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .foregroundStyle(.secondary)
                        .clipShape(Capsule())
                }
            }

            SettingsSubHint(text: description)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Sub-View 4: Triggers & Automations

@MainActor private struct KeepAwakeTriggersSubView: View {
    @Bindable var viewModel: MonteViewModel
    @Binding var selectedNewAppBundle: String
    private var awake: KeepAwakeService { viewModel.keepAwake }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Hardware Power & Displays
            SettingsSectionRow(label: "Hardware Connections:") {
                Toggle("Auto-awake when connected to AC Power Adapter", isOn: Binding(
                    get: { awake.config.autoAwakeOnACPower },
                    set: { awake.config.autoAwakeOnACPower = $0 }
                ))
                .font(.system(size: 12))

                Toggle("Auto-awake when an External Display / Monitor is attached", isOn: Binding(
                    get: { awake.config.autoAwakeOnExternalDisplay },
                    set: { awake.config.autoAwakeOnExternalDisplay = $0 }
                ))
                .font(.system(size: 12))
            }

            Divider()

            // Network & Download
            SettingsSectionRow(label: "Network & Location:") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Auto-awake when connected to Target Wi-Fi SSID", isOn: Binding(
                        get: { awake.config.autoAwakeOnWiFi },
                        set: { awake.config.autoAwakeOnWiFi = $0 }
                    ))
                    .font(.system(size: 12))

                    if awake.config.autoAwakeOnWiFi {
                        HStack(spacing: 8) {
                            TextField("Target Wi-Fi SSID…", text: Binding(
                                get: { awake.config.targetWiFiSSID },
                                set: { awake.config.targetWiFiSSID = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11))

                            Button("Use Current Wi-Fi") {
                                if let ssid = awake.getCurrentWiFiSSID() {
                                    awake.config.targetWiFiSSID = ssid
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Auto-awake while active network Download is running", isOn: Binding(
                        get: { awake.config.autoAwakeOnDownload },
                        set: { awake.config.autoAwakeOnDownload = $0 }
                    ))
                    .font(.system(size: 12))

                    if awake.config.autoAwakeOnDownload {
                        HStack {
                            Text("Speed threshold: > \(Int(awake.config.downloadThresholdKbSec)) KB/s")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Slider(value: Binding(
                                get: { awake.config.downloadThresholdKbSec },
                                set: { awake.config.downloadThresholdKbSec = $0 }
                            ), in: 100...5000, step: 100)
                            .frame(width: 140)
                        }
                    }
                }
            }

            Divider()

            // Audio Playback
            SettingsSectionRow(label: "Audio Playback:") {
                Toggle("Auto-awake while system Audio is playing", isOn: Binding(
                    get: { awake.config.autoAwakeOnAudio },
                    set: { awake.config.autoAwakeOnAudio = $0 }
                ))
                .font(.system(size: 12))

                SettingsSubHint(text: "Monitors CoreAudio output device activity (e.g. music, podcasts, or background sound)")
            }

            Divider()

            // Scheduled Hours
            SettingsSectionRow(label: "Daily Scheduled Hours:") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Auto-awake during Daily Scheduled Hours", isOn: Binding(
                        get: { awake.config.autoAwakeOnSchedule },
                        set: { awake.config.autoAwakeOnSchedule = $0 }
                    ))
                    .font(.system(size: 12))

                    if awake.config.autoAwakeOnSchedule {
                        HStack(spacing: 12) {
                            Text(String(format: "Schedule: %02d:%02d to %02d:%02d", awake.config.scheduleStartHour, awake.config.scheduleStartMinute, awake.config.scheduleEndHour, awake.config.scheduleEndMinute))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)

                            Spacer()

                            Toggle("Weekdays only (Mon–Fri)", isOn: Binding(
                                get: { awake.config.scheduleWeekdaysOnly },
                                set: { awake.config.scheduleWeekdaysOnly = $0 }
                            ))
                            .font(.system(size: 11))
                        }
                    }
                }
            }

            Divider()

            // Watched Applications
            SettingsSectionRow(label: "Watched Applications:") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Auto-awake while any Watched Application is running", isOn: Binding(
                        get: { awake.config.autoAwakeOnWatchedApps },
                        set: { awake.config.autoAwakeOnWatchedApps = $0 }
                    ))
                    .font(.system(size: 12))

                    // App List
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(awake.config.watchedApps, id: \.self) { bundleID in
                            HStack {
                                Text(bundleID)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.primary)

                                Spacer()

                                Button {
                                    awake.removeWatchedApp(bundleID)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                                .help("Remove \(bundleID)")
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }

                    // Add from running apps
                    let runningApps = awake.getRunningUserApps()
                    if !runningApps.isEmpty {
                        Menu("+ Add Running Application…") {
                            ForEach(runningApps, id: \.bundleID) { app in
                                Button(app.name) {
                                    awake.addWatchedApp(app.bundleID)
                                }
                            }
                        }
                        .menuStyle(.borderedButton)
                        .controlSize(.small)
                    }
                }
            }
        }
    }
}

// MARK: - Sub-View 5: Hardware & Battery Safety

@MainActor private struct KeepAwakeSafetySubView: View {
    @Bindable var viewModel: MonteViewModel
    private var awake: KeepAwakeService { viewModel.keepAwake }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Low Battery Cutoff
            SettingsSectionRow(label: "Battery Protection:") {
                HStack {
                    Text("Low Battery Cutoff Threshold: \(awake.config.batterySafetyCutoffPercent)%")
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                    Spacer()
                    Slider(value: Binding(
                        get: { Double(awake.config.batterySafetyCutoffPercent) },
                        set: { awake.config.batterySafetyCutoffPercent = Int($0) }
                    ), in: 5...50, step: 5)
                    .frame(width: 140)
                }

                SettingsSubHint(text: "Immediately terminates keep-awake session if running on battery to prevent deep discharge")

                Toggle("AC Power Only Policy: Never keep awake on battery", isOn: Binding(
                    get: { awake.config.onlyOnACPower },
                    set: { awake.config.onlyOnACPower = $0 }
                ))
                .font(.system(size: 12))

                SettingsSubHint(text: "Automatically ends any active session immediately if the AC power adapter is unplugged")
            }

            Divider()

            // Thermal Protection
            SettingsSectionRow(label: "Thermal Safety:") {
                Toggle("Emergency stop on thermal throttling (Serious / Critical)", isOn: Binding(
                    get: { awake.config.stopOnOverheating },
                    set: { awake.config.stopOnOverheating = $0 }
                ))
                .font(.system(size: 12))

                SettingsSubHint(text: "Protects Apple Silicon CPU/GPU by automatically ending session if thermal state throttles")

                Toggle("Emergency stop on high battery temperature (> \(Int(awake.config.maxBatteryTemperatureCelsius))°C)", isOn: Binding(
                    get: { awake.config.stopOnHighBatteryTemperature },
                    set: { awake.config.stopOnHighBatteryTemperature = $0 }
                ))
                .font(.system(size: 12))

                if awake.config.stopOnHighBatteryTemperature {
                    HStack {
                        Text("Max Battery Temperature: \(Int(awake.config.maxBatteryTemperatureCelsius))°C (\(Int(awake.config.maxBatteryTemperatureCelsius * 9.0 / 5.0 + 32.0))°F)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Slider(value: Binding(
                            get: { awake.config.maxBatteryTemperatureCelsius },
                            set: { awake.config.maxBatteryTemperatureCelsius = $0 }
                        ), in: 38...50, step: 1)
                        .frame(width: 140)
                    }
                }

                SettingsSubHint(text: "Prevents high battery cell degradation caused by combined computing load and charging heat")
            }
        }
    }
}

// MARK: - Tab 5: Battery & SMC Settings

@MainActor struct BatterySettingsTab: View {
    @Bindable var viewModel: MonteViewModel
    private var h: SystemHealth { viewModel.health }
    private let limitOptions: [Int] = [70, 75, 80, 100]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // 1. Target Charge Limit
            SettingsSectionRow(label: "Target Charge Limit:") {
                HStack(spacing: 8) {
                    ForEach(limitOptions, id: \.self) { pct in
                        limitButton(for: pct)
                    }
                }

                SettingsSubHint(text: "Configures Apple Silicon SMC registers to reduce cell voltage stress from ~4.20V to ~3.85V")
            }

            Divider()

            // 2. AC Power Routing & Pass-Through
            SettingsSectionRow(label: "AC Power Routing:") {
                Toggle("Direct AC Power Pass-Through (Bypass charging once cap is reached)", isOn: $viewModel.settings.directPowerPassThrough)
                    .font(.system(size: 12))

                SettingsSubHint(text: "Runs purely on wall adapter power, stopping battery cycle wear and heat buildup")

                Toggle("Auto-discharge to target limit when connected to AC power", isOn: $viewModel.settings.autoDischargeToLimit)
                    .font(.system(size: 12))

                SettingsSubHint(text: "Discharges battery down to 80% if plugged in at full charge to relieve high cell voltage")

                Toggle("Continuous SMC watchdog (re-asserts limit after sleep/reboot)", isOn: $viewModel.settings.enforceBatteryLimitWatchdog)
                    .font(.system(size: 12))
            }

            Divider()

            // 3. Live Telemetry
            SettingsSectionRow(label: "Live SMC Status:") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        GlowingStatusDot(color: h.isCharging ? .green : (h.isAcPower ? .blue : .orange), size: 7.0)
                        Text("Battery Level: \(h.batteryPercent)% (\(h.isCharging ? "Charging" : (h.isAcPower ? "AC Pass-Through" : "On Battery")))")
                            .font(.system(size: 12, weight: .semibold))
                    }

                    Text("SMC Hardware Register: \(h.batteryLimit != nil ? "Capped at \(h.batteryLimit!)%" : "Uncapped (100%)") • \(h.isAcPower ? "Wall Charger Connected" : "Battery Discharging")")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    @ViewBuilder
    private func limitButton(for pct: Int) -> some View {
        let isSelected: Bool = (pct == 100 && (h.batteryLimit == nil || h.batteryLimit == 100)) || (h.batteryLimit == pct)
        let label = pct == 100 ? "100% (No Cap)" : "\(pct)%"

        if isSelected {
            Button(label) {
                Task { await viewModel.setBatteryLimit(pct) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        } else {
            Button(label) {
                Task { await viewModel.setBatteryLimit(pct) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

// MARK: - Tab 6: Menu Bar & HUD Settings

@MainActor struct MenuBarHudSettingsTab: View {
    @Bindable var viewModel: MonteViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // 1. Menu Bar Preview
            SettingsSectionRow(label: "Menu Bar Preview:") {
                HStack(spacing: 8) {
                    Text("Tray Live Output:")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    Text(viewModel.menuBarTitle)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color(NSColor.textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                        )
                }
            }

            Divider()

            // 2. Visible Tray Metrics
            SettingsSectionRow(label: "Menu Bar Display:") {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        Toggle("Overall Health Dot (Score Color)", isOn: $viewModel.settings.showMenuBarStatusDot)
                        Toggle("Memory / RAM (Default)", isOn: $viewModel.settings.showMenuBarRAM)
                    }
                    GridRow {
                        Toggle("CPU Usage %", isOn: $viewModel.settings.showMenuBarCPU)
                        Toggle("GPU Usage %", isOn: $viewModel.settings.showMenuBarGPU)
                    }
                    GridRow {
                        Toggle("SSD Swap Usage", isOn: $viewModel.settings.showMenuBarSwap)
                        Toggle("Thermal State", isOn: $viewModel.settings.showMenuBarThermal)
                    }
                    GridRow {
                        Toggle("Battery & Charging %", isOn: $viewModel.settings.showMenuBarBattery)
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    }
                }

                if viewModel.settings.showMenuBarRAM {
                    Toggle("Display RAM as Percentage (%) instead of GB", isOn: $viewModel.settings.ramDisplayInPercent)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }

            Divider()

            // 3. Dropdown HUD Customization
            SettingsSectionRow(label: "Dropdown HUD:") {
                HStack {
                    Text("HUD Layout Style:")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Picker("", selection: $viewModel.settings.hud.layoutMode) {
                        ForEach(HUDLayoutMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .frame(width: 170)
                }

                Text("Visible HUD Cards:")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.top, 4)

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow {
                        Toggle("CPU Load", isOn: $viewModel.settings.hud.showCPU)
                        Toggle("GPU Accelerator", isOn: $viewModel.settings.hud.showGPU)
                    }
                    GridRow {
                        Toggle("Memory / RAM", isOn: $viewModel.settings.hud.showMemory)
                        Toggle("SSD Swap", isOn: $viewModel.settings.hud.showSwap)
                    }
                    GridRow {
                        Toggle("Battery & Power", isOn: $viewModel.settings.hud.showBattery)
                        Toggle("Bluetooth Accessories", isOn: $viewModel.settings.hud.showBluetooth)
                    }
                    GridRow {
                        Toggle("P/E Core Breakdown", isOn: $viewModel.settings.hud.showCoreGrid)
                        Toggle("Cooling & Fans", isOn: $viewModel.settings.hud.showFans)
                    }
                    GridRow {
                        Toggle("APFS Free Disk", isOn: $viewModel.settings.hud.showDiskSpace)
                        Toggle("Top RAM App", isOn: $viewModel.settings.hud.showTopProcess)
                    }
                    GridRow {
                        Toggle("Battery Cycles", isOn: $viewModel.settings.hud.showBatteryHealth)
                        Toggle("Network I/O", isOn: $viewModel.settings.hud.showNetworkIO)
                    }
                    GridRow {
                        Toggle("Xcode DerivedData", isOn: $viewModel.settings.hud.showXcodeDerivedData)
                        Toggle("Agent Brain Storage", isOn: $viewModel.settings.hud.showAgentStorage)
                    }
                    GridRow {
                        Toggle("Wi-Fi & Link Quality", isOn: $viewModel.settings.hud.showWiFi)
                        Toggle("Mounted External Drives", isOn: $viewModel.settings.hud.showMountedVolumes)
                    }
                }
            }

            Divider()

            // 4. Dashboard Overview Cards Layout
            SettingsSectionRow(label: "Dashboard Overview:") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Re-arrange card order and toggle card visibility in the Dashboard Overview tab:")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)

                    DashboardOverviewCardsSettingsView(viewModel: viewModel)
                }
            }
        }
    }
}

// MARK: - Tab 7: Dev Tools & Memory Settings

@MainActor struct DevToolsSettingsTab: View {
    @Bindable var viewModel: MonteViewModel
    @Binding var memoryOptResult: String?
    @Binding var isFreeingRam: Bool
    private var h: SystemHealth { viewModel.health }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // 1. RAM Optimizer
            SettingsSectionRow(label: "Memory Optimizer:") {
                HStack(spacing: 12) {
                    Button {
                        isFreeingRam = true
                        Task {
                            memoryOptResult = await viewModel.optimizeMemory()
                            isFreeingRam = false
                        }
                    } label: {
                        Label(isFreeingRam ? "Freeing RAM…" : "Optimize Memory Now", systemImage: "memorychip")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isFreeingRam)

                    if let res = memoryOptResult {
                        Text(res)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.green)
                    }
                }

                SettingsSubHint(text: "Safely purges inactive file caches and stops idle background Gradle daemons")
            }

            Divider()

            // 2. Storage Cleaners
            SettingsSectionRow(label: "Storage Retention:") {
                HStack {
                    Text("Auto-Prune logs older than: \(viewModel.logRetentionDays) days")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Slider(value: Binding(
                        get: { Double(viewModel.logRetentionDays) },
                        set: { viewModel.logRetentionDays = Int($0) }
                    ), in: 3...30, step: 1)
                    .frame(width: 140)
                }

                HStack(spacing: 8) {
                    Button {
                        Task { _ = await viewModel.pruneLogs(days: viewModel.logRetentionDays) }
                    } label: {
                        Label("Prune Agent Logs (> \(viewModel.logRetentionDays)d)", systemImage: "trash")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        Task { _ = await viewModel.cleanDerivedData() }
                    } label: {
                        Label("Clear Xcode DerivedData", systemImage: "hammer")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            Divider()

            // 3. Active Monitors
            SettingsSectionRow(label: "Monitored Services:") {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        Toggle("CPU Load", isOn: $viewModel.settings.monitorCPU)
                        Toggle("Thermal State", isOn: $viewModel.settings.monitorThermal)
                    }
                    GridRow {
                        Toggle("Battery & SMC", isOn: $viewModel.settings.monitorBattery)
                        Toggle("RAM / Memory", isOn: $viewModel.settings.monitorMemory)
                    }
                    GridRow {
                        Toggle("SSD Swap", isOn: $viewModel.settings.monitorSwap)
                        Toggle("Gradle Daemons", isOn: $viewModel.settings.monitorGradle)
                    }
                    GridRow {
                        Toggle("Python Scripts", isOn: $viewModel.settings.monitorPython)
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    }
                }
            }
        }
    }
}

// MARK: - Tab 8: About Mont-E

@MainActor struct AboutSettingsTab: View {
    @Bindable var viewModel: MonteViewModel
    private var h: SystemHealth { viewModel.health }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Image(systemName: "bolt.shield.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.blue, Color.cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)
                    .background(Color.blue.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                Text("Mont-E")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.primary)

                Text("Mac Developer Hardware & Swap Optimizer")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    Text("Version 1.0.0 (Build 2026.10.09)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Text("• Native Swift 6")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.green)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.green.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            .padding(.top, 4)

            // System Specs
            VStack(alignment: .leading, spacing: 6) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    GridRow {
                        Text("Architecture:").font(.system(size: 11.5)).foregroundStyle(.secondary)
                        Text("Apple Silicon (arm64 Unified Memory)").font(.system(size: 11.5, weight: .medium))
                    }
                    GridRow {
                        Text("Memory Profile:").font(.system(size: 11.5)).foregroundStyle(.secondary)
                        Text("\(String(format: "%.0f", h.ramTotalGb)) GB Unified RAM • Direct Mach Subsystem").font(.system(size: 11.5, weight: .medium))
                    }
                    GridRow {
                        Text("Active SSD Swap:").font(.system(size: 11.5)).foregroundStyle(.secondary)
                        Text("\(String(format: "%.1f GB (%@)", h.swapUsedMb / 1024.0, h.swapRisk.label))").font(.system(size: 11.5, weight: .medium))
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Text("Designed for Mac Developers, AI Agent Workflows & Long Battery Health.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
