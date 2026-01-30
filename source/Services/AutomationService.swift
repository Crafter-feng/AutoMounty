import Foundation
import AppKit

struct AutomationService {
    static let shared = AutomationService()
    
    private init() {}
    
    /// Executes all enabled automations for a specific event within a profile.
    /// - Parameters:
    ///   - event: The lifecycle event (e.g., .preMount, .mounted).
    ///   - profile: The mount profile containing the automations.
    func executeAutomations(for event: ScriptEvent, profile: MountProfile) async {
        let tasks = profile.automations.filter { $0.enabled && $0.events.contains(event) }
        guard !tasks.isEmpty else { return }
        
        Logger.info("Executing automations for event: \(event.rawValue) (Count: \(tasks.count))")
        
        for task in tasks {
            await runAutomation(task)
        }
    }
    
    private func runAutomation(_ config: AutomationConfig) async {
        switch config.type {
        case .shell, .app:
            await runScriptOrApp(config)
        case .wol:
            await NetworkService.shared.sendWOL(
                macAddress: config.macAddress,
                broadcastAddress: config.broadcastAddress,
                port: config.port
            )
        }
        
        // Handle Wait Time
        if config.waitTime > 0 {
            Logger.info("Waiting \(config.waitTime)s after automation task...")
            try? await Task.sleep(nanoseconds: UInt64(config.waitTime * 1_000_000_000))
        }
    }
    
    private func runScriptOrApp(_ config: AutomationConfig) async {
        guard !config.path.isEmpty else { return }
        
        // Check if it's an app
        if config.type == .app || config.path.hasSuffix(".app") {
             Logger.debug("Launching App: \(config.path)")
             await MainActor.run {
                 _ = NSWorkspace.shared.open(URL(fileURLWithPath: config.path))
             }
             return
        }
        
        Logger.debug("Running Script: \(config.path) \(config.arguments)")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: config.path)
        
        // Simple argument parsing (split by space)
        if !config.arguments.isEmpty {
            let args = config.arguments.split(separator: " ").map { String($0) }
            process.arguments = args
        }
        
        do {
            try process.run()
            process.waitUntilExit()
            Logger.debug("Script finished with status: \(process.terminationStatus)")
        } catch {
            Logger.error("Failed to run script \(config.path): \(error)")
        }
    }
}
