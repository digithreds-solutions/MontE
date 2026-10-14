import Foundation
import Observation

// MARK: - ViewModel

/// Central state store. @Observable drives both the NSMenu rebuild and the SwiftUI dashboard.
@Observable
@MainActor
final class MonteViewModel {

    private(set) var health: SystemHealth
    var settings: MonteSettings {
        didSet {
            MonteSettingsStore.shared.settings = settings
        }
    }
    var logRetentionDays: Int = 7
    var keepAwake = KeepAwakeService.shared

    var showSettingsSheet: Bool = false
    var showStorageInspectorSheet: Bool = false
    var showProcessInvestigatorSheet: Bool = false
    var selectedSettingsTab: SettingsTab = .general
    var selectedKeepAwakeSubTab: KeepAwakeSettingsSubTab = .session
    var selectedDashboardTab: DashboardTab = .overview
    var cleaningProgress: CleaningProgressState = CleaningProgressState()
    var investigatorProcesses: [ProcessInvestigatorItem] = []
    var isScanningProcesses: Bool = false

    init() {
        self.settings = MonteSettingsStore.shared.settings

        // Initial instant hardware snapshot synchronously
        let batt = BatteryService.read()
        let cpu  = SystemStatsService.shared.readCPU()
        let therm = SystemStatsService.readThermal()
        let swap = SystemStatsService.readSwap()
        let ram  = SystemStatsService.readRAM()
        let disk = SystemStatsService.readDiskSpace()
        let topProc = SystemStatsService.shared.readTopMemoryProcess()
        let net = SystemStatsService.shared.readNetworkBandwidth()
        let ssdDriver = SystemStatsService.readIOBlockStorageDriverStats()
        let gpu = GPUService.shared.readGPU()
        let cores = SystemStatsService.shared.readProcessorCores()
        let bt = BluetoothBatteryService.shared.readConnectedDevices()
        let fans = SensorService.shared.readFans()
        let wifi = NetworkDiagnosticsService.shared.readWiFi()
        let volumes = StorageVolumeService.shared.readVolumes()

        self.health = SystemHealth(
            batteryPercent: batt.percent,
            isCharging: batt.isCharging,
            isAcPower: batt.isAcPower,
            batteryCycles: batt.cycleCount,
            batteryCondition: batt.condition,
            batteryHealthPercent: batt.healthPercent,
            batteryDesignCapacityMah: batt.designCapacityMah,
            batteryMaxCapacityMah: batt.maxCapacityMah,
            batteryCurrentCapacityMah: batt.currentCapacityMah,
            batteryTemperatureCelsius: batt.temperatureCelsius,
            batteryVoltageVolts: batt.voltageVolts,
            batteryDesignCycles: batt.designCycles,
            cpuUsagePercent: cpu,
            thermalStatus: therm,
            swapTotalMb: swap.totalMb,
            swapUsedMb: swap.usedMb,
            swapFreeMb: swap.freeMb,
            ramUsedGb: ram.usedGb,
            ramTotalGb: ram.totalGb,
            ssdBytesWrittenGb: ssdDriver.bytesWrittenGb,
            ssdBytesReadGb: ssdDriver.bytesReadGb,
            ssdWriteOperations: ssdDriver.writeOps,
            ssdReadOperations: ssdDriver.readOps,
            diskFreeGb: disk.freeGb,
            diskTotalGb: disk.totalGb,
            diskUsedPercent: disk.usedPercent,
            topProcessName: topProc.name,
            topProcessRamMb: topProc.ramMb,
            networkDownloadKbSec: net.downloadKbSec,
            networkUploadKbSec: net.uploadKbSec,
            gpu: gpu,
            processorCores: cores,
            bluetoothDevices: bt,
            fans: fans,
            wifi: wifi,
            mountedVolumes: volumes,
            cpuHistory: [cpu],
            gpuHistory: [gpu.deviceUtilizationPercent],
            ramHistory: [(ram.usedGb / max(ram.totalGb, 1.0)) * 100.0],
            networkHistory: [net.downloadKbSec]
        )

        WatchdogAlertService.shared.requestNotificationPermissions()
    }

    // MARK: - Menu Bar Title String (Dynamic Multi-Metric Combination)

    var menuBarTitle: String {
        var segments: [String] = []

        // 1. Keep-Awake icon if active
        if keepAwake.isActive {
            segments.append("☕")
        }

        // 2. RAM (Default: ON)
        if settings.showMenuBarRAM {
            if settings.ramDisplayInPercent {
                segments.append(String(format: "%.0f%%", health.ramPercent))
            } else {
                segments.append(String(format: "%.1fG", health.ramUsedGb))
            }
        }

        // 3. GPU Usage (Optional opt-in token)
        if settings.showMenuBarGPU && health.gpu.isAvailable {
            segments.append(String(format: "GPU %.0f%%", health.gpu.deviceUtilizationPercent))
        }

        // 4. CPU Usage
        if settings.showMenuBarCPU {
            segments.append(String(format: "CPU %.0f%%", health.cpuUsagePercent))
        }

        // 5. SSD Swap Usage
        if settings.showMenuBarSwap {
            let swapGb = health.swapUsedMb / 1024.0
            segments.append(String(format: "Swp %.1fG", swapGb))
        }

        // 6. Thermal Throttling Status
        if settings.showMenuBarThermal {
            segments.append("\(health.thermalStatus.emoji) \(health.thermalStatus.rawValue)")
        }

        // 7. Battery
        if settings.showMenuBarBattery {
            let icon = health.isCharging ? "⚡" : "🔋"
            segments.append("\(icon)\(health.batteryPercent)%")
        }

        if segments.isEmpty {
            return health.overallHealth.emoji
        }

        return segments.joined(separator: " ")
    }

    // MARK: - Refresh

    func refresh(forceStorage: Bool = false) async {
        let battery = settings.monitorBattery ? BatteryService.read() : BatteryService.BatteryInfo()
        let cpu     = settings.monitorCPU ? SystemStatsService.shared.readCPU() : 0.0
        let therm   = settings.monitorThermal ? SystemStatsService.readThermal() : .nominal
        let swap    = settings.monitorSwap ? SystemStatsService.readSwap() : SystemStatsService.SwapInfo()
        let ram     = settings.monitorMemory ? SystemStatsService.readRAM() : SystemStatsService.RAMInfo()
        let disk    = SystemStatsService.readDiskSpace()
        let topProc = SystemStatsService.shared.readTopMemoryProcess()
        let net     = SystemStatsService.shared.readNetworkBandwidth()
        let ssdDriver = SystemStatsService.readIOBlockStorageDriverStats()

        let swapRisk: SwapRiskLevel = {
            switch swap.usedMb {
            case ..<2000:  return .safe
            case ..<6000:  return .moderate
            default:       return .critical
            }
        }()

        // 1. Immediately apply real-time hardware metrics (Mach/IOKit fast path <0.1ms)
        health.batteryPercent = battery.percent
        health.isCharging     = battery.isCharging
        health.isAcPower      = battery.isAcPower
        health.batteryCycles  = battery.cycleCount
        health.batteryCondition = battery.condition
        health.batteryHealthPercent = battery.healthPercent
        health.batteryDesignCapacityMah = battery.designCapacityMah
        health.batteryMaxCapacityMah = battery.maxCapacityMah
        health.batteryCurrentCapacityMah = battery.currentCapacityMah
        health.batteryTemperatureCelsius = battery.temperatureCelsius
        health.batteryVoltageVolts = battery.voltageVolts
        health.batteryDesignCycles = battery.designCycles
        health.ssdBytesWrittenGb = ssdDriver.bytesWrittenGb
        health.ssdBytesReadGb = ssdDriver.bytesReadGb
        health.ssdWriteOperations = ssdDriver.writeOps
        health.ssdReadOperations = ssdDriver.readOps
        health.cpuUsagePercent = cpu
        health.thermalStatus  = therm
        health.swapTotalMb    = swap.totalMb
        health.swapUsedMb     = swap.usedMb
        health.swapFreeMb     = swap.freeMb
        health.swapRisk       = swapRisk
        health.ramUsedGb      = ram.usedGb
        health.ramTotalGb     = ram.totalGb
        health.diskFreeGb     = disk.freeGb
        health.diskTotalGb    = disk.totalGb
        health.diskUsedPercent = disk.usedPercent
        health.topProcessName = topProc.name
        health.topProcessRamMb = topProc.ramMb
        health.networkDownloadKbSec = net.downloadKbSec
        health.networkUploadKbSec = net.uploadKbSec

        // Update Mont-E v2 hardware metrics (IOAccelerator, Mach host_processor_info, IOBluetooth, Sensors)
        let gpu = GPUService.shared.readGPU()
        let cores = SystemStatsService.shared.readProcessorCores()
        let bt = BluetoothBatteryService.shared.readConnectedDevices()
        let fans = SensorService.shared.readFans()
        let wifi = NetworkDiagnosticsService.shared.readWiFi()
        let volumes = StorageVolumeService.shared.readVolumes()

        health.gpu = gpu
        health.processorCores = cores
        health.bluetoothDevices = bt
        health.fans = fans
        health.wifi = wifi
        health.mountedVolumes = volumes

        // Buffer rolling history samples (max 30 points)
        health.cpuHistory.append(cpu)
        if health.cpuHistory.count > 30 { health.cpuHistory.removeFirst() }

        health.gpuHistory.append(gpu.deviceUtilizationPercent)
        if health.gpuHistory.count > 30 { health.gpuHistory.removeFirst() }

        health.ramHistory.append(health.ramPercent)
        if health.ramHistory.count > 30 { health.ramHistory.removeFirst() }

        health.networkHistory.append(net.downloadKbSec)
        if health.networkHistory.count > 30 { health.networkHistory.removeFirst() }

        // Evaluate proactive watchdog alerts
        WatchdogAlertService.shared.evaluate(health: health, settings: settings.watchdog)

        // Check Keep-Awake safety thresholds & auto-triggers
        keepAwake.evaluateSafetyAndTriggers(
            batteryPercent: battery.percent,
            isAcPower: battery.isAcPower,
            thermalStatus: therm,
            daemonCount: health.daemons.count,
            downloadKbSec: net.downloadKbSec
        )

        // 2. Fetch secondary disk & daemon metrics in background without blocking UI
        let monitorGradle = settings.monitorGradle
        let monitorStorage = settings.monitorAgentStorage
        let monitorBattery = settings.monitorBattery

        let (storage, daemons, batteryLimitInfo, helpers, nvmeSmart) = await Task.detached(priority: .utility) {
            let s = monitorStorage ? StorageService.readMetrics(force: forceStorage) : StorageMetrics()
            let d = monitorGradle ? GradleService.listDaemons() : []
            let l = monitorBattery ? StorageService.readBatteryLimit() : (limit: nil, isInstalled: false)
            let h = StorageService.readHelperStatus()
            let nvme = SystemStatsService.readNVMeSmartInfo()
            return (s, d, l, h, nvme)
        }.value

        // Update secondary metrics
        health.storage = storage
        health.daemons = daemons
        health.batteryLimit = batteryLimitInfo.limit
        health.isBatteryLimiterInstalled = batteryLimitInfo.isInstalled
        health.helpers = helpers

        // Update NVMe SMART metrics
        health.ssdModelName = nvmeSmart.modelName
        health.ssdSmartStatus = nvmeSmart.smartStatus
        health.ssdPercentageUsed = nvmeSmart.percentageUsed
        health.ssdAvailableSparePercent = nvmeSmart.availableSpare
        health.ssdLifetimeBytesWrittenTb = nvmeSmart.lifetimeWrittenTb
        health.ssdLifetimeBytesReadTb = nvmeSmart.lifetimeReadTb
        health.ssdPowerCycles = nvmeSmart.powerCycles
        health.ssdPowerOnHours = nvmeSmart.powerOnHours
        health.ssdTemperatureCelsius = nvmeSmart.tempCelsius
        health.ssdUnsafeShutdowns = nvmeSmart.unsafeShutdowns
        health.ssdMediaErrors = nvmeSmart.mediaErrors

        // Limiter Watchdog Enforcement
        if settings.enforceBatteryLimitWatchdog, let target = batteryLimitInfo.limit {
            let curPct = battery.percent
            let isChg = battery.isCharging
            let autoD = settings.autoDischargeToLimit
            Task.detached(priority: .utility) {
                StorageService.enforceWatchdog(currentPercent: curPct, isCharging: isChg, targetLimit: target, autoDischarge: autoD)
            }
        }
    }

    // MARK: - Actions

    @discardableResult
    func setBatteryLimit(_ pct: Int, forceDischarge: Bool? = nil) async -> (success: Bool, message: String) {
        let shouldDischarge = forceDischarge ?? settings.autoDischargeToLimit
        let result = await Task.detached(priority: .userInitiated) {
            StorageService.setBatteryLimit(pct, forceDischarge: shouldDischarge)
        }.value
        if result.success {
            health.batteryLimit = pct
            health.isBatteryLimiterInstalled = true
            settings.targetBatteryLimit = pct
        }
        return result
    }

    @discardableResult
    func forceDischargeNow() async -> (success: Bool, message: String) {
        guard let limit = health.batteryLimit, limit < 100 else {
            return (false, "No active limit to discharge to.")
        }
        return await setBatteryLimit(limit, forceDischarge: true)
    }

    func installBatteryTool() {
        StorageService.installBatteryTool()
    }

    /// Returns daemon count that was stopped.
    func stopGradleDaemons() async -> Int {
        let count = await Task.detached(priority: .userInitiated) {
            GradleService.stopAll()
        }.value
        health.daemons = []
        return count
    }

    func pruneLogs(days: Int) async -> String {
        cleaningProgress = CleaningProgressState(
            isCleaning: true,
            currentStep: 1,
            totalSteps: 2,
            statusText: "Pruning agent logs older than \(days) days…",
            activeItemKey: "antigravity"
        )
        let msg = await Task.detached(priority: .utility) {
            StorageService.pruneLogs(olderThanDays: days)
        }.value

        cleaningProgress = CleaningProgressState(
            isCleaning: true,
            currentStep: 2,
            totalSteps: 2,
            statusText: "Recalculating storage sizes…",
            activeItemKey: nil
        )
        await refresh(forceStorage: true)
        cleaningProgress = CleaningProgressState()
        return msg
    }

    func cleanDerivedData() async -> String {
        cleaningProgress = CleaningProgressState(
            isCleaning: true,
            currentStep: 1,
            totalSteps: 2,
            statusText: "Purging Xcode DerivedData build caches…",
            activeItemKey: "xcode"
        )
        let msg = await Task.detached(priority: .utility) {
            StorageService.cleanXcodeDerivedData()
        }.value

        cleaningProgress = CleaningProgressState(
            isCleaning: true,
            currentStep: 2,
            totalSteps: 2,
            statusText: "Recalculating storage sizes…",
            activeItemKey: nil
        )
        await refresh(forceStorage: true)
        cleaningProgress = CleaningProgressState()
        return msg
    }

    func cleanStorageItem(key: String, days: Int? = nil) async -> String {
        let name: String = {
            switch key {
            case "antigravity": return "Google Antigravity brain logs"
            case "claude": return "Claude Desktop logs & cache"
            case "xcode": return "Xcode DerivedData build cache"
            case "gradle_cache": return "Gradle dependency transforms"
            case "gradle_daemons": return "Gradle daemon log files"
            case "cocoapods": return "CocoaPods cache"
            default: return "developer logs"
            }
        }()

        cleaningProgress = CleaningProgressState(
            isCleaning: true,
            currentStep: 1,
            totalSteps: 2,
            statusText: "Cleaning \(name)…",
            activeItemKey: key
        )

        let msg = await Task.detached(priority: .utility) {
            switch key {
            case "antigravity":
                return StorageService.cleanAntigravityLogs(olderThanDays: days)
            case "claude":
                return StorageService.cleanClaudeLogs()
            case "xcode":
                return StorageService.cleanXcodeDerivedData()
            case "gradle_cache":
                return StorageService.cleanGradleCaches()
            case "gradle_daemons":
                return StorageService.cleanGradleDaemonLogs()
            case "cocoapods":
                return StorageService.cleanCocoaPodsCache()
            default:
                return StorageService.pruneLogs(olderThanDays: days ?? 7)
            }
        }.value

        cleaningProgress = CleaningProgressState(
            isCleaning: true,
            currentStep: 2,
            totalSteps: 2,
            statusText: "Recalculating storage sizes…",
            activeItemKey: nil
        )
        await refresh(forceStorage: true)
        cleaningProgress = CleaningProgressState()
        return msg
    }

    func revealStorageInFinder(path: String) {
        StorageService.revealInFinder(path: path)
    }

    func cleanAllStorage() async -> String {
        let days = self.logRetentionDays
        let totalSteps = 6

        // Step 1: Antigravity logs
        cleaningProgress = CleaningProgressState(
            isCleaning: true,
            currentStep: 1,
            totalSteps: totalSteps,
            statusText: "Pruning Antigravity agent brain logs (>\(days)d)…",
            activeItemKey: "antigravity"
        )
        let ag = await Task.detached(priority: .utility) {
            StorageService.cleanAntigravityLogs(olderThanDays: days)
        }.value

        // Step 2: Claude logs
        cleaningProgress = CleaningProgressState(
            isCleaning: true,
            currentStep: 2,
            totalSteps: totalSteps,
            statusText: "Cleaning Claude Desktop logs & caches…",
            activeItemKey: "claude"
        )
        let cl = await Task.detached(priority: .utility) {
            StorageService.cleanClaudeLogs()
        }.value

        // Step 3: Xcode DerivedData
        cleaningProgress = CleaningProgressState(
            isCleaning: true,
            currentStep: 3,
            totalSteps: totalSteps,
            statusText: "Purging Xcode DerivedData build artifacts…",
            activeItemKey: "xcode"
        )
        let xc = await Task.detached(priority: .utility) {
            StorageService.cleanXcodeDerivedData()
        }.value

        // Step 4: Gradle caches
        cleaningProgress = CleaningProgressState(
            isCleaning: true,
            currentStep: 4,
            totalSteps: totalSteps,
            statusText: "Cleaning Gradle transforms and build caches…",
            activeItemKey: "gradle_cache"
        )
        let gc = await Task.detached(priority: .utility) {
            StorageService.cleanGradleCaches()
        }.value

        // Step 5: Gradle daemon logs
        cleaningProgress = CleaningProgressState(
            isCleaning: true,
            currentStep: 5,
            totalSteps: totalSteps,
            statusText: "Clearing Gradle worker daemon logs…",
            activeItemKey: "gradle_daemons"
        )
        let gd = await Task.detached(priority: .utility) {
            StorageService.cleanGradleDaemonLogs()
        }.value

        // Step 6: Recalculate
        cleaningProgress = CleaningProgressState(
            isCleaning: true,
            currentStep: 6,
            totalSteps: totalSteps,
            statusText: "Rescanning storage sizes…",
            activeItemKey: nil
        )
        await refresh(forceStorage: true)
        cleaningProgress = CleaningProgressState()

        return "\(ag) • \(cl) • \(xc) • \(gc) • \(gd)"
    }

    @discardableResult
    func optimizeMemory() async -> String {
        let result = await Task.detached(priority: .userInitiated) {
            await MemoryOptimizerService.shared.optimizeMemory()
        }.value
        await refresh(forceStorage: false)
        return result.details
    }

    func optimizeAll() async -> String {
        let memResult = await optimizeMemory()
        let days = self.logRetentionDays
        let logMsg = await Task.detached(priority: .utility) {
            StorageService.pruneLogs(olderThanDays: days)
        }.value
        await refresh(forceStorage: true)
        return "\(memResult) • \(logMsg)"
    }

    // MARK: - Process Investigator Actions

    func fetchInvestigatorProcesses() async {
        isScanningProcesses = true
        let (list, topCpu, topDisk, topRam) = await Task.detached(priority: .userInitiated) {
            let l = SystemStatsService.shared.readInvestigatorProcesses()
            let c = SystemStatsService.shared.readTopCpuProcesses()
            let d = SystemStatsService.shared.readTopDiskWriters()
            let m = SystemStatsService.shared.readTopMemoryProcesses()
            return (l, c, d, m)
        }.value
        investigatorProcesses = list
        health.topCpuProcesses = topCpu
        health.topDiskProcesses = topDisk
        health.topMemoryProcesses = topRam
        isScanningProcesses = false
    }

    @discardableResult
    func killInvestigatorProcess(pid: Int32, force: Bool = false) async -> String {
        let targetName = investigatorProcesses.first(where: { $0.pid == pid })?.displayName ?? "Process \(pid)"
        _ = await Task.detached(priority: .userInitiated) {
            SystemStatsService.shared.killProcess(pid: pid, force: force)
        }.value
        await fetchInvestigatorProcesses()
        await refresh(forceStorage: false)
        return "Terminated \(targetName) (PID \(pid))"
    }

    @discardableResult
    func killAllSafeDaemons() async -> String {
        let count = await Task.detached(priority: .userInitiated) {
            SystemStatsService.shared.killAllSafeDaemons()
        }.value
        await fetchInvestigatorProcesses()
        await refresh(forceStorage: false)
        return "Terminated \(count) idle background developer daemon\(count == 1 ? "" : "s")"
    }
}
