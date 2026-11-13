#if DEBUG
import AppKit
import FermataCore
import SwiftUI

/// Debug launch arguments for checking the UI without clicking the menu bar:
/// `--panel-window` shows the panel in a window, `--snapshot <path>` saves it as a PNG, and
/// `--editing`, `--manual` and `--dark` set up what to show. `--demo` shows sample devices
/// in place of this Mac's.
enum DebugPanel {
    private static var window: NSWindow?

    static func handleLaunchArguments(model: AppModel) {
        let arguments = CommandLine.arguments
        let model = arguments.contains("--demo") ? demoModel : model
        if arguments.contains("--editing") { model.isEditing = true }
        if arguments.contains("--manual") { model.setAutomatic(false) }
        if arguments.contains("--dark") { NSApp.appearance = NSAppearance(named: .darkAqua) }
        guard arguments.contains("--panel-window") else { return }

        let window = NSWindow(contentViewController: NSHostingController(rootView: PanelView().environment(model)))
        window.title = "Fermata"
        window.makeKeyAndOrderFront(nil)
        self.window = window

        if let index = arguments.firstIndex(of: "--snapshot"), arguments.indices.contains(index + 1) {
            // Controls are dimmed in a window that isn't key; no focus ring either.
            NSApp.activate()
            window.makeFirstResponder(nil)
            Task {
                try? await Task.sleep(for: .seconds(2))
                snapshot(window, to: URL(fileURLWithPath: arguments[index + 1]))
            }
        }
    }

    private static var demoModel: AppModel {
        let devices = [
            Device(uid: "display", name: "Studio Display Speakers", transport: .usb, hasOutput: true),
            Device(uid: "speakers", name: "MacBook Pro Speakers", transport: .builtIn, hasOutput: true),
            Device(uid: "homepod", name: "Living Room", transport: .airPlay, hasOutput: true, model: "AudioAccessory5,1"),
            Device(uid: "monitor", name: "LG UltraFine", transport: .displayPort, hasOutput: true),
            Device(uid: "usb-mic", name: "Shure MV7", transport: .usb, hasInput: true),
            Device(uid: "mic", name: "MacBook Pro Microphone", transport: .builtIn, hasInput: true),
            Device(uid: "iphone", name: "iPhone Microphone", transport: .continuity, hasInput: true),
        ]
        var settings = Settings()
        settings.remember(devices, now: .now)
        settings.lists = [.speakers: ["display", "speakers", "homepod"], .microphones: ["usb-mic", "mic", "iphone"]]
        return AppModel(demo: HardwareSnapshot(devices: devices, defaultInput: "usb-mic", defaultOutput: "display"), settings: settings)
    }

    /// Draws the panel at three pixels per point, on the window background with rounded corners.
    private static func snapshot(_ window: NSWindow, to url: URL, scale: CGFloat = 3) {
        guard let view = window.contentView,
              let content = bitmap(size: view.bounds.size, scale: scale),
              let image = bitmap(size: view.bounds.size, scale: scale),
              let context = NSGraphicsContext(bitmapImageRep: image)
        else { return }
        view.cacheDisplay(in: view.bounds, to: content)

        // The window's own background isn't part of the cached view, so draw it underneath.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSBezierPath(roundedRect: view.bounds, xRadius: 16, yRadius: 16).addClip()
        window.effectiveAppearance.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            view.bounds.fill()
        }
        content.draw(in: view.bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()

        try? image.representation(using: .png, properties: [:])?.write(to: url)
    }

    private static func bitmap(size: NSSize, scale: CGFloat) -> NSBitmapImageRep? {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )
        bitmap?.size = size
        return bitmap
    }
}
#endif
