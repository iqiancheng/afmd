//
//  afmdApp.swift
//  afmd
//
//  Created by Channing Dai on 6/15/25.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct afmdApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    @StateObject private var viewModel: ServerViewModel
    @State private var showingPreferences = false

    init() {
        // Initialize the server view model early and auto-start the server
        _viewModel = StateObject(wrappedValue: ServerViewModel())
    }

    var body: some Scene {
        #if os(macOS)
        MenuBarExtra { 
            StatusMenuView(viewModel: viewModel, showingPreferences: $showingPreferences)
        } label: {
            // Dynamic icon reflecting server status with subtle effects
            Image(systemName: viewModel.isRunning ? "bolt.horizontal.circle.fill" : "bolt.horizontal.circle")
                .symbolRenderingMode(.multicolor)
                .foregroundStyle(viewModel.isRunning ? .green : .secondary)
                .help(viewModel.isRunning ? "afmd: Running" : "afmd: Stopped")
                .contentTransition(.symbolEffect(.replace))
        }
        .menuBarExtraStyle(.automatic)
        
        // Preferences Window
        Window("Preferences", id: "preferences") {
            PreferencesView(viewModel: viewModel)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        #else
        // Fallback for non-macOS builds (not used, but keeps the type consistent)
        WindowGroup { EmptyView() }
        #endif
    }
}

#if os(macOS)
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Check if running in daemon mode
        let isDaemonMode = ProcessInfo.processInfo.environment["AFMD_DAEMON_MODE"] == "true"
        
        if isDaemonMode {
            // In daemon mode, hide Dock icon completely
            NSApp.setActivationPolicy(.accessory)
        } else {
            // Normal mode, hide Dock icon for menu bar–only experience
            NSApp.setActivationPolicy(.accessory)
        }
        
        // Setup global keyboard shortcuts
        setupKeyboardShortcuts()
    }
    
    private func setupKeyboardShortcuts() {
        // Register Command+, for Preferences
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains(.command) && event.characters == "," {
                // Open Preferences window
                DispatchQueue.main.async {
                    if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "preferences" }) {
                        window.makeKeyAndOrderFront(nil)
                        NSApp.activate(ignoringOtherApps: true)
                    } else {
                        // Create new preferences window
                        let contentView = PreferencesView(viewModel: ServerViewModel())
                        let hostingController = NSHostingController(rootView: contentView)
                        let window = NSWindow(contentViewController: hostingController)
                        window.title = "Preferences"
                        window.identifier = NSUserInterfaceItemIdentifier("preferences")
                        window.setContentSize(NSSize(width: 500, height: 600))
                        window.center()
                        window.makeKeyAndOrderFront(nil)
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
                return nil
            }
            return event
        }
    }
}

struct StatusMenuView: View {
    @ObservedObject var viewModel: ServerViewModel
    @Binding var showingPreferences: Bool
    @Environment(\.openURL) private var openURL
    @Environment(\.openWindow) private var openWindow
    @State private var isWorking: Bool = false

    private var readmeURL: URL? {
        URL(string: "https://github.com/iqiancheng/afmd#readme")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.isModelAvailable ? "Available" : "Unavailable")
                        .font(.headline)
                    Text(viewModel.modelName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: viewModel.isModelAvailable ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(viewModel.isModelAvailable ? .green : .red)
                    .symbolEffect(.bounce, options: .repeat(1), value: viewModel.isModelAvailable)
            }

            Divider()

            // Group {
            //     Button {
            //         viewModel.copyToClipboard(viewModel.openaiBaseURL)
            //     } label: {
            //         VStack(alignment: .leading, spacing: 2) {
            //             Text("Base URL")
            //                 .font(.caption)
            //                 .foregroundStyle(.secondary)
            //             Text(viewModel.openaiBaseURL)
            //                 .font(.system(.caption, design: .monospaced))
            //                 .truncationMode(.middle)
            //         }
            //         .frame(maxWidth: .infinity, alignment: .leading)
            //     }
            //     .buttonStyle(.plain)
            //     .help("Click to copy Base URL")

            //     Button {
            //         viewModel.copyToClipboard(viewModel.chatCompletionsEndpoint)
            //     } label: {
            //         VStack(alignment: .leading, spacing: 2) {
            //             Text("Chat Completions")
            //                 .font(.caption)
            //                 .foregroundStyle(.secondary)
            //             Text(viewModel.chatCompletionsEndpoint)
            //                 .font(.system(.caption, design: .monospaced))
            //                 .truncationMode(.middle)
            //         }
            //         .frame(maxWidth: .infinity, alignment: .leading)
            //     }
            //     .buttonStyle(.plain)
            //     .help("Click to copy Chat Completions endpoint")

            //     Button {
            //         viewModel.copyToClipboard(viewModel.modelName)
            //     } label: {
            //         VStack(alignment: .leading, spacing: 2) {
            //             Text("Model")
            //                 .font(.caption)
            //                 .foregroundStyle(.secondary)
            //             Text(viewModel.modelName)
            //         }
            //         .frame(maxWidth: .infinity, alignment: .leading)
            //     }
            //     .buttonStyle(.plain)
            //     .help("Click to copy model name")
            // }

            // Divider()

            Button {
                // Close any existing Preferences window and open a fresh one
                DispatchQueue.main.async {
                    if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "preferences" }) {
                        // Close previous preferences window to ensure a clean new instance
                        window.close()
                        // Small delay to allow the system to release the window, then open a new one
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            openWindow(id: "preferences")
                            NSApp.activate(ignoringOtherApps: true)
                        }
                    } else {
                        openWindow(id: "preferences")
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
            } label: {
                Label("Preferences...", systemImage: "gear")
            }
            .keyboardShortcut(",", modifiers: .command)
            .help("Open Preferences (⌘,)")

            Divider()
            
            Button {
                viewModel.copyCurlCommand()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Label("cURL Test Example", systemImage: "terminal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let lanIP = viewModel.getLocalNetworkIP() {
                        Text("LAN: \(lanIP):\(viewModel.configuration.port)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.primary)
                    } else {
                        Text("Local: \(viewModel.configuration.host):\(viewModel.configuration.port)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.primary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .help("Copy cURL command to clipboard for testing")

//            Divider()

            HStack {
                Button {
                    if let url = readmeURL { openURL(url) }
                } label: {
                    Label("Usage Docs", systemImage: "questionmark.circle")
                }

                // Spacer()
            }
        }
        // .padding(10)
        .task {
            await viewModel.checkModelAvailability()
            if viewModel.isModelAvailable && !viewModel.isRunning {
                await viewModel.startServer()
            }
        }
    }
}
#endif
