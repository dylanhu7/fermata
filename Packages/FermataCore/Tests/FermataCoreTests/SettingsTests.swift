import Foundation
import Testing
@testable import FermataCore

private func emptyDefaults() -> UserDefaults {
    let name = "FermataCoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@Suite struct SettingsTests {
    @Test func savedSettingsLoadBack() {
        let store = SettingsStore(defaults: emptyDefaults())
        #expect(store.load() == Settings())

        var settings = Settings()
        settings.lists[.speakers] = ["display", "spk"]
        settings.setHidden(true, uid: "hdmi", in: .speaker)
        settings.known["display"] = KnownDevice(name: "Studio Display", hasInput: false, hasOutput: true, lastSeen: .now)
        store.save(settings)
        #expect(store.load() == settings)
    }

    @Test func firstSightDefaultsApplyOnce() {
        var settings = Settings()
        let devices = [
            Device(uid: "zoom", name: "ZoomAudioDevice", transport: .virtual, hasInput: true, hasOutput: true),
            Device(uid: "hdmi", name: "LG", transport: .hdmi, hasOutput: true),
            Device(uid: "homepod", name: "Kitchen", transport: .airPlay, hasOutput: true, model: "AudioAccessory6,1"),
            Device(uid: "usb", name: "Interface", transport: .usb, hasInput: true),
        ]
        settings.remember(devices, now: .now)
        #expect(settings.neverAuto == ["zoom", "homepod"])
        #expect(settings.isHidden("hdmi", in: .speaker))
        #expect(settings.known["homepod"]?.model == "AudioAccessory6,1")

        // The user's later choices stick.
        settings.neverAuto = []
        settings.remember(devices, now: .now)
        #expect(settings.neverAuto.isEmpty)
    }

    @Test func reorderingKeepsAbsentDevicesRanked() {
        var settings = Settings()
        settings.lists[.speakers] = ["a", "gone", "b"]
        settings.setOrder(["b", "a"], for: .speakers)
        #expect(settings.lists[.speakers] == ["b", "a", "gone"])
        #expect(settings.ordered(["unranked", "a", "b"], by: .speakers) == ["b", "a", "unranked"])
    }

    @Test func classifiesHeadphonesByTerminalTypeThenName() {
        #expect(DeviceClassifier.category(outputTerminalTypes: [0x0302], transport: .usb) == .headphone)
        // Bluetooth speakers report the headphone terminal type too.
        #expect(DeviceClassifier.category(outputTerminalTypes: [fourCC("hdph")], transport: .bluetooth) == nil)

        func category(_ name: String, _ transport: Transport) -> OutputCategory {
            DeviceClassifier.category(for: Device(uid: name, name: name, transport: transport, hasOutput: true))
        }
        #expect(category("Sam’s AirPods Max", .bluetooth) == .headphone)
        #expect(category("Marshall Stanmore", .bluetooth) == .speaker)
        #expect(category("Headphones", .builtIn) == .speaker)
    }

    @Test func urlCommandsAcceptOnlyTheBareForm() {
        #expect(URLCommand(url: URL(string: "fermata://toggle-mic-mute")!) == .toggleMicMute)
        #expect(URLCommand(url: URL(string: "Fermata://Headphones/")!) == .headphones)
        for string in ["fermata://mute-mic?x=1", "fermata://mute-mic/extra", "fermata://user@mute-mic", "fermata://unknown", "https://mute-mic"] {
            #expect(URLCommand(url: URL(string: string)!) == nil, "\(string)")
        }
    }
}
