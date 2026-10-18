# Mont-E Architecture & Technical Specifications

> **Notice:** The canonical, fully illustrated architectural documentation with sequence diagrams and subsystem deep dives is maintained in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

---

## Architecture Summary

Mont-E is built in pure **Swift 6** using a clean, layered architecture separating user interface presentation, observable domain state, specialized hardware drivers, and low-level Darwin/Mach kernel interfaces:

```mermaid
graph TD
    subgraph UI ["User Interface Layer (SwiftUI + AppKit)"]
        MenuBarItem["NSStatusItem (Menu Bar)"]
        DropdownHUD["MenuStatsGridView (Custom NSMenuItem)"]
        Dashboard["DashboardWindow (Multi-Tab Telemetry Cockpit)"]
        Settings["SettingsWindow (Preferences & Hardware Controls)"]
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
        LoginSvc["LaunchAtLoginService (Triple-Engine Launch Manager)"]
    end

    subgraph DarwinKernel ["macOS Subsystems & Kernel APIs"]
        Mach["Mach Kernel (host_processor_info)"]
        IOKit["IOKit / Apple Silicon SMC (AppleSmartBattery, PMU, SMC Keys)"]
        DarwinLibProc["Darwin libproc & sysctl (proc_pidinfo, vm.swapusage, statvfs)"]
        CoreWLAN["CoreWLAN Framework (CWWiFiClient)"]
        IOPM["IOPMAssertion (Power Management Assertions)"]
    end

    MenuBarItem --> VM
    DropdownHUD --> VM
    Dashboard --> VM
    Settings --> VM

    VM --> KeepAwake
    VM --> SettingsStore
    VM --> StatsService
    VM --> BatterySvc
    VM --> GPUSvc
    VM --> NetDiag
    VM --> SensorSvc
    Settings --> LoginSvc

    StatsService --> Mach
    StatsService --> DarwinLibProc
    BatterySvc --> IOKit
    GPUSvc --> IOKit
    SensorSvc --> IOKit
    NetDiag --> CoreWLAN
    KeepAwake --> IOPM
```

For full details on:
* **Telemetry Sampling & Polling Lifecycles**
* **Battery SMC Management & Direct AC Pass-Through**
* **Triple-Engine Launch at Login Architecture**
* **Subsystem Implementations (P/E-Cores, GPU, Network, Keep-Awake)**
* **Swift 6 Strict Concurrency & Performance Guarantees**

Please read the complete document at **[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)**.
