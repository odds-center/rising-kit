import AppKit
import RisingKitCore

/// 창을 끌어서 화면 가장자리에 대면 그 자리에 맞춰 붙인다 (Magnet 의 끌어 붙이기).
/// 왼쪽·오른쪽 = 절반, 모서리 = 1/4, 위 = 최대화, 아래 = 1/3.
final class DragSnap {
    static let shared = DragSnap()

    private var monitor: Any?
    private var overlay: NSPanel?

    /// 끌기 시작할 때의 맨 앞 창과 그 위치
    private var tracked: (window: AXUIElement, start: CGRect)?
    private var moving = false
    private var target: CGRect?
    private var lastCheck = Date.distantPast

    var enabled: Bool { ConfigStore.shared.config.dragSnap }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            self?.handle(event)
        }
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            reset()
        case .leftMouseDragged:
            guard enabled, WindowManager.hasPermission, !Self.frontAppIgnored else { return }
            // 손쉬운 사용 API 호출은 느리므로 끄는 동안 초당 25번 정도만 확인한다
            guard Date().timeIntervalSince(lastCheck) > 0.04 else { return }
            lastCheck = Date()
            update()
        case .leftMouseUp:
            let window = tracked?.window
            let rect = target
            reset()
            if let window, let rect {
                // 앱이 자기 끌기 처리를 끝낸 뒤에 옮겨야 덮어쓰이지 않는다
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                    if let current = WindowManager.frame(of: window) { WindowManager.remember(window, frame: current) }
                    WindowManager.setFrame(rect, of: window)
                }
            }
        default:
            break
        }
    }

    private func update() {
        if tracked == nil {
            guard let window = WindowManager.focusedWindow(), let frame = WindowManager.frame(of: window) else { return }
            tracked = (window, frame)
            return
        }
        guard let tracked, let now = WindowManager.frame(of: tracked.window) else { return }
        if !moving {
            // 위치는 바뀌고 크기는 그대로면 창을 옮기는 중이다 (크기 조절이나 창 안에서의 끌기는 제외)
            let moved = abs(now.minX - tracked.start.minX) > 3 || abs(now.minY - tracked.start.minY) > 3
            let sameSize = abs(now.width - tracked.start.width) < 2 && abs(now.height - tracked.start.height) < 2
            guard moved, sameSize else { return }
            moving = true
        }

        let point = Self.mouseLocation()
        guard let screen = WindowManager.screens().first(where: { $0.full.insetBy(dx: -1, dy: -1).contains(point) }),
              let placement = EdgeSnap.placement(at: point, in: screen.full) else {
            target = nil
            hideOverlay()
            return
        }
        let rect = placement.rect(in: screen.visible, current: now)
        target = rect
        showOverlay(at: rect)
    }

    private func reset() {
        tracked = nil
        moving = false
        target = nil
        hideOverlay()
    }

    static var frontAppIgnored: Bool {
        guard let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        return ConfigStore.shared.config.ignoredApps.contains(id)
    }

    /// 마우스 위치 (주 화면 왼쪽 위가 원점인 전역 좌표)
    private static func mouseLocation() -> CGPoint {
        let p = NSEvent.mouseLocation
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: p.x, y: primaryHeight - p.y)
    }

    // MARK: - 놓일 자리 미리 보기

    private func showOverlay(at rect: CGRect) {
        let panel = overlay ?? makeOverlay()
        overlay = panel
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let cocoa = NSRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
        panel.setFrame(cocoa.insetBy(dx: 5, dy: 5), display: true)
        panel.orderFrontRegardless()
    }

    private func hideOverlay() {
        overlay?.orderOut(nil)
    }

    private func makeOverlay() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor
        view.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.9).cgColor
        view.layer?.borderWidth = 2
        view.layer?.cornerRadius = 10
        panel.contentView = view
        return panel
    }
}
