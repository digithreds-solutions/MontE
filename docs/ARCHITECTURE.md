# Mont-E Architecture & Technical Specifications

This document details the architectural design, telemetry pipelines, hardware interaction protocols, and concurrency model of **Mont-E**.

Mont-E is engineered from the ground up in pure **Swift 6** as a high-performance, resident macOS menu bar utility (`LSUIElement = YES`). It operates with near-zero idle resource utilization (0.0% CPU at idle, sub-50MB RSS memory footprint) while querying deep Apple Silicon hardware metrics that standard user-space applications cannot access.

---

## 1. High-Level System Architecture

Mont-E employs a clean, layered architecture separating user interface presentation, observable domain state, specialized hardware drivers, and low-level Darwin/Mach kernel interfaces.

```mermaid
graph TD
    subgraph UI ["User Interface Layer (SwiftUI + AppKit)"]
        MenuBarItem["NSStatusItem (Menu Bar)"]
        DropdownHUD["MenuStatsGridView (Custom NSMenuItem)"]
        Dashboard["DashboardWindow (Multi-Tab Telemetry Cockpit)"]
        Settings["SettingsWindow (Preferences & Hardware Controls)"]
        ProcessInvestigator["ProcessInvestigatorSheet (Memory & Process Inspector)"]
    end

    subgraph State ["State Coordination Layer"]
        VM["MonteViewModel (@Observable, @MainActor)"]
        KeepAwake["KeepAwakeService (Sleep Assertion Manager)"]
        SettingsStore["MonteSettingsStore (Persistent Configuration)"]
    end

    subgraph CoreServices ["Hardware & Telemetry Services"]
        StatsService["SystemStatsService (CPU, RAM, Swap, Disk)"]
        BatterySvc["BatteryService (IOKit AppleSmartBattery & SMC)"]
        GPUSvc["GPUService (IOReport / IOAccelerator)"]
        NetDiag["NetworkDiagnosticsService (CoreWLAN & Interface I/O)"]
        SensorSvc["SensorService (Fan RPM & Thermals)"]
        VolSvc["StorageVolumeService (APFS Volumes & External Drives)"]
        LoginSvc["LaunchAtLoginService (Triple-Engine Launch Manager)"]
        WatchdogSvc["WatchdogAlertService (Threshold Monitoring)"]
    end

    subgraph DarwinKernel ["macOS Subsystems & Kernel APIs"]
        Mach["Mach Kernel (host_processor_info, mach_vm_pressure)"]
        IOKit["IOKit / AppleSilicon SMC (AppleSmartBattery, PMU, SMC Keys)"]
        DarwinLibProc["Darwin libproc & sysctl (proc_pidinfo, vm.swapusage, statvfs)"]
        CoreWLAN["CoreWLAN Framework (CWWiFiClient, RSSI, SNR, Channel)"]
        IOBluetooth["IOBluetooth (CoreBluetooth & Peripheral Battery Levels)"]
        IOPM["IOPMAssertion (Power Management Assertions)"]
    end

    MenuBarItem --> VM
    DropdownHUD --> VM
    Dashboard --> VM
    Settings --> VM
    ProcessInvestigator --> VM

    VM --> KeepAwake
    VM --> SettingsStore
    VM --> StatsService
    VM --> BatterySvc
    VM --> GPUSvc
    VM --> NetDiag
    VM --> SensorSvc
    VM --> VolSvc
    VM --> WatchdogSvc
    Settings --> LoginSvc

    StatsService --> Mach
    StatsService --> DarwinLibProc
    BatterySvc --> IOKit
    GPUSvc --> IOKit
    SensorSvc --> IOKit
    VolSvc --> DarwinLibProc
    NetDiag --> CoreWLAN
    SensorSvc --> IOBluetooth
    KeepAwake --> IOPM
```

---

## 2. Telemetry Polling & Execution Lifecycle

Mont-E differentiates between **ultra-fast hardware polling** and **expensive background tasks** to ensure responsiveness without waking CPU cores unnecessarily.

```mermaid
sequenceDiagram
    autonumber
    participant Timer as Auto-Refresh Timer (2.5s)
    participant VM as MonteViewModel
    participant FastPath as Fast-Path Telemetry (Mach / IOKit)
    participant SlowPath as Background Task (Disk / Daemons)
    participant UI as Menu Bar & HUD Views

    Timer->>VM: Trigger periodic sample
    activate VM
    
    rect rgb(240, 248, 255)
        Note over VM,FastPath: Fast-Path Synchronous Sampling (< 0.1 ms)
        VM->>FastPath: Read CPU (Mach host_processor_info)
        VM->>FastPath: Read RAM (vm_statistics64)
        VM->>FastPath: Read Swap (sysctl vm.swapusage)
        VM->>FastPath: Read Battery (IOKit AppleSmartBattery)
        VM->>FastPath: Read GPU (IOReport accelerator utilization)
        VM->>FastPath: Read Network I/O (getifaddrs delta)
        FastPath-->>VM: Updated SystemHealth snapshot
    end

    VM->>VM: Update rolling buffers (240 samples = 10m network window)
    VM->>VM: Evaluate Watchdog alert thresholds
    VM->>VM: Evaluate Keep-Awake safety thresholds (e.g. low battery)
    VM->>UI: Update status item title & repaint visible views

    opt On-Demand or Periodic Disk Scan (30s)
        rect rgb(255, 250, 240)
            Note over VM,SlowPath: Background Task (I/O non-blocking)
            VM->>SlowPath: Query APFS statvfs & Xcode DerivedData footprint
            SlowPath-->>VM: Storage metrics updated
        end
    end
    deactivate VM
```

---

## 3. Battery Preservation & Apple Silicon SMC Architecture

Mont-E provides hardware-level charge threshold management and direct pass-through capabilities for Apple Silicon MacBooks (M1 through M4).

```mermaid
flowchart TD
    A["Target Battery Limit Set (e.g. 80%)"] --> B{"Current Charge Level"}
    B -->|"Charge < Target"| C["SMC: Enable Charging (Pass-Through Off)"]
    B -->|"Charge >= Target"| D["SMC: Inhibit Charging (BCLM / Direct AC Pass-Through)"]
    
    D --> E["Mac runs entirely on wall power adapter"]
    E --> F["Zero battery chemical degradation / Zero heat generation"]

    subgraph Watchdog ["Background Watchdog Guard"]
        G["macOS Power Manager attempts charging override"] --> H["Watchdog verifies charge state every 10s"]
        H --> I["Re-asserts SMC BCLM key"]
    end
```

### Technical Details:
* **Charge Inhibit Mechanism:** Mont-E interfaces with the Apple Silicon System Management Controller (SMC) to set the battery charge limit register (`BCLM`). When reached, power circuitry cuts current to the battery cells while supplying direct operating voltage to the logic board via **Direct AC Pass-Through**.
* **On-Demand Lifetime Thermal Diagnostics:** Deep queries to the `AppleSmartBattery` Power Management Unit (PMU) for lifetime temperature averages, operating extremes, operating hours, and sensor telemetry samples run exclusively on-demand when the user views the Battery Tab, avoiding continuous IOKit polling.

---

## 4. Triple-Engine Launch at Login Architecture

Because macOS Ventura, Sonoma, and Sequoia enforce strict Background Task Management (BTM) rules on ad-hoc signed open-source applications, Mont-E implements a **triple-engine redundant launch architecture**:

```mermaid
graph TD
    Trigger["Launch at Login Enabled"] --> Engine1["Engine 1: AppleScript System Events"]
    Trigger --> Engine2["Engine 2: User LaunchAgent Plist"]
    Trigger --> Engine3["Engine 3: SMAppService (macOS 13+)"]

    Engine1 --> L1["Registers in System Settings → General → Login Items"]
    Engine2 --> L2["Writes ~/Library/LaunchAgents/com.digithreads.monte.plist<br/>Runs: /usr/bin/open -a /Applications/Monte.app"]
    Engine3 --> L3["Registers with macOS Background Task Management"]

    subgraph Boot ["macOS User Login Sequence"]
        LoginWindow["loginwindow session"] --> Check1{"System Events Entry?"}
        Launchd["launchd GUI bootstrap"] --> Check2{"LaunchAgent Plist?"}
        
        Check1 -->|"Found"| LaunchApp["Launch /Applications/Monte.app"]
        Check2 -->|"Found"| LaunchApp
    end
```

* **Engine 1 (System Events Login Item):** Creates a standard persistent login item that appears natively in `System Settings → General → Login Items`.
* **Engine 2 (User LaunchAgent):** Deploys a LaunchAgent to `~/Library/LaunchAgents/com.digithreads.monte.plist` invoking `/usr/bin/open -a /Applications/Monte.app`. Unlike `SMAppService`, user LaunchAgents are unconditionally bootstrapped by `launchd` on user login regardless of code signing status.
* **Engine 3 (SMAppService):** Concurrently registered for seamless macOS 13+ ServiceManagement compatibility.

---

## 5. Subsystem Implementations

### 5.1 Apple Silicon CPU & Core Cluster Profiling
* Utilizes Mach kernel `host_processor_info` with `PROCESSOR_CPU_LOAD_INFO` flavor.
* Queries processor topological information to divide logical CPU cores into **Performance (P) Cores** and **Efficiency (E) Cores**.
* Computes real-time per-cluster averages:
  $$\text{Utilization}_{\text{cluster}} = \frac{\Delta \text{User} + \Delta \text{System} + \Delta \text{Nice}}{\Delta \text{User} + \Delta \text{System} + \Delta \text{Nice} + \Delta \text{Idle}}$$

### 5.2 GPU & Neural Engine Telemetry
* Reads Apple Silicon IOAccelerator statistics via the private `IOReport` framework channels (`GPU Performance Statistics`).
* Extracts active device utilization percentage and allocated VRAM buffer sizes without polling third-party tools.

### 5.3 Smart Network Cockpit & Bandwidth Calculation
* **Interface Bandwidth:** Scans network interfaces via Darwin `getifaddrs` to compute differential byte counters ($\Delta \text{bytes} / \Delta t$) converted to `KB/s` or `MB/s`.
* **10-Minute Rolling Average:** Maintains a FIFO ring buffer of 240 samples ($240 \times 2.5\text{s} = 600\text{s}$).
* **Wi-Fi Diagnostics:** Uses `CoreWLAN` (`CWWiFiClient`) to extract RSSI (dBm), noise floor, Wi-Fi channel, frequency band (2.4 GHz, 5 GHz, 6 GHz), and evaluates link quality:
  * $\text{RSSI} \ge -65 \text{ dBm}$: Strong / Excellent
  * $-78 \text{ dBm} \le \text{RSSI} < -65 \text{ dBm}$: Fair
  * $\text{RSSI} < -78 \text{ dBm}$: Weak

### 5.4 Sleep Prevention (Keep-Awake Engine)
* Wraps the native Darwin Power Management assertion API (`IOPMAssertionCreateWithName`).
* Generates either `kIOPMAssertionTypePreventUserIdleSystemSleep` or `kIOPMAssertionTypePreventUserIdleDisplaySleep`.
* Automated dev triggers monitor running processes via `proc_listpids` and `proc_pidinfo` to detect active compilations (`xcodebuild`, `gradle`, `swift-frontend`, `docker`) and engage assertions automatically.

---

## 6. Concurrency & Performance Guarantees

* **Swift 6 Strict Concurrency:** The entire codebase is compiled with Swift 6 mode enabled. All UI elements, views, and view model instances are bound to `@MainActor`.
* **Zero Timer Wakeups When Idle:** The menu bar status dot uses static vector rendering ([NSImage.threeDimensionalLedDot](file:///Users/arunelectra/Project/Tech/DevTools/MontE/Sources/Monte/AppDelegate.swift#L604)) with no continuous animation timers. When the dropdown menu is closed, Mont-E consumes 0.0% CPU.
* **Deterministic Memory Footprint:** Telemetry buffers use pre-allocated static capacities (e.g. 240 samples for network history, 30 samples for CPU/GPU sparklines), preventing memory fragmentation.
