import AppKit
import RisingKitCore

/// 창 배치를 이름 붙여 저장하고 다시 적용한다.
enum Layouts {
    /// 지금 화면에 보이는 창들로 레이아웃을 만든다 (현재 데스크탑 공간의 창만 해당).
    static func capture(name: String) -> Layout {
        let screens = WindowManager.screens()
        let items = WindowManager.snapshot().compactMap { window -> Layout.Item? in
            guard !window.bundleId.isEmpty, screens.indices.contains(window.display) else { return nil }
            return Layout.Item(
                bundleId: window.bundleId, app: window.app, title: window.title, display: window.display,
                rect: FractionRect(window.frame, in: screens[window.display].visible))
        }
        return Layout(name: name, items: items)
    }

    /// 같은 이름이 있으면 바꾸고, 없으면 추가한다. 단축키 설정은 이름에 묶여 있어 그대로 유지된다.
    static func save(_ layout: Layout) {
        ConfigStore.shared.update { config in
            if let index = config.layouts.firstIndex(where: { $0.name == layout.name }) {
                config.layouts[index] = layout
            } else {
                config.layouts.append(layout)
            }
        }
    }

    /// 지운 레이아웃이 있었으면 true. 묶여 있던 단축키도 함께 지운다.
    @discardableResult
    static func delete(name: String) -> Bool {
        guard ConfigStore.shared.config.layouts.contains(where: { $0.name == name }) else { return false }
        ConfigStore.shared.update { config in
            config.layouts.removeAll { $0.name == name }
            config.shortcuts.removeValue(forKey: "layout:" + name)
        }
        return true
    }

    @discardableResult
    static func apply(_ layout: Layout) -> (moved: Int, skipped: [String]) {
        let result = WindowManager.apply(layout)
        if result.moved == 0 { NSSound.beep() }
        return result
    }
}
