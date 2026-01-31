import Foundation
import AutoMountyModel
import AppKit
import CoreWLAN
import SystemConfiguration.CaptiveNetwork

struct RuleService {
    static let shared = RuleService()
    
    private init() {}
    
    // MARK: - Rule Evaluation
    
    /// Evaluates if a profile's auto-mount rules are satisfied.
    /// - Parameters:
    ///   - profile: The profile to evaluate.
    ///   - currentSSID: The current WiFi SSID (optional, passed from Monitor to avoid re-fetching).
    /// - Returns: True if rules are satisfied (or no rules exist), false otherwise.
    func evaluateRules(for profile: MountProfile, currentSSID: String?) async -> Bool {
        // If no rules, assume "Any Network" (default behavior for empty rules with autoMount=true)
        if profile.rules.isEmpty {
            return true
        }
        
        let logic = profile.ruleLogic
        
        // Check all rules
        // We need to use a loop or map with async, but map doesn't support async directly in a clean way for .contains(false)
        // Let's iterate and collect results
        
        var results: [Bool] = []
        
        for rule in profile.rules {
            let result: Bool
            switch rule.type {
            case .wifi:
                guard let current = currentSSID else {
                    // No WiFi connected.
                    result = rule.operator == .doesNotEqual
                    break
                }
                
                switch rule.operator {
                case .equals:
                    result = current == rule.value
                case .doesNotEqual:
                    result = current != rule.value
                case .contains:
                    result = current.contains(rule.value)
                }
                
            case .app:
                let runningApps = await SystemInfoService.shared.getRunningApplications()
                let isAppRunning = runningApps.contains { name in
                    if rule.operator == .contains {
                         return name.localizedCaseInsensitiveContains(rule.value)
                    }
                    return name.localizedCaseInsensitiveCompare(rule.value) == .orderedSame
                }
                
                if rule.operator == .doesNotEqual {
                    result = !isAppRunning
                } else {
                    result = isAppRunning
                }
                
            case .vpn:
                let availableVPNs = NetworkService.shared.getAvailableVPNInterfaces()
                let vpnActive = !availableVPNs.isEmpty
                
                // If value is empty, treat as "Is VPN Connected" check
                if rule.value.isEmpty {
                    result = rule.operator == .doesNotEqual ? !vpnActive : vpnActive
                } else {
                    // If value is present, check interface name
                    if vpnActive {
                        let hasMatchingInterface = availableVPNs.contains { name in
                            if rule.operator == .contains {
                                return name.localizedCaseInsensitiveContains(rule.value)
                            }
                            return name.localizedCaseInsensitiveCompare(rule.value) == .orderedSame
                        }
                        result = rule.operator == .doesNotEqual ? !hasMatchingInterface : hasMatchingInterface
                    } else {
                        result = rule.operator == .doesNotEqual
                    }
                }
            }
            results.append(result)
        }
        
        if logic == .all {
            return !results.contains(false)
        } else { // Any
            return results.contains(true)
        }
    }
    
    // MARK: - System Info Helpers
    
    // SSID and VPN helpers moved to NetworkService
    // App helpers moved to SystemInfoService
}
