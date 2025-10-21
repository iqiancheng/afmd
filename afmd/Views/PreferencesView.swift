//
//  PreferencesView.swift
//  afmd
//
//  Created by Assistant on 8/27/25.
//

import SwiftUI

struct PreferencesView: View {
    @ObservedObject var viewModel: ServerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: Tab = .general
    
    enum Tab: String, CaseIterable {
        case general = "General"
        case examples = "Examples"
        case recent = "Recent"
        
        var icon: String {
            switch self {
            case .general: return "gear"
            case .examples: return "terminal"
            case .recent: return "clock"
            }
        }
    }
    
    var body: some View {
        NavigationSplitView {
            // Sidebar
            List(Tab.allCases, id: \.self, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 200)
            .listStyle(.sidebar)
        } detail: {
            // Detail content
            Group {
                switch selectedTab {
                case .general:
                    GeneralSettingsView(viewModel: viewModel)
                case .examples:
                    ExamplesView(viewModel: viewModel)
                case .recent:
                    RealTimeLogView(viewModel: viewModel)
                }
            }
            .navigationTitle(selectedTab.rawValue)
        }
        .frame(width: 800, height: 600)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    viewModel.saveConfiguration()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

// MARK: - General Settings
struct GeneralSettingsView: View {
    @ObservedObject var viewModel: ServerViewModel
    
    var body: some View {
        Form {
            // Prioritize connection info first
            Section("Connection Information") {
                Button {
                    let urlToCopy = viewModel.getLocalNetworkIP() != nil ? 
                        "http://\(viewModel.getLocalNetworkIP()!):\(String(viewModel.configuration.port))/v1" : 
                        viewModel.openaiBaseURL
                    viewModel.copyToClipboard(urlToCopy)
                } label: {
                    HStack {
                        Text("Base URL")
                        Spacer()
                        Text(viewModel.getLocalNetworkIP() != nil ? 
                            "http://\(viewModel.getLocalNetworkIP()!):\(String(viewModel.configuration.port))/v1" : 
                            viewModel.openaiBaseURL)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(viewModel.getLocalNetworkIP() != nil ? .green : .secondary)
                        Image(systemName: "doc.on.doc")
                            .foregroundStyle(viewModel.getLocalNetworkIP() != nil ? .green : .secondary)
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
                .help("Click to copy Base URL")
                
                Button {
                    let endpointToCopy = viewModel.getLocalNetworkIP() != nil ? 
                        "http://\(viewModel.getLocalNetworkIP()!):\(viewModel.configuration.port)/v1/chat/completions" : 
                        viewModel.chatCompletionsEndpoint
                    viewModel.copyToClipboard(endpointToCopy)
                } label: {
                    HStack {
                        Text("Chat Endpoint")
                        Spacer()
                        Text(viewModel.getLocalNetworkIP() != nil ? 
                            "http://\(viewModel.getLocalNetworkIP()!):\(viewModel.configuration.port)/v1/chat/completions" : 
                            viewModel.chatCompletionsEndpoint)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Image(systemName: "doc.on.doc")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
                .help("Click to copy Chat Endpoint")
                
                if let lanIP = viewModel.getLocalNetworkIP() {
                    Button {
                        viewModel.copyToClipboard("\(lanIP):\(viewModel.configuration.port)")
                    } label: {
                        HStack {
                            Text("LAN IP")
                            Spacer()
                            Text("\(lanIP):\(String(viewModel.configuration.port))")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Image(systemName: "doc.on.doc")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Click to copy LAN IP")
                }
            }
            
            Section("Model Information") {
                Button {
                    viewModel.copyToClipboard(viewModel.modelName)
                } label: {
                    HStack {
                        Text("Model Name")
                        Spacer()
                        Text(viewModel.modelName)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Image(systemName: "doc.on.doc")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
                .help("Click to copy Model Name")
                
                HStack {
                    Text("Status")
                    Spacer()
                    HStack {
                        Image(systemName: viewModel.isModelAvailable ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(viewModel.isModelAvailable ? .green : .red)
                        Text(viewModel.isModelAvailable ? "Available" : "Unavailable")
                    }
                }
                
                if let reason = viewModel.modelUnavailableReason {
                    HStack {
                        Text("Reason")
                        Spacer()
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Section("Server Configuration") {
                HStack {
                    Text("Port")
                    Spacer()
                    TextField("Port", value: Binding(
                        get: { viewModel.configuration.port },
                        set: { viewModel.configuration.port = $0 }
                    ), format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                }
            }
            
            Section("Startup & Background") {
                Toggle("Auto-start on Login", isOn: Binding(
                    get: { viewModel.isAutoStartEnabled },
                    set: { _ in viewModel.toggleAutoStart() }
                ))
                .help("Start afmd automatically when you log in")
                
                Toggle("Daemon Mode", isOn: Binding(
                    get: { viewModel.isDaemonMode },
                    set: { _ in viewModel.toggleDaemonMode() }
                ))
                .help("Run as background daemon (requires restart)")
            }
            
            Section("Supported APIs") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Chat Completions")
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        Text("POST /v1/chat/completions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Models")
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        Text("GET /v1/models")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Health Check")
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        Text("GET /health")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            
            if let error = viewModel.lastError {
                Section("Error Information") {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Network Status (now part of General)

// MARK: - Examples View
struct ExamplesView: View {
    @ObservedObject var viewModel: ServerViewModel
    @State private var selectedExample: ExampleType = .basic
    
    enum ExampleType: String, CaseIterable {
        case basic = "Basic Chat"
        case streaming = "Streaming"
        case withHistory = "With History"
        case custom = "Custom"
        
        var icon: String {
            switch self {
            case .basic: return "message"
            case .streaming: return "waveform"
            case .withHistory: return "clock.arrow.circlepath"
            case .custom: return "slider.horizontal.3"
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Example type selector
            Picker("Example Type", selection: $selectedExample) {
                ForEach(ExampleType.allCases, id: \.self) { example in
                    Label(example.rawValue, systemImage: example.icon)
                        .tag(example)
                }
            }
            .pickerStyle(.segmented)
            
            // Code example
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("cURL Example")
                        .font(.headline)
                    Spacer()
                    Button("Copy") {
                        viewModel.copyToClipboard(generateExample())
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                ScrollView {
                    Text(generateExample())
                        .font(.system(.body, design: .monospaced))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(red: 0.06, green: 0.06, blue: 0.06))
                        .cornerRadius(8)
                        .foregroundColor(.white)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 600)
            }
            
            Spacer()
        }
        .padding()
    }
    
    private func generateExample() -> String {
        let baseURL = viewModel.chatCompletionsEndpoint
        let model = viewModel.modelName
        
        switch selectedExample {
        case .basic:
            return """
curl -X POST "\(baseURL)" \\
  -H "Content-Type: application/json" \\
  -d '{
    "model": "\(model)",
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
        case .streaming:
            return """
curl -X POST "\(baseURL)" \\
  -H "Content-Type: application/json" \\
  -d '{
    "model": "\(model)",
    "messages": [
      {
        "role": "user",
        "content": "Tell me a story"
      }
    ],
    "stream": true,
    "temperature": 0.8
  }'
"""
        case .withHistory:
            return """
curl -X POST "\(baseURL)" \\
  -H "Content-Type: application/json" \\
  -d '{
    "model": "\(model)",
    "messages": [
      {
        "role": "user",
        "content": "What is AI?"
      },
      {
        "role": "assistant",
        "content": "AI is artificial intelligence..."
      },
      {
        "role": "user",
        "content": "Can you explain more?"
      }
    ],
    "temperature": 0.7
  }'
"""
        case .custom:
            return """
curl -X POST "\(baseURL)" \\
  -H "Content-Type: application/json" \\
  -H "Authorization: Bearer your-api-key" \\
  -d '{
    "model": "\(model)",
    "messages": [
      {
        "role": "system",
        "content": "You are a helpful assistant."
      },
      {
        "role": "user",
        "content": "Your custom prompt here"
      }
    ],
    "temperature": 0.5,
    "max_tokens": 2000,
    "top_p": 0.9,
    "frequency_penalty": 0.0,
    "presence_penalty": 0.0
  }'
"""
        }
    }
}

// MARK: - Real-Time Log View
struct RealTimeLogView: View {
    @ObservedObject var viewModel: ServerViewModel
    @State private var selectedLevel: ServerViewModel.LogLevel? = nil
    @State private var selectedCategory: ServerViewModel.LogCategory? = nil
    @State private var isAutoScrollEnabled = true
    
    private var filteredLogs: [ServerViewModel.LogEntry] {
        var logs = viewModel.serverLogs
        
        if let level = selectedLevel {
            logs = logs.filter { $0.level == level }
        }
        
        if let category = selectedCategory {
            logs = logs.filter { $0.category == category }
        }
        
        return logs.reversed() // Show newest first
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Controls
            HStack {
                Text("Server Logs")
                    .font(.headline)
                
                Spacer()
                
                // Logging toggle
                Toggle("Logging", isOn: $viewModel.isLoggingEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: viewModel.isLoggingEnabled) { _, newValue in
                        viewModel.toggleLogging()
                    }
                
                // Level filter
                Menu {
                    Button("All Levels") {
                        selectedLevel = nil
                    }
                    ForEach(ServerViewModel.LogLevel.allCases, id: \.self) { level in
                        Button(level.rawValue) {
                            selectedLevel = level
                        }
                    }
                } label: {
                    Label(selectedLevel?.rawValue ?? "All Levels", systemImage: "line.3.horizontal.decrease.circle")
                }
                .controlSize(.small)
                
                // Category filter
                Menu {
                    Button("All Categories") {
                        selectedCategory = nil
                    }
                    ForEach(ServerViewModel.LogCategory.allCases, id: \.self) { category in
                        Button(category.rawValue) {
                            selectedCategory = category
                        }
                    }
                } label: {
                    Label(selectedCategory?.rawValue ?? "All Categories", systemImage: "tag")
                }
                .controlSize(.small)
                
                // Clear logs
                Button("Clear") {
                    viewModel.clearLogs()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                // Export logs
                Button("Export") {
                    let logsText = viewModel.exportLogs()
                    viewModel.copyToClipboard(logsText)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            // Logs display
            if filteredLogs.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No logs available")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("Server logs will appear here when the server is running")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    List(filteredLogs) { log in
                        LogRowView(log: log)
                            .id(log.id)
                            .onAppear {
                                if isAutoScrollEnabled && log.id == filteredLogs.first?.id {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        proxy.scrollTo(log.id, anchor: .top)
                                    }
                                }
                            }
                    }
                    .listStyle(.plain)
                    .onChange(of: viewModel.serverLogs.count) { _, _ in
                        if isAutoScrollEnabled, let lastLog = filteredLogs.first {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(lastLog.id, anchor: .top)
                            }
                        }
                    }
                }
            }
        }
        .padding()
    }
}

// MARK: - Log Row View
struct LogRowView: View {
    let log: ServerViewModel.LogEntry
    
    private var isRequestContent: Bool {
        log.category == .request && log.message.contains("Request content")
    }
    
    private var isResponseContent: Bool {
        log.category == .response && log.message.contains("Response content")
    }
    
    private var hasStatusCode: Bool {
        log.details?.contains("Status:") == true
    }
    
    private var statusCode: String? {
        guard hasStatusCode else { return nil }
        return log.details?.components(separatedBy: "Status: ").last?.components(separatedBy: ",").first
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // Level icon and text
                Label(log.level.rawValue, systemImage: log.level.icon)
                    .font(.caption)
                    .foregroundStyle(log.level.color == "red" ? .red : 
                                   log.level.color == "orange" ? .orange :
                                   log.level.color == "secondary" ? .secondary : .primary)
                
                // Category
                Label(log.category.rawValue, systemImage: log.category.icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                // Status code badge (if available)
                if let statusCode = statusCode {
                    Text(statusCode)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(statusCodeColor(for: statusCode))
                        .foregroundColor(.white)
                        .cornerRadius(4)
                }
                
                Spacer()
                
                // Timestamp
                Text(log.timestamp, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // Message
            Text(log.message)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.primary)
            
            // Details (if available)
            if let details = log.details {
                if isRequestContent || isResponseContent {
                    // Special formatting for request/response content
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Content:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fontWeight(.medium)
                        
                        Text(details)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.primary)
                            .padding(8)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(6)
                            .lineLimit(nil)
                    }
                    .padding(.leading, 8)
                } else {
                    // Regular details formatting
                    Text(details)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 8)
                }
            }
        }
        .padding(.vertical, 2)
    }
    
    private func statusCodeColor(for statusCode: String) -> Color {
        switch statusCode {
        case "200", "201", "202":
            return .green
        case "400", "401", "403", "404":
            return .orange
        case "500", "502", "503":
            return .red
        default:
            return .gray
        }
    }
}

#Preview {
    PreferencesView(viewModel: ServerViewModel())
}
