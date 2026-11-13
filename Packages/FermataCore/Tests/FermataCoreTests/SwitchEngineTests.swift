import Foundation
import Testing
@testable import FermataCore

private let mic = Device(uid: "mic", name: "MacBook Pro Microphone", transport: .builtIn, hasInput: true)
private let speakers = Device(uid: "spk", name: "MacBook Pro Speakers", transport: .builtIn, hasOutput: true)
private let display = Device(uid: "display", name: "Studio Display Speakers", transport: .usb, hasOutput: true)
private let airPods = Device(uid: "pods", name: "AirPods Pro", transport: .bluetooth, hasOutput: true)
private let homePod = Device(uid: "homepod", name: "Living Room", transport: .airPlay, hasOutput: true)
private let zoom = Device(uid: "zoom", name: "ZoomAudioDevice", transport: .virtual, hasInput: true, hasOutput: true)

private let start = Date(timeIntervalSinceReferenceDate: 1_000_000)

/// An engine with fixed settings (display, then built-in speakers) and a clock in seconds.
private struct Scenario {
    var engine = SwitchEngine()
    var settings = Settings()

    init(_ configure: (inout Settings) -> Void = { _ in }) {
        settings.lists = [.speakers: ["display", "spk"], .headphones: ["pods"], .microphones: ["mic"]]
        configure(&settings)
    }

    mutating func evaluate(_ devices: [Device], output: String, at seconds: TimeInterval, picking: Bool = false) -> SwitchDecision {
        let snapshot = HardwareSnapshot(devices: [mic] + devices, defaultInput: "mic", defaultOutput: output)
        let decision = engine.evaluate(snapshot, settings: settings, now: start + seconds, userIsPicking: picking)
        if let mode = decision.mode { settings.mode = mode }
        return decision
    }
}

@Suite struct SwitchEngineTests {
    @Test func changesTheDefaultOnceAndWaitsForIt() {
        var scenario = Scenario()
        #expect(scenario.evaluate([speakers, display], output: "spk", at: 0).defaults == [.output: "display"])
        // More events arrive before CoreAudio reports the change; it isn't asked for again.
        #expect(scenario.evaluate([speakers, display], output: "spk", at: 0.1).defaults.isEmpty)
        // The change arriving isn't mistaken for someone else's.
        #expect(scenario.evaluate([speakers, display], output: "display", at: 0.3) == SwitchDecision())
    }

    @Test func waitsForANewDeviceToSettle() {
        var scenario = Scenario()
        _ = scenario.evaluate([speakers], output: "spk", at: 0)

        let early = scenario.evaluate([speakers, display], output: "spk", at: 10)
        #expect(early.defaults.isEmpty)
        #expect(early.recheckAt == start + 10 + SwitchEngine.settleTime)

        let settled = scenario.evaluate([speakers, display], output: "spk", at: 10 + SwitchEngine.settleTime)
        #expect(settled.defaults == [.output: "display"])
    }

    @Test func softwareDevicesComingAndGoingChangeNothing() {
        // Apps such as Zoom and Teams create and destroy their own devices.
        var scenario = Scenario { $0.neverAuto = ["zoom"] }
        for step in 0...20 {
            let devices = step.isMultiple(of: 2) ? [speakers] : [speakers, zoom]
            #expect(scenario.evaluate(devices, output: "spk", at: Double(step) * 0.05) == SwitchDecision())
        }
    }

    @Test func modeFollowsHeadphones() {
        var scenario = Scenario()
        _ = scenario.evaluate([speakers], output: "spk", at: 0)

        // macOS moves output to the AirPods as they connect; that's part of the arrival.
        let connected = scenario.evaluate([speakers, airPods], output: "pods", at: 5)
        #expect(connected.mode == .headphone)
        #expect(connected.defaults.isEmpty)

        #expect(scenario.evaluate([speakers], output: "spk", at: 60).mode == .speaker)
    }

    @Test func revertsATakeoverOnceThenYields() {
        var scenario = Scenario()
        _ = scenario.evaluate([speakers, display], output: "display", at: 0)

        #expect(scenario.evaluate([speakers, display], output: "spk", at: 100).defaults == [.output: "display"])
        _ = scenario.evaluate([speakers, display], output: "display", at: 100.2)

        let again = scenario.evaluate([speakers, display], output: "spk", at: 110)
        #expect(again.defaults.isEmpty)
        #expect(again.yielded == [.output: "spk"])
    }

    @Test func keepsWhatTheUserPicksInControlCenter() {
        var scenario = Scenario()
        _ = scenario.evaluate([speakers, display], output: "display", at: 0)
        #expect(scenario.evaluate([speakers, display], output: "spk", at: 50, picking: true) == SwitchDecision())
        #expect(scenario.evaluate([speakers, display], output: "spk", at: 51) == SwitchDecision())
        // Until the picked device goes away.
        #expect(scenario.evaluate([display], output: "spk", at: 60).defaults == [.output: "display"])
    }

    @Test func keepsAnAirPlaySpeakerWhileItConnects() {
        // AirPlay devices appear only as they are picked, and may not be ready at first.
        var scenario = Scenario { $0.mode = .headphone }
        _ = scenario.evaluate([speakers, airPods], output: "pods", at: 0)

        let picked = scenario.evaluate([speakers, airPods, homePod], output: "homepod", at: 5)
        #expect(picked.mode == .speaker)
        #expect(picked.defaults.isEmpty)

        var connecting = homePod
        connecting.isAlive = false
        #expect(scenario.evaluate([speakers, airPods, connecting], output: "homepod", at: 5.5).defaults.isEmpty)
    }

    @Test func skipsHiddenNeverAutoAndUnusableDevices() {
        var dead = display
        dead.isAlive = false
        var scenario = Scenario { $0.lists[.speakers] = ["display", "usb", "spk"] }
        #expect(scenario.evaluate([speakers, dead], output: "spk", at: 0).defaults.isEmpty)

        let usb = Device(uid: "usb", name: "USB Speaker", transport: .usb, hasOutput: true)
        scenario = Scenario {
            $0.lists[.speakers] = ["display", "usb", "spk"]
            $0.neverAuto = ["display"]
            $0.setHidden(true, uid: "usb", in: .speaker)
        }
        #expect(scenario.evaluate([speakers, display, usb], output: "display", at: 0).defaults == [.output: "spk"])
    }

    @Test func manualModeNeverChangesAnything() {
        var scenario = Scenario { $0.isAutomatic = false }
        #expect(scenario.evaluate([speakers, display, airPods], output: "spk", at: 0) == SwitchDecision())
    }
}
