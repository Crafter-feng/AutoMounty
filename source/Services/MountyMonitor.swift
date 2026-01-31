import Foundation
import AutoMountyModel
import Network

@MainActor
class MountyMonitor: NSObject, ObservableObject {
    static let shared = MountyMonitor()
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "MountyMonitor")
    private var lastAutoMountAttempt: [UUID: Date] = [:]
    private let autoMountCooldown: TimeInterval = 5
    
    @Published var currentSSID: String?
    
    override init() {
        super.init()
    }
    
    func start() {
        Logger.info("MountyMonitor starting...")
        monitor.pathUpdateHandler = { path in
            Task { @MainActor in
                Logger.debug("Network path changed. Status: \(path.status)")
                if path.status == .satisfied {
                    self.checkSSID()
                    // Debounce or delay slightly to ensure network is fully ready
                    try? await Task.sleep(nanoseconds: 2 * 1_000_000_000)
                    Logger.info("Network satisfied, triggering checkAutoMount...")
                    self.checkAutoMount()
                }
            }
        }
        monitor.start(queue: queue)
        
        // Trigger initial check immediately after start
        Task { @MainActor in
             Logger.info("Performing initial network check...")
             self.checkSSID()
             // Small delay to ensure initial state is ready
             try? await Task.sleep(nanoseconds: 1 * 1_000_000_000)
             Logger.info("Initial checkAutoMount triggered.")
             self.checkAutoMount()
        }
    }
    
    func checkSSID() {
        // Note: Getting SSID requires Location Permission in recent macOS
        Task.detached {
            if let ssid = NetworkService.shared.getCurrentSSID() {
                await MainActor.run {
                    self.currentSSID = ssid
                }
            } else {
                await MainActor.run {
                    self.currentSSID = nil
                }
            }
        }
    }
    
    func checkAutoMount() {
        let profiles = ConfigManager.shared.profiles
        Logger.debug("Checking auto-mount for \(profiles.count) profiles")
        for profile in profiles {
            checkAutoMount(for: profile)
        }
    }
    
    func checkAutoMount(for profile: MountProfile) {
        // Priority: Enabled > AutoMount
        guard profile.isEnabled else { 
            Logger.debug("Profile \(profile.serverURL) is disabled, skipping auto-mount.")
            return 
        }
        guard profile.autoMount else { 
            Logger.debug("Profile \(profile.serverURL) auto-mount is OFF, skipping.")
            return 
        }
        
        // Check if manually unmounted by user (don't auto remount)
        if MountyManager.shared.isManuallyUnmounted(profile.id) {
            Logger.debug("Profile \(profile.serverURL) was manually unmounted, skipping auto-mount.")
            return
        }
        
        // Check if already mounted or mounting
        if MountyManager.shared.currentStatus[profile.id] == .mounted { 
            Logger.debug("Profile \(profile.serverURL) is already mounted, skipping.")
            return 
        }
        if MountyManager.shared.currentStatus[profile.id] == .mounting {
            Logger.debug("Profile \(profile.serverURL) is mounting, skipping.")
            return
        }
        
        if let lastAttempt = lastAutoMountAttempt[profile.id],
           Date().timeIntervalSince(lastAttempt) < autoMountCooldown {
            Logger.debug("Profile \(profile.serverURL) auto-mount is cooling down, skipping.")
            return
        }
        
        Logger.debug("Evaluating rules for \(profile.serverURL)...")
        Task {
            if await RuleService.shared.evaluateRules(for: profile, currentSSID: currentSSID) {
                Logger.info("Auto mounting \(profile.serverURL) because rules matched")
                lastAutoMountAttempt[profile.id] = Date()
                MountyManager.shared.mount(profile: profile) { _ in }
            } else {
                Logger.debug("Rules did not match for \(profile.serverURL)")
            }
        }
    }
}
