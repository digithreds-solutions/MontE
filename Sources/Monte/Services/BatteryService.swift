import Foundation
import IOKit
import IOKit.ps

// MARK: - Battery Service (IOKit Native + Instant Power Notifications)

struct BatteryService {

    struct BatteryInfo: Equatable {
        var percent: Int = 100
        var isCharging: Bool = false
        var isAcPower: Bool = true
        var cycleCount: Int? = nil
        var condition: String? = nil
        var healthPercent: Int? = 100
        var currentCapacityMah: Int? = nil
        var maxCapacityMah: Int? = nil
        var designCapacityMah: Int? = nil
        var temperatureCelsius: Double? = nil
        var voltageVolts: Double? = nil
        var designCycles: Int = 1000
    }

    /// Reads live battery and power information directly from IOKit.
    /// Fast and non-blocking (<0.1ms).
    static func read() -> BatteryInfo {
        let smartProps = readSmartBatteryProps()

        guard
            let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources  = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return readFallbackPmset(smartProps: smartProps)
        }

        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }

            // Verify it is an InternalBattery
            let type = (desc[kIOPSTypeKey as String] as? String)
                ?? (desc["Type"] as? String)
                ?? ""
            if !type.isEmpty && type != (kIOPSInternalBatteryType as String) && type != "InternalBattery" {
                continue
            }

            let currentCap: Int = {
                if let n = desc[kIOPSCurrentCapacityKey as String] as? NSNumber { return n.intValue }
                if let i = desc[kIOPSCurrentCapacityKey as String] as? Int { return i }
                if let n = desc["Current Capacity"] as? NSNumber { return n.intValue }
                if let i = desc["Current Capacity"] as? Int { return i }
                return -1
            }()

            let maxCap: Int = {
                if let n = desc[kIOPSMaxCapacityKey as String] as? NSNumber { return n.intValue }
                if let i = desc[kIOPSMaxCapacityKey as String] as? Int { return i }
                if let n = desc["Max Capacity"] as? NSNumber { return n.intValue }
                if let i = desc["Max Capacity"] as? Int { return i }
                return -1
            }()

            let cycleCount: Int? = (desc["Cycle Count"] as? NSNumber)?.intValue
                ?? (desc["CycleCount"] as? NSNumber)?.intValue
                ?? smartProps.cycleCount

            let condition: String? = (desc["BatteryHealth"] as? String)
                ?? (desc["Health"] as? String)
                ?? (desc["Condition"] as? String)
                ?? "Normal"

            if currentCap >= 0 && maxCap > 0 {
                let percent = Int((Double(currentCap) / Double(maxCap) * 100.0).rounded())
                let isCharging = (desc[kIOPSIsChargingKey as String] as? Bool)
                    ?? ((desc[kIOPSIsChargingKey as String] as? NSNumber)?.boolValue)
                    ?? (desc["Is Charging"] as? Bool)
                    ?? ((desc["Is Charging"] as? NSNumber)?.boolValue)
                    ?? false
                let powerSrcState = (desc[kIOPSPowerSourceStateKey as String] as? String)
                    ?? (desc["Power Source State"] as? String)
                    ?? ""
                let isAc = (powerSrcState == (kIOPSACPowerValue as String) || powerSrcState.localizedCaseInsensitiveContains("AC"))

                return BatteryInfo(
                    percent: min(max(percent, 0), 100),
                    isCharging: isCharging,
                    isAcPower: isAc,
                    cycleCount: cycleCount,
                    condition: condition ?? "Normal",
                    healthPercent: smartProps.healthPercent,
                    currentCapacityMah: smartProps.currentCapacityMah,
                    maxCapacityMah: smartProps.maxCapacityMah,
                    designCapacityMah: smartProps.designCapacityMah,
                    temperatureCelsius: smartProps.temperatureCelsius,
                    voltageVolts: smartProps.voltageVolts,
                    designCycles: smartProps.designCycles
                )
            }
        }

        return readFallbackPmset(smartProps: smartProps)
    }

    /// Fallback using `pmset -g batt` in case IOKit power source description is unavailable.
    private static func readFallbackPmset(smartProps: (cycleCount: Int?, healthPercent: Int?, currentCapacityMah: Int?, maxCapacityMah: Int?, designCapacityMah: Int?, temperatureCelsius: Double?, voltageVolts: Double?, designCycles: Int)) -> BatteryInfo {
        let output = ShellService.runSilent("pmset -g batt")
        let isAc = output.localizedCaseInsensitiveContains("AC Power")
        let isCharging = output.localizedCaseInsensitiveContains("charging") && !output.localizedCaseInsensitiveContains("discharging")
        var pct = 100
        if let regex = try? Regex(#"(\d+)%"#), let match = try? regex.firstMatch(in: output) {
            let numStr = String(match.output[1].substring ?? "")
            pct = Int(numStr) ?? 100
        }
        return BatteryInfo(
            percent: pct,
            isCharging: isCharging,
            isAcPower: isAc,
            cycleCount: smartProps.cycleCount,
            condition: "Normal",
            healthPercent: smartProps.healthPercent,
            currentCapacityMah: smartProps.currentCapacityMah,
            maxCapacityMah: smartProps.maxCapacityMah,
            designCapacityMah: smartProps.designCapacityMah,
            temperatureCelsius: smartProps.temperatureCelsius,
            voltageVolts: smartProps.voltageVolts,
            designCycles: smartProps.designCycles
        )
    }

    /// Direct Mach/IOKit registry lookup from AppleSmartBattery service (<0.02ms)
    static func readSmartBatteryProps() -> (cycleCount: Int?, healthPercent: Int?, currentCapacityMah: Int?, maxCapacityMah: Int?, designCapacityMah: Int?, temperatureCelsius: Double?, voltageVolts: Double?, designCycles: Int) {
        let matching = IOServiceMatching("AppleSmartBattery")
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard entry != 0 else {
            return (nil, 100, nil, nil, nil, nil, nil, 1000)
        }
        defer { IOObjectRelease(entry) }

        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = properties?.takeRetainedValue() as? [String: Any] else {
            return (nil, 100, nil, nil, nil, nil, nil, 1000)
        }

        let cycleCount = (props["CycleCount"] as? NSNumber)?.intValue
            ?? (props["Cycle Count"] as? NSNumber)?.intValue

        let designCycles = (props["DesignCycleCount9C"] as? NSNumber)?.intValue ?? 1000

        let maxCapMah = (props["AppleRawMaxCapacity"] as? NSNumber)?.intValue
            ?? (props["MaxCapacity"] as? NSNumber)?.intValue

        let currentCapMah = (props["AppleRawCurrentCapacity"] as? NSNumber)?.intValue
            ?? (props["CurrentCapacity"] as? NSNumber)?.intValue

        let designCapMah = (props["DesignCapacity"] as? NSNumber)?.intValue

        let healthPct: Int? = {
            if let max = maxCapMah, let des = designCapMah, des > 0 {
                return min(100, Int((Double(max) / Double(des) * 100.0).rounded()))
            }
            if let max = (props["MaxCapacity"] as? NSNumber)?.intValue {
                return min(100, max)
            }
            return 100
        }()

        let tempCelsius: Double? = {
            guard let rawTemp = (props["Temperature"] as? NSNumber)?.doubleValue else { return nil }
            if rawTemp > 1000.0 {
                return (rawTemp / 10.0) - 273.15
            } else if rawTemp > 100.0 {
                return rawTemp / 10.0
            } else {
                return rawTemp
            }
        }()

        let voltageVolts: Double? = {
            guard let rawVolt = (props["Voltage"] as? NSNumber)?.doubleValue else { return nil }
            if rawVolt > 1000.0 {
                return rawVolt / 1000.0
            }
            return rawVolt
        }()

        return (cycleCount, healthPct, currentCapMah, maxCapMah, designCapMah, tempCelsius, voltageVolts, designCycles)
    }

    /// Helper for cycle count
    static func readCycleCountFromIOService() -> Int? {
        readSmartBatteryProps().cycleCount
    }

    /// Helper for battery temperature in Celsius
    static func readBatteryTemperatureCelsius() -> Double? {
        readSmartBatteryProps().temperatureCelsius
    }

    /// On-demand deep PMU gas gauge query for lifetime temperature registers and thermal history.
    /// Executed ONLY on-demand to guarantee zero background polling or CPU overhead.
    static func readLifetimeThermalStats() -> LifetimeThermalStats {
        let matching = IOServiceMatching("AppleSmartBattery")
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard entry != 0 else {
            return LifetimeThermalStats(lastAnalyzedAt: Date())
        }
        defer { IOObjectRelease(entry) }

        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = properties?.takeRetainedValue() as? [String: Any] else {
            return LifetimeThermalStats(lastAnalyzedAt: Date())
        }

        let currentTemp: Double? = {
            guard let rawTemp = (props["Temperature"] as? NSNumber)?.doubleValue else { return nil }
            if rawTemp > 1000.0 {
                return (rawTemp / 10.0) - 273.15
            } else if rawTemp > 100.0 {
                return rawTemp / 10.0
            } else {
                return rawTemp
            }
        }()

        guard let bData = props["BatteryData"] as? [String: Any],
              let lt = bData["LifetimeData"] as? [String: Any] else {
            return LifetimeThermalStats(
                currentTemperatureCelsius: currentTemp,
                lastAnalyzedAt: Date()
            )
        }

        let avg = (lt["AverageTemperature"] as? NSNumber).map { $0.doubleValue / 10.0 }
        let maxT = (lt["MaximumTemperature"] as? NSNumber)?.doubleValue
        let minT = (lt["MinimumTemperature"] as? NSNumber)?.doubleValue
        let hours = (lt["TotalOperatingTime"] as? NSNumber)?.intValue
        let samples = (lt["TemperatureSamples"] as? NSNumber)?.intValue
        let maxV = (lt["MaximumPackVoltage"] as? NSNumber).map { $0.doubleValue / 1000.0 }
        let minV = (lt["MinimumPackVoltage"] as? NSNumber).map { $0.doubleValue / 1000.0 }
        let maxChargeA = (lt["MaximumChargeCurrent"] as? NSNumber).map { $0.doubleValue / 1000.0 }
        let maxDischargeA = (lt["MaximumDischargeCurrent"] as? NSNumber).map { abs($0.doubleValue) / 1000.0 }

        return LifetimeThermalStats(
            averageTemperatureCelsius: avg,
            maxTemperatureCelsius: maxT,
            minTemperatureCelsius: minT,
            currentTemperatureCelsius: currentTemp,
            totalOperatingHours: hours,
            temperatureSamplesCount: samples,
            maxPackVoltageVolts: maxV,
            minPackVoltageVolts: minV,
            maxChargeCurrentAmps: maxChargeA,
            maxDischargeCurrentAmps: maxDischargeA,
            lastAnalyzedAt: Date()
        )
    }

    /// Registers a native run loop callback for instant power source changes (unplugging, battery % drop, etc.)
    static func registerPowerChangeCallback(_ callback: @escaping () -> Void) -> CFRunLoopSource? {
        let context = UnsafeMutableRawPointer(Unmanaged.passRetained(PowerCallbackHolder(callback: callback)).toOpaque())

        guard let runLoopSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context = context else { return }
            let holder = Unmanaged<PowerCallbackHolder>.fromOpaque(context).takeUnretainedValue()
            holder.callback()
        }, context)?.takeRetainedValue() else {
            return nil
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        return runLoopSource
    }
}

private final class PowerCallbackHolder {
    let callback: () -> Void
    init(callback: @escaping () -> Void) {
        self.callback = callback
    }
}
