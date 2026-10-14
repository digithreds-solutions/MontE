import Foundation
import IOKit
import IOBluetooth

// MARK: - Bluetooth Peripheral Battery Cockpit Service
// Reads connected Bluetooth accessory battery levels (AirPods L/R/Case, Magic Keyboard, Magic Mouse, Trackpad, Headsets).
// Pure native IOKit & IOBluetooth API, zero subprocess overhead.

enum BluetoothDeviceCategory: String, Codable, Sendable {
    case airpods = "AirPods"
    case headphones = "Headphones"
    case mouse = "Mouse"
    case keyboard = "Keyboard"
    case trackpad = "Trackpad"
    case accessory = "Accessory"

    var sfSymbol: String {
        switch self {
        case .airpods: return "airpodspro"
        case .headphones: return "headphones"
        case .mouse: return "magicmouse"
        case .keyboard: return "keyboard"
        case .trackpad: return "hand.tap"
        case .accessory: return "wave.3.forward"
        }
    }
}

struct BluetoothDeviceInfo: Identifiable, Equatable, Sendable {
    var id: String { address }
    let address: String
    let name: String
    let category: BluetoothDeviceCategory
    let isConnected: Bool

    // Battery values (0 - 100, nil if not reported or not applicable)
    var batteryPercent: Int? = nil
    var leftBatteryPercent: Int? = nil
    var rightBatteryPercent: Int? = nil
    var caseBatteryPercent: Int? = nil

    var hasBattery: Bool {
        batteryPercent != nil || leftBatteryPercent != nil || rightBatteryPercent != nil
    }

    var primaryBatteryDisplay: String {
        if let b = batteryPercent, b > 0 {
            return "\(b)%"
        }
        if let l = leftBatteryPercent, let r = rightBatteryPercent {
            return "L:\(l)% R:\(r)%"
        }
        if let l = leftBatteryPercent {
            return "\(l)%"
        }
        if let r = rightBatteryPercent {
            return "\(r)%"
        }
        return "—"
    }
}

final class BluetoothBatteryService: @unchecked Sendable {

    static let shared = BluetoothBatteryService()
    private let lock = NSLock()

    // Cache to avoid querying IOBluetooth at high frequency (rate-limited to 5s)
    private var cachedDevices: [BluetoothDeviceInfo] = []
    private var lastSampleTime: Date = .distantPast

    func readConnectedDevices(force: Bool = false) -> [BluetoothDeviceInfo] {
        lock.lock()
        defer { lock.unlock() }

        let now = Date()
        if !force && now.timeIntervalSince(lastSampleTime) < 4.0 {
            return cachedDevices
        }

        var results: [BluetoothDeviceInfo] = []

        // 1. Query IOBluetooth paired and connected devices
        if let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] {
            for device in paired {
                guard device.isConnected() else { continue }

                let name = device.nameOrAddress ?? device.name ?? "Bluetooth Device"
                let address = device.addressString ?? UUID().uuidString
                let lower = name.lowercased()

                let category: BluetoothDeviceCategory
                if lower.contains("airpod") {
                    category = .airpods
                } else if lower.contains("keyboard") {
                    category = .keyboard
                } else if lower.contains("mouse") {
                    category = .mouse
                } else if lower.contains("trackpad") {
                    category = .trackpad
                } else if lower.contains("headphone") || lower.contains("rockerz") || lower.contains("earbud") || lower.contains("buds") || lower.contains("wh-") || lower.contains("bose") || lower.contains("sony") {
                    category = .headphones
                } else {
                    category = .accessory
                }

                // Read KVC battery values supported natively on Apple IOBluetoothDevice
                let single = (device.value(forKey: "batteryPercentSingle") as? NSNumber)?.intValue
                let left = (device.value(forKey: "batteryPercentLeft") as? NSNumber)?.intValue
                let right = (device.value(forKey: "batteryPercentRight") as? NSNumber)?.intValue
                let casePct = (device.value(forKey: "batteryPercentCase") as? NSNumber)?.intValue
                let combined = (device.value(forKey: "batteryPercentCombined") as? NSNumber)?.intValue

                var mainBatt = single ?? combined
                if let b = mainBatt, b <= 0 {
                    mainBatt = nil
                }

                let validLeft = (left != nil && left! > 0) ? left : nil
                let validRight = (right != nil && right! > 0) ? right : nil
                let validCase = (casePct != nil && casePct! > 0) ? casePct : nil

                results.append(BluetoothDeviceInfo(
                    address: address,
                    name: name,
                    category: category,
                    isConnected: true,
                    batteryPercent: mainBatt,
                    leftBatteryPercent: validLeft,
                    rightBatteryPercent: validRight,
                    caseBatteryPercent: validCase
                ))
            }
        }

        // 2. Query AppleDeviceManagementHIDEventService for Magic Mouse/Keyboard/Trackpad
        var iterator: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"), &iterator) == KERN_SUCCESS {
            var service = IOIteratorNext(iterator)
            while service != 0 {
                var properties: Unmanaged<CFMutableDictionary>?
                if IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                   let dict = properties?.takeRetainedValue() as? [String: Any],
                   let prod = dict["Product"] as? String,
                   !prod.contains("Internal") {

                    let batt = dict["BatteryPercent"] as? Int ?? (dict["BatteryPercent"] as? NSNumber)?.intValue
                    if let batt = batt, batt > 0 {
                        let lower = prod.lowercased()
                        let category: BluetoothDeviceCategory
                        if lower.contains("mouse") {
                            category = .mouse
                        } else if lower.contains("keyboard") {
                            category = .keyboard
                        } else if lower.contains("trackpad") {
                            category = .trackpad
                        } else {
                            category = .accessory
                        }

                        let addr = (dict["DeviceAddress"] as? String) ?? (dict["SerialNumber"] as? String) ?? prod
                        if let index = results.firstIndex(where: { $0.name.lowercased() == prod.lowercased() || $0.address == addr }) {
                            results[index].batteryPercent = batt
                        } else {
                            results.append(BluetoothDeviceInfo(
                                address: addr,
                                name: prod,
                                category: category,
                                isConnected: true,
                                batteryPercent: batt
                            ))
                        }
                    }
                }
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            IOObjectRelease(iterator)
        }

        lastSampleTime = now
        cachedDevices = results
        return results
    }
}
