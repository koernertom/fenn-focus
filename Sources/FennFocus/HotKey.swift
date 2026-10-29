import Carbon.HIToolbox

/// System-wide shortcut via Carbon — works without Accessibility permission.
/// Lives for the whole app session, so it never unregisters.
@MainActor
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    fileprivate let id: UInt32
    fileprivate let action: () -> Void

    init?(id: UInt32, keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.id = id
        self.action = action
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var pressed = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &pressed
                )
                let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
                // Every registered HotKey sees every press; only the matching one acts.
                return MainActor.assumeIsolated {
                    guard pressed.id == hotKey.id else { return OSStatus(eventNotHandledErr) }
                    hotKey.action()
                    return noErr
                }
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        guard status == noErr else { return nil }

        let hotKeyID = EventHotKeyID(signature: OSType(0x4D49_4C4F), id: id) // "FENN"
        guard RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef) == noErr else {
            return nil
        }
    }
}
