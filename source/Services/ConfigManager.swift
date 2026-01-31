import Foundation
import AutoMountyModel

@MainActor
class ConfigManager: ObservableObject {
    static let shared = ConfigManager()
    
    @Published var profiles: [MountProfile] = [] {
        didSet {
            save()
        }
    }
    
    private let savePath: URL
    
    init() {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = paths[0].appendingPathComponent("AutoMounty")
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true, attributes: nil)
        savePath = appSupport.appendingPathComponent("profiles.json")
        
        load()
    }
    
    func load() {
        guard let data = try? Data(contentsOf: savePath) else { return }
        if let decoded = try? JSONDecoder().decode([MountProfile].self, from: data) {
            profiles = decoded
        }
    }
    
    func save() {
        if let encoded = try? JSONEncoder().encode(profiles) {
            try? encoded.write(to: savePath)
        }
    }
    
    func add(profile: MountProfile) {
        profiles.append(profile)
        Logger.info("Added new profile: \(profile.serverURL)")
        save()
    }
    
    func update(profile: MountProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
            Logger.info("Updated profile: \(profile.serverURL)")
            save()
        }
    }
    
    func delete(at offsets: IndexSet) {
        Logger.info("Deleting profile(s) at offsets: \(offsets)")
        profiles.remove(atOffsets: offsets)
        save()
    }
    
    func delete(id: UUID) {
        if let profile = profiles.first(where: { $0.id == id }) {
            Logger.info("Deleting profile: \(profile.serverURL)")
            profiles.removeAll { $0.id == id }
            save()
        }
    }
}
