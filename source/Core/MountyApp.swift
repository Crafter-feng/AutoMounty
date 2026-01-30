import SwiftUI

@main
struct MountyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        MenuBarExtra("Mounty", systemImage: "server.rack") {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)
        
        Window("Mounty Configuration", id: "main") {
            ContentView()
        }
        
        Window("Network Discovery", id: "discovery") {
            DiscoveryView()
        }
        .windowResizability(.contentSize)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 如果是纯二进制运行，默认可能需要 regular；但如果通过 Info.plist 设置了 LSUIElement=1，
        // 这里设置为 accessory 可以确保它是菜单栏应用，不显示 Dock 图标
        // 注意：SwiftUI Window Scene 默认会自动显示，如果不想显示，需要特殊处理
        // 或者依赖 LSUIElement 配合。
        
        // 我们在 Info.plist 中设置 LSUIElement 为 true，应用启动时不会显示窗口
        // 但为了兼容开发模式，这里强制设为 accessory (无 Dock 图标)
        NSApp.setActivationPolicy(.accessory)
        
        // Set default preferences
        UserDefaults.standard.register(defaults: ["AutoUpdateBonjourIP": true])
        
        // Scan for existing network mounts
        MountyManager.shared.scanAndImportMounts()
        
        // Check if we should update IPs before starting monitor
        if UserDefaults.standard.bool(forKey: "AutoUpdateBonjourIP") {
            Logger.info("Starting Bonjour IP update check...")
            
            var hasStarted = false
            func startMonitor() {
                if !hasStarted {
                    hasStarted = true
                    MountyMonitor.shared.start()
                }
            }
            
            // Timeout safety net (5 seconds)
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                if !hasStarted {
                    Logger.error("Bonjour IP update check timed out. Forcing start.")
                    startMonitor()
                }
            }
            
            NetworkDiscovery.shared.updateBonjourIPs(for: ConfigManager.shared.profiles) {
                Logger.info("Bonjour IP update check completed.")
                startMonitor()
            }
        } else {
            MountyMonitor.shared.start()
        }
    }
}
