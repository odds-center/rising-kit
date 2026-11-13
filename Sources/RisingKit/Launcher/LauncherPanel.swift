import AppKit
import Carbon.HIToolbox
import SwiftUI

/// 다른 앱을 비활성화하지 않고 키 입력을 받는 떠 있는 창.
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class LauncherController: NSObject, NSWindowDelegate {
    private let model = LauncherModel()
    private var panel: KeyPanel?
    private var keyMonitor: Any?

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show(filter: LauncherFilter = .all) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        model.prepareForShow(filter: filter)

        // 마우스가 있는 화면의 위쪽 1/4 지점에 띄운다
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(
                x: (visible.midX - size.width / 2).rounded(),
                y: (visible.minY + visible.height * 0.75 - size.height / 2).rounded()))
        }
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func hide() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        panel?.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    private func makePanel() -> KeyPanel {
        let panel = KeyPanel(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 468),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.animationBehavior = .none
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: LauncherView(model: model))
        model.onClose = { [weak self] in self?.hide() }
        return panel
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel = self.panel, event.window === panel else { return event }
            // 한글 조합 중에는 Enter·방향키가 조합 확정에 쓰이므로 건드리지 않는다
            if let editor = panel.firstResponder as? NSTextView, editor.hasMarkedText() { return event }
            // 검색창에서 복사·붙여넣기·전체 선택·실행 취소
            if EditKeys.handle(event) { return nil }
            let control = event.modifierFlags.contains(.control)
            let command = event.modifierFlags.contains(.command)
            let shift = event.modifierFlags.contains(.shift)
            switch Int(event.keyCode) {
            case kVK_Escape:
                self.hide(); return nil
            case kVK_Return, kVK_ANSI_KeypadEnter:
                command ? self.model.revealSelected() : self.model.runSelected()
                return nil
            case kVK_Tab:
                self.model.cycleFilter(shift ? -1 : 1); return nil
            case kVK_ANSI_C where command && shift:
                self.model.copySelected(); return nil
            case kVK_Delete where command:
                self.model.deleteSelectedClip(); return nil
            case kVK_DownArrow:
                self.model.moveSelection(1); return nil
            case kVK_UpArrow:
                self.model.moveSelection(-1); return nil
            case kVK_ANSI_N where control:
                self.model.moveSelection(1); return nil
            case kVK_ANSI_P where control:
                self.model.moveSelection(-1); return nil
            default:
                return event
            }
        }
    }
}
