import Foundation
import UserNotifications

final class WatchdogAlertService: @unchecked Sendable {
    static let shared = WatchdogAlertService()
    private init() {}

    private var lastAlertTimes: [String: Date] = [:]
    private let cooldownSeconds: TimeInterval = 1800 // 30 minutes cooldown per alert type

    func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func evaluate(health: SystemHealth, settings: WatchdogAlertSettings) {
        guard settings.alertsEnabled else { return }

        let now = Date()

        // 1. Low Free Disk Space Alert
        if settings.lowDiskAlert && health.diskFreeGb > 0 && health.diskFreeGb < Double(settings.lowDiskThresholdGb) {
            triggerAlert(
                id: "low_disk",
                title: "⚠️ Low Disk Space Alert",
                body: String(format: "Only %.1f GB free on primary volume. Clean Xcode DerivedData or AI Agent Brain caches in Mont-E.", health.diskFreeGb),
                now: now
            )
        }

        // 2. High SSD Swap Usage Alert
        if settings.highSwapAlert && health.swapUsedMb > Double(settings.highSwapThresholdMb) {
            triggerAlert(
                id: "high_swap",
                title: "🚨 Heavy SSD Swap Thrashing",
                body: String(format: "Active swap is %.1f GB (%@). Purge inactive memory or stop idle daemons to protect SSD wear.", health.swapUsedMb / 1024.0, health.swapRisk.label),
                now: now
            )
        }

        // 3. Thermal Throttling Alert
        if settings.highThermalAlert && (health.thermalStatus == .serious || health.thermalStatus == .critical) {
            triggerAlert(
                id: "high_thermal",
                title: "🔥 High SoC Thermal State",
                body: "Apple Silicon SoC is experiencing elevated thermals (\(health.thermalStatus.rawValue)). Active cooling or throttling engaged.",
                now: now
            )
        }

        // 4. Bluetooth Accessory Low Battery
        if settings.peripheralLowBatteryAlert {
            for dev in health.bluetoothDevices {
                let lowParts = [
                    dev.batteryPercent,
                    dev.leftBatteryPercent,
                    dev.rightBatteryPercent
                ].compactMap { $0 }.filter { $0 <= settings.peripheralBatteryThreshold }

                if !lowParts.isEmpty, let minBatt = lowParts.min() {
                    triggerAlert(
                        id: "bt_low_\(dev.address)",
                        title: "🪫 Low Battery: \(dev.name)",
                        body: "\(dev.name) is at \(minBatt)%. Charge accessory soon to prevent connection drops.",
                        now: now
                    )
                }
            }
        }
    }

    private func triggerAlert(id: String, title: String, body: String, now: Date) {
        if let last = lastAlertTimes[id], now.timeIntervalSince(last) < cooldownSeconds {
            return
        }
        lastAlertTimes[id] = now

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let req = UNNotificationRequest(identifier: "monte_alert_\(id)_\(Int(now.timeIntervalSince1970))", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }
}
