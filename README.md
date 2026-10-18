# Mont-E

> **Native Hardware Telemetry, Battery Longevity & Performance Cockpit for macOS**  
> Engineered in pure Swift 6 and SwiftUI for Apple Silicon (M1/M2/M3/M4) and Intel Macs.

[![macOS](https://img.shields.io/badge/macOS-13.0%2B-000000?logo=apple&logoColor=white)](https://apple.com)
[![Swift](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-Apple%20Silicon%20%7C%20Intel-555555)](https://apple.com)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-00599C.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/digithreds-solutions/MontE?include_prereleases&color=28a745)](https://github.com/digithreds-solutions/MontE/releases)

---

## Overview

**Mont-E** is a lightweight, zero-overhead menu bar monitor and system performance cockpit engineered specifically for software developers and power users on macOS. Operating natively as an agent accessory (`LSUIElement`), Mont-E consumes virtually zero idle resources (0.0% CPU, sub-50MB memory footprint) while exposing deep hardware metrics that standard tools hide.

Mont-E protects battery cell longevity via Apple Silicon SMC charge limiting, prevents unintended sleep during active builds and tasks, tracks multi-core P/E-core distributions, provides a real-time smart network cockpit, and safeguards soldered SSDs from excessive swap wear.

---

## Key Capabilities

### 1. Apple Silicon SoC & Hardware Telemetry
* **P-Core & E-Core Utilization:** Real-time distribution breakdown between Apple Silicon Performance Cores (P-Cores) and Efficiency Cores (E-Cores). Monitor which core cluster handles your active builds versus background daemons.
* **GPU & Neural Accelerator Load:** Direct telemetry from macOS `IOReport` accelerator channels, providing active GPU core load and VRAM residency.
* **Thermal State Classification:** Continuous thermal state monitoring (`Nominal`, `Fair`, `Serious`, `Critical`) via Darwin process APIs.
* **Active Cooling Fan Tachometer:** Live fan speeds in RPM and cooling state for MacBook Pro, Mac Studio, and Mac mini hardware.

### 2. Battery Longevity & SMC Charge Limiter
* **Hardware Charge Threshold (80% / 70% Cap):** Interfaces directly with the Apple Silicon SMC to enforce maximum charge thresholds. Prevents lithium-ion swelling and permanent capacity degradation when connected to chargers or Thunderbolt docks continuously.
* **Direct AC Pass-Through:** Allows the Mac to run directly on AC wall power without cycling or charging the battery cells once the limit is reached.
* **Cycle Count & Health Diagnostics:** Live monitoring of battery cycle count, wear degradation percentage, actual maximum capacity versus factory design capacity, battery temperature, and live wattage.
* **On-Demand PMU Diagnostics:** Inspect lifetime thermal averages, operating extremes, and lifetime sensor sample counts from the AppleSmartBattery Power Management Unit.

### 3. Smart Network Cockpit
* **Full-Width Network Strip:** Consolidated network header placed directly above the HUD grid.
* **Link Identity & Signal:** Real-time Wi-Fi SSID, RSSI signal strength in dBm, and evaluated link quality (`Excellent`, `Good`, `Fair`, `Weak`).
* **Live Differential Bandwidth:** Non-truncating upload and download speeds with fixed-width typography (`KB/s` and `MB/s`).
* **10-Minute Rolling Average:** Continuous 600-second rolling bandwidth average based on a 240-sample ring buffer.

### 4. Smart Keep-Awake Engine
* **Granular Sleep Assertions:** Native macOS power management assertions (`IOPMAssertionCreateWithName`) for both **Display Sleep** and **System Idle Sleep**.
* **Pre-configured Presets:** Indefinite, 15m, 30m, 1h, 2h, 4h, 8h, or custom until-time durations.
* **Automated Dev Build Triggers:** Automatically engages sleep prevention when active developer tasks are running:
  * Xcode compilations (`xcodebuild`)
  * Gradle daemons & Kotlin Multiplatform builds (`gradle`)
  * Docker containers (`com.docker.backend`)
  * Swift Package Manager builds (`swift-frontend`)
* **Hardware Fail-safes:** Automatically deactivates sleep prevention if running on battery below a configurable threshold (e.g., 20%) or if thermal throttling is detected.

### 5. Storage, SSD Swap & Cache Optimization
* **SSD Swap Risk Analysis:** Real-time tracking of swap memory pressure (`sysctl vm.swapusage`) and visual risk indicators (`Safe`, `Moderate`, `Critical`) to protect soldered Apple Silicon NAND storage from excessive wear.
* **APFS Multi-Volume Tracking:** Available free space and total capacity across all internal APFS containers and mounted external USB/Thunderbolt drives.
* **1-Click Developer Cache Cleaners:**
  * Clean Xcode `DerivedData` cache footprints.
  * Reclaim space from AI Agent brain logs and build artifacts.
  * Terminate idle Gradle daemons to free resident RAM immediately.

### 6. Customizable Menu Bar & HUD
* **Responsive Sizing:** Choose between **Small**, **Medium (Default)**, and **Large** HUD menu sizes to match your screen resolution and font preference.
* **Layout Styles:** Choose between a 2-Column Grid or a Compact List.
* **Zero-Resource Status Dot:** High-resolution static 3D LED indicator with physical bezel socket rendering and zero ongoing animation or CPU overhead.
* **Triple-Engine Launch at Login:** Seamlessly starts on macOS boot through synchronized System Events Login Items, user LaunchAgent plists, and `SMAppService`.

---

## Installation

### Option 1: Homebrew Cask (Recommended)

Install directly using Homebrew:

```bash
# Direct cask installation from repository
brew install --cask https://raw.githubusercontent.com/digithreds-solutions/MontE/main/Casks/monte.rb
```

Or tap the repository:

```bash
brew tap digithreds-solutions/monte
brew install --cask monte
```

### Option 2: Pre-built DMG Installer

1. Download the latest `Monte-<version>.dmg` from the **[GitHub Releases](https://github.com/digithreds-solutions/MontE/releases/latest)** page.
2. Open the downloaded `.dmg` file.
3. Drag **Monte.app** into your `/Applications` directory.
4. Launch Mont-E from Spotlight, Launchpad, or Finder.

### Option 3: Build from Source

Ensure Xcode 15.4+ or Command Line Tools with Swift 6 is installed:

```bash
# Clone the repository
git clone https://github.com/digithreds-solutions/MontE.git
cd MontE

# Build release binary, codesign, create DMG, and install to /Applications
./build.sh
```

---

## System Requirements

* **Operating System:** macOS 13.0 (Ventura), macOS 14.0 (Sonoma), macOS 15.0 (Sequoia), or later.
* **Hardware:** Apple Silicon (M1, M2, M3, M4, Pro, Max, Ultra) or Intel Core 64-bit processors.
* **Privileges:** Standard user privileges. Optional battery charge limiting features require standard administrator authorization once to configure the underlying SMC driver.

---

## Keyboard Shortcuts

| Shortcut | Description |
| :--- | :--- |
| `Cmd + Shift + M` | Open or focus the Mont-E Dashboard Overview |
| `Cmd + P` | Open Process Investigator & RAM Inspector |
| `Cmd + R` | Refresh all hardware metrics and telemetry |
| `Cmd + ,` | Open Preferences & Settings |
| `Cmd + W` | Close the active window |
| `Cmd + Q` | Terminate and quit Mont-E |

---

## Architecture & Technical Documentation

For developers, contributors, and systems engineers interested in the internal implementation, telemetry pipelines, and low-level kernel interfaces, please consult our detailed architecture documentation:

* **[Architecture & Technical Specifications (`docs/ARCHITECTURE.md`)](docs/ARCHITECTURE.md)**
  * High-level system architecture and component flow diagrams
  * Fast-path Mach kernel versus non-blocking asynchronous sampling lifecycles
  * Apple Silicon SMC charge limiting and Direct AC Pass-Through sequence
  * Triple-engine redundant Launch at Login mechanism
  * Swift 6 strict concurrency model and zero-overhead performance guarantees

---

## Project Structure

```text
MontE/
├── Casks/
│   └── monte.rb                # Official Homebrew Cask formula
├── docs/
│   └── ARCHITECTURE.md         # Comprehensive architectural specification with Mermaid diagrams
├── Package.swift               # Swift Package Manager manifest
├── Info.plist                  # macOS Application bundle metadata (LSUIElement = YES)
├── build.sh                    # Automated release build, codesigning & DMG packager
├── VERSION                     # Semantic version tracker (e.g. 2.6.0)
├── Packages/                   # Generated distributable release DMGs
│   └── Monte-2.6.0.dmg
├── Resources/
│   └── AppIcon.icns            # High-resolution macOS application icon
└── Sources/
    └── Monte/
        ├── AppDelegate.swift   # AppKit lifecycle, status item, & static 3D LED renderer
        ├── Models/             # Hardware models, telemetry structs, and HUDSettings
        ├── ViewModels/         # Observable ViewModel coordinating telemetry and UI state
        ├── Views/              # MenuStatsGridView, DashboardWindow, SettingsWindow
        └── Services/           # BatteryService, SensorService, GPUService,
                                # ShellService, StorageVolumeService, WatchdogAlertService,
                                # KeepAwakeService, LaunchAtLoginService
```

---

## License

Mont-E is open-source software licensed under the terms of the **GNU General Public License v3.0**. See the [LICENSE](LICENSE) file for complete details.

Copyright &copy; 2026 Digithreads. All rights reserved.
