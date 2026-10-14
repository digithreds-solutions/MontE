import Foundation
import SwiftUI

// MARK: - Overall System Health Level

enum SystemHealthLevel: String, CaseIterable, Codable {
    case optimal  = "Optimal"
    case good     = "Good"
    case fair     = "Fair"
    case strained = "Strained"
    case critical = "Critical"

    var emoji: String {
        switch self {
        case .optimal:  return "🟢"
        case .good:     return "🟢"
        case .fair:     return "🟡"
        case .strained: return "🟠"
        case .critical: return "🔴"
        }
    }

    var colorHex: UInt32 {
        switch self {
        case .optimal:  return 0x34D399  // Luminous Emerald LED (#34D399)
        case .good:     return 0x4ADE80  // Bright Mint LED (#4ADE80)
        case .fair:     return 0xFBBF24  // Bright Amber / Gold LED (#FBBF24)
        case .strained: return 0xFB923C  // Neon Tangerine LED (#FB923C)
        case .critical: return 0xEF4444  // Intense Ruby LED (#EF4444)
        }
    }

    var color: Color {
        Color(
            red:   Double((colorHex >> 16) & 0xFF) / 255,
            green: Double((colorHex >> 8)  & 0xFF) / 255,
            blue:  Double( colorHex        & 0xFF) / 255
        )
    }

    var nsColor: NSColor {
        NSColor(
            red:   CGFloat((colorHex >> 16) & 0xFF) / 255.0,
            green: CGFloat((colorHex >> 8)  & 0xFF) / 255.0,
            blue:  CGFloat( colorHex        & 0xFF) / 255.0,
            alpha: 1.0
        )
    }

    var description: String {
        switch self {
        case .optimal:  return "System running smoothly & cool"
        case .good:     return "Normal developer workload"
        case .fair:     return "Moderate memory/thermal load"
        case .strained: return "High memory pressure or CPU load"
        case .critical: return "Critical memory swap or thermal throttling"
        }
    }
}

// MARK: - Swap Risk

enum SwapRiskLevel {
    case safe       // 0–2 GB used
    case moderate   // 2–6 GB used
    case critical   // >6 GB used

    var label: String {
        switch self {
        case .safe:     return "SAFE"
        case .moderate: return "MODERATE"
        case .critical: return "CRITICAL"
        }
    }
}

// MARK: - Thermal Status

enum ThermalStatus: String, CaseIterable, Codable {
    case nominal = "Nominal"
    case fair = "Fair"
    case serious = "Serious"
    case critical = "Critical"

    var emoji: String {
        switch self {
        case .nominal: return "🟢"
        case .fair: return "🟡"
        case .serious: return "🟠"
        case .critical: return "🔴"
        }
    }

    var description: String {
        switch self {
        case .nominal: return "Cool / Normal"
        case .fair: return "Warm / Minor Heat"
        case .serious: return "High Heat / Fan Active"
        case .critical: return "Thermal Throttling Active"
        }
    }
}

struct GradleDaemonInfo: Identifiable {
    let id = UUID()
    let pid: String
    let maxHeap: String
    let version: String
    var details: String { "PID \(pid) (\(maxHeap) heap)" }
}

struct StorageBreakdownItem: Identifiable {
    var id: String { key }
    let key: String
    let name: String
    let category: String
    let path: String
    let sizeMb: Double
    let whyDescription: String
    let iconName: String
    let canPruneWithDays: Bool
}

struct CleaningProgressState: Equatable {
    var isCleaning: Bool = false
    var currentStep: Int = 0
    var totalSteps: Int = 0
    var statusText: String = ""
    var activeItemKey: String? = nil

    var progressRatio: Double {
        guard totalSteps > 0 else { return 0.0 }
        return Double(currentStep) / Double(totalSteps)
    }
}

struct StorageMetrics {
    var antigravityBrainMb: Double = 0
    var claudeLogsMb: Double = 0
    var claudeCacheMb: Double = 0
    var gradleCachesGb: Double = 0
    var gradleDaemonLogsMb: Double = 0
    var xcodeDerivedDataGb: Double = 0
    var cocoapodsCacheMb: Double = 0

    var totalReclaimableMb: Double {
        antigravityBrainMb + claudeLogsMb + claudeCacheMb + (gradleCachesGb * 1024.0) + gradleDaemonLogsMb + (xcodeDerivedDataGb * 1024.0) + cocoapodsCacheMb
    }

    var totalReclaimableFormatted: String {
        if totalReclaimableMb >= 1024.0 {
            return String(format: "%.1f GB", totalReclaimableMb / 1024.0)
        } else {
            return String(format: "%.0f MB", totalReclaimableMb)
        }
    }

    func getBreakdownItems(home: String) -> [StorageBreakdownItem] {
        return [
            StorageBreakdownItem(
                key: "antigravity",
                name: "Google Antigravity Agent Brain",
                category: "AI Agent Logs",
                path: "\(home)/.gemini/antigravity/brain",
                sizeMb: antigravityBrainMb,
                whyDescription: "Stores agent conversation transcripts, tool execution traces, subagent branches, and code scratchpads.",
                iconName: "brain.head.profile",
                canPruneWithDays: true
            ),
            StorageBreakdownItem(
                key: "claude",
                name: "Claude Desktop Logs & Cache",
                category: "AI Agent Logs",
                path: "\(home)/Library/Logs/Claude",
                sizeMb: claudeLogsMb + claudeCacheMb,
                whyDescription: "Electron runtime logs, MCP stderr debugging traces, and local conversation context cache.",
                iconName: "bubble.left.and.bubble.right",
                canPruneWithDays: true
            ),
            StorageBreakdownItem(
                key: "xcode",
                name: "Xcode DerivedData Build Products",
                category: "Build Caches",
                path: "\(home)/Library/Developer/Xcode/DerivedData",
                sizeMb: xcodeDerivedDataGb * 1024.0,
                whyDescription: "Precompiled headers, indexing databases, LLVM intermediate object files, and simulator bundles. 100% safe to clear.",
                iconName: "hammer.fill",
                canPruneWithDays: false
            ),
            StorageBreakdownItem(
                key: "gradle_cache",
                name: "Gradle Global Dependency Cache",
                category: "Build Caches",
                path: "\(home)/.gradle/caches",
                sizeMb: gradleCachesGb * 1024.0,
                whyDescription: "Downloaded remote Maven dependencies (AAR/JAR) and compiled build script plugins across all projects.",
                iconName: "shippingbox.fill",
                canPruneWithDays: false
            ),
            StorageBreakdownItem(
                key: "gradle_daemons",
                name: "Gradle Daemon Process Logs",
                category: "Dev Logs",
                path: "\(home)/.gradle/daemon",
                sizeMb: gradleDaemonLogsMb,
                whyDescription: "Worker daemon logs, execution error traces, and build environment outputs.",
                iconName: "gearshape.2",
                canPruneWithDays: false
            ),
            StorageBreakdownItem(
                key: "cocoapods",
                name: "CocoaPods Cache",
                category: "Package Manager",
                path: "\(home)/.cocoapods/cache",
                sizeMb: cocoapodsCacheMb,
                whyDescription: "Locally cached iOS/macOS pod tarballs and git clone checkouts.",
                iconName: "cube.box",
                canPruneWithDays: false
            )
        ]
    }
}

struct SystemHelperStatus {
    var isBatteryLimiterInstalled: Bool = false
    var batteryToolPath: String? = nil
    var isBrewInstalled: Bool = false
    var isGradleInstalled: Bool = false
    var isAdbInstalled: Bool = false
}

struct SystemHealth {
    var batteryPercent: Int = 100
    var isCharging: Bool = false
    var isAcPower: Bool = true
    var batteryLimit: Int? = nil
    var batteryCycles: Int? = nil
    var batteryCondition: String? = "Normal"
    var batteryHealthPercent: Int? = 100
    var batteryDesignCapacityMah: Int? = nil
    var batteryMaxCapacityMah: Int? = nil
    var batteryCurrentCapacityMah: Int? = nil
    var batteryTemperatureCelsius: Double? = nil
    var batteryVoltageVolts: Double? = nil
    var batteryDesignCycles: Int = 1000
    var isBatteryLimiterInstalled: Bool = false
    var helpers: SystemHelperStatus = SystemHelperStatus()
    var cpuUsagePercent: Double = 0.0
    var thermalStatus: ThermalStatus = .nominal
    var swapTotalMb: Double = 0
    var swapUsedMb: Double = 0
    var swapFreeMb: Double = 0
    var swapRisk: SwapRiskLevel = .safe
    var ramUsedGb: Double = 0
    var ramTotalGb: Double = 24

    // Detailed SSD SMART & Storage Health
    var ssdModelName: String = "APPLE SSD"
    var ssdSmartStatus: String = "Verified"
    var ssdPercentageUsed: Int? = 0
    var ssdAvailableSparePercent: Int? = 100
    var ssdLifetimeBytesWrittenTb: Double? = nil
    var ssdLifetimeBytesReadTb: Double? = nil
    var ssdPowerCycles: Int? = nil
    var ssdPowerOnHours: Int? = nil
    var ssdTemperatureCelsius: Double? = nil
    var ssdUnsafeShutdowns: Int? = nil
    var ssdMediaErrors: Int? = nil
    var ssdBytesWrittenGb: Double = 0.0
    var ssdBytesReadGb: Double = 0.0
    var ssdWriteOperations: UInt64 = 0
    var ssdReadOperations: UInt64 = 0

    // Safe zero-subprocess metrics
    var diskFreeGb: Double = 0
    var diskTotalGb: Double = 0
    var diskUsedPercent: Double = 0
    var topProcessName: String = "—"
    var topProcessRamMb: Double = 0
    var networkDownloadKbSec: Double = 0
    var networkUploadKbSec: Double = 0

    // MARK: - Mont-E v2 Hardware & Telemetry Additions
    var gpu: GPUService.GPUInfo = GPUService.GPUInfo()
    var processorCores: SystemStatsService.ProcessorCoreInfo = SystemStatsService.ProcessorCoreInfo()
    var bluetoothDevices: [BluetoothDeviceInfo] = []
    var fans: [FanInfo] = []
    var topCpuProcesses: [ProcessInvestigatorItem] = []
    var topDiskProcesses: [ProcessInvestigatorItem] = []
    var topMemoryProcesses: [ProcessInvestigatorItem] = []

    // MARK: - Wi-Fi Diagnostics, Multi-Volume Storage & Telemetry Sparklines
    var wifi: WiFiDiagnostics = WiFiDiagnostics()
    var mountedVolumes: [MountedVolumeInfo] = []
    var cpuHistory: [Double] = []
    var gpuHistory: [Double] = []
    var ramHistory: [Double] = []
    var networkHistory: [Double] = []

    var ramPercent: Double {
        (ramUsedGb / max(ramTotalGb, 1.0)) * 100.0
    }

    var overallHealth: SystemHealthLevel {
        // Evaluate combination of RAM, CPU, Swap, and Thermal
        var score = 0 // higher = worse

        // RAM factor
        if ramPercent > 90 { score += 4 }
        else if ramPercent > 80 { score += 3 }
        else if ramPercent > 65 { score += 1 }

        // CPU factor
        if cpuUsagePercent > 85 { score += 3 }
        else if cpuUsagePercent > 65 { score += 2 }
        else if cpuUsagePercent > 40 { score += 1 }

        // Swap factor
        switch swapRisk {
        case .critical: score += 4
        case .moderate: score += 2
        case .safe:     break
        }

        // Thermal factor
        switch thermalStatus {
        case .critical: score += 4
        case .serious:  score += 3
        case .fair:     score += 1
        case .nominal:  break
        }

        switch score {
        case 0...1: return .optimal   // Dark Green
        case 2...3: return .good      // Green
        case 4...5: return .fair      // Yellow
        case 6...8: return .strained  // Orange
        default:    return .critical  // Bright Red
        }
    }

    var storage: StorageMetrics = StorageMetrics()
    var daemons: [GradleDaemonInfo] = []
}
