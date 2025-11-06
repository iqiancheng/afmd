//  ServerViewModel.swift
//  afmd

import Combine
import Foundation
import Network

#if os(macOS)
import AppKit
#endif

// MARK: - Server Configuration

struct ServerConfiguration {
    var host: String
    var port: Int

    static let `default` = ServerConfiguration(host: "0.0.0.0", port: 11535)

    var url: String { "http://\(host):\(port)" }
    var openaiBaseURL: String { "\(url)/v1" }
    var chatCompletionsEndpoint: String { "\(url)/v1/chat/completions" }
}

// MARK: - View Model

@MainActor
final class ServerViewModel: ObservableObject {
    // Public, bindable state
    @Published var configuration: ServerConfiguration = .default
    @Published var isModelAvailable: Bool = false
    @Published var modelUnavailableReason: String?
    @Published var isCheckingModel: Bool = false
    @Published var isRunning: Bool = false
    @Published var lastError: String?
    @Published var isAutoStartEnabled: Bool = false
    @Published var isDaemonMode: Bool = false
    @Published var chatHistory: [ChatHistory] = []
    @Published var serverLogs: [LogEntry] = []
    @Published var isLoggingEnabled: Bool = true
    
    struct ChatHistory: Identifiable, Codable {
        let id = UUID()
        let timestamp: Date
        let prompt: String
        let response: String
        let model: String
        
        init(timestamp: Date = Date(), prompt: String, response: String, model: String) {
            self.timestamp = timestamp
            self.prompt = prompt
            self.response = response
            self.model = model
        }
    }
    
    struct LogEntry: Identifiable, Codable {
        let id = UUID()
        let timestamp: Date
        let level: LogLevel
        let category: LogCategory
        let message: String
        let details: String?
        
        init(timestamp: Date = Date(), level: LogLevel, category: LogCategory, message: String, details: String? = nil) {
            self.timestamp = timestamp
            self.level = level
            self.category = category
            self.message = message
            self.details = details
        }
    }
    
    enum LogLevel: String, CaseIterable, Codable {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
        
        var color: String {
            switch self {
            case .debug: return "secondary"
            case .info: return "primary"
            case .warning: return "orange"
            case .error: return "red"
            }
        }
        
        var icon: String {
            switch self {
            case .debug: return "ladybug"
            case .info: return "info.circle"
            case .warning: return "exclamationmark.triangle"
            case .error: return "xmark.circle"
            }
        }
    }
    
    enum LogCategory: String, CaseIterable, Codable {
        case server = "Server"
        case request = "Request"
        case response = "Response"
        case model = "Model"
        case system = "System"
        case network = "Network"
        
        var icon: String {
            switch self {
            case .server: return "server.rack"
            case .request: return "arrow.down.circle"
            case .response: return "arrow.up.circle"
            case .model: return "brain"
            case .system: return "gear"
            case .network: return "network"
            }
        }
    }

    // Service manager
    private let serverManager = VaporServerManager()
    private var cancellables = Set<AnyCancellable>()

    // Model identifier used by the server endpoints
    let modelName = "AFM-on-device"

    // Convenience API strings for the menu
    var openaiBaseURL: String { configuration.openaiBaseURL }
    var chatCompletionsEndpoint: String { configuration.chatCompletionsEndpoint }

    init() {
        // Load saved configuration
        loadConfiguration()
        
        // Verify Apple Intelligence availability at startup
        Task { await checkModelAvailability() }
        
        // Check auto-start status and enable it by default if not already enabled
        checkAutoStartStatus()
        if !isAutoStartEnabled {
            enableAutoStart()
        }
        
        // Check if running in daemon mode
        checkDaemonMode()
        
        // Set daemon mode preference to true by default
        // The daemon mode is automatically enabled via LaunchAgent plist environment variable
        if !UserDefaults.standard.bool(forKey: "AFMD_DaemonMode") {
            isDaemonMode = true
            saveDaemonModePreference()
        } else {
            loadDaemonModePreference()
        }
        
        // Load chat history
        loadChatHistory()
        
        // Load server logs
        loadLogs()
        
        // Set up server manager reference for logging
        serverManager.setViewModel(self)
        
        // Observe server manager state changes
        serverManager.$isRunning
            .receive(on: DispatchQueue.main)
            .assign(to: \.isRunning, on: self)
            .store(in: &cancellables)
            
        serverManager.$lastError
            .receive(on: DispatchQueue.main)
            .assign(to: \.lastError, on: self)
            .store(in: &cancellables)
    }

    func checkModelAvailability() async {
        isCheckingModel = true
        let result = await aiManager.isModelAvailable()
        isModelAvailable = result.available
        modelUnavailableReason = result.reason
        isCheckingModel = false
    }

    func startServer() async {
        await checkModelAvailability()
        guard isModelAvailable else { 
            addLog(level: .error, category: .server, message: "Cannot start server", details: "Model not available")
            return 
        }
        await serverManager.startServer(configuration: configuration)
    }

    func stopServer() async {
        await serverManager.stopServer()
    }

    func copyToClipboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
    
    func getLocalNetworkIP() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        guard let firstAddr = ifaddr else { return nil }
        
        for ifptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ifptr.pointee
            
            // Check for IPv4 or IPv6 interface
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) || addrFamily == UInt8(AF_INET6) {
                
                // Check interface name (en0 is usually WiFi, en1 is usually Ethernet)
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name == "en1" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                              &hostname, socklen_t(hostname.count),
                              nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                    
                    // Prefer IPv4 addresses for LAN access
                    if addrFamily == UInt8(AF_INET) {
                        break
                    }
                }
            }
        }
        
        freeifaddrs(ifaddr)
        return address
    }
    
    func generateCurlCommand() -> String {
        // Try to get LAN IP address, fallback to localhost
        let lanIP = getLocalNetworkIP()
        let targetHost = lanIP ?? configuration.host
        let targetURL = "http://\(targetHost):\(configuration.port)/v1/chat/completions"
        
        let curlCommand = """
curl -X POST "\(targetURL)" \\
  -H "Content-Type: application/json" \\
  -d '{
    "model": "\(modelName)",
    "messages": [
      {
        "role": "user",
        "content": "Hello, how are you?"
      }
    ],
    "temperature": 0.7,
    "max_tokens": 1000
  }'
"""
        return curlCommand
    }
    
    func copyCurlCommand() {
        let curlCommand = generateCurlCommand()
        copyToClipboard(curlCommand)
    }
    
    // MARK: - LaunchAgent Management
    
    private func checkAutoStartStatus() {
        let launchAgentPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.iqiancheng.afmd.launchagent.plist")
        isAutoStartEnabled = FileManager.default.fileExists(atPath: launchAgentPath.path)
        print("🔍 Auto-start status: \(isAutoStartEnabled ? "Enabled" : "Disabled")")
    }
    
    private func checkDaemonMode() {
        isDaemonMode = ProcessInfo.processInfo.environment["AFMD_DAEMON_MODE"] == "true"
    }
    
    func toggleAutoStart() {
        if isAutoStartEnabled {
            disableAutoStart()
        } else {
            enableAutoStart()
        }
    }
    
    private func enableAutoStart() {
        let launchAgentPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.iqiancheng.afmd.launchagent.plist")
        
        // Get the current app bundle path
        let appPath = Bundle.main.bundlePath
        print("🔍 App bundle path: \(appPath)")
        
        // Ensure LaunchAgents directory exists
        let launchAgentsDir = launchAgentPath.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            lastError = "Failed to create LaunchAgents directory: \(error.localizedDescription)"
            return
        }
        
        // Create plist content
        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.iqiancheng.afmd.launchagent</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(appPath)/Contents/MacOS/afmd</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>ProcessType</key>
            <string>Background</string>
            <key>EnvironmentVariables</key>
            <dict>
                <key>AFMD_DAEMON_MODE</key>
                <string>true</string>
            </dict>
        </dict>
        </plist>
        """
        
        do {
            try plistContent.write(to: launchAgentPath, atomically: true, encoding: .utf8)
            isAutoStartEnabled = true
            lastError = nil
            print("✅ Auto-start enabled successfully")
        } catch {
            lastError = "Failed to enable auto-start: \(error.localizedDescription)"
            print("❌ Failed to enable auto-start: \(error)")
        }
    }
    
    private func disableAutoStart() {
        let launchAgentPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.iqiancheng.afmd.launchagent.plist")
        
        do {
            if FileManager.default.fileExists(atPath: launchAgentPath.path) {
                try FileManager.default.removeItem(at: launchAgentPath)
            }
            isAutoStartEnabled = false
            lastError = nil
            print("✅ Auto-start disabled successfully")
        } catch {
            lastError = "Failed to disable auto-start: \(error.localizedDescription)"
            print("❌ Failed to disable auto-start: \(error)")
        }
    }
    
    func toggleDaemonMode() {
        isDaemonMode.toggle()
        saveDaemonModePreference()
    }
    
    private func saveDaemonModePreference() {
        UserDefaults.standard.set(isDaemonMode, forKey: "AFMD_DaemonMode")
    }
    
    private func loadDaemonModePreference() {
        isDaemonMode = UserDefaults.standard.bool(forKey: "AFMD_DaemonMode")
    }
    
    func testLaunchAgent() {
        let launchAgentPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.iqiancheng.afmd.launchagent.plist")
        
        if FileManager.default.fileExists(atPath: launchAgentPath.path) {
            lastError = "LaunchAgent file exists at: \(launchAgentPath.path)"
        } else {
            lastError = "LaunchAgent file not found"
        }
    }
    
    // MARK: - Configuration Management
    
    private func loadConfiguration() {
        let host = UserDefaults.standard.string(forKey: "AFMD_Host") ?? "0.0.0.0"
        let port = UserDefaults.standard.integer(forKey: "AFMD_Port")
        configuration = ServerConfiguration(
            host: host,
            port: port > 0 ? port : 11535
        )
    }
    
    func saveConfiguration() {
        UserDefaults.standard.set(configuration.host, forKey: "AFMD_Host")
        UserDefaults.standard.set(configuration.port, forKey: "AFMD_Port")
        print("💾 Configuration saved: \(configuration.host):\(configuration.port)")
    }
    
    // MARK: - Chat History Management
    
    func addChatHistory(prompt: String, response: String) {
        let history = ChatHistory(
            prompt: prompt,
            response: response,
            model: modelName
        )
        chatHistory.append(history)
        saveChatHistory()
    }
    
    func clearChatHistory() {
        chatHistory.removeAll()
        saveChatHistory()
    }
    
    private func saveChatHistory() {
        if let data = try? JSONEncoder().encode(chatHistory) {
            UserDefaults.standard.set(data, forKey: "AFMD_ChatHistory")
        }
    }
    
    private func loadChatHistory() {
        if let data = UserDefaults.standard.data(forKey: "AFMD_ChatHistory"),
           let history = try? JSONDecoder().decode([ChatHistory].self, from: data) {
            chatHistory = history
        }
    }
    
    // MARK: - Log Management
    
    func addLog(level: LogLevel, category: LogCategory, message: String, details: String? = nil) {
        guard isLoggingEnabled else { return }
        
        let logEntry = LogEntry(
            level: level,
            category: category,
            message: message,
            details: details
        )
        
        serverLogs.append(logEntry)
        
        // Keep only the last 1000 logs to prevent memory issues
        if serverLogs.count > 1000 {
            serverLogs.removeFirst(serverLogs.count - 1000)
        }
        
        // Save logs to UserDefaults for persistence
        saveLogs()
    }
    
    func clearLogs() {
        serverLogs.removeAll()
        saveLogs()
    }
    
    func toggleLogging() {
        isLoggingEnabled.toggle()
        UserDefaults.standard.set(isLoggingEnabled, forKey: "AFMD_LoggingEnabled")
    }
    
    func exportLogs() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        
        return serverLogs.map { log in
            let timestamp = formatter.string(from: log.timestamp)
            let details = log.details != nil ? " | \(log.details!)" : ""
            return "[\(timestamp)] [\(log.level.rawValue)] [\(log.category.rawValue)] \(log.message)\(details)"
        }.joined(separator: "\n")
    }
    
    private func saveLogs() {
        if let data = try? JSONEncoder().encode(serverLogs) {
            UserDefaults.standard.set(data, forKey: "AFMD_ServerLogs")
        }
    }
    
    private func loadLogs() {
        if let data = UserDefaults.standard.data(forKey: "AFMD_ServerLogs"),
           let logs = try? JSONDecoder().decode([LogEntry].self, from: data) {
            serverLogs = logs
        }
        
        // Load logging preference
        isLoggingEnabled = UserDefaults.standard.object(forKey: "AFMD_LoggingEnabled") as? Bool ?? true
    }
}