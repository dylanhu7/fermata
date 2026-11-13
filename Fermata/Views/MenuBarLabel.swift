import AppKit
import FermataCore
import SwiftUI

/// The menu bar icon: output (with volume), plus a muted microphone and manual mode when
/// they apply. MenuBarExtra shows a single image, so the symbols are drawn into one
/// template image that the menu bar tints itself.
struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        Image(nsImage: Self.render(symbols))
            .accessibilityLabel("Fermata")
    }

    private var symbols: [Symbol] {
        var symbols: [Symbol] = []
        if model.isMicrophoneMuted {
            symbols.append(Symbol(name: "mic.slash.fill"))
        }
        if !model.settings.isAutomatic {
            symbols.append(Symbol(name: "hand.raised.fill"))
        }
        if model.isOutputMuted {
            symbols.append(Symbol(name: "speaker.slash.fill"))
        } else if model.settings.mode == .headphone {
            symbols.append(Symbol(name: "headphones"))
        } else {
            symbols.append(Symbol(name: "speaker.wave.3.fill", value: Double(model.levels.outputVolume)))
        }
        return symbols
    }

    struct Symbol: Hashable {
        var name: String
        var value: Double?
    }

    private static func render(_ symbols: [Symbol]) -> NSImage {
        let content = HStack(spacing: 4) {
            ForEach(symbols, id: \.self) { symbol in
                Image(systemName: symbol.name, variableValue: symbol.value)
            }
        }
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(.black)
        .frame(height: 18)

        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = true
        return image
    }
}
