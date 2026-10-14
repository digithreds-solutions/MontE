import AppKit
import SwiftUI
import UserNotifications

// MARK: - Entry Point

/// LSUIElement = YES means no Dock icon. AppDelegate manages the entire lifecycle.
@main
struct MonteApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

// MARK: - AppDelegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private var viewModel: MonteViewModel!
    private var dashboardWindowController: DashboardWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var refreshTimer: Timer?
    private var pulseTimer: Timer?
    private var powerNotificationSource: CFRunLoopSource?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        viewModel = MonteViewModel()

        // Ensure Launch at Login is registered and synchronized
        LaunchAtLoginService.ensureSynchronized()

        // Re-apply persistent battery charge limit to SMC on startup
        if let targetLimit = viewModel.settings.targetBatteryLimit, targetLimit < 100 {
            Task(priority: .utility) {
                _ = await self.viewModel.setBatteryLimit(targetLimit)
            }
        }

        setupStatusItem()
        setupPowerChangeObserver()
        startAutoRefresh()
        startPulseAnimation()
        setupGlobalHotkey()

        // Initial data load
        Task {
            await viewModel.refresh(forceStorage: true)
            self.updateStatusItemTitle()
            self.buildMenu()
        }
    }

    // MARK: Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "MontEStatusItem"
        updateStatusItemTitle()
        buildMenu()
    }

    private func setupGlobalHotkey() {
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains([.command, .option]) && event.charactersIgnoringModifiers?.lowercased() == "k" {
                Task { @MainActor in
                    self?.toggleKeepAwakeGlobal()
                }
            }
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains([.command, .option]) && event.charactersIgnoringModifiers?.lowercased() == "k" {
                Task { @MainActor in
                    self?.toggleKeepAwakeGlobal()
                }
                return nil
            }
            return event
        }
    }

    @objc private func toggleKeepAwakeGlobal() {
        if viewModel.keepAwake.isActive {
            viewModel.keepAwake.stop(reason: "Keep-Awake disabled via ⌥⌘K shortcut.", manual: true)
        } else {
            viewModel.keepAwake.start(mode: .indefinite)
        }
        updateStatusItemTitle()
        buildMenu()
    }

    private func startPulseAnimation() {
        pulseTimer?.invalidate()
        // Smooth 20 FPS LED breathing pulse (t = 0.05s)
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self,
                      let button = self.statusItem?.button,
                      self.viewModel.settings.showMenuBarStatusDot else { return }

                let nsColor = self.viewModel.health.overallHealth.nsColor
                let time = Date().timeIntervalSinceReferenceDate
                // Slow sinusoidal breathing wave over exactly 3.0 seconds: (2π / 3.0)
                let pulseFactor = CGFloat((sin(time * (2.0 * .pi / 3.0)) + 1.0) / 2.0)

                button.image = NSImage.glowingStatusDot(color: nsColor, size: 8.0, pulseFactor: pulseFactor)
                button.imagePosition = .imageLeading
            }
        }
    }

    private func updateStatusItemTitle() {
        guard let button = statusItem.button else { return }
        button.title = viewModel.menuBarTitle

        if viewModel.settings.showMenuBarStatusDot {
            let nsColor = viewModel.health.overallHealth.nsColor
            let time = Date().timeIntervalSinceReferenceDate
            let pulseFactor = CGFloat((sin(time * (2.0 * .pi / 3.0)) + 1.0) / 2.0)
            button.image = NSImage.glowingStatusDot(color: nsColor, size: 8.0, pulseFactor: pulseFactor)
            button.imagePosition = .imageLeading
        } else {
            button.image = nil
        }

        let h = viewModel.health
        let awakeStr = viewModel.keepAwake.isActive ? " | Awake: \(viewModel.keepAwake.statusSummary)" : ""
        button.toolTip = "Mont-E [\(h.overallHealth.rawValue)] — RAM: \(String(format: "%.1f", h.ramUsedGb))G | Swap: \(String(format: "%.1f", h.swapUsedMb / 1024.0))G | CPU: \(String(format: "%.0f", h.cpuUsagePercent))% | Batt: \(h.batteryPercent)%\(awakeStr)"
    }

    private func buildMenu() {
        let menu = NSMenu()
        let h = viewModel.health
        let awake = viewModel.keepAwake
        let hud = viewModel.settings.hud

        // ── 1. Embedded SwiftUI Statistics Grid Header ───────────────────────
        let gridView = MenuStatsGridView(
            viewModel: viewModel,
            onRefresh: { [weak self] in
                self?.manualRefresh()
            },
            onOpenDashboard: { [weak self] in
                self?.openDashboard()
            },
            onOpenStorageInspector: { [weak self] in
                self?.openStorageInspector()
            },
            onOpenProcessInvestigator: { [weak self] in
                self?.openProcessInvestigator()
            },
            onOpenSettings: { [weak self] tab in
                self?.openSettings(tab: tab)
            }
        )
        let hostingView = NSHostingView(rootView: gridView)
        let hudWidth: CGFloat = hud.layoutMode == .compactList ? 270 : 310
        let tileCount = [
            hud.showCPU,
            (hud.showGPU && h.gpu.isAvailable),
            hud.showMemory,
            hud.showSwap,
            hud.showBattery,
            hud.showDiskSpace,
            hud.showTopProcess,
            hud.showBatteryHealth,
            hud.showNetworkIO,
            hud.showFans,
            hud.showXcodeDerivedData,
            (viewModel.settings.monitorGradle && hud.showGradle),
            hud.showAgentStorage
        ].filter { $0 }.count
        let rows = hud.layoutMode == .compactList ? CGFloat(tileCount) : ceil(CGFloat(tileCount) / 2.0)
        let interSpacing = max(0, rows - 1) * 10
        let awakeHeight: CGFloat = awake.isActive ? 42 : 0
        let btHeight: CGFloat = (hud.showBluetooth && !h.bluetoothDevices.isEmpty) ? CGFloat(14 + min(h.bluetoothDevices.count, 3) * 22) : 0
        let calculatedHeight = 14 + 20 + 12 + awakeHeight + btHeight + (rows * 52) + interSpacing + 16
        hostingView.frame = NSRect(x: 0, y: 0, width: hudWidth, height: calculatedHeight)

        let gridItem = NSMenuItem()
        gridItem.view = hostingView
        menu.addItem(gridItem)

        // ── Divider ───────────────────────────────────────────────────────────
        menu.addItem(.separator())

        // ── 2. Primary 1-Click Action: Free RAM ──────────────────────────────
        let freeRamItem = NSMenuItem(title: "Free RAM (Purge Caches)", action: #selector(optimizeMemory), keyEquivalent: "o")
        freeRamItem.image = NSImage(systemSymbolName: "memorychip", accessibilityDescription: "Free RAM")
        freeRamItem.target = self
        menu.addItem(freeRamItem)

        // ── 3. Keep-Awake Presets Submenu ────────────────────────────────────
        let awakeMenu = NSMenu()

        if awake.isActive {
            let activeItem = NSMenuItem(title: "Status: \(awake.statusSummary)", action: nil, keyEquivalent: "")
            activeItem.isEnabled = false
            awakeMenu.addItem(activeItem)

            let stopItem = NSMenuItem(title: "Deactivate Keep-Awake", action: #selector(stopKeepAwake), keyEquivalent: "")
            stopItem.target = self
            awakeMenu.addItem(stopItem)
            awakeMenu.addItem(.separator())
        }

        let indefItem = NSMenuItem(title: "Indefinitely", action: #selector(startKeepAwakeIndefinite), keyEquivalent: "")
        indefItem.target = self
        indefItem.state = (awake.isActive && awake.activeMode == .indefinite) ? .on : .off
        awakeMenu.addItem(indefItem)

        let timedPresets: [(String, TimeInterval)] = [
            ("For 15 Minutes", 15 * 60),
            ("For 30 Minutes", 30 * 60),
            ("For 1 Hour", 60 * 60),
            ("For 2 Hours", 2 * 3600),
            ("For 4 Hours", 4 * 3600),
            ("For 8 Hours", 8 * 3600)
        ]

        for (title, secs) in timedPresets {
            let item = NSMenuItem(title: title, action: #selector(startKeepAwakeTimed(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = secs
            if case .timed(let activeSecs) = awake.activeMode, activeSecs == secs, awake.isActive {
                item.state = .on
            } else {
                item.state = .off
            }
            awakeMenu.addItem(item)
        }

        let customItem = NSMenuItem(title: "Custom Duration / Until Time…", action: #selector(openKeepAwakeCustomTime), keyEquivalent: "")
        customItem.target = self
        customItem.image = NSImage(systemSymbolName: "clock", accessibilityDescription: "Custom Time")
        let isCustom = {
            guard awake.isActive else { return false }
            switch awake.activeMode {
            case .untilTime: return true
            case .timed(let secs): return !timedPresets.contains(where: { $0.1 == secs })
            default: return false
            }
        }()
        customItem.state = isCustom ? .on : .off
        awakeMenu.addItem(customItem)

        awakeMenu.addItem(.separator())

        let dispItem = NSMenuItem(title: "Prevent Display Sleep", action: #selector(toggleDisplaySleep), keyEquivalent: "")
        dispItem.target = self
        dispItem.state = awake.config.preventDisplaySleep ? .on : .off
        awakeMenu.addItem(dispItem)

        let keepAwakePrefsItem = NSMenuItem(title: "Keep-Awake Settings…", action: #selector(openKeepAwakeSettings), keyEquivalent: "")
        keepAwakePrefsItem.target = self
        keepAwakePrefsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
        awakeMenu.addItem(keepAwakePrefsItem)

        let awakeSubmenuItem = NSMenuItem(title: awake.isActive ? "Keep-Awake (Active)…" : "Keep-Awake…", action: nil, keyEquivalent: "")
        awakeSubmenuItem.image = NSImage(systemSymbolName: "cup.and.saucer", accessibilityDescription: "Keep-Awake")
        awakeSubmenuItem.submenu = awakeMenu
        menu.addItem(awakeSubmenuItem)

        // ── 4. Battery & Charge Limit Submenu ────────────────────────────────
        let limitMenu = NSMenu()
        if !h.isBatteryLimiterInstalled {
            let setupItem = NSMenuItem(title: "Install Battery Limiter Tool…", action: #selector(installBatteryTool), keyEquivalent: "")
            setupItem.target = self
            setupItem.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "Install")
            limitMenu.addItem(setupItem)
            limitMenu.addItem(.separator())
        }

        for pct in [70, 75, 80, 100] {
            let title = pct == 100 ? "100% (Full Charge / No Cap)" : "Limit to \(pct)%"
            let item = NSMenuItem(title: title, action: #selector(setBatteryLimit(_:)), keyEquivalent: "")
            item.target = self
            item.tag = pct
            if pct == 100 {
                item.state = (h.batteryLimit == nil || h.batteryLimit == 100) ? .on : .off
            } else {
                item.state = (h.batteryLimit == pct) ? .on : .off
            }
            limitMenu.addItem(item)
        }

        if let cap = h.batteryLimit, cap < 100 {
            limitMenu.addItem(.separator())
            if h.batteryPercent > cap {
                let dischargeItem = NSMenuItem(title: "Discharge to \(cap)% Now (Currently \(h.batteryPercent)%)", action: #selector(forceDischargeNow), keyEquivalent: "")
                dischargeItem.target = self
                dischargeItem.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: "Discharge")
                limitMenu.addItem(dischargeItem)
            }
        }

        let limitItem = NSMenuItem(title: "Battery Charge Limit…", action: nil, keyEquivalent: "")
        limitItem.image = NSImage(systemSymbolName: "battery.100.bolt", accessibilityDescription: "Battery")
        limitItem.submenu = limitMenu
        menu.addItem(limitItem)

        // ── 5. Developer Tools & Cleaners Submenu ────────────────────────────
        let devMenu = NSMenu()

        let fullOptItem = NSMenuItem(title: "Full System Optimize", action: #selector(optimizeAll), keyEquivalent: "O")
        fullOptItem.image = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: "Full Optimize")
        fullOptItem.target = self
        devMenu.addItem(fullOptItem)

        let inspectProcItem = NSMenuItem(title: "Investigate Heavy Processes…", action: #selector(openProcessInvestigator), keyEquivalent: "")
        inspectProcItem.image = NSImage(systemSymbolName: "cpu", accessibilityDescription: "Process Investigator")
        inspectProcItem.target = self
        devMenu.addItem(inspectProcItem)

        if viewModel.settings.monitorGradle {
            let stopGradleItem = NSMenuItem(
                title: h.daemons.isEmpty ? "No Idle Gradle Daemons" : "Stop \(h.daemons.count) Gradle Daemon\(h.daemons.count == 1 ? "" : "s")",
                action: #selector(stopDaemons),
                keyEquivalent: ""
            )
            stopGradleItem.image = NSImage(systemSymbolName: "hammer", accessibilityDescription: "Gradle")
            stopGradleItem.target = self
            stopGradleItem.isEnabled = !h.daemons.isEmpty
            devMenu.addItem(stopGradleItem)
        }

        let pruneLogsItem = NSMenuItem(title: "Prune AI Agent Brain Logs (>\(viewModel.logRetentionDays)d)", action: #selector(pruneAgentLogs), keyEquivalent: "")
        pruneLogsItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Prune")
        pruneLogsItem.target = self
        devMenu.addItem(pruneLogsItem)

        let inspectStorageItem = NSMenuItem(title: "Inspect Agent & Dev Storage…", action: #selector(openStorageInspector), keyEquivalent: "i")
        inspectStorageItem.image = NSImage(systemSymbolName: "folder.badge.gearshape", accessibilityDescription: "Inspect Storage")
        inspectStorageItem.target = self
        devMenu.addItem(inspectStorageItem)

        let devSubmenuItem = NSMenuItem(title: "Developer Tools & Cleaners…", action: nil, keyEquivalent: "")
        devSubmenuItem.image = NSImage(systemSymbolName: "wrench.and.screwdriver", accessibilityDescription: "Tools")
        devSubmenuItem.submenu = devMenu
        menu.addItem(devSubmenuItem)

        // ── Divider ───────────────────────────────────────────────────────────
        menu.addItem(.separator())

        // ── 6. Navigation & Tools ────────────────────────────────────────────
        let procItem = NSMenuItem(title: "Process & RAM Investigator…", action: #selector(openProcessInvestigator), keyEquivalent: "p")
        procItem.image = NSImage(systemSymbolName: "cpu", accessibilityDescription: "Process Investigator")
        procItem.target = self
        menu.addItem(procItem)

        let dashItem = NSMenuItem(title: "Open Mont-E Dashboard", action: #selector(openDashboard), keyEquivalent: "m")
        dashItem.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: "Dashboard")
        dashItem.target = self
        menu.addItem(dashItem)

        let actMonItem = NSMenuItem(title: "Activity Monitor", action: #selector(openActivityMonitor), keyEquivalent: "a")
        actMonItem.image = NSImage(systemSymbolName: "chart.xyaxis.line", accessibilityDescription: "Activity Monitor")
        actMonItem.target = self
        menu.addItem(actMonItem)

        // ── Divider ───────────────────────────────────────────────────────────
        menu.addItem(.separator())

        // ── 7. Preferences & About ────────────────────────────────────────────
        let prefItem = NSMenuItem(title: "Settings & HUD Config…", action: #selector(openPreferences), keyEquivalent: ",")
        prefItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
        prefItem.target = self
        menu.addItem(prefItem)

        let aboutItem = NSMenuItem(title: "About Mont-E", action: #selector(openAbout), keyEquivalent: "")
        aboutItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "About")
        aboutItem.target = self
        menu.addItem(aboutItem)

        // ── Divider ───────────────────────────────────────────────────────────
        menu.addItem(.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit Mont-E", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: "Quit")
        menu.addItem(quitItem)

        menu.delegate = self
        statusItem.menu = menu
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        Task { @MainActor in
            await viewModel.refresh(forceStorage: false)
            self.updateStatusItemTitle()
        }
    }

    // MARK: - Actions

    @objc private func optimizeMemory() {
        Task {
            let msg = await viewModel.optimizeMemory()
            self.updateStatusItemTitle()
            self.buildMenu()
            self.dashboardWindowController?.refresh()
            sendNotification(title: "Memory Optimized", body: msg)
        }
    }

    @objc private func pruneAgentLogs() {
        Task {
            let msg = await viewModel.pruneLogs(days: viewModel.logRetentionDays)
            self.buildMenu()
            self.dashboardWindowController?.refresh()
            sendNotification(title: "Agent Logs Pruned", body: msg)
        }
    }

    @objc private func startKeepAwakeIndefinite() {
        viewModel.keepAwake.start(mode: .indefinite)
        updateStatusItemTitle()
        buildMenu()
    }

    @objc private func startKeepAwakeTimed(_ sender: NSMenuItem) {
        guard let secs = sender.representedObject as? TimeInterval else { return }
        viewModel.keepAwake.start(mode: .timed(secs))
        updateStatusItemTitle()
        buildMenu()
    }

    @objc private func toggleDisplaySleep() {
        viewModel.keepAwake.config.preventDisplaySleep.toggle()
        viewModel.keepAwake.reapplyPolicies()
        buildMenu()
    }

    @objc private func stopKeepAwake() {
        viewModel.keepAwake.stop(reason: "Keep-Awake disabled manually.", manual: true)
        updateStatusItemTitle()
        buildMenu()
    }

    @objc private func openKeepAwakeCustomTime() {
        viewModel.selectedKeepAwakeSubTab = .session
        openSettings(tab: .keepAwake)
    }

    @objc private func openKeepAwakeSettings() {
        openSettings(tab: .keepAwake)
    }

    @objc private func openActivityMonitor() {
        let path = "/System/Applications/Utilities/Activity Monitor.app"
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
    }

    @objc private func setBatteryLimit(_ sender: NSMenuItem) {
        let pct = sender.tag
        Task {
            let result = await viewModel.setBatteryLimit(pct)
            await viewModel.refresh(forceStorage: false)
            self.updateStatusItemTitle()
            self.buildMenu()
            self.dashboardWindowController?.refresh()
            if result.success {
                sendNotification(title: "Battery Limit Set", body: result.message)
            } else {
                sendNotification(title: "Battery Limiter Notice", body: result.message)
            }
        }
    }

    @objc private func forceDischargeNow() {
        Task {
            let result = await viewModel.forceDischargeNow()
            await viewModel.refresh(forceStorage: false)
            self.updateStatusItemTitle()
            self.buildMenu()
            self.dashboardWindowController?.refresh()
            sendNotification(title: "Battery Discharge", body: result.message)
        }
    }

    @objc private func installBatteryTool() {
        viewModel.installBatteryTool()
    }

    @objc private func stopDaemons() {
        Task {
            let count = await viewModel.stopGradleDaemons()
            self.buildMenu()
            sendNotification(title: "Gradle Daemons Stopped", body: "Stopped \(count) daemon(s). RAM reclaimed!")
        }
    }

    @objc private func optimizeAll() {
        Task {
            let msg = await viewModel.optimizeAll()
            self.updateStatusItemTitle()
            self.buildMenu()
            self.dashboardWindowController?.refresh()
            sendNotification(title: "Mont-E — Optimized!", body: msg)
        }
    }

    @objc private func openDashboard() {
        if dashboardWindowController == nil {
            dashboardWindowController = DashboardWindowController(viewModel: viewModel, onOpenSettings: { [weak self] tab in
                self?.openSettings(tab: tab)
            })
        }
        dashboardWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openSettings(tab: SettingsTab = .general) {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(viewModel: viewModel)
        }
        settingsWindowController?.showSettings(tab: tab)
    }

    @objc private func openPreferences() {
        openSettings(tab: .general)
    }

    @objc private func openStorageInspector() {
        if dashboardWindowController == nil {
            dashboardWindowController = DashboardWindowController(viewModel: viewModel, onOpenSettings: { [weak self] tab in
                self?.openSettings(tab: tab)
            })
        }
        dashboardWindowController?.showStorageInspector()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openProcessInvestigator() {
        if dashboardWindowController == nil {
            dashboardWindowController = DashboardWindowController(viewModel: viewModel, onOpenSettings: { [weak self] tab in
                self?.openSettings(tab: tab)
            })
        }
        dashboardWindowController?.showProcessInvestigator()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openAbout() {
        openSettings(tab: .about)
    }

    @objc private func manualRefresh() {
        Task {
            await viewModel.refresh(forceStorage: true)
            self.updateStatusItemTitle()
            self.buildMenu()
            self.dashboardWindowController?.refresh()
        }
    }

    // MARK: Power Event Observer

    private func setupPowerChangeObserver() {
        powerNotificationSource = BatteryService.registerPowerChangeCallback { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.viewModel.refresh(forceStorage: false)
                self.updateStatusItemTitle()
                self.buildMenu()
            }
        }
    }

    // MARK: Auto-Refresh Timer

    private func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.viewModel.refresh(forceStorage: false)
                self.updateStatusItemTitle()
                self.buildMenu()
                self.dashboardWindowController?.refresh()
            }
        }
        RunLoop.main.add(refreshTimer!, forMode: .common)
    }

    // MARK: Notifications

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - Menu Bar Glowing LED Status Dot Image Generator
 
extension NSImage {
    static func glowingStatusDot(color: NSColor, size: CGFloat = 8.0, pulseFactor: CGFloat = 0.5) -> NSImage {
        let canvasWidth: CGFloat = 18.0
        let canvasHeight: CGFloat = 18.0
        let img = NSImage(size: NSSize(width: canvasWidth, height: canvasHeight), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            let center = CGPoint(x: canvasWidth / 2.0, y: canvasHeight / 2.0)
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let transparentColor = color.withAlphaComponent(0.0).cgColor

            // 1. Layer 1: Diffuse Outer Aura Bloom (breathes smoothly with pulseFactor)
            let outerRadius: CGFloat = (size / 2.0) + 2.0 + (3.0 * pulseFactor)
            let outerAlpha: CGFloat = 0.25 + (0.35 * pulseFactor)
            let glowOuterColor = color.withAlphaComponent(outerAlpha).cgColor

            if let outerGradient = CGGradient(colorsSpace: colorSpace, colors: [glowOuterColor, transparentColor] as CFArray, locations: [0.0, 1.0]) {
                ctx.drawRadialGradient(
                    outerGradient,
                    startCenter: center,
                    startRadius: size / 2.0,
                    endCenter: center,
                    endRadius: outerRadius,
                    options: .drawsAfterEndLocation
                )
            }

            // 2. Layer 2: Intense Corona Halo Glow (close to the diode body)
            let coronaRadius: CGFloat = (size / 2.0) + 1.8
            let coronaAlpha: CGFloat = 0.50 + (0.35 * pulseFactor)
            let glowCoronaColor = color.withAlphaComponent(coronaAlpha).cgColor

            if let coronaGradient = CGGradient(colorsSpace: colorSpace, colors: [glowCoronaColor, transparentColor] as CFArray, locations: [0.0, 1.0]) {
                ctx.drawRadialGradient(
                    coronaGradient,
                    startCenter: center,
                    startRadius: max(size / 2.0 - 1.0, 0),
                    endCenter: center,
                    endRadius: coronaRadius,
                    options: .drawsAfterEndLocation
                )
            }

            // 3. Layer 3: Vibrant Solid LED Diode Core
            ctx.setFillColor(color.cgColor)
            let dotRect = CGRect(x: center.x - size / 2.0, y: center.y - size / 2.0, width: size, height: size)
            ctx.fillEllipse(in: dotRect)

            // 4. Layer 4: Specular LED Lens Highlight / Glaze Hotspot
            let highlightSize: CGFloat = size * 0.40
            let highlightCenter = CGPoint(x: center.x - size * 0.16, y: center.y + size * 0.16)
            let highlightColor = NSColor.white.withAlphaComponent(0.50 + (0.30 * pulseFactor)).cgColor
            let highlightClear = NSColor.white.withAlphaComponent(0.0).cgColor

            if let highlightGradient = CGGradient(colorsSpace: colorSpace, colors: [highlightColor, highlightClear] as CFArray, locations: [0.0, 1.0]) {
                ctx.drawRadialGradient(
                    highlightGradient,
                    startCenter: highlightCenter,
                    startRadius: 0.0,
                    endCenter: highlightCenter,
                    endRadius: highlightSize,
                    options: .drawsAfterEndLocation
                )
            }

            return true
        }
        img.isTemplate = false
        return img
    }
}
