import Foundation
import CoreWLAN
import SystemConfiguration

public struct WiFiDiagnostics: Sendable, Codable, Equatable {
    public var isConnected: Bool = false
    public var ssid: String = ""
    public var bssid: String = ""
    public var rssi: Int = 0
    public var noise: Int = 0
    public var channel: Int = 0
    public var band: String = ""
    public var interfaceName: String = "en0"
    public var localIPv4: String = ""
    public var transmitRateMbps: Double = 0.0

    public init(
        isConnected: Bool = false,
        ssid: String = "",
        bssid: String = "",
        rssi: Int = 0,
        noise: Int = 0,
        channel: Int = 0,
        band: String = "",
        interfaceName: String = "en0",
        localIPv4: String = "",
        transmitRateMbps: Double = 0.0
    ) {
        self.isConnected = isConnected
        self.ssid = ssid
        self.bssid = bssid
        self.rssi = rssi
        self.noise = noise
        self.channel = channel
        self.band = band
        self.interfaceName = interfaceName
        self.localIPv4 = localIPv4
        self.transmitRateMbps = transmitRateMbps
    }

    public var snr: Int {
        if rssi != 0 && noise != 0 {
            return rssi - noise
        }
        return 0
    }

    public var qualityLabel: String {
        guard isConnected else { return "Disconnected" }
        if rssi >= -55 { return "Excellent" }
        if rssi >= -67 { return "Good" }
        if rssi >= -78 { return "Fair" }
        return "Weak"
    }

    public var signalBars: Int {
        guard isConnected else { return 0 }
        if rssi >= -55 { return 4 }
        if rssi >= -67 { return 3 }
        if rssi >= -78 { return 2 }
        if rssi >= -88 { return 1 }
        return 1
    }

    public var channelBandDescription: String {
        if !band.isEmpty && channel > 0 {
            return "Ch \(channel) (\(band))"
        } else if channel > 0 {
            return "Ch \(channel)"
        }
        return "—"
    }
}

public final class NetworkDiagnosticsService: @unchecked Sendable {
    public static let shared = NetworkDiagnosticsService()
    private init() {}

    public func readWiFi() -> WiFiDiagnostics {
        var info = WiFiDiagnostics()
        info.localIPv4 = getLocalIPv4Address()

        guard let iface = CWWiFiClient.shared().interface() else {
            return info
        }

        info.interfaceName = iface.interfaceName ?? "en0"

        guard iface.powerOn() else {
            return info
        }

        let rssi = iface.rssiValue()
        if rssi != 0 {
            info.isConnected = true
            info.rssi = rssi
            info.noise = iface.noiseMeasurement()
            info.transmitRateMbps = iface.transmitRate()

            if let ssid = iface.ssid(), !ssid.isEmpty {
                info.ssid = ssid
            } else {
                info.ssid = "Wi-Fi (Connected)"
            }

            if let bssid = iface.bssid() {
                info.bssid = bssid
            }

            if let channel = iface.wlanChannel() {
                info.channel = channel.channelNumber
                switch channel.channelBand {
                case .band2GHz:
                    info.band = "2.4 GHz"
                case .band5GHz:
                    info.band = "5 GHz"
                case .band6GHz:
                    info.band = "6 GHz"
                case .bandUnknown:
                    info.band = channel.channelNumber > 14 ? "5 GHz" : "2.4 GHz"
                @unknown default:
                    info.band = channel.channelNumber > 14 ? "5 GHz" : "2.4 GHz"
                }
            }
        }

        return info
    }

    private func getLocalIPv4Address() -> String {
        var address = "—"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return address }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let addr = ptr.pointee.ifa_addr.pointee

            if (flags & (IFF_UP|IFF_RUNNING)) == (IFF_UP|IFF_RUNNING),
               (flags & IFF_LOOPBACK) == 0,
               addr.sa_family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(
                    ptr.pointee.ifa_addr,
                    socklen_t(addr.sa_len),
                    &hostname,
                    socklen_t(hostname.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                ) == 0 {
                    let ipStr = String(cString: hostname)
                    let ifName = String(cString: ptr.pointee.ifa_name)
                    if ifName == "en0" || ifName == "en1" {
                        return ipStr
                    }
                    if address == "—" {
                        address = ipStr
                    }
                }
            }
        }
        return address
    }
}
