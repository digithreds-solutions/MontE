import Foundation

// MARK: - Settings Tab Navigation

enum SettingsTab: String, Codable, CaseIterable, Identifiable {
    case general = "General"
    case keepAwake = "Keep-Awake"
    case battery = "Battery & SMC"
    case menuBarHud = "Menu Bar & HUD"
    case devTools = "Dev Tools"
    case about = "About"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .keepAwake: return "cup.and.saucer.fill"
        case .battery: return "battery.100.bolt"
        case .menuBarHud: return "menubar.rectangle"
        case .devTools: return "hammer"
        case .about: return "info.circle"
        }
    }
}

// MARK: - Keep-Awake Sub-Sections

enum KeepAwakeSettingsSubTab: String, Codable, CaseIterable, Identifiable {
    case session = "Sessions & Durations"
    case display = "Display & Sleep"
    case builds = "Dev Builds & Daemons"
    case triggers = "Triggers & Automation"
    case safety = "Hardware Safety"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .session: return "clock.arrow.circlepath"
        case .display: return "display"
        case .builds: return "hammer.fill"
        case .triggers: return "bolt.badge.automatic"
        case .safety: return "shield.lefthalf.filled"
        }
    }
}

// MARK: - HUD Configuration

public enum HUDLayoutMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case grid2Column = "2-Column Grid"
    case compactList = "Compact List"

    public var id: String { rawValue }
}

public enum HUDMenuSize: String, Codable, CaseIterable, Identifiable, Sendable {
    case small = "Small"
    case medium = "Medium"
    case large = "Large"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium (Default)"
        case .large: return "Large"
        }
    }

    public func menuWidth(for mode: HUDLayoutMode) -> CGFloat {
        if mode == .compactList {
            switch self {
            case .small: return 260
            case .medium: return 285
            case .large: return 305
            }
        } else {
            switch self {
            case .small: return 304
            case .medium: return 332
            case .large: return 356
            }
        }
    }

    public var tileHeight: CGFloat {
        switch self {
        case .small: return 48
        case .medium: return 52
        case .large: return 56
        }
    }

    public var networkStripHeight: CGFloat {
        switch self {
        case .small: return 42
        case .medium: return 45
        case .large: return 48
        }
    }

    public var titleFontSize: CGFloat {
        switch self {
        case .small: return 10
        case .medium: return 10.5
        case .large: return 11
        }
    }

    public var valueFontSize: CGFloat {
        switch self {
        case .small: return 12
        case .medium: return 12.5
        case .large: return 13.5
        }
    }

    public var detailFontSize: CGFloat {
        switch self {
        case .small: return 8.5
        case .medium: return 9.5
        case .large: return 10
        }
    }

    public var iconFontSize: CGFloat {
        switch self {
        case .small: return 12.5
        case .medium: return 13.5
        case .large: return 14.5
        }
    }
}

public struct HUDSettings: Codable, Equatable, Sendable {
    public var showCPU: Bool = true
    public var showMemory: Bool = true
    public var showSwap: Bool = true
    public var showBattery: Bool = true
    public var showGradle: Bool = false        // Default: OFF unless explicitly configured by developer
    public var showAgentStorage: Bool = true
    public var showDiskSpace: Bool = false     // Safe statvfs APFS free space
    public var showTopProcess: Bool = false    // Safe proc_pidinfo top RAM consumer
    public var showBatteryHealth: Bool = false // Battery cycles & condition
    public var showSsdHealth: Bool = false     // SSD wear & TBW write cycles
    public var showNetworkIO: Bool = false     // Active interface I/O bandwidth
    public var showXcodeDerivedData: Bool = false // Cached Xcode DerivedData size
    public var showGPU: Bool = true               // Real-time GPU & Apple Silicon Accelerator
    public var showCoreGrid: Bool = true          // Apple Silicon P-Core vs E-Core breakdown
    public var showBluetooth: Bool = true         // Connected Bluetooth accessories (AirPods, Mouse, etc.)
    public var showFans: Bool = false             // Fan speeds & cooling state
    public var showWiFi: Bool = true              // Wi-Fi SSID, RSSI dBm & link quality
    public var showMountedVolumes: Bool = false   // External storage & mounted volumes
    public var layoutMode: HUDLayoutMode = .grid2Column
    public var menuSize: HUDMenuSize = .medium    // Default: Medium!
    public var showQuickKillButtons: Bool = true

    public init(
        showCPU: Bool = true,
        showMemory: Bool = true,
        showSwap: Bool = true,
        showBattery: Bool = true,
        showGradle: Bool = false,
        showAgentStorage: Bool = true,
        showDiskSpace: Bool = false,
        showTopProcess: Bool = false,
        showBatteryHealth: Bool = false,
        showSsdHealth: Bool = false,
        showNetworkIO: Bool = false,
        showXcodeDerivedData: Bool = false,
        showGPU: Bool = true,
        showCoreGrid: Bool = true,
        showBluetooth: Bool = true,
        showFans: Bool = false,
        showWiFi: Bool = true,
        showMountedVolumes: Bool = false,
        layoutMode: HUDLayoutMode = .grid2Column,
        menuSize: HUDMenuSize = .medium,
        showQuickKillButtons: Bool = true
    ) {
        self.showCPU = showCPU
        self.showMemory = showMemory
        self.showSwap = showSwap
        self.showBattery = showBattery
        self.showGradle = showGradle
        self.showAgentStorage = showAgentStorage
        self.showDiskSpace = showDiskSpace
        self.showTopProcess = showTopProcess
        self.showBatteryHealth = showBatteryHealth
        self.showSsdHealth = showSsdHealth
        self.showNetworkIO = showNetworkIO
        self.showXcodeDerivedData = showXcodeDerivedData
        self.showGPU = showGPU
        self.showCoreGrid = showCoreGrid
        self.showBluetooth = showBluetooth
        self.showFans = showFans
        self.showWiFi = showWiFi
        self.showMountedVolumes = showMountedVolumes
        self.layoutMode = layoutMode
        self.menuSize = menuSize
        self.showQuickKillButtons = showQuickKillButtons
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.showCPU = try container.decodeIfPresent(Bool.self, forKey: .showCPU) ?? true
        self.showMemory = try container.decodeIfPresent(Bool.self, forKey: .showMemory) ?? true
        self.showSwap = try container.decodeIfPresent(Bool.self, forKey: .showSwap) ?? true
        self.showBattery = try container.decodeIfPresent(Bool.self, forKey: .showBattery) ?? true
        self.showGradle = try container.decodeIfPresent(Bool.self, forKey: .showGradle) ?? false
        self.showAgentStorage = try container.decodeIfPresent(Bool.self, forKey: .showAgentStorage) ?? true
        self.showDiskSpace = try container.decodeIfPresent(Bool.self, forKey: .showDiskSpace) ?? false
        self.showTopProcess = try container.decodeIfPresent(Bool.self, forKey: .showTopProcess) ?? false
        self.showBatteryHealth = try container.decodeIfPresent(Bool.self, forKey: .showBatteryHealth) ?? false
        self.showSsdHealth = try container.decodeIfPresent(Bool.self, forKey: .showSsdHealth) ?? false
        self.showNetworkIO = try container.decodeIfPresent(Bool.self, forKey: .showNetworkIO) ?? false
        self.showXcodeDerivedData = try container.decodeIfPresent(Bool.self, forKey: .showXcodeDerivedData) ?? false
        self.showGPU = try container.decodeIfPresent(Bool.self, forKey: .showGPU) ?? true
        self.showCoreGrid = try container.decodeIfPresent(Bool.self, forKey: .showCoreGrid) ?? true
        self.showBluetooth = try container.decodeIfPresent(Bool.self, forKey: .showBluetooth) ?? true
        self.showFans = try container.decodeIfPresent(Bool.self, forKey: .showFans) ?? false
        self.showWiFi = try container.decodeIfPresent(Bool.self, forKey: .showWiFi) ?? true
        self.showMountedVolumes = try container.decodeIfPresent(Bool.self, forKey: .showMountedVolumes) ?? false
        self.layoutMode = try container.decodeIfPresent(HUDLayoutMode.self, forKey: .layoutMode) ?? .grid2Column
        self.menuSize = try container.decodeIfPresent(HUDMenuSize.self, forKey: .menuSize) ?? .medium
        self.showQuickKillButtons = try container.decodeIfPresent(Bool.self, forKey: .showQuickKillButtons) ?? true
    }
}

// MARK: - Proactive Watchdog & Threshold Alert Settings

public struct WatchdogAlertSettings: Codable, Equatable {
    public var alertsEnabled: Bool = true
    public var lowDiskAlert: Bool = true
    public var lowDiskThresholdGb: Int = 15      // Alert when free space < 15 GB
    public var highSwapAlert: Bool = true
    public var highSwapThresholdMb: Int = 2048   // Alert when swap > 2 GB
    public var peripheralLowBatteryAlert: Bool = true
    public var peripheralBatteryThreshold: Int = 20 // Alert when mouse/AirPods <= 20%
    public var highThermalAlert: Bool = true     // Alert when thermal state is serious/critical
    public var highCpuAlert: Bool = false        // Alert when CPU sustained > 90%
    public var highCpuThreshold: Int = 90

    public init() {}
}

// MARK: - Dashboard Overview Configuration (Hide / Show / Re-arrange)

public enum DashboardOverviewCardId: String, Codable, CaseIterable, Identifiable {
    case keepAwake
    case battery
    case batteryHealth
    case ssdHealth
    case cpuThermal
    case averageThermal
    case memorySwap
    case gradleDaemons
    case agentStorage
    case gpu
    case bluetooth
    case cores
    case fans
    case keepAwakeDiagnostics
    case wifiNetwork
    case mountedVolumes

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .keepAwake: return "Keep-Awake Quick Controls"
        case .battery: return "Battery & Power Longevity"
        case .batteryHealth: return "Battery Health & Hardware Vitals"
        case .ssdHealth: return "SSD Health & S.M.A.R.T. Wear"
        case .cpuThermal: return "CPU & Thermal Health"
        case .averageThermal: return "Average Thermals & Lifetime History"
        case .memorySwap: return "Memory & Swap"
        case .gradleDaemons: return "Gradle Daemons"
        case .agentStorage: return "Dev Storage Cleaners"
        case .gpu: return "GPU & Graphics Accelerator"
        case .bluetooth: return "Connected Bluetooth Peripherals"
        case .cores: return "Apple Silicon Cores (P/E Load)"
        case .fans: return "Fans & Active Cooling"
        case .keepAwakeDiagnostics: return "Keep-Awake Triggers & Sensors"
        case .wifiNetwork: return "Wi-Fi & Link Quality"
        case .mountedVolumes: return "Mounted Volumes & Dev Drives"
        }
    }

    public var subtitle: String {
        switch self {
        case .keepAwake: return "Active sleep prevention, display & safety policies"
        case .battery: return "Charge limit, adapter power & bypass status"
        case .batteryHealth: return "Cycles, capacity, wear level & temperature"
        case .ssdHealth: return "TBW wear, read/write ops & endurance"
        case .cpuThermal: return "CPU % usage & Apple Silicon thermal zone"
        case .averageThermal: return "Historical PMU gas gauge telemetry, lifetime average & temperature bounds"
        case .memorySwap: return "Unified RAM pressure & swap risk index"
        case .gradleDaemons: return "Active Kotlin/Android daemon processes"
        case .agentStorage: return "AI brain caches & developer artifacts"
        case .gpu: return "Silicon accelerator %, VRAM & architecture"
        case .bluetooth: return "AirPods, Mouse, Keyboard & Trackpad batteries"
        case .cores: return "Individual Performance vs. Efficiency core load"
        case .fans: return "Dual fan RPM speeds & thermal throttling state"
        case .keepAwakeDiagnostics: return "Display, download & power triggers"
        case .wifiNetwork: return "SSID, RSSI (-dBm), SNR, channel & local IP"
        case .mountedVolumes: return "External dev SSDs, APFS volumes & mounted DMGs"
        }
    }

    public var icon: String {
        switch self {
        case .keepAwake: return "cup.and.saucer.fill"
        case .battery: return "battery.100.bolt"
        case .batteryHealth: return "heart.text.square"
        case .ssdHealth: return "internaldrive"
        case .cpuThermal: return "cpu"
        case .averageThermal: return "thermometer.medium"
        case .memorySwap: return "memorychip"
        case .gradleDaemons: return "hammer"
        case .agentStorage: return "folder.badge.gearshape"
        case .gpu: return "display.2"
        case .bluetooth: return "dot.radiowaves.left.and.right"
        case .cores: return "cpu.fill"
        case .fans: return "fanblades"
        case .keepAwakeDiagnostics: return "bolt.badge.automatic"
        case .wifiNetwork: return "wifi"
        case .mountedVolumes: return "externaldrive.connected.to.line.below"
        }
    }
}

public struct DashboardOverviewCardConfig: Codable, Equatable, Identifiable {
    public var id: DashboardOverviewCardId
    public var isVisible: Bool

    public init(id: DashboardOverviewCardId, isVisible: Bool = true) {
        self.id = id
        self.isVisible = isVisible
    }

    public static var defaultCards: [DashboardOverviewCardConfig] {
        [
            DashboardOverviewCardConfig(id: .keepAwake, isVisible: true),
            DashboardOverviewCardConfig(id: .battery, isVisible: true),
            DashboardOverviewCardConfig(id: .batteryHealth, isVisible: true),
            DashboardOverviewCardConfig(id: .ssdHealth, isVisible: true),
            DashboardOverviewCardConfig(id: .cpuThermal, isVisible: true),
            DashboardOverviewCardConfig(id: .averageThermal, isVisible: true),
            DashboardOverviewCardConfig(id: .memorySwap, isVisible: true),
            DashboardOverviewCardConfig(id: .gradleDaemons, isVisible: true),
            DashboardOverviewCardConfig(id: .agentStorage, isVisible: true),
            DashboardOverviewCardConfig(id: .gpu, isVisible: true),
            DashboardOverviewCardConfig(id: .bluetooth, isVisible: true),
            DashboardOverviewCardConfig(id: .cores, isVisible: true),
            DashboardOverviewCardConfig(id: .fans, isVisible: true),
            DashboardOverviewCardConfig(id: .wifiNetwork, isVisible: true),
            DashboardOverviewCardConfig(id: .mountedVolumes, isVisible: true),
            DashboardOverviewCardConfig(id: .keepAwakeDiagnostics, isVisible: false)
        ]
    }
}

public enum DashboardOverviewPreset: String, CaseIterable, Identifiable {
    case recommended = "Recommended Default"
    case siliconHardware = "Hardware & Silicon Focus"
    case batteryPower = "Battery & Power Focus"
    case devCleaners = "Dev Storage & Daemons"
    case allCards = "Show All Cards"

    public var id: String { rawValue }
}

public struct DashboardOverviewSettings: Codable, Equatable {
    public var cards: [DashboardOverviewCardConfig] = DashboardOverviewCardConfig.defaultCards

    public init(cards: [DashboardOverviewCardConfig] = DashboardOverviewCardConfig.defaultCards) {
        self.cards = cards
    }

    /// Guarantees that any newly introduced card IDs exist in the persisted array
    public mutating func sanitize() {
        var existingIds = Set(cards.map(\.id))
        for defaultCard in DashboardOverviewCardConfig.defaultCards {
            if !existingIds.contains(defaultCard.id) {
                cards.append(defaultCard)
                existingIds.insert(defaultCard.id)
            }
        }
    }

    public mutating func moveUp(at index: Int) {
        guard index > 0 && index < cards.count else { return }
        cards.swapAt(index, index - 1)
    }

    public mutating func moveDown(at index: Int) {
        guard index >= 0 && index < cards.count - 1 else { return }
        cards.swapAt(index, index + 1)
    }

    public mutating func moveCard(id: DashboardOverviewCardId, direction: Int) {
        guard let currentIndex = cards.firstIndex(where: { $0.id == id }) else { return }
        let targetIndex = currentIndex + direction
        guard targetIndex >= 0 && targetIndex < cards.count else { return }
        cards.swapAt(currentIndex, targetIndex)
    }

    public mutating func moveVisibleCard(id: DashboardOverviewCardId, direction: Int) {
        let visibleIds = cards.filter(\.isVisible).map(\.id)
        guard let currentVisIndex = visibleIds.firstIndex(of: id) else { return }
        let targetVisIndex = currentVisIndex + direction
        guard targetVisIndex >= 0 && targetVisIndex < visibleIds.count else { return }
        let targetId = visibleIds[targetVisIndex]

        guard let rawCurrent = cards.firstIndex(where: { $0.id == id }),
              let rawTarget = cards.firstIndex(where: { $0.id == targetId }) else { return }
        cards.swapAt(rawCurrent, rawTarget)
    }

    public mutating func setVisible(id: DashboardOverviewCardId, isVisible: Bool) {
        if let idx = cards.firstIndex(where: { $0.id == id }) {
            cards[idx].isVisible = isVisible
        }
    }

    public mutating func toggle(id: DashboardOverviewCardId) {
        if let idx = cards.firstIndex(where: { $0.id == id }) {
            cards[idx].isVisible.toggle()
        }
    }

    public mutating func showAll() {
        for idx in cards.indices {
            cards[idx].isVisible = true
        }
    }

    public mutating func resetToDefaults() {
        cards = DashboardOverviewCardConfig.defaultCards
    }

    public mutating func applyPreset(_ preset: DashboardOverviewPreset) {
        switch preset {
        case .recommended:
            resetToDefaults()
        case .allCards:
            showAll()
        case .siliconHardware:
            let allowed: Set<DashboardOverviewCardId> = [.cpuThermal, .averageThermal, .cores, .gpu, .fans, .memorySwap, .ssdHealth]
            for idx in cards.indices {
                cards[idx].isVisible = allowed.contains(cards[idx].id)
            }
        case .batteryPower:
            let allowed: Set<DashboardOverviewCardId> = [.battery, .batteryHealth, .averageThermal, .keepAwake, .keepAwakeDiagnostics]
            for idx in cards.indices {
                cards[idx].isVisible = allowed.contains(cards[idx].id)
            }
        case .devCleaners:
            let allowed: Set<DashboardOverviewCardId> = [.agentStorage, .gradleDaemons, .memorySwap, .ssdHealth]
            for idx in cards.indices {
                cards[idx].isVisible = allowed.contains(cards[idx].id)
            }
        }
    }
}

// MARK: - Mont-E Configuration & Monitoring Settings

struct MonteSettings: Codable, Equatable {
    // Menu Bar Display Customization (Any combination side-by-side, default: RAM only + Status Dot)
    var showMenuBarStatusDot: Bool = true
    var showMenuBarRAM: Bool = true             // Default: ON
    var showMenuBarCPU: Bool = false
    var showMenuBarGPU: Bool = false            // GPU load % (default: false, keeps menu bar minimal)
    var showMenuBarSwap: Bool = false
    var showMenuBarThermal: Bool = false
    var showMenuBarBattery: Bool = false
    var ramDisplayInPercent: Bool = false       // false = "12.4G", true = "52%"

    // HUD Dropdown Customization
    var hud: HUDSettings = HUDSettings()

    // Dashboard Overview Customization (Hide / Show / Re-arrange)
    var overview: DashboardOverviewSettings = DashboardOverviewSettings()

    // Battery Limiter Settings
    var targetBatteryLimit: Int? = 80           // Persistent target charge limit (70, 75, 80, 100), survives reboots
    var autoDischargeToLimit: Bool = false      // Automatically force-discharge battery down to target limit when above cap
    var directPowerPassThrough: Bool = true     // Direct AC Power Pass-Through (Bypass battery charging once cap is reached)
    var enforceBatteryLimitWatchdog: Bool = true // Watchdog: re-assert SMC limit if macOS resets charging state

    // System Startup & General
    var launchAtLogin: Bool = true

    // Active monitoring toggles for cards/services
    var monitorBattery: Bool = true
    var monitorCPU: Bool = true
    var monitorMemory: Bool = true
    var monitorSwap: Bool = true
    var monitorThermal: Bool = true
    var monitorGradle: Bool = true
    var monitorPython: Bool = false
    var monitorAgentStorage: Bool = true

    // Proactive Watchdog & Threshold Alerts
    var watchdog: WatchdogAlertSettings = WatchdogAlertSettings()

    init() {}

    private enum CodingKeys: String, CodingKey {
        case showMenuBarStatusDot, showMenuBarRAM, showMenuBarCPU, showMenuBarGPU
        case showMenuBarSwap, showMenuBarThermal, showMenuBarBattery, ramDisplayInPercent
        case hud, overview, watchdog
        case targetBatteryLimit, autoDischargeToLimit, directPowerPassThrough, enforceBatteryLimitWatchdog
        case launchAtLogin
        case monitorBattery, monitorCPU, monitorMemory, monitorSwap, monitorThermal
        case monitorGradle, monitorPython, monitorAgentStorage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showMenuBarStatusDot = try container.decodeIfPresent(Bool.self, forKey: .showMenuBarStatusDot) ?? true
        showMenuBarRAM = try container.decodeIfPresent(Bool.self, forKey: .showMenuBarRAM) ?? true
        showMenuBarCPU = try container.decodeIfPresent(Bool.self, forKey: .showMenuBarCPU) ?? false
        showMenuBarGPU = try container.decodeIfPresent(Bool.self, forKey: .showMenuBarGPU) ?? false
        showMenuBarSwap = try container.decodeIfPresent(Bool.self, forKey: .showMenuBarSwap) ?? false
        showMenuBarThermal = try container.decodeIfPresent(Bool.self, forKey: .showMenuBarThermal) ?? false
        showMenuBarBattery = try container.decodeIfPresent(Bool.self, forKey: .showMenuBarBattery) ?? false
        ramDisplayInPercent = try container.decodeIfPresent(Bool.self, forKey: .ramDisplayInPercent) ?? false
        hud = try container.decodeIfPresent(HUDSettings.self, forKey: .hud) ?? HUDSettings()
        var loadedOverview = try container.decodeIfPresent(DashboardOverviewSettings.self, forKey: .overview) ?? DashboardOverviewSettings()
        loadedOverview.sanitize()
        overview = loadedOverview
        watchdog = try container.decodeIfPresent(WatchdogAlertSettings.self, forKey: .watchdog) ?? WatchdogAlertSettings()
        targetBatteryLimit = try container.decodeIfPresent(Int.self, forKey: .targetBatteryLimit) ?? 80
        autoDischargeToLimit = try container.decodeIfPresent(Bool.self, forKey: .autoDischargeToLimit) ?? false
        directPowerPassThrough = try container.decodeIfPresent(Bool.self, forKey: .directPowerPassThrough) ?? true
        enforceBatteryLimitWatchdog = try container.decodeIfPresent(Bool.self, forKey: .enforceBatteryLimitWatchdog) ?? true
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? true
        monitorBattery = try container.decodeIfPresent(Bool.self, forKey: .monitorBattery) ?? true
        monitorCPU = try container.decodeIfPresent(Bool.self, forKey: .monitorCPU) ?? true
        monitorMemory = try container.decodeIfPresent(Bool.self, forKey: .monitorMemory) ?? true
        monitorSwap = try container.decodeIfPresent(Bool.self, forKey: .monitorSwap) ?? true
        monitorThermal = try container.decodeIfPresent(Bool.self, forKey: .monitorThermal) ?? true
        monitorGradle = try container.decodeIfPresent(Bool.self, forKey: .monitorGradle) ?? true
        monitorPython = try container.decodeIfPresent(Bool.self, forKey: .monitorPython) ?? false
        monitorAgentStorage = try container.decodeIfPresent(Bool.self, forKey: .monitorAgentStorage) ?? true
    }

    static var `default`: MonteSettings {
        MonteSettings()
    }
}

// MARK: - Settings Store

final class MonteSettingsStore: @unchecked Sendable {
    static let shared = MonteSettingsStore()
    private let key = "MontESettings_v2"
    private let defaults = UserDefaults.standard

    var settings: MonteSettings {
        get {
            guard
                let data = defaults.data(forKey: key),
                let decoded = try? JSONDecoder().decode(MonteSettings.self, from: data)
            else {
                return .default
            }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: key)
            }
        }
    }
}


