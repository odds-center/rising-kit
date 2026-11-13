import AppKit
import RisingKitCore

/// 설정 창에서 "단축키를 누르세요" 상태를 관리한다. 한 번에 하나만 받는다.
final class ShortcutRecorder: ObservableObject {
    static let shared = ShortcutRecorder()

    /// 지금 단축키를 받고 있는 대상 (명령 id 등). 없으면 nil.
    @Published private(set) var activeID: String?
    /// 받는 중에 보여 줄 안내나 오류
    @Published var message = ""

    /// 누른 조합을 처리한다 (nil 은 "단축키 지우기"). 문제가 있으면 그 설명을, 받아들였으면 nil 을 돌려준다.
    private var handler: ((KeyCombo?) -> String?)?

    var isRecording: Bool { activeID != nil }

    func begin(id: String, handler: @escaping (KeyCombo?) -> String?) {
        if isRecording { finish() }
        activeID = id
        self.handler = handler
        message = "단축키를 누르세요 · ⌫ 지우기 · esc 취소"
        // 누르는 조합이 기존 단축키로 실행되어 버리지 않게 잠시 모두 푼다
        HotKeyCenter.shared.unregisterAll()
    }

    func submit(_ combo: KeyCombo?) {
        guard let handler else { return }
        if let problem = handler(combo) {
            message = problem
            return
        }
        message = ""
        finish()
    }

    func cancel() {
        guard isRecording else { return }
        message = ""
        finish()
    }

    private func finish() {
        activeID = nil
        handler = nil
        ConfigStore.shared.onChange?()  // 단축키 다시 등록
    }

    /// 명령 하나의 단축키를 받아 설정에 저장한다.
    func beginCommand(_ id: String) {
        begin(id: id) { combo in
            guard let combo else {
                ConfigStore.shared.update { $0.shortcuts[id] = "" }
                return nil
            }
            if let other = Commands.conflict(for: combo, excluding: id) {
                return "\(combo.display) 는 이미 '\(other.title)' 에 쓰이고 있습니다. 다른 조합을 누르세요."
            }
            ConfigStore.shared.update { $0.shortcuts[id] = combo.string }
            return nil
        }
    }

    /// 키 입력을 단축키로 해석해 넘긴다. 받는 중이 아니면 false (이벤트를 그대로 흘려보내라는 뜻).
    func handle(_ event: NSEvent) -> Bool {
        guard isRecording else { return false }
        let flags = event.modifierFlags.intersection([.control, .option, .command, .shift])
        switch Int(event.keyCode) {
        case 53 where flags.isEmpty:  // esc
            cancel()
        case 51 where flags.isEmpty:  // delete
            submit(nil)
        default:
            if let combo = KeyCombo(
                keyCode: UInt32(event.keyCode), control: flags.contains(.control), option: flags.contains(.option),
                command: flags.contains(.command), shift: flags.contains(.shift)) {
                submit(combo)
            } else {
                message = "⌃ ⌥ ⌘ 중 하나 이상과 함께 눌러 주세요 · esc 취소"
            }
        }
        return true
    }
}
