import Foundation
import ServiceManagement

// MARK: - Bulletproof Dual-Engine Launch at Login Service (SMAppService + User LaunchAgent)

struct LaunchAtLoginService {
    private static let launchAgentLabel = "com.digithreads.monte"
    
    private static var launchAgentPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(launchAgentLabel).plist")
    }

    static var isEnabled: Bool {
        get {
            MonteSettingsStore.shared.settings.launchAtLogin
        }
        set {
            var s = MonteSettingsStore.shared.settings
            s.launchAtLogin = newValue
            MonteSettingsStore.shared.settings = s
            setEnabled(newValue)
        }
    }

    /// Asynchronously registers or unregisters launch at login without blocking the main thread
    static func setEnabled(_ enabled: Bool) {
        Task(priority: .utility) {
            if enabled {
                register()
            } else {
                unregister()
            }
        }
    }

    /// Ensures login items and launch agents are active on startup if enabled in settings
    static func ensureSynchronized() {
        let shouldBeEnabled = MonteSettingsStore.shared.settings.launchAtLogin
        setEnabled(shouldBeEnabled)
    }

    private static func register() {
        var smRegistered = false
        // 1. SMAppService for macOS 13+ (Apple System Settings Login Items)
        if #available(macOS 13.0, *) {
            do {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
                if SMAppService.mainApp.status == .enabled {
                    smRegistered = true
                    // Remove fallback launch agent if SMAppService succeeded
                    removeLaunchAgent()
                }
            } catch {
                NSLog("SMAppService registration notice: \(error.localizedDescription)")
            }
        }

        // 2. Universal User LaunchAgent Plist Fallback (Survives ad-hoc signing, updates, & reboots)
        if !smRegistered {
            setupLaunchAgent()
        }
    }

    private static func unregister() {
        // 1. SMAppService
        if #available(macOS 13.0, *) {
            if SMAppService.mainApp.status == .enabled {
                try? SMAppService.mainApp.unregister()
            }
        }

        // 2. LaunchAgent removal
        removeLaunchAgent()
    }

    private static func setupLaunchAgent() {
        let launchAgentsDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
        try? FileManager.default.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)

        let execPath: String = {
            if let path = Bundle.main.executablePath, FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
            return "/Applications/Monte.app/Contents/MacOS/Monte"
        }()

        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(launchAgentLabel)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(execPath)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>ProcessType</key>
            <string>Interactive</string>
        </dict>
        </plist>
        """

        let plistURL = launchAgentPlistURL
        try? plistContent.write(to: plistURL, atomically: true, encoding: .utf8)
        
        let uid = getuid()
        _ = ShellService.runSilent("launchctl bootout gui/\(uid)/\(launchAgentLabel) 2>/dev/null || true")
        _ = ShellService.runSilent("launchctl bootstrap gui/\(uid) '\(plistURL.path)' 2>/dev/null || launchctl load -w '\(plistURL.path)' 2>/dev/null")
    }

    private static func removeLaunchAgent() {
        let plistURL = launchAgentPlistURL
        let uid = getuid()
        _ = ShellService.runSilent("launchctl bootout gui/\(uid)/\(launchAgentLabel) 2>/dev/null || launchctl unload -w '\(plistURL.path)' 2>/dev/null")
        try? FileManager.default.removeItem(at: plistURL)
    }
}
