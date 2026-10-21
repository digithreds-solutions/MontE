import Foundation
import ServiceManagement

// MARK: - Bulletproof Triple-Engine Launch at Login Service (SMAppService + LaunchAgent + System Events)

struct LaunchAtLoginService {
    private static let launchAgentLabel = "com.digithreads.monte"
    
    static var launchAgentPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(launchAgentLabel).plist")
    }

    private static var appPath: String {
        if let path = Bundle.main.bundlePath as String?, path.hasSuffix(".app") {
            return path
        }
        return "/Applications/Monte.app"
    }

    /// Fast, non-blocking check whether Monte is registered in the OS (via LaunchAgent file or SMAppService status)
    static var isRegisteredWithSystem: Bool {
        if FileManager.default.fileExists(atPath: launchAgentPlistURL.path) {
            return true
        }
        if #available(macOS 13.0, *) {
            if SMAppService.mainApp.status == .enabled {
                return true
            }
        }
        return false
    }

    static var isEnabled: Bool {
        get {
            if isRegisteredWithSystem {
                return true
            }
            return MonteSettingsStore.shared.settings.launchAtLogin
        }
        set {
            var s = MonteSettingsStore.shared.settings
            s.launchAtLogin = newValue
            MonteSettingsStore.shared.settings = s
            setEnabled(newValue)
        }
    }

    /// Opens macOS System Settings directly to the Login Items pane
    static func openSystemLoginItems() {
        if #available(macOS 13.0, *) {
            SMAppService.openSystemSettingsLoginItems()
        } else {
            _ = ShellService.runSilent("open 'x-apple.systempreferences:com.apple.LoginItems-Settings.extension' 2>/dev/null || open '/System/Library/PreferencePanes/Accounts.prefPane' 2>/dev/null")
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
        let shouldBeEnabled = MonteSettingsStore.shared.settings.launchAtLogin || isRegisteredWithSystem
        if shouldBeEnabled {
            setEnabled(true)
        } else {
            setEnabled(false)
        }
    }

    private static func register() {
        let path = appPath

        // 1. AppleScript System Events Login Item (Standard macOS Settings -> General -> Login Items)
        let addScript = """
        tell application "System Events"
            set existingItems to (every login item whose path contains "\(path)" or name is "Monte")
            if (count of existingItems) is 0 then
                make new login item at end of login items with properties {name:"Monte", path:"\(path)", hidden:false}
            end if
        end tell
        """
        _ = ShellService.runSilent("osascript -e '\(addScript)' 2>/dev/null || true")

        // 2. User LaunchAgent Plist Fallback (uses /usr/bin/open -a to launch cleanly with full windowing environment)
        setupLaunchAgent(appPath: path)

        // 3. SMAppService for macOS 13+ (System Settings Login Items integration)
        if #available(macOS 13.0, *) {
            do {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } catch {
                NSLog("SMAppService registration notice: \(error.localizedDescription)")
            }
        }
    }

    private static func unregister() {
        let path = appPath

        // 1. Remove System Events Login Item
        let removeScript = """
        tell application "System Events"
            delete (every login item whose path contains "\(path)")
            delete (every login item whose name is "Monte")
        end tell
        """
        _ = ShellService.runSilent("osascript -e '\(removeScript)' 2>/dev/null || true")

        // 2. Remove User LaunchAgent Plist
        removeLaunchAgent()

        // 3. SMAppService unregister
        if #available(macOS 13.0, *) {
            if SMAppService.mainApp.status == .enabled {
                try? SMAppService.mainApp.unregister()
            }
        }
    }

    private static func setupLaunchAgent(appPath: String) {
        let launchAgentsDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
        try? FileManager.default.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)

        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(launchAgentLabel)</string>
            <key>ProgramArguments</key>
            <array>
                <string>/usr/bin/open</string>
                <string>-a</string>
                <string>\(appPath)</string>
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
