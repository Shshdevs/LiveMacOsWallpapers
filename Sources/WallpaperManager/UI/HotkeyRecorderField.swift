import AppKit

final class HotkeyRecorderButton: NSButton {
    var onChange: ((GlobalHotkey) -> Void)?
    var onBeginRecording: (() -> Void)?
    var onCancelRecording: (() -> Void)?
    private var isRecording = false
    private var currentHotkey: GlobalHotkey

    init(hotkey: GlobalHotkey) {
        currentHotkey = hotkey
        super.init(frame: .zero)
        title = Self.title(for: hotkey)
        bezelStyle = .rounded
        font = .systemFont(ofSize: 14, weight: .medium)
        target = self
        action = #selector(beginRecording(_:))
        setAccessibilityLabel("Горячая клавиша. Нажмите, чтобы записать сочетание.")
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        beginRecording(self)
    }

    @objc private func beginRecording(_ sender: Any?) {
        window?.makeFirstResponder(self)
        isRecording = true
        title = "Нажмите сочетание…"
        onBeginRecording?()
    }

    override func keyDown(with event: NSEvent) {
        record(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        record(event)
        return true
    }

    override func resignFirstResponder() -> Bool {
        if isRecording {
            isRecording = false
            title = Self.title(for: currentHotkey)
            onCancelRecording?()
        }
        return super.resignFirstResponder()
    }

    private func record(_ event: NSEvent) {
        guard isRecording else { return }
        let flags = event.modifierFlags.intersection([.shift, .control, .option, .command])
        var modifierMask: UInt8 = 0
        if flags.contains(.shift) { modifierMask |= 1 }
        if flags.contains(.control) { modifierMask |= 2 }
        if flags.contains(.option) { modifierMask |= 4 }
        if flags.contains(.command) { modifierMask |= 8 }
        guard modifierMask != 0 else { return }
        let hotkey = GlobalHotkey(keyCode: event.keyCode, modifierMask: modifierMask)
        currentHotkey = hotkey
        isRecording = false
        title = Self.title(for: hotkey)
        onChange?(hotkey)
    }

    private static func title(for hotkey: GlobalHotkey) -> String {
        var title = ""
        if hotkey.modifierMask & 8 != 0 { title += "⌘" }
        if hotkey.modifierMask & 1 != 0 { title += "⇧" }
        if hotkey.modifierMask & 2 != 0 { title += "⌃" }
        if hotkey.modifierMask & 4 != 0 { title += "⌥" }
        title += keyName(hotkey.keyCode)
        return title
    }

    private static func keyName(_ keyCode: UInt16) -> String {
        let names: [UInt16: String] = [
            36: "Ввод", 48: "Tab", 49: "Пробел", 51: "Удалить", 53: "Esc",
            115: "Домой", 116: "Страница вверх", 117: "Удалить вперёд", 119: "Конец", 121: "Страница вниз",
            123: "←", 124: "→", 125: "↓", 126: "↑", 35: "P", 0: "A", 1: "S", 2: "D",
            3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B",
            12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U",
            34: "I", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M", 18: "1", 19: "2",
            20: "3", 21: "4", 22: "6", 23: "5", 25: "9", 26: "7", 28: "8", 29: "0",
            24: "=", 27: "-", 30: "]", 33: "[", 39: "'", 41: ";", 42: "\\", 43: ",",
            44: "/", 47: ".", 50: "`", 122: "F1", 120: "F2", 99: "F3", 118: "F4",
            96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11",
            111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17",
            79: "F18", 80: "F19", 90: "F20"
        ]
        if let name = names[keyCode] { return name }
        return "Клавиша \(keyCode)"
    }
}
