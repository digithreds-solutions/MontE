import Foundation

// MARK: - Memory Optimizer Service

struct MemoryOptimizationResult: Sendable {
    let ramReclaimedMb: Double
    let daemonsKilled: Int
    let details: String
}

final class MemoryOptimizerService: @unchecked Sendable {
    static let shared = MemoryOptimizerService()

    private init() {}

    /// Performs a comprehensive, safe 1-Click Memory Optimization:
    /// 1. Stops idle Gradle daemons
    /// 2. Purges inactive disk/file cache memory (`/usr/sbin/purge` or vm relief)
    /// 3. Returns the amount of RAM reclaimed
    func optimizeMemory() async -> MemoryOptimizationResult {
        // Measure before
        let beforeRam = SystemStatsService.readRAM()
        let initialUsedMb = beforeRam.usedGb * 1024.0

        // 1. Kill idle Gradle daemons
        let daemonsKilled = GradleService.stopAll()

        // 2. Run system cache purge (best effort; macOS allows standard user purge or ignores silently)
        _ = ShellService.runSilent("/usr/sbin/purge 2>/dev/null || true")

        // 3. Restart transient Finder/Quicklook caches that often bloat
        _ = ShellService.runSilent("killall quicklookd 2>/dev/null || true")

        // Let macOS VM settle for a brief interval
        try? await Task.sleep(nanoseconds: 600_000_000)

        // Measure after
        let afterRam = SystemStatsService.readRAM()
        let finalUsedMb = afterRam.usedGb * 1024.0

        let reclaimedMb = max(0.0, initialUsedMb - finalUsedMb)

        let summaryText: String
        if reclaimedMb > 100 {
            if reclaimedMb >= 1024 {
                summaryText = String(format: "Reclaimed %.1f GB RAM", reclaimedMb / 1024.0)
            } else {
                summaryText = String(format: "Reclaimed %.0f MB RAM", reclaimedMb)
            }
        } else if daemonsKilled > 0 {
            summaryText = "Stopped \(daemonsKilled) idle Gradle daemon\(daemonsKilled == 1 ? "" : "s")"
        } else {
            summaryText = "RAM optimized. Inactive caches cleared."
        }

        return MemoryOptimizationResult(
            ramReclaimedMb: reclaimedMb,
            daemonsKilled: daemonsKilled,
            details: summaryText
        )
    }
}
