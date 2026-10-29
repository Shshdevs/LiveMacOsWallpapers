import AppKit
import Carbon
import Foundation

private func wallpaperHotkeyEventHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return noErr }
    var hotkeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotkeyID
    )
    guard status == noErr else { return noErr }
    Unmanaged<GlobalHotkeyMonitor>.fromOpaque(userData).takeUnretainedValue().onHotkey(hotkeyID.id)
    return noErr
}

final class GlobalHotkeyMonitor {
    private var eventHandler: EventHandlerRef?
    private var playbackHotkeyRef: EventHotKeyRef?
    private var nextPlaylistHotkeyRef: EventHotKeyRef?
    private var previousPlaylistHotkeyRef: EventHotKeyRef?
    let onHotkey: (UInt32) -> Void

    init(onHotkey: @escaping (UInt32) -> Void) {
        self.onHotkey = onHotkey
    }

    func register(_ hotkeys: PlaylistHotkeys) {
        unregister()
        if eventHandler == nil {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(
                GetApplicationEventTarget(),
                wallpaperHotkeyEventHandler,
                1,
                &eventType,
                Unmanaged.passUnretained(self).toOpaque(),
                &eventHandler
            )
        }
        register(hotkeys.playback, id: 1, reference: &playbackHotkeyRef)
        register(hotkeys.nextPlaylist, id: 2, reference: &nextPlaylistHotkeyRef)
        register(hotkeys.previousPlaylist, id: 3, reference: &previousPlaylistHotkeyRef)
    }

    func unregister() {
        unregister(&playbackHotkeyRef)
        unregister(&nextPlaylistHotkeyRef)
        unregister(&previousPlaylistHotkeyRef)
    }

    private func register(_ hotkey: GlobalHotkey, id: UInt32, reference: inout EventHotKeyRef?) {
        var modifiers: UInt32 = 0
        if hotkey.modifierMask & 1 != 0 { modifiers |= UInt32(shiftKey) }
        if hotkey.modifierMask & 2 != 0 { modifiers |= UInt32(controlKey) }
        if hotkey.modifierMask & 4 != 0 { modifiers |= UInt32(optionKey) }
        if hotkey.modifierMask & 8 != 0 { modifiers |= UInt32(cmdKey) }
        let identifier = EventHotKeyID(signature: OSType(0x4C575050), id: id)
        RegisterEventHotKey(UInt32(hotkey.keyCode), modifiers, identifier, GetApplicationEventTarget(), 0, &reference)
    }

    private func unregister(_ reference: inout EventHotKeyRef?) {
        if let registered = reference {
            UnregisterEventHotKey(registered)
            reference = nil
        }
    }
}
