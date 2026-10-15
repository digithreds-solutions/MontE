# Mont-E ⚡💻

> **High-Performance macOS Developer Hardware, Battery & SSD Swap Optimizer**  
> Native Swift 6 / SwiftUI Menu Bar & Dashboard Suite for Apple Silicon (M1/M2/M3/M4) and Intel Macs.

[![macOS](https://img.shields.io/badge/macOS-13.0%2B-blue?logo=apple)](https://apple.com)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange?logo=swift)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-Apple%20Silicon%20%7C%20Intel-lightgrey)](https://apple.com)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/digithreds-solutions/MontE?include_prereleases&color=green)](https://github.com/digithreds-solutions/MontE/releases)

---

## 🌟 Overview

**Mont-E** is a lightweight, zero-bloat system monitor, hardware telemetry dashboard, and battery preservation tool engineered specifically for software engineers and power users on macOS. Built with pure Swift 6 and SwiftUI, Mont-E runs as an ultra-efficient menu bar accessory (`LSUIElement = YES`) with minimal CPU and memory footprints.

Whether you are running heavy Docker containers, compiling large Xcode/Gradle builds, or docked at your desk all day, Mont-E protects your hardware longevity and gives you immediate visibility into critical system vitals.

---

## ✨ Comprehensive Features

### ⚡ 1. Apple Silicon Hardware & SoC Telemetry
* **P-Core & E-Core Breakdown**: Real-time utilization split between Apple Silicon Performance Cores (P-Cores) and Efficiency Cores (E-Cores). Monitor which core cluster handles your foreground compilations vs background daemons.
* **Apple Silicon GPU & Neural Accelerator**: Direct telemetry from macOS `IOReport` channels reporting real-time GPU load, active frequency, and accelerator pressure.
* **Thermal State Monitoring**: Proactive thermal state reporting (`Nominal`, `Fair`, `Serious`, `Critical`) using `NSProcessInfo.thermalState`.
* **Active Cooling Fan RPM**: Live fan tachometer readings (RPM) and cooling states for MacBook Pro, Mac Studio, and Mac mini hardware.

### 🔋 2. Battery Longevity & Hardware SMC Limiter
* **Hardware Charge Limiter (80% / 70% Cap)**: Enforces hardware charge thresholds on Apple Silicon SMC firmware using the open-source `battery` CLI helper. Prevents lithium-ion swelling and permanent capacity degradation when connected to chargers or Thunderbolt docks continuously.
* **Battery Health & Wear Analytics**: Real-time reporting of battery cycle count, wear degradation percentage, current maximum capacity vs original factory design capacity, battery temperature, and live charging wattage.
* **Bluetooth Accessories Battery Monitor**: Automatically discovers and displays battery percentages for connected Apple and third-party peripherals:
  * AirPods & Charging Case
  * Magic Mouse, Magic Keyboard, and Magic Trackpad
  * Supported Bluetooth headsets and accessories

### ☕ 3. Smart Keep-Awake Engine
* **Flexible Sleep Assertions**: Prevents Mac sleep via native macOS `IOPMAssertionCreateWithName` APIs. Choose between **Prevent Display Sleep** or **Prevent System Idle Sleep**.
* **Pre-configured Timers**: Indefinite, 15m, 30m, 1h, 2h, 4h, 8h, or custom durations.
* **Automated Dev Build Triggers**: Automatically engages Keep-Awake whenever active developer tasks are running:
  * Xcode builds (`xcodebuild`)
  * Gradle daemons & Kotlin Multiplatform compilations (`gradle`)
  * Docker desktop & containers (`com.docker.backend`)
  * Swift Package Manager builds (`swift-frontend`)
* **Hardware Safety Fail-safe**:
  * Automatically disengages Keep-Awake if running on battery and charge drops below a configurable threshold (e.g. 20%).
  * Clamshell mode safety prevents accidental overheating while the lid is closed.

### 💾 4. SSD Swap & APFS Multi-Volume Monitor
* **SSD Swap Memory Pressure**: Real-time tracking of swap allocation (`sysctl vm.swapusage`) and SSD write bandwidth to prevent excessive wear on soldered Apple Silicon NAND storage.
* **APFS Multi-Volume Tracking**: Displays available free space and total capacity across all internal APFS containers as well as connected external drives and USB volumes.
* **Xcode DerivedData Cache Cleaner**: Continuously monitors the disk footprint of `~/Library/Developer/Xcode/DerivedData` with a 1-click safe purge action to reclaim tens of gigabytes of disk space instantly.

### 📶 5. Wi-Fi Diagnostics & Link Quality
* **Native CoreWLAN Integration**: Displays live SSID, BSSID, RSSI dBm signal strength, noise floor dBm, and calculated Signal-to-Noise Ratio (SNR).
* **Channel & Frequency Band**: Real-time channel identification and Wi-Fi band reporting (2.4 GHz, 5 GHz, or 6 GHz Wi-Fi 6E).
* **Transmit Link Rate & Local IPv4**: Live Wi-Fi transmit rate in Mbps alongside the active local network IPv4 address.

### 🚨 6. Proactive Watchdog & Threshold Alerts
* Background health watchdog monitors critical thresholds and triggers native macOS notifications:
  * **Low APFS Disk Space**: Alert when boot volume free space dips below 15 GB.
  * **Excessive Swap Thrashing**: Alert when swap memory exceeds 2 GB.
  * **Thermal Throttling**: Alert when thermal state reaches `Serious` or `Critical`.
  * **Low Peripheral Battery**: Alert when Magic Mouse, Trackpad, or AirPods reach $\le 20\%$.

### 🎛️ 7. Customizable Dashboard Overview & Menu Bar HUD
* **Modular Cards**: Toggle visibility and re-order cards for CPU/Cores, GPU, Memory/Swap, Battery, Storage, Wi-Fi, Bluetooth Accessories, and Keep-Awake.
* **Live Sparkline Telemetry**: Dynamic mini-charts render historical trends over time.
* **Configurable Menu Bar View**: Choose between a 2-column stats grid or a compact list layout.

---

## 🚀 Installation

### Option 1: Download Pre-built DMG (Recommended)
1. Download the latest `Monte-<version>.dmg` installer from the [GitHub Releases](https://github.com/digithreds-solutions/MontE/releases) page.
2. Open the `.dmg` file and drag **Mont-E.app** into your `/Applications` directory.
3. Launch Mont-E from Spotlight or Launchpad.

### Option 2: Build from Source
Ensure Xcode 15.4+ or Command Line Tools with Swift 6 is installed:
```bash
# Clone repository
git clone https://github.com/digithreds-solutions/MontE.git
cd MontE

# Build release DMG & automatically install to /Applications
./build.sh
```

---

## ⌨️ Global Shortcuts

| Shortcut | Action |
|---|---|
| `Cmd + Shift + M` | Open / Focus Mont-E Dashboard Overview |
| `Cmd + ,` | Open Preferences & Settings |
| `Cmd + W` | Close Dashboard Window |
| `Cmd + Q` | Quit Mont-E |

---

## 🛠️ Project Structure & Architecture

Mont-E strictly follows clean Swift 6 architecture with strict concurrency:

```text
MontE/
├── Package.swift               # Swift Package Manager manifest
├── Info.plist                  # macOS Application bundle metadata (LSUIElement = YES)
├── build.sh                    # Automated release build, codesigning & DMG packager
├── VERSION                     # Semantic version tracker (e.g. 2.0.0)
├── Packages/                   # Local distributable DMGs & package notes
│   ├── README.md
│   └── Monte-2.0.0.dmg
├── scripts/
│   └── bump-version.sh         # Semver bump script (major, minor, patch, custom)
├── .github/workflows/
│   ├── release-auto-minor.yml  # Automated release CI/CD workflow on commit to main
│   └── release-manual-major.yml# Manual workflow dispatch for major/custom releases
├── Resources/
│   └── AppIcon.icns            # High-resolution macOS application icon
└── Sources/
    └── Monte/
        ├── AppDelegate.swift   # NSApplication lifecycle & NSStatusItem controller
        ├── Models/             # System health models, telemetry structs, settings
        ├── ViewModels/         # MainActor Observable ViewModel & state coordination
        ├── Views/              # DashboardWindow, SettingsWindow, MenuStatsGridView
        └── Services/           # BatteryService, SensorService, GPUService,
                                # ShellService, StorageVolumeService, WatchdogAlertService
```

---

## 📄 License

This project is licensed under the terms of the **GNU General Public License v3.0**. See the [LICENSE](LICENSE) file for complete details.
