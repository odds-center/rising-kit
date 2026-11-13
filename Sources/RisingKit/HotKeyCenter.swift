import AppKit
import Carbon.HIToolbox
import RisingKitCore

extension KeyCombo {
    var carbonModifiers: UInt32 {
        var m: UInt32 = 0
        if control { m |= UInt32(controlKey) }
        if option { m |= UInt32(optionKey) }
        if command { m |= UInt32(cmdKey) }
        if shift { m |= UInt32(shiftKey) }
        return m
    }

    var modifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if control { flags.insert(.control) }
        if option { flags.insert(.option) }
        if command { flags.insert(.command) }
        if shift { flags.insert(.shift) }
        return flags
    }

    /// NSMenuItem.keyEquivalent 에 넣을 문자
    var menuKey: String {
        switch key {
        case "left": return "\u{F702}"
        case "right": return "\u{F703}"
        case "up": return "\u{F700}"
        case "down": return "\u{F701}"
        case "return": return "\r"
        case "delete": return "\u{08}"
        case "space": return " "
        case "tab": return "\t"
        case "escape": return "\u{1B}"
        default:
            if key.hasPrefix("f"), let n = Int(key.dropFirst()), let scalar = Unicode.Scalar(0xF704 + n - 1) {
                return String(Character(scalar))
            }
            return key
        }
    }
}

/// Carbon RegisterEventHotKey 래퍼. 손쉬운 사용 권한 없이도 전역 단축키를 받는다.
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef] = []
    private var nextID: UInt32 = 1
    private var installed = false

    private func installHandlerIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            if status == noErr { HotKeyCenter.shared.handlers[hk.id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }

    /// 등록에 실패하면(시스템이 거부한 조합 등) false.
    @discardableResult
    func register(_ combo: KeyCombo, handler: @escaping () -> Void) -> Bool {
        installHandlerIfNeeded()
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x524B_4954) /* 'RKIT' */, id: id)
        let status = RegisterEventHotKey(
            combo.keyCode, combo.carbonModifiers, hkID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            NSLog("RisingKit: 단축키 등록 실패 \(combo.string) (\(status))")
            return false
        }
        refs.append(ref)
        handlers[id] = handler
        return true
    }

    func unregisterAll() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        handlers.removeAll()
    }
}
