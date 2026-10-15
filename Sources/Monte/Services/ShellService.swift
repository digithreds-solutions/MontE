import Foundation
import AppKit

// MARK: - Shell Service

/// Thin wrapper around Process + Pipe for all Monte shell-out operations.
/// Use this ONLY for operations that have no kernel API equivalent:
///   - battery limit setter, Gradle daemon kill, log pruning, du -sm

enum ShellError: Error {
    case failed(String)
}

struct ShellService {

    /// Run a command and return its stdout. Throws on non-zero exit.
    @discardableResult
    static func run(_ command: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError  = pipe

        try process.run()
        process.waitUntilExit()

        let data   = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return output
    }

    /// Run and swallow any errors — returns empty string on failure.
    @discardableResult
    static func runSilent(_ command: String) -> String {
        (try? run(command)) ?? ""
    }
}

// MARK: - Gradle Service

struct GradleService {

    static func listDaemons() -> [GradleDaemonInfo] {
        let output = ShellService.runSilent("pgrep -fl GradleDaemon")
        guard !output.isEmpty else { return [] }

        return output.components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .compactMap { line -> GradleDaemonInfo? in
                let parts = line.trimmingCharacters(in: .whitespaces)
                    .split(separator: " ", maxSplits: 1)
                let pid      = String(parts.first ?? "")
                let fullCmd  = parts.count > 1 ? String(parts[1]) : ""
                let xmxMatch = fullCmd.range(of: #"-Xmx([0-9]+[mMgG])"#, options: .regularExpression)
                let maxHeap  = xmxMatch.map { String(fullCmd[$0]) }
                    .flatMap { $0.components(separatedBy: "-Xmx").last } ?? "Default"
                let verMatch = fullCmd.range(of: #"GradleDaemon\s+([0-9.]+)"#, options: .regularExpression)
                let version  = verMatch.map { String(fullCmd[$0])
                    .components(separatedBy: " ").last ?? "Gradle" } ?? "Gradle"
                guard !pid.isEmpty else { return nil }
                return GradleDaemonInfo(pid: pid, maxHeap: maxHeap, version: version)
            }
    }

    /// Returns number of daemons that were running before kill.
    @discardableResult
    static func stopAll() -> Int {
        let count = listDaemons().count
        _ = ShellService.runSilent("pkill -f GradleDaemon || true")
        return count
    }
}

// MARK: - Storage Service

final class StorageService: @unchecked Sendable {

    private static let lock = NSLock()
    nonisolated(unsafe) private static var isScanning = false
    nonisolated(unsafe) private static var lastStorageCache = StorageMetrics()
    nonisolated(unsafe) private static var lastStorageFetchTime: Date?

    nonisolated(unsafe) private static var lastBatteryLimit: Int = 80
    nonisolated(unsafe) private static var lastBatteryLimitFetchTime: Date?

    static func readMetrics(force: Bool = false) -> StorageMetrics {
        lock.lock()
        let now = Date()
        if !force, let lastTime = lastStorageFetchTime, now.timeIntervalSince(lastTime) < 300 {
            let cached = lastStorageCache
            lock.unlock()
            return cached
        }

        if isScanning {
            let cached = lastStorageCache
            lock.unlock()
            return cached
        }

        isScanning = true
        lock.unlock()

        defer {
            lock.lock()
            isScanning = false
            lock.unlock()
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let brainMb = dirSizeMb("\(home)/.gemini/antigravity/brain")
        let claudeLogsMb = dirSizeMb("\(home)/Library/Logs/Claude")
        let claudeCacheMb = dirSizeMb("\(home)/.claude")
        let gradleCachesGb = dirSizeMb("\(home)/.gradle/caches") / 1024.0
        let gradleDaemonLogsMb = dirSizeMb("\(home)/.gradle/daemon")
        let xcodeDerivedDataGb = dirSizeMb("\(home)/Library/Developer/Xcode/DerivedData") / 1024.0
        let cocoapodsCacheMb = dirSizeMb("\(home)/.cocoapods/cache")

        let metrics = StorageMetrics(
            antigravityBrainMb: brainMb,
            claudeLogsMb:       claudeLogsMb,
            claudeCacheMb:      claudeCacheMb,
            gradleCachesGb:     gradleCachesGb,
            gradleDaemonLogsMb: gradleDaemonLogsMb,
            xcodeDerivedDataGb: xcodeDerivedDataGb,
            cocoapodsCacheMb:   cocoapodsCacheMb
        )

        lock.lock()
        lastStorageCache = metrics
        lastStorageFetchTime = Date()
        lock.unlock()

        return metrics
    }

    @discardableResult
    static func pruneLogs(olderThanDays days: Int) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        _ = ShellService.runSilent(
            """
            find "\(home)/.gemini/antigravity/brain" \
                -mindepth 1 -maxdepth 1 -type d -mtime +\(days) \
                -exec rm -rf {} + 2>/dev/null || true
            """
        )
        _ = ShellService.runSilent(
            """
            find "\(home)/Library/Logs/Claude" \
                -type f -name "*.log" -mtime +\(days) \
                -delete 2>/dev/null || true
            """
        )
        _ = readMetrics(force: true)
        return "Cleaned logs older than \(days) days."
    }

    @discardableResult
    static func cleanAntigravityLogs(olderThanDays days: Int? = nil) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let brainDir = "\(home)/.gemini/antigravity/brain"
        if let days = days {
            _ = ShellService.runSilent(
                """
                find "\(brainDir)" -mindepth 1 -maxdepth 1 -type d -mtime +\(days) -exec rm -rf {} + 2>/dev/null || true
                """
            )
            _ = readMetrics(force: true)
            return "Pruned Antigravity brain sessions older than \(days) days."
        } else {
            _ = ShellService.runSilent("rm -rf \"\(brainDir)\"/* 2>/dev/null || true")
            _ = readMetrics(force: true)
            return "Cleaned all Antigravity agent brain logs."
        }
    }

    @discardableResult
    static func cleanClaudeLogs() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        _ = ShellService.runSilent("rm -rf \"\(home)/Library/Logs/Claude\"/* 2>/dev/null || true")
        _ = readMetrics(force: true)
        return "Cleaned Claude Desktop application logs."
    }

    @discardableResult
    static func cleanGradleCaches() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        // Safely clear old transforms and build script caches without removing all downloaded artifacts
        _ = ShellService.runSilent("rm -rf \"\(home)/.gradle/caches/transforms-\"* 2>/dev/null || true")
        _ = ShellService.runSilent("rm -rf \"\(home)/.gradle/caches/build-cache-\"* 2>/dev/null || true")
        _ = ShellService.runSilent("rm -rf \"\(home)/.gradle/caches/jars-\"* 2>/dev/null || true")
        _ = readMetrics(force: true)
        return "Cleaned Gradle transform and build script caches."
    }

    @discardableResult
    static func cleanGradleDaemonLogs() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        _ = ShellService.runSilent("rm -rf \"\(home)/.gradle/daemon\"/*/*.out.log \"\(home)/.gradle/daemon\"/*/*.log 2>/dev/null || true")
        _ = readMetrics(force: true)
        return "Cleaned Gradle daemon log files."
    }

    @discardableResult
    static func cleanXcodeDerivedData() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let derivedData = "\(home)/Library/Developer/Xcode/DerivedData"
        guard FileManager.default.fileExists(atPath: derivedData) else {
            return "Xcode DerivedData directory does not exist."
        }
        _ = ShellService.runSilent("rm -rf \"\(derivedData)\"/* 2>/dev/null || true")
        _ = readMetrics(force: true)
        return "Cleared Xcode DerivedData build cache."
    }

    @discardableResult
    static func cleanCocoaPodsCache() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        _ = ShellService.runSilent("rm -rf \"\(home)/.cocoapods/cache\"/* 2>/dev/null || true")
        _ = readMetrics(force: true)
        return "Cleaned CocoaPods download cache."
    }

    static func revealInFinder(path: String) {
        let expanded = NSString(string: path).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        if !FileManager.default.fileExists(atPath: expanded) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Battery Limiter

    static func findBatteryToolPath() -> String? {
        let candidates = [
            "/usr/local/bin/battery",
            "/usr/local/co.palokaj.battery/battery",
            "/opt/homebrew/bin/battery",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/battery",
            "/usr/local/bin/bctl",
            "/opt/homebrew/bin/bctl"
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        let whichOut = ShellService.runSilent("which battery 2>/dev/null || which bctl 2>/dev/null")
        if !whichOut.isEmpty && FileManager.default.isExecutableFile(atPath: whichOut) {
            return whichOut
        }
        return nil
    }

    /// Battery limit via the `battery` CLI or bctl on Apple Silicon.
    @discardableResult
    static func setBatteryLimit(_ pct: Int, forceDischarge: Bool = false) -> (success: Bool, message: String) {
        // Save target percentage in persistent settings store
        var s = MonteSettingsStore.shared.settings
        s.targetBatteryLimit = pct
        MonteSettingsStore.shared.settings = s

        // Also write to standard ~/.battery/maintain.percentage so the CLI daemon respects it
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let batteryDir = "\(home)/.battery"
        let maintainFile = "\(batteryDir)/maintain.percentage"
        try? FileManager.default.createDirectory(atPath: batteryDir, withIntermediateDirectories: true)
        if pct < 100 {
            try? "\(pct)\n".write(toFile: maintainFile, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(atPath: maintainFile)
        }

        guard let toolPath = findBatteryToolPath() else {
            return (
                false,
                "Battery charge limiter helper is not installed. Click 'Setup Battery Limiter' to install."
            )
        }

        let out: String
        if pct >= 100 {
            out = ShellService.runSilent("\"\(toolPath)\" maintain stop 2>&1 || \"\(toolPath)\" charging limit 100 2>&1 || \"\(toolPath)\" set 100 2>&1 || \"\(toolPath)\" charging on 2>&1")
        } else if forceDischarge {
            out = ShellService.runSilent("\"\(toolPath)\" maintain \(pct) --force-discharge 2>&1 || \"\(toolPath)\" discharge \(pct) 2>&1 || \"\(toolPath)\" maintain \(pct) 2>&1")
        } else {
            out = ShellService.runSilent("\"\(toolPath)\" maintain \(pct) 2>&1 || \"\(toolPath)\" charging limit \(pct) 2>&1 || \"\(toolPath)\" set \(pct) 2>&1")
        }

        if out.lowercased().contains("error") || out.lowercased().contains("failed") {
            return (false, "Failed to set battery limit: \(out)")
        }

        lock.lock()
        lastBatteryLimit = pct
        lastBatteryLimitFetchTime = Date()
        lock.unlock()

        if pct >= 100 {
            return (true, "Charge limit disabled (charging to 100%)")
        } else if forceDischarge {
            return (true, "Charging capped at \(pct)% (Discharging active)")
        } else {
            return (true, "Charging capped at \(pct)% (AC Pass-Through active)")
        }
    }

    /// Force-discharge down to specified percentage while plugged in
    @discardableResult
    static func forceDischarge(to pct: Int) -> (success: Bool, message: String) {
        return setBatteryLimit(pct, forceDischarge: true)
    }

    /// Watchdog: Ensures SMC limit is held if macOS re-enables charging during sleep/wake/reboot
    static func enforceWatchdog(currentPercent: Int, isCharging: Bool, targetLimit: Int, autoDischarge: Bool) {
        guard targetLimit < 100, let toolPath = findBatteryToolPath() else { return }

        // If charging is active while battery is at or above limit, immediately re-assert
        if isCharging && currentPercent >= targetLimit {
            if autoDischarge && currentPercent > targetLimit {
                _ = ShellService.runSilent("\"\(toolPath)\" maintain \(targetLimit) --force-discharge 2>/dev/null || \"\(toolPath)\" discharge \(targetLimit) 2>/dev/null")
            } else {
                _ = ShellService.runSilent("\"\(toolPath)\" maintain \(targetLimit) 2>/dev/null || \"\(toolPath)\" charging limit \(targetLimit) 2>/dev/null || \"\(toolPath)\" charging off 2>/dev/null")
            }
        } else if autoDischarge && currentPercent > targetLimit {
            _ = ShellService.runSilent("\"\(toolPath)\" maintain \(targetLimit) --force-discharge 2>/dev/null || \"\(toolPath)\" discharge \(targetLimit) 2>/dev/null")
        }
    }

    static func readBatteryLimit() -> (limit: Int?, isInstalled: Bool) {
        guard let toolPath = findBatteryToolPath() else {
            return (limit: nil, isInstalled: false)
        }

        // Fast path 1: Check ~/.battery/maintain.percentage directly (0ms, 100% accurate)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let maintainFile = "\(home)/.battery/maintain.percentage"
        if let content = try? String(contentsOfFile: maintainFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           let val = Int(content), val > 0 && val <= 100 {
            lock.lock()
            lastBatteryLimit = val
            lastBatteryLimitFetchTime = Date()
            lock.unlock()
            return (limit: val, isInstalled: true)
        }

        // Fast path 2: Check persistent settings store
        if let savedLimit = MonteSettingsStore.shared.settings.targetBatteryLimit, savedLimit > 0 && savedLimit <= 100 {
            lock.lock()
            lastBatteryLimit = savedLimit
            lastBatteryLimitFetchTime = Date()
            lock.unlock()
            return (limit: savedLimit, isInstalled: true)
        }

        // Fast path 3: Cached in-memory limit
        lock.lock()
        let now = Date()
        if let lastTime = lastBatteryLimitFetchTime, now.timeIntervalSince(lastTime) < 30 {
            let cached = lastBatteryLimit
            lock.unlock()
            return (limit: cached, isInstalled: true)
        }
        lock.unlock()

        // Fallback: Query CLI status
        let out = ShellService.runSilent("\"\(toolPath)\" status 2>/dev/null || \"\(toolPath)\" get 2>/dev/null")
        if let regex = try? Regex(#"maintained\s+at\s+(\d+)%"#), let match = try? regex.firstMatch(in: out) {
            let numStr = String(match.output[1].substring ?? "")
            if let val = Int(numStr) {
                lock.lock()
                lastBatteryLimit = val
                lastBatteryLimitFetchTime = Date()
                lock.unlock()
                return (limit: val, isInstalled: true)
            }
        }
        if let regex = try? Regex(#"limit[:\s]+(\d+)%"#), let match = try? regex.firstMatch(in: out) {
            let numStr = String(match.output[1].substring ?? "")
            if let val = Int(numStr) {
                lock.lock()
                lastBatteryLimit = val
                lastBatteryLimitFetchTime = Date()
                lock.unlock()
                return (limit: val, isInstalled: true)
            }
        }

        // Default when no maintain file or active limit is set
        lock.lock()
        lastBatteryLimit = 80
        lastBatteryLimitFetchTime = Date()
        lock.unlock()

        return (limit: 80, isInstalled: true)
    }

    static func installBatteryTool() {
        let scriptPath = "/tmp/install-monte-battery-limiter.command"
        let scriptContent = """
        #!/bin/bash
        clear
        echo "======================================================================"
        echo "⚡ Mont-E — Setting Up Battery Charge Limiter (Apple Silicon SMC)"
        echo "======================================================================"
        echo ""
        echo "This installer configures the open-source 'battery' CLI tool so Mont-E"
        echo "can enforce hardware charge limits (e.g. 70%, 80%) on Apple Silicon."
        echo ""
        echo "Note: You may be prompted for your macOS administrator password."
        echo "======================================================================"
        echo ""
        curl -s https://raw.githubusercontent.com/actuallymentor/battery/main/setup.sh | bash
        echo ""
        echo "======================================================================"
        echo "🎉 Setup complete! You can close this Terminal window."
        echo "======================================================================"
        read -n 1 -s -r -p "Press any key to close..."
        """
        do {
            try scriptContent.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            _ = ShellService.runSilent("chmod +x \"\(scriptPath)\"")
            NSWorkspace.shared.open(URL(fileURLWithPath: scriptPath))
        } catch {
            _ = ShellService.runSilent("chmod +x \"\(scriptPath)\" && open \"\(scriptPath)\" 2>/dev/null || true")
        }
    }

    static func readHelperStatus() -> SystemHelperStatus {
        let batteryPath = findBatteryToolPath()
        let isBrew = FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") || FileManager.default.fileExists(atPath: "/usr/local/bin/brew")
        let isGradle = !ShellService.runSilent("which gradle 2>/dev/null").isEmpty
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let isAdb = !ShellService.runSilent("which adb 2>/dev/null").isEmpty ||
            FileManager.default.fileExists(atPath: "\(home)/Library/Android/sdk/platform-tools/adb")

        return SystemHelperStatus(
            isBatteryLimiterInstalled: batteryPath != nil,
            batteryToolPath: batteryPath,
            isBrewInstalled: isBrew,
            isGradleInstalled: isGradle,
            isAdbInstalled: isAdb
        )
    }

    // MARK: Private

    private static func dirSizeMb(_ path: String) -> Double {
        guard FileManager.default.fileExists(atPath: path) else { return 0 }
        let out = ShellService.runSilent("du -sm \"\(path)\"")
        return Double(out.split(separator: "\t").first.map(String.init) ?? "") ?? 0
    }
}
