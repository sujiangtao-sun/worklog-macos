import AppKit
import Foundation
import SwiftUI
import WorkLogCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            sender.windows.first?.makeKeyAndOrderFront(nil)
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct WorkLogApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    enum Startup {
        case ready(AppModel)
        case failed(String)
    }

    private let startup: Startup

    @MainActor
    init() {
        let result: Startup
        do {
            result = .ready(try AppModel())
        } catch {
            result = .failed(error.localizedDescription)
        }
        startup = result
    }

    var body: some Scene {
        Window("待办进展", id: "main") {
            switch startup {
            case .ready(let model):
                RootView(model: model)
            case .failed(let message):
                StartupFailureView(message: message)
            }
        }
        .defaultSize(width: 1260, height: 820)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建事项或任务") {
                    NotificationCenter.default.post(name: .workLogCreateItem, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            CommandGroup(after: .sidebar) {
                Button("回到今天") {
                    NotificationCenter.default.post(name: .workLogGoToday, object: nil)
                }
                .keyboardShortcut("t", modifiers: .command)
            }

            CommandGroup(replacing: .appTermination) {
                Button("退出待办进展") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }

        Settings {
            switch startup {
            case .ready(let model):
                DataSettingsView(model: model)
            case .failed(let message):
                Text(message)
                    .padding(24)
                    .frame(width: 480, height: 220)
            }
        }
    }
}
