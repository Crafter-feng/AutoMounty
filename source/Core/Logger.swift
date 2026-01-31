import Foundation
import SwiftUI

enum LogLevel: Int, CaseIterable, Identifiable {
    case none = 0
    case error = 1
    case info = 2
    case debug = 3
    
    var id: Int { rawValue }
    
    var displayName: String {
        switch self {
        case .none: return "None"
        case .error: return "Error"
        case .info: return "Info"
        case .debug: return "Debug"
        }
    }
}

@MainActor
class Logger: ObservableObject {
    static let shared = Logger()
    
    @Published var logLevel: LogLevel = .none {
        didSet {
            UserDefaults.standard.set(logLevel.rawValue, forKey: "LogLevel")
        }
    }
    
    private let logFileURL: URL
    private let fileHandle: FileHandle?
    private let dateFormatter: DateFormatter
    
    private init() {
        // Load settings
        let savedLevel = UserDefaults.standard.integer(forKey: "LogLevel")
        self.logLevel = LogLevel(rawValue: savedLevel) ?? .none
        
        // Setup file path
        // Use ~/Library/Logs/AutoMounty/ which is the standard log directory for user apps
        let paths = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
        let logsDir = paths[0].appendingPathComponent("Logs").appendingPathComponent("AutoMounty")
        
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        self.logFileURL = logsDir.appendingPathComponent("automounty.log")
        
        // Create file if not exists
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }
        
        // Open file handle
        do {
            self.fileHandle = try FileHandle(forWritingTo: logFileURL)
            self.fileHandle?.seekToEndOfFile()
        } catch {
            print("Failed to open log file: \(error)")
            self.fileHandle = nil
        }
        
        // Setup date formatter
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        
        log("Logger initialized. Level: \(logLevel.displayName). Path: \(logFileURL.path)", level: .info)
    }
    
    deinit {
        try? fileHandle?.close()
    }
    
    func log(_ message: String, level: LogLevel) {
        guard level.rawValue <= logLevel.rawValue && level != .none else { return }
        
        let timestamp = dateFormatter.string(from: Date())
        let logEntry = "[\(timestamp)] [\(level.displayName.uppercased())] \(message)\n"
        
        // Print to console
        print(logEntry, terminator: "")
        
        // Write to file
        if let data = logEntry.data(using: .utf8) {
            fileHandle?.write(data)
        }
    }
    
    func openLogFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([logFileURL])
    }
    
    nonisolated static func error(_ message: String) {
        Task { @MainActor in
            shared.log(message, level: .error)
        }
    }
    
    nonisolated static func info(_ message: String) {
        Task { @MainActor in
            shared.log(message, level: .info)
        }
    }
    
    nonisolated static func debug(_ message: String) {
        Task { @MainActor in
            shared.log(message, level: .debug)
        }
    }
}
