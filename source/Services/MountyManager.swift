import Foundation
import AutoMountyModel
import NetFS
import AppKit

// Define NetFS keys if not available
nonisolated(unsafe) let kNetFSSoftMountKey = "SoftMount" as CFString
nonisolated(unsafe) let kNetFSMountAtMountDirKey = "MountAtMountDir" as CFString

@MainActor
class MountyManager: ObservableObject {
    static let shared = MountyManager()
    
    @Published var currentStatus: [UUID: MountStatus] = [:]
    @Published var mountPaths: [UUID: String] = [:] // Store actual mount paths
    
    // Track manually unmounted profiles to prevent auto-remount
    private var manuallyUnmountedProfiles: Set<UUID> = []
    
    private init() {
        setupObservers()
    }
    
    private func setupObservers() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleUnmountNotification(_:)),
            name: NSWorkspace.didUnmountNotification,
            object: nil
        )
    }
    
    @objc private func handleUnmountNotification(_ notification: Notification) {
        guard let path = notification.userInfo?["NSDevicePath"] as? String else { return }
        Logger.debug("System unmounted path: \(path)")
        
        Task { @MainActor in
            // Find profile matching this path
            if let (id, _) = mountPaths.first(where: { $0.value == path }) {
                Logger.info("Detected external unmount for profile ID: \(id)")
                updateStatus(for: id, status: .unmounted)
                mountPaths.removeValue(forKey: id)
                
                // Determine if this was a manual unmount or a network drop
                // If the server is reachable now, it's likely a manual unmount by user
                if let profile = ConfigManager.shared.profiles.first(where: { $0.id == id }) {
                    checkReachabilityAndMarkManual(for: profile)
                }
            }
        }
    }
    
    private func checkReachabilityAndMarkManual(for profile: MountProfile) {
        // We need a simple check. If we can resolve/ping the host, we assume network is fine
        // and the unmount was intentional.
        guard let host = URL(string: profile.serverURL)?.host else { return }
        
        // Use a simple task to check
        Task.detached {
            let isReachable = await NetworkService.shared.isHostReachable(host)
            if isReachable {
                await MainActor.run {
                    Logger.info("Server \(host) is reachable. Marking \(profile.serverURL) as manually unmounted.")
                    self.manuallyUnmountedProfiles.insert(profile.id)
                }
            } else {
                await MainActor.run {
                    Logger.info("Server \(host) is unreachable. Assuming network disconnect for \(profile.serverURL).")
                    // Do NOT mark as manual, so auto-mount can retry when network returns
                }
            }
        }
    }
    
    func isManuallyUnmounted(_ id: UUID) -> Bool {
        return manuallyUnmountedProfiles.contains(id)
    }
    
    func clearManualUnmountStatus(_ id: UUID) {
        if manuallyUnmountedProfiles.contains(id) {
            Logger.info("Clearing manual unmount status for ID: \(id)")
            manuallyUnmountedProfiles.remove(id)
        }
    }
    
    func updateStatus(for id: UUID, status: MountStatus) {
        currentStatus[id] = status
    }
    
    // MARK: - Automation Helpers (Delegated to AutomationService)


    func mount(profile: MountProfile, completion: @escaping @Sendable (Result<String, Error>) -> Void) {
        // User requested mount -> Clear manual unmount flag
        clearManualUnmountStatus(profile.id)
        
        Logger.info("Starting mount for \(profile.serverURL)")
        self.updateStatus(for: profile.id, status: .mounting)
        
        Task.detached {
            // Pre-mount automations (WOL, Scripts, etc.)
            await AutomationService.shared.executeAutomations(for: .preMount, profile: profile)
            
            guard let shareURL = URL(string: profile.serverURL) else {
                Logger.error("Invalid URL: \(profile.serverURL)")
                await self.updateStatus(for: profile.id, status: .error("Invalid URL"))
                await MainActor.run { completion(.failure(NSError(domain: "AutoMounty", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid Server URL"]))) }
                return
            }
            
            var mountPointURL: URL? = nil
            if !profile.mountPoint.isEmpty {
                let path = (profile.mountPoint as NSString).expandingTildeInPath
                mountPointURL = URL(fileURLWithPath: path)
                
                // Ensure directory exists
                var isDirectory: ObjCBool = false
                if !FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) {
                    do {
                        Logger.debug("Creating mount point directory: \(path)")
                        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
                    } catch {
                        Logger.error("Failed to create mount directory: \(error)")
                        await self.updateStatus(for: profile.id, status: .error("Create Dir Failed"))
                        await MainActor.run { completion(.failure(error)) }
                        return
                    }
                }
            }
            
            // Options
            let options = NSMutableDictionary()
            options[kNetFSSoftMountKey] = kCFBooleanTrue
            if mountPointURL != nil {
                options[kNetFSMountAtMountDirKey] = kCFBooleanTrue
            }
            
            Logger.debug("Mounting with NetFS...")
            var mountPoints: Unmanaged<CFArray>?
            
            let result = NetFSMountURLSync(
                shareURL as CFURL,
                mountPointURL as CFURL?,
                nil, // User
                nil, // Password (nil means use Keychain or prompt)
                nil, // Open options
                options, // Mount options
                &mountPoints // Result mount points
            )
            
            // Wait, looking at original code:
            // NetFSMountURLSync(shareURL, mountPointURL, nil, nil, nil, options, &mountPoints)
            // I need to match the original call exactly.
            // Original:
            // let result = NetFSMountURLSync(
            //    shareURL as CFURL,
            //    mountPointURL as CFURL?,
            //    nil, // User
            //    nil, // Password (nil means use Keychain or prompt)
            //    nil, // Open options
            //    options, // Mount options
            //    &mountPoints // Result mount points
            // )
            
            // Extract mount points before hopping to MainActor to avoid capturing non-Sendable state
            let pointsArray = mountPoints?.takeRetainedValue() as? [String]
            
            await MainActor.run {
                if result == 0 {
                    // Success
                    var actualMountPoint = profile.mountPoint
                    if let first = pointsArray?.first {
                        actualMountPoint = first
                    }
                    
                    Logger.info("Mount success: \(profile.serverURL) at \(actualMountPoint)")
                    self.currentStatus[profile.id] = .mounted
                    self.mountPaths[profile.id] = actualMountPoint
                    
                    // Check actual mounted URL to update profile if user selected a subfolder
                    self.checkAndUpdateProfileURL(profile: profile, mountPoint: actualMountPoint)
                    
                    // Post-mount automations (Success)
                    Task { await AutomationService.shared.executeAutomations(for: .mounted, profile: profile) }
                    
                    completion(.success(actualMountPoint))
                } else {
                    let errorMsg = "Error: \(result)"
                    Logger.error("Mount failed for \(profile.serverURL). Code: \(result)")
                    self.currentStatus[profile.id] = .error(errorMsg)
                    
                    // Post-mount automations (Failure)
                    Task { await AutomationService.shared.executeAutomations(for: .mountFailed, profile: profile) }
                    
                    completion(.failure(NSError(domain: "NetFS", code: Int(result), userInfo: [NSLocalizedDescriptionKey: "Mount failed with code \(result)"])))
                }
            }
        }
    }
    
    // Expose this as a public helper
    func getActualURL(from mountPoint: String) -> String? {
        var stat = statfs()
        if statfs(mountPoint, &stat) == 0 {
            let f_mntfromname = withUnsafePointer(to: stat.f_mntfromname) {
                $0.withMemoryRebound(to: UInt8.self, capacity: 1024) {
                    String(cString: $0)
                }
            }
            
            // Construct actual URL from mount info
            var actualURL = f_mntfromname
            
            // Helper to fix URL prefix
            let f_type = withUnsafePointer(to: stat.f_fstypename) {
                $0.withMemoryRebound(to: UInt8.self, capacity: 16) {
                    String(cString: $0)
                }
            }
            
            if f_type == "smbfs" && actualURL.hasPrefix("//") {
                actualURL = "smb:" + actualURL
            } else if f_type == "afpfs" && !actualURL.hasPrefix("afp://") {
                if !actualURL.contains("://") {
                     actualURL = "afp://" + actualURL
                }
            }
            
            return actualURL
        }
        return nil
    }

    private func checkAndUpdateProfileURL(profile: MountProfile, mountPoint: String) {
        guard let actualURL = getActualURL(from: mountPoint) else { return }
        
        // Normalize URLs for comparison
        // We need to decode URL encoding to compare properly (e.g. %20 vs space)
        let profileURLStr = profile.serverURL.removingPercentEncoding ?? profile.serverURL
        let detectedURLStr = actualURL.removingPercentEncoding ?? actualURL
        
        // Compare without trailing slashes
        let cleanProfile = profileURLStr.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let cleanDetected = detectedURLStr.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        if cleanProfile != cleanDetected {
            Logger.info("Detected URL mismatch. Profile: \(cleanProfile), Actual: \(cleanDetected). Updating profile.")
            
            var finalNewURL = actualURL
            
            // Preserve port if it exists in profile but missing in actual
            if let profileURL = URL(string: profile.serverURL),
               let profilePort = profileURL.port,
               let detectedURL = URL(string: actualURL),
               detectedURL.port == nil {
                
                // Construct new URL with original port
                var components = URLComponents(url: detectedURL, resolvingAgainstBaseURL: false)
                components?.port = profilePort
                if let fixedURL = components?.string {
                    finalNewURL = fixedURL
                    Logger.info("Preserving custom port \(profilePort) in updated URL: \(finalNewURL)")
                }
            }
            
            // Update profile with actual URL
            var updatedProfile = profile
            updatedProfile.serverURL = finalNewURL
            ConfigManager.shared.update(profile: updatedProfile)
        }
    }
    
    func unmount(profileId: UUID) {
        // User requested unmount -> Mark as manually unmounted
        manuallyUnmountedProfiles.insert(profileId)
        
        guard let path = mountPaths[profileId] else { return }
        
        // Retrieve profile for automations
        let profile = ConfigManager.shared.profiles.first(where: { $0.id == profileId })
        
        Logger.info("Unmounting \(path)")
        
        Task.detached {
            // Pre-unmount automations
            if let profile = profile {
                await AutomationService.shared.executeAutomations(for: .preUnmount, profile: profile)
            }
            
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/sbin/umount")
            task.arguments = [path]
            try? task.run()
            task.waitUntilExit()
            
            await MainActor.run {
                if task.terminationStatus == 0 {
                    Logger.info("Unmount success: \(path)")
                    self.currentStatus[profileId] = .unmounted
                    self.mountPaths.removeValue(forKey: profileId)
                    
                    // Post-unmount automations
                    if let profile = profile {
                        Task { await AutomationService.shared.executeAutomations(for: .unmounted, profile: profile) }
                    }
                } else {
                    Logger.error("Unmount failed for \(path). Exit code: \(task.terminationStatus)")
                }
            }
        }
    }
    
    func scanAndImportMounts() {
        var mntbuf: UnsafeMutablePointer<statfs>? = nil
        let count = getmntinfo(&mntbuf, MNT_NOWAIT)
        
        guard count > 0, let mnt = mntbuf else { return }
        
        for i in 0..<Int(count) {
            let stat = mnt[i]
            let f_type = withUnsafePointer(to: stat.f_fstypename) {
                $0.withMemoryRebound(to: UInt8.self, capacity: 16) {
                    String(cString: $0)
                }
            }
            
            // Filter for network filesystems
            if ["smbfs", "afpfs", "nfs", "webdav"].contains(f_type) {
                let f_mntfromname = withUnsafePointer(to: stat.f_mntfromname) {
                    $0.withMemoryRebound(to: UInt8.self, capacity: 1024) {
                        String(cString: $0)
                    }
                }
                
                let f_mntonname = withUnsafePointer(to: stat.f_mntonname) {
                    $0.withMemoryRebound(to: UInt8.self, capacity: 1024) {
                        String(cString: $0)
                    }
                }
                
                // Construct URL
                var serverURL = f_mntfromname
                if f_type == "smbfs" && serverURL.hasPrefix("//") {
                    serverURL = "smb:" + serverURL
                } else if f_type == "afpfs" && !serverURL.hasPrefix("afp://") {
                    if !serverURL.contains("://") {
                         serverURL = "afp://" + serverURL
                    }
                }
                
                // Normalize URL for comparison (remove trailing slash, lowercase scheme)
                let normalizedServerURL = serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                
                // Avoid duplicates based on normalized Server URL
                if !ConfigManager.shared.profiles.contains(where: { 
                    $0.serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == normalizedServerURL 
                }) {
                    Logger.info("Importing found mount: \(serverURL) at \(f_mntonname)")
                    let newProfile = MountProfile(
                        serverURL: serverURL, // Keep original format for display/use
                        mountPoint: ""
                    )
                    ConfigManager.shared.add(profile: newProfile)
                    
                    // Mark as mounted
                    self.updateStatus(for: newProfile.id, status: .mounted)
                    self.mountPaths[newProfile.id] = f_mntonname
                } else if let existingProfile = ConfigManager.shared.profiles.first(where: { 
                    $0.serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == normalizedServerURL 
                }) {
                     // Update status for existing profile if it's already mounted
                     Logger.debug("Found existing mounted profile: \(serverURL)")
                     self.updateStatus(for: existingProfile.id, status: .mounted)
                     self.mountPaths[existingProfile.id] = f_mntonname
                }
            }
        }
    }
    
    /// Adds a discovered server profile with validation (try-mount first).
    /// This method is intended for the Network Discovery flow.
    /// - Parameters:
    ///   - url: The server URL string.
    ///   - bonjourHostname: Optional Bonjour hostname if discovered via mDNS.
    ///   - mountPoint: Optional specific local mount point.
    ///   - completion: Callback with the result (Success with Profile, or Failure with Error).
    func importDiscoveredServer(url: String, bonjourHostname: String? = nil, mountPoint: String = "", completion: @escaping @Sendable (Result<MountProfile, Error>) -> Void) {
        
        // 1. Check for existing profile by Bonjour Hostname (if provided)
        if let hostname = bonjourHostname,
           let existingIndex = ConfigManager.shared.profiles.firstIndex(where: { $0.bonjourHostname == hostname }) {
            
            var profile = ConfigManager.shared.profiles[existingIndex]
            
            // Check if IP needs update (if url contains IP)
            if let newURL = URL(string: url), let newHost = newURL.host,
               let currentURL = URL(string: profile.serverURL), let currentHost = currentURL.host,
               newHost != currentHost {
                
                Logger.info("Updating IP for \(hostname) from \(currentHost) to \(newHost)")
                
                if var components = URLComponents(string: profile.serverURL) {
                    components.host = newHost
                    if let updatedURLStr = components.string {
                        profile.serverURL = updatedURLStr
                        ConfigManager.shared.update(profile: profile)
                    }
                }
            }
            
            completion(.success(profile))
            return
        }
        
        // 2. Check for existing profile by URL (if bonjour check didn't match or wasn't applicable)
        // Normalize URL for comparison (remove trailing slash)
        let normalizedURL = url.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if let existingProfile = ConfigManager.shared.profiles.first(where: {
            $0.serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == normalizedURL
        }) {
            // Update bonjour name if missing and we have one now
            if existingProfile.bonjourHostname == nil && bonjourHostname != nil {
                var updated = existingProfile
                updated.bonjourHostname = bonjourHostname
                ConfigManager.shared.update(profile: updated)
            }
            
            // If the profile exists but is NOT mounted, try to mount it now.
            // This satisfies the user expectation that "Adding" verifies the connection.
            if self.currentStatus[existingProfile.id] != .mounted {
                Logger.info("Profile exists but is unmounted. Attempting to mount: \(existingProfile.serverURL)")
                self.mount(profile: existingProfile) { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success:
                            completion(.success(existingProfile))
                        case .failure(let error):
                            completion(.failure(error))
                        }
                    }
                }
            } else {
                completion(.success(existingProfile))
            }
            return
        }
        
        // 3. Try to mount (Pre-flight check)
        // Create a temporary profile for mounting
        let tempProfile = MountProfile(serverURL: url, mountPoint: mountPoint, bonjourHostname: bonjourHostname)
        
        self.mount(profile: tempProfile) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let mountedPath):
                    // 4. Success! Resolve actual URL
                    var finalURL = url
                    // Try to resolve the actual URL from the mount point to handle subfolders or redirects
                    // But be careful not to lose the IP if we prefer it
                    if let resolvedURL = self.getActualURL(from: mountedPath) {
                        // Check if we lost the port info
                        if let originalURLObj = URL(string: url),
                           let originalPort = originalURLObj.port,
                           let resolvedURLObj = URL(string: resolvedURL),
                           resolvedURLObj.port == nil {
                            
                            // If original had port, ensure resolved has it too
                            var components = URLComponents(url: resolvedURLObj, resolvingAgainstBaseURL: false)
                            components?.port = originalPort
                            if let fixedURL = components?.string {
                                finalURL = fixedURL
                                Logger.info("Preserved custom port \(originalPort) in resolved URL: \(finalURL)")
                            } else {
                                finalURL = resolvedURL
                            }
                        } else {
                            finalURL = resolvedURL
                        }
                    }
                    
                    // 5. Create Final Profile
                    let newProfile = MountProfile(serverURL: finalURL, mountPoint: mountPoint, bonjourHostname: bonjourHostname)
                    
                    // Double check duplicate before adding
                    if let existing = ConfigManager.shared.profiles.first(where: { $0.serverURL == finalURL }) {
                        Logger.info("Profile already exists for \(finalURL). Skipping add.")
                        completion(.success(existing))
                    } else {
                        ConfigManager.shared.add(profile: newProfile)
                        
                        // Update MountyManager status since we are already mounted
                        // Clean up temp ID
                        self.mountPaths.removeValue(forKey: tempProfile.id)
                        self.currentStatus.removeValue(forKey: tempProfile.id)
                        
                        // Set status for new ID
                        self.updateStatus(for: newProfile.id, status: .mounted)
                        self.mountPaths[newProfile.id] = mountedPath
                        
                        Logger.info("Successfully added and mounted: \(finalURL)")
                        completion(.success(newProfile))
                    }
                    
                case .failure(let error):
                    // 6. Failed
                    Logger.error("Failed to verify/mount server \(url): \(error.localizedDescription)")
                    completion(.failure(error))
                }
            }
        }
    }
    

}
