# Mont-E ⚡💻

> **High-Performance macOS Developer Hardware, Battery & SSD Swap Optimizer**  
> Native Swift 6 / SwiftUI Menu Bar & Dashboard Suite for Apple Silicon (M1/M2/M3/M4) and Intel Macs.

[![macOS](https://img.shields.io/badge/macOS-13.0%2B-blue?logo=apple)](https://apple.com)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange?logo=swift)](https://swift.org)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

---

## ✨ Features

- **⚡ Apple Silicon Hardware Telemetry**:
  - Live Performance Cores (P-Cores) vs Efficiency Cores (E-Cores) cluster load breakdown.
  - Real-time Apple Silicon GPU usage & Neural Accelerator metrics via `IOReport`.
  - Thermal pressure monitoring with automatic safety thresholds.
  - Active fan speed monitoring (RPM) and cooling status.

- **🔋 Battery & Hardware SMC Limiter**:
  - Direct integration with open-source Apple Silicon SMC charge limits (e.g., 70%, 80% cap to prevent battery degradation).
  - Health monitoring: cycle count, wear degradation percentage, and design capacity.
  - Bluetooth peripheral battery levels (AirPods, Magic Mouse, Trackpad, Keyboards).

- **☕ Smart Keep-Awake Engine**:
  - Session timers with automatic display sleep controls via `IOPMAssertion`.
  - Dev build & daemon triggers: keep Mac awake while Xcode builds, Docker, or Gradle run.
  - Proactive battery fail-safe (auto-disengages keep-awake if battery dips below threshold).

- **💾 SSD Swap & Multi-Volume Storage**:
  - Real-time swap memory pressure and SSD write bandwidth monitoring.
  - Multi-volume APFS free space monitoring for internal and external drives.
  - Xcode DerivedData cache footprint detection with quick purge.

- **📶 Wi-Fi Diagnostics**:
  - Active SSID, BSSID, RSSI dBm signal strength, noise floor, and Signal-to-Noise Ratio (SNR).
  - Channel, band (2.4 GHz, 5 GHz, 6 GHz), link transmit rate (Mbps), and local IPv4.

- **🚨 Proactive Watchdog & Threshold Alerts**:
  - Real-time notifications for critical system states (low APFS disk space < 15 GB, excessive swap > 2 GB, high thermal throttling, low peripheral battery).

- **🎛️ Customizable Dashboard Overview**:
  - Modular cards with persistent user-arranged ordering and hide/show toggles.
  - Live sparkline telemetry graphs.

---

## 🚀 Installation & Quick Start

### Option 1: Download Pre-built DMG
Download the latest `Monte-2.0.0.dmg` installer directly from the [GitHub Releases](https://github.com/digithreds-solutions/MontE/releases) page. Open the DMG and drag **Mont-E.app** to your `/Applications` folder.

### Option 2: Build from Source (SwiftPM)
```bash
# Clone the repository
git clone https://github.com/digithreds-solutions/MontE.git
cd MontE

# Build release DMG & automatically install to /Applications
./build.sh
```

---

## ⌨️ Global Shortcuts

| Shortcut | Action |
|---|---|
| `Cmd + Shift + M` | Toggle Mont-E Dashboard Overview |
| `Cmd + ,` | Open Preferences & Settings |
| `Cmd + Q` | Quit Mont-E |

---

## 📄 License

This project is licensed under the terms of the GNU General Public License v3.0. See [LICENSE](LICENSE) for details.
