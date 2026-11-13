/// How a device is connected.
public enum Transport: String, Codable, Sendable {
    case builtIn
    case usb
    case bluetooth
    case bluetoothLE
    case hdmi
    case displayPort
    case thunderbolt
    case airPlay
    case continuity
    case virtual
    case aggregate
    case unknown

    /// Software devices (Zoom, Teams, Loom, BlackHole, Multi-Output) that should never be
    /// picked automatically.
    public var isSoftware: Bool { self == .virtual || self == .aggregate }

    /// Monitor speakers, which most people never want as an automatic choice.
    public var isDisplay: Bool { self == .hdmi || self == .displayPort }

    /// AirPlay speakers (HomePod, Apple TV, AirPlay receivers). macOS only routes audio to
    /// them when someone picks one, so the default moving there is always a person's choice.
    public var isPickedOnly: Bool { self == .airPlay }
}

extension Transport {
    /// Maps a CoreAudio `kAudioDeviceTransportType*` code.
    public init(code: UInt32) {
        self = switch code {
        case fourCC("bltn"): .builtIn
        case fourCC("usb "): .usb
        case fourCC("blue"): .bluetooth
        case fourCC("blea"): .bluetoothLE
        case fourCC("hdmi"): .hdmi
        case fourCC("dprt"): .displayPort
        case fourCC("thun"): .thunderbolt
        case fourCC("airp"): .airPlay
        case fourCC("ccwd"), fourCC("ccwl"): .continuity
        case fourCC("virt"): .virtual
        case fourCC("grup"), fourCC("fgrp"): .aggregate
        default: .unknown
        }
    }
}

/// A CoreAudio four-character code, such as `fourCC("blue")` for Bluetooth.
func fourCC(_ string: StaticString) -> UInt32 {
    string.withUTF8Buffer { bytes in
        bytes.reduce(0) { ($0 << 8) | UInt32($1) }
    }
}
