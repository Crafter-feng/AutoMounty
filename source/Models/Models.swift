import Foundation

struct MountProfile: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var serverURL: String // smb://user@server/share
    var mountPoint: String // Optional: local path to mount at
    // var allowedSSIDs: [String] = [] // Deprecated, use rules instead
    var isEnabled: Bool = true
    var autoMount: Bool = false
    
    // New Rules System
    var rules: [MountRule] = []
    var ruleLogic: RuleLogic = .all
    
    // Bonjour Support
    var bonjourHostname: String? // Stores the Bonjour service name (e.g. "MyNAS") for IP updates
    
    // Scripting & Automation
    var automations: [AutomationConfig] = []
    
    // UI Helper
    var displayName: String {
        if serverURL.isEmpty { return "Untitled Server" }
        guard let url = URL(string: serverURL) else { return serverURL }
        
        // Try to get the last path component
        let lastComponent = url.lastPathComponent
        if !lastComponent.isEmpty && lastComponent != "/" {
            return lastComponent
        }
        
        // If no path component, try host
        if let host = url.host {
            return host
        }
        
        return serverURL
    }
    
    // Custom decoding to handle migration
    enum CodingKeys: String, CodingKey {
        case id, name, serverURL, mountPoint, allowedSSIDs, isEnabled, autoMount, wifiSSID, rules, ruleLogic, bonjourHostname, scripts, wolConfig, automations
    }
    
    init(id: UUID = UUID(), serverURL: String, mountPoint: String, rules: [MountRule] = [], ruleLogic: RuleLogic = .all, isEnabled: Bool = true, autoMount: Bool = false, bonjourHostname: String? = nil, automations: [AutomationConfig] = []) {
        self.id = id
        self.serverURL = serverURL
        self.mountPoint = mountPoint
        self.rules = rules
        self.ruleLogic = ruleLogic
        self.isEnabled = isEnabled
        self.autoMount = autoMount
        self.bonjourHostname = bonjourHostname
        self.automations = automations
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        serverURL = try container.decode(String.self, forKey: .serverURL)
        mountPoint = try container.decode(String.self, forKey: .mountPoint)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        autoMount = try container.decode(Bool.self, forKey: .autoMount)
        bonjourHostname = try container.decodeIfPresent(String.self, forKey: .bonjourHostname)
        
        // Load new automations
        automations = try container.decodeIfPresent([AutomationConfig].self, forKey: .automations) ?? []
        
        // Migration: Load old scripts
        if let oldScripts = try? container.decodeIfPresent([OldScriptConfig].self, forKey: .scripts), !oldScripts.isEmpty {
            for script in oldScripts {
                var newAuto = AutomationConfig()
                newAuto.type = script.path.hasSuffix(".app") ? .app : .shell
                newAuto.path = script.path
                newAuto.arguments = script.arguments
                newAuto.enabled = script.enabled
                newAuto.events = script.events
                automations.append(newAuto)
            }
        }
        
        // Migration: Load old WOL
        if let wol = try? container.decodeIfPresent(WOLConfig.self, forKey: .wolConfig) {
            var newAuto = AutomationConfig()
            newAuto.type = .wol
            newAuto.macAddress = wol.macAddress
            newAuto.broadcastAddress = wol.broadcastAddress
            newAuto.port = wol.port
            newAuto.waitTime = wol.waitTime
            newAuto.events = [.preMount] // Default WOL to pre-mount
            automations.append(newAuto)
        }
        
        // New fields
        rules = try container.decodeIfPresent([MountRule].self, forKey: .rules) ?? []
        ruleLogic = try container.decodeIfPresent(RuleLogic.self, forKey: .ruleLogic) ?? .all
        
        // Migration logic: Convert old SSIDs to rules if rules are empty
        if rules.isEmpty {
            if let ssids = try? container.decode([String].self, forKey: .allowedSSIDs), !ssids.isEmpty {
                // If we had a list of allowed SSIDs, it effectively meant "Connect if ANY of these match"
                // OR "Connect if current SSID is in this list".
                // In the new system, we can represent this as:
                // Rule Logic: ANY
                // Rule 1: WiFi is SSID1
                // Rule 2: WiFi is SSID2
                // ...
                ruleLogic = .any
                for ssid in ssids {
                    rules.append(MountRule(type: .wifi, operator: .equals, value: ssid))
                }
            } else if let singleSSID = try? container.decodeIfPresent(String.self, forKey: .wifiSSID), !singleSSID.isEmpty {
                rules.append(MountRule(type: .wifi, operator: .equals, value: singleSSID))
            }
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(serverURL, forKey: .serverURL)
        try container.encode(mountPoint, forKey: .mountPoint)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(autoMount, forKey: .autoMount)
        try container.encode(rules, forKey: .rules)
        try container.encode(ruleLogic, forKey: .ruleLogic)
        try container.encode(bonjourHostname, forKey: .bonjourHostname)
        try container.encode(automations, forKey: .automations)
    }
}

// MARK: - Automation Types

enum ScriptEvent: String, Codable, CaseIterable, Identifiable {
    case preMount = "Mounting"
    case mounted = "Mounted"
    case preUnmount = "Unmounting"
    case unmounted = "Unmounted"
    case mountFailed = "Mount Failed"
    
    var id: String { rawValue }
    
    var localizedName: String {
        switch self {
        case .preMount: return NSLocalizedString("Mounting", comment: "Event: Before mount starts")
        case .mounted: return NSLocalizedString("Mounted", comment: "Event: After mount success")
        case .preUnmount: return NSLocalizedString("Unmounting", comment: "Event: Before unmount starts")
        case .unmounted: return NSLocalizedString("Unmounted", comment: "Event: After unmount success")
        case .mountFailed: return NSLocalizedString("Mount Failed", comment: "Event: When mount fails")
        }
    }
}

enum AutomationType: String, Codable, CaseIterable, Identifiable {
    case shell = "Shell Script"
    case app = "Application"
    case wol = "Wake On LAN"
    
    var id: String { rawValue }
    
    var localizedName: String {
        switch self {
        case .shell: return NSLocalizedString("Shell Script", comment: "Automation type: Shell Script")
        case .app: return NSLocalizedString("Application", comment: "Automation type: Application")
        case .wol: return NSLocalizedString("Wake On LAN", comment: "Automation type: Wake On LAN")
        }
    }
}

struct AutomationConfig: Codable, Identifiable, Hashable {
    var id = UUID()
    var type: AutomationType = .shell
    var enabled: Bool = true
    
    // Common/Script
    var path: String = ""
    var arguments: String = ""
    var events: Set<ScriptEvent> = []
    
    // WOL
    var macAddress: String = ""
    var broadcastAddress: String = "255.255.255.255"
    var port: UInt16 = 9
    var waitTime: TimeInterval = 0
}

// For Migration
struct OldScriptConfig: Codable {
    var id = UUID()
    var path: String
    var arguments: String
    var enabled: Bool
    var events: Set<ScriptEvent>
}

// WOLConfig is deprecated, but kept for migration if needed by other files temporarily? 
// No, I'm handling it in init(from:).
// But wait, WOLConfig might be used in other files.
// I will keep it but mark as deprecated or just use it for migration.
struct WOLConfig: Codable, Hashable {
    var macAddress: String = ""
    var broadcastAddress: String = "255.255.255.255"
    var port: UInt16 = 9
    var waitTime: TimeInterval = 0
}

enum RuleType: String, Codable, CaseIterable, Identifiable {
    case wifi = "WiFi Connection"
    case vpn = "VPN Connection"
    case app = "Running Application"
    
    var id: String { rawValue }
    
    var localizedName: String {
        switch self {
        case .wifi: return NSLocalizedString("WiFi Connection", comment: "Rule type: WiFi")
        case .vpn: return NSLocalizedString("VPN Connection", comment: "Rule type: VPN")
        case .app: return NSLocalizedString("Running Application", comment: "Rule type: Application")
        }
    }
}

enum RuleOperator: String, Codable, CaseIterable, Identifiable {
    case equals = "is"
    case doesNotEqual = "is not"
    case contains = "contains"
    
    var id: String { rawValue }
    
    var localizedName: String {
        switch self {
        case .equals: return NSLocalizedString("is", comment: "Operator: equals")
        case .doesNotEqual: return NSLocalizedString("is not", comment: "Operator: does not equal")
        case .contains: return NSLocalizedString("contains", comment: "Operator: contains")
        }
    }
}

enum RuleLogic: String, Codable, CaseIterable, Identifiable {
    case all = "All"
    case any = "Any"
    
    var id: String { rawValue }
    
    var localizedName: String {
        switch self {
        case .all: return NSLocalizedString("All", comment: "Logic: All rules must match")
        case .any: return NSLocalizedString("Any", comment: "Logic: Any rule matches")
        }
    }
}

struct MountRule: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var type: RuleType
    var `operator`: RuleOperator
    var value: String
}

enum MountStatus: Equatable {
    case mounted
    case unmounted
    case error(String)
    case mounting
}
