import Foundation

/// "ctrl+opt+left" 같은 문자열로 표현하는 단축키.
public struct KeyCombo: Equatable {
    public let key: String        // 정규화된 키 이름: "a", "1", "left", "return", "f5" ...
    public let keyCode: UInt32    // macOS 가상 키 코드
    public let control: Bool
    public let option: Bool
    public let command: Bool
    public let shift: Bool

    /// 형식이 틀리거나 모르는 키면 nil. 기능 키(F1~F12)가 아니면 조합 키가 하나 이상 있어야 한다.
    public init?(_ string: String) {
        var control = false, option = false, command = false, shift = false
        var key: String?
        for raw in string.lowercased().split(separator: "+", omittingEmptySubsequences: false) {
            let part = raw.trimmingCharacters(in: .whitespaces)
            switch part {
            case "ctrl", "control", "⌃": control = true
            case "opt", "option", "alt", "⌥": option = true
            case "cmd", "command", "⌘": command = true
            case "shift", "⇧": shift = true
            default:
                guard key == nil, let name = Self.aliases[part] ?? (Self.keyCodes[part] != nil ? part : nil) else {
                    return nil
                }
                key = name
            }
        }
        guard let key, let code = Self.keyCodes[key] else { return nil }
        let isFunctionKey = key.hasPrefix("f") && key.count > 1
        guard control || option || command || isFunctionKey else { return nil }
        self.key = key
        self.keyCode = code
        self.control = control
        self.option = option
        self.command = command
        self.shift = shift
    }

    /// 눌린 키(가상 키 코드)와 조합 키로 만든다. 단축키로 쓸 수 없는 조합이면 nil.
    public init?(keyCode: UInt32, control: Bool, option: Bool, command: Bool, shift: Bool) {
        guard let key = Self.keyCodes.first(where: { $0.value == keyCode })?.key else { return nil }
        var parts: [String] = []
        if control { parts.append("ctrl") }
        if option { parts.append("opt") }
        if command { parts.append("cmd") }
        if shift { parts.append("shift") }
        self.init((parts + [key]).joined(separator: "+"))
    }

    /// 다시 읽을 수 있는 표준 표기: "ctrl+opt+cmd+shift+키"
    public var string: String {
        var parts: [String] = []
        if control { parts.append("ctrl") }
        if option { parts.append("opt") }
        if command { parts.append("cmd") }
        if shift { parts.append("shift") }
        return (parts + [key]).joined(separator: "+")
    }

    /// 화면 표시용: "⌃⌥←"
    public var display: String {
        var s = ""
        if control { s += "⌃" }
        if option { s += "⌥" }
        if shift { s += "⇧" }
        if command { s += "⌘" }
        return s + (Self.symbols[key] ?? key.uppercased())
    }

    /// 키캡 하나씩 나눈 표시: ["⌃", "⌥", "←"]
    public var displayParts: [String] {
        var parts: [String] = []
        if control { parts.append("⌃") }
        if option { parts.append("⌥") }
        if shift { parts.append("⇧") }
        if command { parts.append("⌘") }
        parts.append(Self.symbols[key] ?? key.uppercased())
        return parts
    }

    private static let aliases: [String: String] = [
        "enter": "return", "backspace": "delete", "esc": "escape", "spacebar": "space",
        "←": "left", "→": "right", "↑": "up", "↓": "down",
    ]

    private static let symbols: [String: String] = [
        "left": "←", "right": "→", "up": "↑", "down": "↓",
        "return": "↩", "delete": "⌫", "space": "Space", "tab": "⇥", "escape": "⎋",
    ]

    public static let keyCodes: [String: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26,
        "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
        "return": 36, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43,
        "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49, "`": 50, "delete": 51,
        "escape": 53,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100,
        "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "left": 123, "right": 124, "down": 125, "up": 126,
    ]
}
