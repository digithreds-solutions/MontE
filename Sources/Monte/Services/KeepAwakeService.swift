import Foundation
import AppKit
import IOKit.pwr_mgt
import UserNotifications
import CoreAudio
import CoreWLAN

// MARK: - Keep-Awake Modes & Durations

enum KeepAwakeMode: Equatable {
    case indefinite
    case timed(TimeInterval)                                // Duration in seconds (e.g. 15m, 1h, 2h30m)
    case untilTime(Date)                                    // Until a specific time of day (e.g. 5:00 PM)
    case whileAppRunning(bundleID: String, appName: String) // Active while app is running
    case whileGradleActive                                  // Active while Gradle daemons run
    case whilePythonActive                                  // Active while Python scripts/builds run
    case whileXcodeActive                                   // Active while Xcode / Swift compilation runs
    case whileNodeActive                                    // Active while Node.js / web builds run
    case whileCargoActive                                   // Active while Cargo / Rust compilation runs
    case whileDockerActive                                  // Active while Docker containers/engine run
    case whileMakeActive                                    // Active while Make / CMake compilation runs
    case whileOnACPower                                     // Active while plugged into power adapter
    case whileDisplayConnected                              // Active while external display is attached
    case whileWiFiConnected(ssid: String)                   // Active while on specific Wi-Fi
    case whileAudioPlaying                                  // Active while audio is playing
    case whileDownloading(thresholdKbSec: Double)           // Active while download speed > threshold
    case whileScheduled(start: String, end: String)         // Active during scheduled hours (e.g. 09:00 - 17:00)

    var displayName: String {
        switch self {
        case .indefinite:
            return "Indefinitely"
        case .timed(let secs):
            let hours = Int(secs) / 3600
            let mins = (Int(secs) % 3600) / 60
            if hours > 0 && mins > 0 { return "\(hours)h \(mins)m" }
            if hours > 0 { return "\(hours) Hour\(hours > 1 ? "s" : "")" }
            return "\(mins) Minute\(mins > 1 ? "s" : "")"
        case .untilTime(let date):
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return "Until \(formatter.string(from: date))"
        case .whileAppRunning(_, let name):
            return "While \(name) is Running"
        case .whileGradleActive:
            return "While Gradle Builds Run"
        case .whilePythonActive:
            return "While Python Scripts Run"
        case .whileXcodeActive:
            return "While Xcode Builds Run"
        case .whileNodeActive:
            return "While Node.js Builds Run"
        case .whileCargoActive:
            return "While Cargo / Rust Builds Run"
        case .whileDockerActive:
            return "While Docker Engine Runs"
        case .whileMakeActive:
            return "While Make / CMake Builds Run"
        case .whileOnACPower:
            return "While on AC Power"
        case .whileDisplayConnected:
            return "While External Display Attached"
        case .whileWiFiConnected(let ssid):
            return "While Connected to '\(ssid)'"
        case .whileAudioPlaying:
            return "While Audio is Playing"
        case .whileDownloading(let rate):
            return "While Downloading (> \(Int(rate)) KB/s)"
        case .whileScheduled(let start, let end):
            return "Scheduled (\(start) - \(end))"
        }
    }
}

// MARK: - Active Build Process Telemetry

struct ActiveBuildStatus: Equatable {
    var isGradleActive: Bool = false
    var gradleCount: Int = 0
    var isPythonActive: Bool = false
    var pythonCount: Int = 0
    var isXcodeActive: Bool = false
    var xcodeCount: Int = 0
    var isNodeActive: Bool = false
    var nodeCount: Int = 0
    var isCargoActive: Bool = false
    var cargoCount: Int = 0
    var isDockerActive: Bool = false
    var dockerCount: Int = 0
    var isMakeActive: Bool = false
    var makeCount: Int = 0

    var anyBuildActive: Bool {
        isGradleActive || isPythonActive || isXcodeActive || isNodeActive || isCargoActive || isDockerActive || isMakeActive
    }

    var activeSummary: String {
        var active: [String] = []
        if isGradleActive { active.append("Gradle (\(gradleCount))") }
        if isPythonActive { active.append("Python (\(pythonCount))") }
        if isXcodeActive { active.append("Xcode (\(xcodeCount))") }
        if isNodeActive { active.append("Node (\(nodeCount))") }
        if isCargoActive { active.append("Cargo (\(cargoCount))") }
        if isDockerActive { active.append("Docker (\(dockerCount))") }
        if isMakeActive { active.append("Make (\(makeCount))") }
        return active.isEmpty ? "No active dev builds" : active.joined(separator: ", ")
    }
}

// MARK: - Zero-Subprocess Darwin Build Process Detector

struct BuildProcessDetector {
    static func detectActiveBuilds(gradleDaemonCount: Int = 0) -> ActiveBuildStatus {
        var status = ActiveBuildStatus()
        if gradleDaemonCount > 0 {
            status.isGradleActive = true
            status.gradleCount = gradleDaemonCount
        }

        var pids = [pid_t](repeating: 0, count: 2048)
        let bytesReturned = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(MemoryLayout<pid_t>.size * pids.count))
        guard bytesReturned > 0 else { return status }

        let count = Int(bytesReturned) / MemoryLayout<pid_t>.size
        var pathBuffer = [CChar](repeating: 0, count: 1024)
        var nameBuffer = [CChar](repeating: 0, count: 256)

        for i in 0..<count {
            let pid = pids[i]
            guard pid > 1 else { continue } // Skip kernel_task and launchd

            let nameLen = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
            let procName = nameLen > 0 ? String(cString: nameBuffer).lowercased() : ""

            var fullPath = ""
            let pathLen = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
            if pathLen > 0 {
                fullPath = String(cString: pathBuffer).lowercased()
            }

            // Python (python, python3, pytest, uv, mypy, ipython)
            if procName == "python" || procName == "python3" || procName.hasPrefix("python3.") ||
               procName == "pytest" || procName == "uv" || fullPath.contains("/python") {
                status.isPythonActive = true
                status.pythonCount += 1
            }

            // Gradle
            if procName.contains("gradledaemon") || procName == "gradle" || fullPath.contains("gradledaemon") {
                status.isGradleActive = true
                status.gradleCount += 1
            }

            // Xcode & Swift compilation
            if procName == "xcodebuild" || procName == "swift-frontend" || procName == "swift-build" || procName == "swift" {
                status.isXcodeActive = true
                status.xcodeCount += 1
            }

            // Node.js & Web builds
            if procName == "node" || procName == "npm" || procName == "yarn" || procName == "pnpm" ||
               procName == "bun" || procName == "next-server" || procName == "vite" || procName == "webpack" {
                status.isNodeActive = true
                status.nodeCount += 1
            }

            // Rust / Cargo
            if procName == "cargo" || procName == "rustc" {
                status.isCargoActive = true
                status.cargoCount += 1
            }

            // Docker
            if procName == "docker" || procName == "dockerd" || procName.contains("com.docker") || fullPath.contains("docker") {
                status.isDockerActive = true
                status.dockerCount += 1
            }

            // Make / CMake / Ninja
            if procName == "make" || procName == "cmake" || procName == "ninja" {
                status.isMakeActive = true
                status.makeCount += 1
            }
        }
        return status
    }
}

// MARK: - Keep-Awake Configuration & Safety Policies

struct KeepAwakeConfig: Codable, Equatable {
    // ── 1. Sleep & Display Assertions ─────────────────────────────────────────
    var preventDisplaySleep: Bool = true             // Prevent screen from turning off/dimming
    var dimDisplayWhileAwake: Bool = false           // Allow display to dim to save energy while CPU is kept 100% awake
    var preventDiskSleep: Bool = true                // Prevent external drives/disks from idle spindown
    var allowScreenSaver: Bool = false               // Allow screensaver to run while keeping system awake
    var lockScreenOnSessionEnd: Bool = false         // Lock macOS immediately when keep-awake session concludes

    // ── 2. Hardware Protection & Battery Safety ──────────────────────────────
    var batterySafetyCutoffPercent: Int = 20         // Auto-disable if on battery <= N%
    var stopOnOverheating: Bool = true               // Auto-disable if thermal state reaches Critical/Serious
    var stopOnHighBatteryTemperature: Bool = true    // Auto-disable if battery temperature exceeds max threshold
    var maxBatteryTemperatureCelsius: Double = 42.0  // Default: 42°C (107.6°F)
    var onlyOnACPower: Bool = false                  // Only keep awake when plugged in; stop immediately on battery

    // ── 3. Developer Build & Process Triggers ────────────────────────────────
    var autoAwakeOnGradle: Bool = true               // Auto-start session whenever Gradle builds/daemons active
    var autoAwakeOnPython: Bool = false              // Auto-start session whenever Python scripts/builds run
    var autoAwakeOnXcode: Bool = false               // Auto-start session whenever Xcode / swift compilation runs
    var autoAwakeOnNode: Bool = false                // Auto-start session whenever Node.js / web builds run
    var autoAwakeOnCargo: Bool = false               // Auto-start session whenever Cargo / Rust compilation runs
    var autoAwakeOnDocker: Bool = false              // Auto-start session whenever Docker containers/engine run
    var autoAwakeOnMake: Bool = false                // Auto-start session whenever Make / CMake / Ninja builds run

    // ── 4. Hardware & Environmental Triggers ─────────────────────────────────
    var autoAwakeOnACPower: Bool = false             // Auto-start session whenever plugged into AC
    var autoAwakeOnExternalDisplay: Bool = false      // Auto-start session when an external monitor is attached
    var autoAwakeOnWiFi: Bool = false                // Auto-start session when connected to a target Wi-Fi SSID
    var targetWiFiSSID: String = ""                  // Name of Wi-Fi network for auto-awake
    var autoAwakeOnAudio: Bool = false               // Auto-start session while system audio is playing
    var autoAwakeOnDownload: Bool = false            // Auto-start session while active download > threshold
    var downloadThresholdKbSec: Double = 500.0       // Min download throughput threshold in KB/s
    var autoAwakeOnSchedule: Bool = false            // Auto-start during daily schedule
    var scheduleStartHour: Int = 9                   // e.g. 9 AM
    var scheduleStartMinute: Int = 0
    var scheduleEndHour: Int = 17                    // e.g. 5 PM
    var scheduleEndMinute: Int = 0
    var scheduleWeekdaysOnly: Bool = true            // Monday - Friday only

    // ── 5. Sound & Periodic Reminders ────────────────────────────────────────
    var playSoundEffects: Bool = true                // Subtle sound on session start/stop/alerts
    var periodicChimeIntervalMinutes: Int = 0        // 0 = disabled, 15 = 15m, 30 = 30m, 60 = hourly chime

    // ── 6. App Triggers ──────────────────────────────────────────────────────
    var autoAwakeOnWatchedApps: Bool = false         // Auto-start session while any watched app is open
    var watchedApps: [String] = [
        "com.apple.dt.Xcode",
        "com.google.android.studio",
        "com.microsoft.VSCode",
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.docker.docker"
    ]

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        preventDisplaySleep = try container.decodeIfPresent(Bool.self, forKey: .preventDisplaySleep) ?? true
        dimDisplayWhileAwake = try container.decodeIfPresent(Bool.self, forKey: .dimDisplayWhileAwake) ?? false
        preventDiskSleep = try container.decodeIfPresent(Bool.self, forKey: .preventDiskSleep) ?? true
        allowScreenSaver = try container.decodeIfPresent(Bool.self, forKey: .allowScreenSaver) ?? false
        lockScreenOnSessionEnd = try container.decodeIfPresent(Bool.self, forKey: .lockScreenOnSessionEnd) ?? false
        batterySafetyCutoffPercent = try container.decodeIfPresent(Int.self, forKey: .batterySafetyCutoffPercent) ?? 20
        stopOnOverheating = try container.decodeIfPresent(Bool.self, forKey: .stopOnOverheating) ?? true
        stopOnHighBatteryTemperature = try container.decodeIfPresent(Bool.self, forKey: .stopOnHighBatteryTemperature) ?? true
        maxBatteryTemperatureCelsius = try container.decodeIfPresent(Double.self, forKey: .maxBatteryTemperatureCelsius) ?? 42.0
        onlyOnACPower = try container.decodeIfPresent(Bool.self, forKey: .onlyOnACPower) ?? false
        autoAwakeOnGradle = try container.decodeIfPresent(Bool.self, forKey: .autoAwakeOnGradle) ?? true
        autoAwakeOnPython = try container.decodeIfPresent(Bool.self, forKey: .autoAwakeOnPython) ?? false
        autoAwakeOnXcode = try container.decodeIfPresent(Bool.self, forKey: .autoAwakeOnXcode) ?? false
        autoAwakeOnNode = try container.decodeIfPresent(Bool.self, forKey: .autoAwakeOnNode) ?? false
        autoAwakeOnCargo = try container.decodeIfPresent(Bool.self, forKey: .autoAwakeOnCargo) ?? false
        autoAwakeOnDocker = try container.decodeIfPresent(Bool.self, forKey: .autoAwakeOnDocker) ?? false
        autoAwakeOnMake = try container.decodeIfPresent(Bool.self, forKey: .autoAwakeOnMake) ?? false
        autoAwakeOnACPower = try container.decodeIfPresent(Bool.self, forKey: .autoAwakeOnACPower) ?? false
        autoAwakeOnExternalDisplay = try container.decodeIfPresent(Bool.self, forKey: .autoAwakeOnExternalDisplay) ?? false
        autoAwakeOnWiFi = try container.decodeIfPresent(Bool.self, forKey: .autoAwakeOnWiFi) ?? false
        targetWiFiSSID = try container.decodeIfPresent(String.self, forKey: .targetWiFiSSID) ?? ""
        autoAwakeOnAudio = try container.decodeIfPresent(Bool.self, forKey: .autoAwakeOnAudio) ?? false
        autoAwakeOnDownload = try container.decodeIfPresent(Bool.self, forKey: .autoAwakeOnDownload) ?? false
        downloadThresholdKbSec = try container.decodeIfPresent(Double.self, forKey: .downloadThresholdKbSec) ?? 500.0
        autoAwakeOnSchedule = try container.decodeIfPresent(Bool.self, forKey: .autoAwakeOnSchedule) ?? false
        scheduleStartHour = try container.decodeIfPresent(Int.self, forKey: .scheduleStartHour) ?? 9
        scheduleStartMinute = try container.decodeIfPresent(Int.self, forKey: .scheduleStartMinute) ?? 0
        scheduleEndHour = try container.decodeIfPresent(Int.self, forKey: .scheduleEndHour) ?? 17
        scheduleEndMinute = try container.decodeIfPresent(Int.self, forKey: .scheduleEndMinute) ?? 0
        scheduleWeekdaysOnly = try container.decodeIfPresent(Bool.self, forKey: .scheduleWeekdaysOnly) ?? true
        playSoundEffects = try container.decodeIfPresent(Bool.self, forKey: .playSoundEffects) ?? true
        periodicChimeIntervalMinutes = try container.decodeIfPresent(Int.self, forKey: .periodicChimeIntervalMinutes) ?? 0
        autoAwakeOnWatchedApps = try container.decodeIfPresent(Bool.self, forKey: .autoAwakeOnWatchedApps) ?? false
        watchedApps = try container.decodeIfPresent([String].self, forKey: .watchedApps) ?? [
            "com.apple.dt.Xcode",
            "com.google.android.studio",
            "com.microsoft.VSCode",
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "com.docker.docker"
        ]
    }
}

// MARK: - Keep-Awake Service (IOKit Sleep, Display & Audio Engine)

@Observable
@MainActor
final class KeepAwakeService {

    static let shared = KeepAwakeService()

    private(set) var isActive: Bool = false
    private(set) var activeMode: KeepAwakeMode = .indefinite
    private(set) var sessionEndTime: Date?
    private(set) var remainingSeconds: TimeInterval = 0
    private(set) var activeSessionDuration: TimeInterval = 0
    var activeBuilds: ActiveBuildStatus = ActiveBuildStatus()
    private(set) var isManuallyStopped: Bool = false

    private var lastObservedACPower: Bool?
    private var lastObservedExternalDisplay: Bool?
    private var lastObservedGradleDaemons: Int = 0

    var config: KeepAwakeConfig {
        didSet {
            applyConfigChanges()
        }
    }

    private var systemAssertionID: IOPMAssertionID = 0
    private var displayAssertionID: IOPMAssertionID = 0
    private var diskAssertionID: IOPMAssertionID = 0
    private var countdownTimer: Timer?
    private var sessionStartTime: Date?
    private var lastPeriodicChimeTime: Date?
    private let configKey = "MontEKeepAwakeConfig_v3"

    init() {
        if let data = UserDefaults.standard.data(forKey: configKey),
           let decoded = try? JSONDecoder().decode(KeepAwakeConfig.self, from: data) {
            self.config = decoded
        } else {
            self.config = KeepAwakeConfig()
        }
    }

    func saveConfig() {
        if let encoded = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(encoded, forKey: configKey)
        }
    }

    func applyConfigChanges() {
        saveConfig()

        if isActive {
            reapplyPolicies()
        }

        switch activeMode {
        case .whileGradleActive where !config.autoAwakeOnGradle:
            stop(reason: "Gradle build keep-awake disabled.", manual: true)
        case .whilePythonActive where !config.autoAwakeOnPython:
            stop(reason: "Python script keep-awake disabled.", manual: true)
        case .whileXcodeActive where !config.autoAwakeOnXcode:
            stop(reason: "Xcode build keep-awake disabled.", manual: true)
        case .whileNodeActive where !config.autoAwakeOnNode:
            stop(reason: "Node.js build keep-awake disabled.", manual: true)
        case .whileCargoActive where !config.autoAwakeOnCargo:
            stop(reason: "Cargo build keep-awake disabled.", manual: true)
        case .whileDockerActive where !config.autoAwakeOnDocker:
            stop(reason: "Docker keep-awake disabled.", manual: true)
        case .whileMakeActive where !config.autoAwakeOnMake:
            stop(reason: "Make build keep-awake disabled.", manual: true)
        case .whileOnACPower where !config.autoAwakeOnACPower:
            stop(reason: "AC power auto-awake disabled.", manual: true)
        case .whileDisplayConnected where !config.autoAwakeOnExternalDisplay:
            stop(reason: "External display auto-awake disabled.", manual: true)
        case .whileWiFiConnected where !config.autoAwakeOnWiFi:
            stop(reason: "Wi-Fi auto-awake disabled.", manual: true)
        case .whileAudioPlaying where !config.autoAwakeOnAudio:
            stop(reason: "Audio auto-awake disabled.", manual: true)
        case .whileDownloading where !config.autoAwakeOnDownload:
            stop(reason: "Download auto-awake disabled.", manual: true)
        case .whileScheduled where !config.autoAwakeOnSchedule:
            stop(reason: "Schedule auto-awake disabled.", manual: true)
        default:
            break
        }
    }

    func resumeAutoTriggers() {
        self.isManuallyStopped = false
    }

    var statusSummary: String {
        guard isActive else {
            return isManuallyStopped ? "Inactive (Auto-Triggers on Standby)" : "Inactive (Normal Sleep)"
        }
        switch activeMode {
        case .indefinite:
            return "Active (Indefinite)"
        case .whileGradleActive:
            return "Active (Gradle Build Active)"
        case .whilePythonActive:
            return "Active (Python Script Active)"
        case .whileXcodeActive:
            return "Active (Xcode Build Active)"
        case .whileNodeActive:
            return "Active (Node.js Build Active)"
        case .whileCargoActive:
            return "Active (Cargo Build Active)"
        case .whileDockerActive:
            return "Active (Docker Engine Active)"
        case .whileMakeActive:
            return "Active (Make / CMake Active)"
        case .whileOnACPower:
            return "Active (On AC Power)"
        case .whileDisplayConnected:
            return "Active (External Display Attached)"
        case .whileWiFiConnected(let ssid):
            return "Active (Wi-Fi '\(ssid)')"
        case .whileAudioPlaying:
            return "Active (Audio Playing)"
        case .whileDownloading:
            return "Active (Download in Progress)"
        case .whileScheduled(let s, let e):
            return "Active (Scheduled \(s)-\(e))"
        case .whileAppRunning(_, let name):
            return "Active (\(name) Running)"
        case .untilTime(let date):
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return "Active (Until \(formatter.string(from: date)))"
        case .timed:
            let hours = Int(remainingSeconds) / 3600
            let mins = (Int(remainingSeconds) % 3600) / 60
            let secs = Int(remainingSeconds) % 60
            if hours > 0 {
                return String(format: "Active (%02d:%02d:%02d remaining)", hours, mins, secs)
            }
            return String(format: "Active (%02d:%02d remaining)", mins, secs)
        }
    }

    // MARK: - Start Session

    func start(mode: KeepAwakeMode = .indefinite) {
        stop(silent: true)
        self.isManuallyStopped = false

        self.activeMode = mode
        let reason = "Mont-E Keep-Awake: \(mode.displayName)" as CFString

        // 1. Prevent User Idle System Sleep
        var sysID: IOPMAssertionID = 0
        let sysRes = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &sysID
        )

        guard sysRes == kIOReturnSuccess else { return }
        self.systemAssertionID = sysID
        self.isActive = true
        self.sessionStartTime = Date()
        self.lastPeriodicChimeTime = Date()

        // 2. Prevent Display Sleep (if enabled in config, not set to dim, and screensaver not allowed)
        if config.preventDisplaySleep && !config.dimDisplayWhileAwake && !config.allowScreenSaver {
            var dispID: IOPMAssertionID = 0
            let dispRes = IOPMAssertionCreateWithName(
                kIOPMAssertPreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason,
                &dispID
            )
            if dispRes == kIOReturnSuccess {
                self.displayAssertionID = dispID
            }
        }

        // 3. Prevent Disk Spindown (if enabled in config)
        if config.preventDiskSleep {
            var diskID: IOPMAssertionID = 0
            let diskRes = IOPMAssertionCreateWithName(
                kIOPMAssertPreventDiskIdle as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason,
                &diskID
            )
            if diskRes == kIOReturnSuccess {
                self.diskAssertionID = diskID
            }
        }

        // Setup timer based on mode
        switch mode {
        case .timed(let duration):
            self.sessionEndTime = Date().addingTimeInterval(duration)
            self.remainingSeconds = duration
            startCountdown()

        case .untilTime(let targetDate):
            let duration = max(targetDate.timeIntervalSinceNow, 0)
            self.sessionEndTime = targetDate
            self.remainingSeconds = duration
            startCountdown()

        default:
            self.sessionEndTime = nil
            self.remainingSeconds = 0
            startCountdown()
        }

        playSound(named: "Hero")

        sendNotification(
            title: "Keep-Awake Active ☕",
            body: "Mac sleep prevented: \(mode.displayName)"
        )
    }

    // MARK: - Stop Session

    func stop(reason: String? = nil, silent: Bool = false, manual: Bool = false) {
        let wasActive = isActive
        if manual {
            self.isManuallyStopped = true
        }

        countdownTimer?.invalidate()
        countdownTimer = nil

        if systemAssertionID != 0 {
            IOPMAssertionRelease(systemAssertionID)
            systemAssertionID = 0
        }
        if displayAssertionID != 0 {
            IOPMAssertionRelease(displayAssertionID)
            displayAssertionID = 0
        }
        if diskAssertionID != 0 {
            IOPMAssertionRelease(diskAssertionID)
            diskAssertionID = 0
        }

        isActive = false
        sessionEndTime = nil
        remainingSeconds = 0
        sessionStartTime = nil

        if wasActive && !silent {
            playSound(named: "Purr")

            if let reason = reason {
                sendNotification(title: "Keep-Awake Ended", body: reason)
            }

            // Lock screen if requested
            if config.lockScreenOnSessionEnd {
                lockScreen()
            }
        }
    }

    // MARK: - Re-apply Active Policies

    func reapplyPolicies() {
        if isActive {
            start(mode: activeMode)
        }
    }

    // MARK: - Comprehensive Triggers & Safety Evaluator

    func evaluateSafetyAndTriggers(
        batteryPercent: Int,
        isAcPower: Bool,
        thermalStatus: ThermalStatus,
        daemonCount: Int,
        downloadKbSec: Double = 0
    ) {
        // Detect active build processes across the system
        let builds = BuildProcessDetector.detectActiveBuilds(gradleDaemonCount: daemonCount)
        self.activeBuilds = builds

        // Check if user manually stopped session and hardware state hasn't changed
        if isManuallyStopped && !isActive {
            let acConnectedNow = (lastObservedACPower == false && isAcPower == true)
            let extDisplayConnectedNow = (lastObservedExternalDisplay == false && NSScreen.screens.count > 1)
            let newDaemonStarted = (daemonCount > lastObservedGradleDaemons)

            if acConnectedNow || extDisplayConnectedNow || newDaemonStarted {
                self.isManuallyStopped = false
            } else {
                self.lastObservedACPower = isAcPower
                self.lastObservedExternalDisplay = NSScreen.screens.count > 1
                self.lastObservedGradleDaemons = daemonCount
                return
            }
        }

        self.lastObservedACPower = isAcPower
        self.lastObservedExternalDisplay = NSScreen.screens.count > 1
        self.lastObservedGradleDaemons = daemonCount

        // ── 1. Safety Cutoffs ────────────────────────────────────────────────
        if isActive {
            // AC-Only policy: Stop immediately if on battery power
            if config.onlyOnACPower && !isAcPower {
                stop(reason: "Safety Stop: Disconnected from AC power (AC Only policy).")
                playSound(named: "Basso")
                return
            }

            // Thermal Overheating Safety
            if config.stopOnOverheating && (thermalStatus == .critical || thermalStatus == .serious) {
                stop(reason: "Safety Stop: Thermal throttling reached \(thermalStatus.rawValue).")
                playSound(named: "Basso")
                return
            }

            // Battery Cutoff %
            if !isAcPower && batteryPercent <= config.batterySafetyCutoffPercent {
                stop(reason: "Battery reached \(batteryPercent)% (<= \(config.batterySafetyCutoffPercent)% safety cutoff).")
                playSound(named: "Basso")
                return
            }

            // Battery Temperature Safety
            if config.stopOnHighBatteryTemperature, let temp = BatteryService.readBatteryTemperatureCelsius() {
                if temp >= config.maxBatteryTemperatureCelsius {
                    stop(reason: String(format: "Battery temperature reached %.1f°C (>= %.1f°C threshold).", temp, config.maxBatteryTemperatureCelsius))
                    playSound(named: "Basso")
                    return
                }
            }
        }

        // ── 2. Automated Triggers Evaluation ─────────────────────────────────

        // Trigger A: AC Power Adapter
        if config.autoAwakeOnACPower {
            if isAcPower && !isActive {
                start(mode: .whileOnACPower)
                return
            } else if !isAcPower && isActive && activeMode == .whileOnACPower {
                stop(reason: "Disconnected from AC power.")
                return
            }
        }

        // Trigger B: Developer Builds & Compilers
        // B1. Gradle Builds
        if config.autoAwakeOnGradle {
            if builds.isGradleActive && !isActive {
                start(mode: .whileGradleActive)
                return
            } else if !builds.isGradleActive && isActive && activeMode == .whileGradleActive {
                stop(reason: "Gradle build completed.")
                return
            }
        } else if isActive && activeMode == .whileGradleActive {
            stop(reason: "Gradle build keep-awake disabled.")
            return
        }

        // B2. Python Scripts & Builds
        if config.autoAwakeOnPython {
            if builds.isPythonActive && !isActive {
                start(mode: .whilePythonActive)
                return
            } else if !builds.isPythonActive && isActive && activeMode == .whilePythonActive {
                stop(reason: "Python script completed.")
                return
            }
        } else if isActive && activeMode == .whilePythonActive {
            stop(reason: "Python keep-awake disabled.")
            return
        }

        // B3. Xcode / Swift Builds
        if config.autoAwakeOnXcode {
            if builds.isXcodeActive && !isActive {
                start(mode: .whileXcodeActive)
                return
            } else if !builds.isXcodeActive && isActive && activeMode == .whileXcodeActive {
                stop(reason: "Xcode compilation completed.")
                return
            }
        } else if isActive && activeMode == .whileXcodeActive {
            stop(reason: "Xcode keep-awake disabled.")
            return
        }

        // B4. Node.js & Web Dev Builds
        if config.autoAwakeOnNode {
            if builds.isNodeActive && !isActive {
                start(mode: .whileNodeActive)
                return
            } else if !builds.isNodeActive && isActive && activeMode == .whileNodeActive {
                stop(reason: "Node.js build completed.")
                return
            }
        } else if isActive && activeMode == .whileNodeActive {
            stop(reason: "Node.js keep-awake disabled.")
            return
        }

        // B5. Rust / Cargo Builds
        if config.autoAwakeOnCargo {
            if builds.isCargoActive && !isActive {
                start(mode: .whileCargoActive)
                return
            } else if !builds.isCargoActive && isActive && activeMode == .whileCargoActive {
                stop(reason: "Cargo compilation completed.")
                return
            }
        } else if isActive && activeMode == .whileCargoActive {
            stop(reason: "Cargo keep-awake disabled.")
            return
        }

        // B6. Docker Engine & Containers
        if config.autoAwakeOnDocker {
            if builds.isDockerActive && !isActive {
                start(mode: .whileDockerActive)
                return
            } else if !builds.isDockerActive && isActive && activeMode == .whileDockerActive {
                stop(reason: "Docker container execution ended.")
                return
            }
        } else if isActive && activeMode == .whileDockerActive {
            stop(reason: "Docker keep-awake disabled.")
            return
        }

        // B7. Make / CMake / Ninja Builds
        if config.autoAwakeOnMake {
            if builds.isMakeActive && !isActive {
                start(mode: .whileMakeActive)
                return
            } else if !builds.isMakeActive && isActive && activeMode == .whileMakeActive {
                stop(reason: "Make compilation completed.")
                return
            }
        } else if isActive && activeMode == .whileMakeActive {
            stop(reason: "Make keep-awake disabled.")
            return
        }

        // Trigger C: External Display Connected
        if config.autoAwakeOnExternalDisplay {
            let hasExternalDisplay = NSScreen.screens.count > 1
            if hasExternalDisplay && !isActive {
                start(mode: .whileDisplayConnected)
                return
            } else if !hasExternalDisplay && isActive && activeMode == .whileDisplayConnected {
                stop(reason: "External display was disconnected.")
                return
            }
        }

        // Trigger D: Wi-Fi SSID
        if config.autoAwakeOnWiFi && !config.targetWiFiSSID.isEmpty {
            let currentSSID = getCurrentWiFiSSID() ?? ""
            let matches = currentSSID.localizedCaseInsensitiveCompare(config.targetWiFiSSID) == .orderedSame
            if matches && !isActive {
                start(mode: .whileWiFiConnected(ssid: currentSSID))
                return
            } else if !matches && isActive, case .whileWiFiConnected = activeMode {
                stop(reason: "Disconnected from Wi-Fi '\(config.targetWiFiSSID)'.")
                return
            }
        }

        // Trigger E: Audio Playing
        if config.autoAwakeOnAudio {
            let isAudio = isAudioPlaying()
            if isAudio && !isActive {
                start(mode: .whileAudioPlaying)
                return
            } else if !isAudio && isActive && activeMode == .whileAudioPlaying {
                stop(reason: "Audio playback stopped.")
                return
            }
        }

        // Trigger F: Active Download Speed
        if config.autoAwakeOnDownload {
            if downloadKbSec >= config.downloadThresholdKbSec && !isActive {
                start(mode: .whileDownloading(thresholdKbSec: config.downloadThresholdKbSec))
                return
            } else if downloadKbSec < (config.downloadThresholdKbSec * 0.2) && isActive, case .whileDownloading = activeMode {
                stop(reason: "Download throughput dropped below threshold.")
                return
            }
        }

        // Trigger G: Scheduled Time Range
        if config.autoAwakeOnSchedule {
            let isInsideSchedule = checkScheduleMatch()
            let timeStr = String(format: "%02d:%02d-%02d:%02d", config.scheduleStartHour, config.scheduleStartMinute, config.scheduleEndHour, config.scheduleEndMinute)
            if isInsideSchedule && !isActive {
                start(mode: .whileScheduled(start: String(format: "%02d:%02d", config.scheduleStartHour, config.scheduleStartMinute), end: String(format: "%02d:%02d", config.scheduleEndHour, config.scheduleEndMinute)))
                return
            } else if !isInsideSchedule && isActive, case .whileScheduled = activeMode {
                stop(reason: "Scheduled session ended (\(timeStr)).")
                return
            }
        }

        // Trigger H: Watched Apps Auto-Awake
        if config.autoAwakeOnWatchedApps && !config.watchedApps.isEmpty {
            let runningApps = NSWorkspace.shared.runningApplications
            let matchingApp = runningApps.first { app in
                guard let bId = app.bundleIdentifier else { return false }
                return config.watchedApps.contains(bId)
            }
            if let app = matchingApp, !isActive {
                let name = app.localizedName ?? app.bundleIdentifier ?? "Watched App"
                start(mode: .whileAppRunning(bundleID: app.bundleIdentifier ?? "", appName: name))
                return
            }
        }

        // Trigger I: Watched Apps Lifecycle
        checkWatchedApps()
    }

    private func checkWatchedApps() {
        guard case .whileAppRunning(let bundleID, let appName) = activeMode else { return }
        let runningApps = NSWorkspace.shared.runningApplications
        let isStillRunning = runningApps.contains { app in
            app.bundleIdentifier == bundleID || app.localizedName == appName
        }

        if !isStillRunning && isActive {
            stop(reason: "\(appName) was closed.")
        }
    }

    // MARK: - Watched Apps Management

    func addWatchedApp(_ bundleID: String) {
        if !config.watchedApps.contains(bundleID) {
            config.watchedApps.append(bundleID)
        }
    }

    func removeWatchedApp(_ bundleID: String) {
        config.watchedApps.removeAll { $0 == bundleID }
    }

    // MARK: - CoreAudio Live Audio Check

    func isAudioPlaying() -> Bool {
        var defaultOutputDeviceID = AudioDeviceID(0)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &defaultOutputDeviceID
        )
        guard status == noErr, defaultOutputDeviceID != 0 else { return false }

        var isRunning: UInt32 = 0
        propertySize = UInt32(MemoryLayout<UInt32>.size)
        propertyAddress.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        propertyAddress.mScope = kAudioObjectPropertyScopeGlobal

        let runStatus = AudioObjectGetPropertyData(
            defaultOutputDeviceID,
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &isRunning
        )
        return runStatus == noErr && isRunning != 0
    }

    // MARK: - Wi-Fi SSID Lookup

    func getCurrentWiFiSSID() -> String? {
        return CWWiFiClient.shared().interface()?.ssid()
    }

    // MARK: - Schedule Check

    private func checkScheduleMatch() -> Bool {
        let calendar = Calendar.current
        let now = Date()
        let comps = calendar.dateComponents([.weekday, .hour, .minute], from: now)

        if config.scheduleWeekdaysOnly {
            guard let weekday = comps.weekday, weekday >= 2 && weekday <= 6 else {
                return false // Saturday or Sunday
            }
        }

        let currentMinutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        let startMinutes = config.scheduleStartHour * 60 + config.scheduleStartMinute
        let endMinutes = config.scheduleEndHour * 60 + config.scheduleEndMinute

        if startMinutes <= endMinutes {
            return currentMinutes >= startMinutes && currentMinutes < endMinutes
        } else {
            // Crosses midnight
            return currentMinutes >= startMinutes || currentMinutes < endMinutes
        }
    }

    // MARK: - Lock Screen

    func lockScreen() {
        let lib = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY)
        if let sym = dlsym(lib, "SACLockScreenImmediate") {
            typealias SACLockFunc = @convention(c) () -> Void
            let fn = unsafeBitCast(sym, to: SACLockFunc.self)
            fn()
        } else {
            _ = ShellService.runSilent("/System/Library/CoreServices/Menu\\ Extras/User.menu/Contents/Resources/CGSession -suspend")
        }
    }

    // MARK: - Sound Player

    func playSound(named soundName: String) {
        guard config.playSoundEffects else { return }
        NSSound(named: NSSound.Name(soundName))?.play()
    }

    // MARK: - Running User Applications List

    func getRunningUserApps() -> [(bundleID: String, name: String, icon: NSImage?)] {
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.localizedName != nil && $0.bundleIdentifier != nil
        }
        return apps.map {
            ($0.bundleIdentifier ?? "", $0.localizedName ?? "", $0.icon)
        }
    }

    // MARK: - Countdown & Periodic Chime Loop

    private func startCountdown() {
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                if let start = self.sessionStartTime {
                    self.activeSessionDuration = Date().timeIntervalSince(start)
                }

                // Handle timed modes
                if let end = self.sessionEndTime {
                    let remaining = end.timeIntervalSinceNow
                    if remaining <= 0 {
                        self.stop(reason: "Session time completed.")
                        return
                    } else {
                        self.remainingSeconds = remaining
                    }
                }

                // Periodic Status Chime
                if self.isActive && self.config.periodicChimeIntervalMinutes > 0, let lastChime = self.lastPeriodicChimeTime {
                    let intervalSecs = Double(self.config.periodicChimeIntervalMinutes * 60)
                    if Date().timeIntervalSince(lastChime) >= intervalSecs {
                        self.playSound(named: "Tink")
                        self.lastPeriodicChimeTime = Date()
                    }
                }
            }
        }
    }

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
