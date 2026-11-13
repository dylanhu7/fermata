import Carbon.HIToolbox

/// ⌥⇧M from anywhere. Carbon hot keys are still the only system-wide shortcut API that
/// needs no Accessibility permission.
enum MicrophoneHotKey {
    private static var action: (() -> Void)?
    private static var reference: EventHotKeyRef?

    static func register(_ action: @escaping () -> Void) {
        guard reference == nil else { return }
        self.action = action
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyPressed, 1, &pressed, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x4652_4D54), id: 1) // 'FRMT'
        RegisterEventHotKey(UInt32(kVK_ANSI_M), UInt32(optionKey | shiftKey), id, GetApplicationEventTarget(), 0, &reference)
    }

    fileprivate static func fire() {
        action?()
    }
}

/// Carbon delivers hot key events on the main thread.
private nonisolated func hotKeyPressed(_: EventHandlerCallRef?, _: EventRef?, _: UnsafeMutableRawPointer?) -> OSStatus {
    MainActor.assumeIsolated { MicrophoneHotKey.fire() }
    return noErr
}
