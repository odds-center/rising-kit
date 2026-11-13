import AppKit
import Carbon.HIToolbox

/// 메뉴바 전용 앱에는 "편집" 메뉴가 없어서 ⌘V 같은 단축키가 입력란에 전달되지 않는다.
/// 창의 키 입력 감시에서 이 함수를 불러 직접 전달한다.
enum EditKeys {
    /// 편집 단축키였고 처리했으면 true.
    static func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let action: Selector
        switch (Int(event.keyCode), flags) {
        case (kVK_ANSI_V, [.command]): action = #selector(NSText.paste(_:))
        case (kVK_ANSI_C, [.command]): action = #selector(NSText.copy(_:))
        case (kVK_ANSI_X, [.command]): action = #selector(NSText.cut(_:))
        case (kVK_ANSI_A, [.command]): action = #selector(NSText.selectAll(_:))
        case (kVK_ANSI_Z, [.command]): action = Selector(("undo:"))
        case (kVK_ANSI_Z, [.command, .shift]): action = Selector(("redo:"))
        default: return false
        }
        // 지금 입력 중인 칸(첫 응답자)으로 보낸다
        return NSApp.sendAction(action, to: nil, from: nil)
    }
}
