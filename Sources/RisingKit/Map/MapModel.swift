import AppKit
import RisingKitCore

/// 디스플레이 배치도의 상태: 화면들, 그 위의 창들, 선택과 끌기.
final class MapModel: ObservableObject {
    @Published private(set) var screens: [WindowManager.ScreenInfo] = []
    /// 앞에 있는 창부터
    @Published private(set) var windows: [WindowManager.WindowSnapshot] = []
    @Published var selectedID: CGWindowID?
    @Published private(set) var layouts: [Layout] = []
    @Published private(set) var hasPermission = true
    @Published var message = ""

    /// 가장자리에 놓으면 절반·1/4 로 붙일지. 끄면 어디에 놓든 놓은 자리 그대로.
    @Published var snapsToEdges = true
    /// 배치도 위에 직접 그린 영역 (전역 좌표)과 그 디스플레이
    @Published var drawn: (display: Int, rect: CGRect)?

    /// 끌고 있는 창과, 놓으면 적용될 위치 (전역 좌표)
    @Published var dragging: (id: CGWindowID, translation: CGSize, preview: CGRect?)?

    private var icons: [pid_t: NSImage] = [:]

    var selected: WindowManager.WindowSnapshot? {
        windows.first { $0.id == selectedID }
    }

    /// 모든 화면을 감싸는 영역
    var bounds: CGRect {
        screens.reduce(CGRect.null) { $0.union($1.full) }
    }

    /// 창이 놓인 디스플레이의 사용 가능한 영역
    func visibleFrame(of window: WindowManager.WindowSnapshot) -> CGRect {
        screens.indices.contains(window.display) ? screens[window.display].visible : window.frame
    }

    func refresh() {
        screens = WindowManager.screens()
        windows = WindowManager.snapshot()
        layouts = ConfigStore.shared.config.layouts
        hasPermission = WindowManager.hasPermission
        if selected == nil { selectedID = windows.first?.id }
    }

    func icon(for pid: pid_t) -> NSImage? {
        if let cached = icons[pid] { return cached }
        let image = NSRunningApplication(processIdentifier: pid)?.icon
        icons[pid] = image
        return image
    }

    func selectNext(_ delta: Int) {
        guard !windows.isEmpty else { return }
        let current = windows.firstIndex { $0.id == selectedID } ?? -1
        selectedID = windows[(current + delta + windows.count) % windows.count].id
    }

    // MARK: - 배치

    func place(_ placement: Placement) {
        guard let window = selected, screens.indices.contains(window.display) else { return }
        move(window, to: placement.rect(in: screens[window.display].visible, current: window.frame))
    }

    /// 선택한 창을 n번 디스플레이로 (크기 비율 유지)
    func sendToDisplay(_ index: Int) {
        guard let window = selected, screens.indices.contains(index), screens.indices.contains(window.display),
              index != window.display else { return }
        move(window, to: DisplayMove.remap(
            window.frame, from: screens[window.display].visible, to: screens[index].visible))
    }

    /// 창을 끌어다 놓았을 때 갈 자리.
    /// 놓은 지점이 디스플레이 가장자리에 가까우면 절반·1/4·최대화·1/3 로 붙이고,
    /// 그 밖에는 놓은 자리 그대로 둔다. `point` 는 놓은 지점, `translation` 은 끈 거리 (둘 다 전역 좌표).
    func dropTarget(for window: WindowManager.WindowSnapshot, at point: CGPoint, translation: CGSize) -> CGRect? {
        if snapsToEdges, let screen = screens.first(where: { $0.full.contains(point) }),
           let placement = DropZone.edgePlacement(
               atUnitX: Double((point.x - screen.full.minX) / screen.full.width),
               y: Double((point.y - screen.full.minY) / screen.full.height)) {
            return placement.rect(in: screen.visible, current: window.frame)
        }
        return freeTarget(for: window, translation: translation)
    }

    // MARK: - 자유 배치

    /// 창을 `translation`(전역 좌표 기준)만큼 옮긴 자리. 옮겨 간 곳의 디스플레이 안으로 맞춘다.
    func freeTarget(for window: WindowManager.WindowSnapshot, translation: CGSize) -> CGRect? {
        let moved = window.frame.offsetBy(dx: translation.width, dy: translation.height)
        let center = CGPoint(x: moved.midX, y: moved.midY)
        guard let screen = screens.first(where: { $0.full.contains(center) })
            ?? screens.min(by: { distance(center, $0.full) < distance(center, $1.full) }) else { return nil }
        return FreePlacement.fit(moved, in: screen.visible)
    }

    /// 오른쪽 아래 모서리를 끌어 크기를 바꾼 자리.
    func resizeTarget(for window: WindowManager.WindowSnapshot, translation: CGSize) -> CGRect {
        FreePlacement.resized(window.frame, by: translation, in: visibleFrame(of: window))
    }

    /// 빈 곳을 끌어 그린 영역. 끌기 시작한 디스플레이 안으로 맞춘다.
    func draw(from start: CGPoint, to end: CGPoint) {
        guard let screen = screens.first(where: { $0.full.contains(start) }) else { return }
        let rect = FreePlacement.fit(FreePlacement.rect(from: start, to: end), in: screen.visible,
                                     minSize: CGSize(width: 1, height: 1))
        drawn = (screen.index, rect)
    }

    /// 그려 둔 영역이 너무 작으면(그냥 누른 것) 지운다.
    func finishDrawing() {
        if let drawn, drawn.rect.width < 150 || drawn.rect.height < 100 { self.drawn = nil }
    }

    func moveSelectedIntoDrawn() {
        guard let window = selected, let drawn else { return }
        move(window, to: drawn.rect)
    }

    private func distance(_ point: CGPoint, _ rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }

    func move(_ window: WindowManager.WindowSnapshot, to rect: CGRect) {
        let id = window.id
        guard WindowManager.move(window, to: rect) else {
            hasPermission = WindowManager.hasPermission
            message = hasPermission ? "\(window.app) 창을 옮기지 못했습니다" : ""
            NSSound.beep()
            return
        }
        message = ""
        // 창이 실제로 옮겨진 뒤의 위치로 다시 그린다
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.refresh()
            self?.selectedID = id
        }
    }

    // MARK: - 레이아웃

    func saveLayout(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let layout = Layouts.capture(name: trimmed)
        guard !layout.items.isEmpty else { message = "저장할 창이 없습니다"; return }
        Layouts.save(layout)
        layouts = ConfigStore.shared.config.layouts
        message = "'\(trimmed)' 저장됨 (창 \(layout.items.count)개)"
    }

    func applyLayout(_ layout: Layout) {
        let result = Layouts.apply(layout)
        message = result.skipped.isEmpty
            ? "'\(layout.name)' 적용 (창 \(result.moved)개)"
            : "'\(layout.name)' 적용 (창 \(result.moved)개, 건너뜀: \(result.skipped.joined(separator: ", ")))"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.refresh() }
    }

    func deleteLayout(_ layout: Layout) {
        Layouts.delete(name: layout.name)
        layouts = ConfigStore.shared.config.layouts
        message = "'\(layout.name)' 삭제됨"
    }

    // MARK: - 창 하나를 지금 위치로 보내는 단축키

    func beginRecording() {
        guard selected != nil else { return }
        message = ""
        ShortcutRecorder.shared.begin(id: "map.rule") { [weak self] combo in
            guard let self else { return nil }
            return self.saveRule(combo)
        }
    }

    /// 고른 창을 지금 위치로 보내는 단축키를 저장한다. 저장하지 못하면 이유를 돌려준다.
    private func saveRule(_ combo: KeyCombo?) -> String? {
        guard let combo else { return "단축키 없이는 저장할 수 없습니다 · esc 취소" }
        guard let window = selected, screens.indices.contains(window.display), !window.bundleId.isEmpty else {
            return "창을 먼저 고르세요 · esc 취소"
        }
        if let other = Commands.conflict(for: combo, excluding: "") {
            return "\(combo.display) 는 이미 '\(other.title)' 에 쓰이고 있습니다. 다른 조합을 누르세요."
        }
        let visible = screens[window.display].visible
        let rect = FractionRect(window.frame, in: visible)
        let name = "\(window.app) → \(window.display + 1)번 \(Self.placementName(for: window.frame, in: visible))"
        let layout = Layout(
            name: name,
            items: [Layout.Item(bundleId: window.bundleId, app: window.app, title: window.title,
                                display: window.display, rect: rect)],
            activate: true)
        ConfigStore.shared.update { config in
            config.layouts.removeAll { $0.name == name }
            config.layouts.append(layout)
            config.shortcuts["layout:" + name] = combo.string
        }
        layouts = ConfigStore.shared.config.layouts
        message = "\(combo.display) → \(name)"
        return nil
    }

    // MARK: - 어떤 창이든 그 자리로 보내는 단축키 (영역)

    /// 고른 창이 지금 있는 자리를 영역으로 저장한다.
    func beginZoneRecordingForSelected() {
        guard let window = selected, screens.indices.contains(window.display) else { return }
        beginZoneRecording(display: window.display, rect: window.frame)
    }

    /// 그려 둔 영역을 저장한다.
    func beginZoneRecordingForDrawn() {
        guard let drawn else { return }
        beginZoneRecording(display: drawn.display, rect: drawn.rect)
    }

    private func beginZoneRecording(display: Int, rect: CGRect) {
        message = ""
        ShortcutRecorder.shared.begin(id: "map.zone") { [weak self] combo in
            guard let self else { return nil }
            guard let combo else { return "단축키 없이는 저장할 수 없습니다 · esc 취소" }
            guard self.screens.indices.contains(display) else { return "디스플레이를 찾을 수 없습니다 · esc 취소" }
            if let other = Commands.conflict(for: combo, excluding: "") {
                return "\(combo.display) 는 이미 '\(other.title)' 에 쓰이고 있습니다. 다른 조합을 누르세요."
            }
            let visible = self.screens[display].visible
            let fraction = FractionRect(rect, in: visible)
            var place = Self.placementName(for: rect, in: visible)
            if place == "사용자 위치" {
                place = String(format: "영역 %.0f%%×%.0f%% (왼쪽 %.0f%%, 위 %.0f%%)",
                               fraction.width * 100, fraction.height * 100, fraction.x * 100, fraction.y * 100)
            }
            let name = "\(display + 1)번 \(place)"
            ConfigStore.shared.update { config in
                config.zones.removeAll { $0.name == name }
                config.zones.append(Zone(name: name, display: display, rect: fraction))
                config.shortcuts["zone:" + name] = combo.string
            }
            self.message = "\(combo.display) → 맨 앞 창을 \(name) 로"
            return nil
        }
    }

    func reloadLayouts() {
        layouts = ConfigStore.shared.config.layouts
    }

    /// 창 위치가 프리셋(왼쪽 절반, 오른쪽 위 …)과 같으면 그 이름, 아니면 "사용자 위치".
    static func placementName(for frame: CGRect, in visible: CGRect) -> String {
        for placement in Placement.allCases where placement != .center {
            let target = placement.rect(in: visible, current: frame)
            if abs(target.minX - frame.minX) <= 12, abs(target.minY - frame.minY) <= 12,
               abs(target.width - frame.width) <= 12, abs(target.height - frame.height) <= 12,
               let title = Commands.window.first(where: { $0.id == "window." + placement.rawValue })?.title {
                return title.hasPrefix("창 ") ? String(title.dropFirst(2)) : title
            }
        }
        return "사용자 위치"
    }

    func shortcutDisplay(for layout: Layout) -> String? {
        Commands.custom.first { $0.id == "layout:" + layout.name }?.combo?.display
    }
}
