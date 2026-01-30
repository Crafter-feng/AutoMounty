import Foundation
import AppKit
import ServiceManagement

@MainActor
class SystemInfoService: ObservableObject {
    static let shared = SystemInfoService()
    
    @Published var isLaunchAtLoginEnabled: Bool = false
    
    private init() {
        self.isLaunchAtLoginEnabled = checkLaunchAtLoginEnabled()
    }
    
    // MARK: - Launch At Login
    
    private func checkLaunchAtLoginEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }
    
    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                self.isLaunchAtLoginEnabled = enabled
            } catch {
                Logger.error("Failed to toggle Launch at Login: \(error.localizedDescription)")
                // Revert UI state if operation failed
                DispatchQueue.main.async {
                    self.isLaunchAtLoginEnabled = self.checkLaunchAtLoginEnabled()
                }
            }
        }
    }
    
    // MARK: - Application Info
    
    /// Returns a list of currently running application names.
    func getRunningApplications() -> [String] {
        return NSWorkspace.shared.runningApplications.compactMap { $0.localizedName }.sorted()
    }
    
    /// Returns a list of installed application names (scanned from standard locations).
    /// This is a potentially heavy operation, consider running in a background task.
    nonisolated func getInstalledApplications() -> [String] {
        let directories = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities"
        ]
        var names = Set<String>()
        for directory in directories {
            let url = URL(fileURLWithPath: directory, isDirectory: true)
            if let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) {
                for case let fileURL as URL in enumerator where fileURL.pathExtension == "app" {
                    names.insert(fileURL.deletingPathExtension().lastPathComponent)
                }
            }
        }
        return Array(names).sorted()
    }
}
