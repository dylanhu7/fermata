import AppIntents
import AppKit
import FermataCore
import SwiftUI

@main
struct FermataApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        MenuBarExtra {
            PanelView().environment(delegate.model)
        } label: {
            MenuBarLabel(model: delegate.model)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Handles what SwiftUI scenes don't: URLs while no window is open, the global shortcut,
/// and cleaning up before quitting.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    override init() {
        super.init()
        // Registered before any App Intent can run.
        let model = model
        AppDependencyManager.shared.add(dependency: model)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
        MicrophoneHotKey.register { [model] in model.toggleMicrophoneMute() }
        #if DEBUG
        DebugPanel.handleLaunchArguments(model: model)
        #endif
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.compactMap(URLCommand.init(url:)).forEach(model.perform)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Unmute a microphone the app muted and remove listeners before going.
        Task {
            await model.stop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
