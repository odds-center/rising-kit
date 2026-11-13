import AppKit
import ApplicationServices
import RisingKitCore

/// 손쉬운 사용(AX) API 로 다른 앱의 창을 옮기고 크기를 바꾼다.
/// 좌표는 모두 주 화면 왼쪽 위가 원점인 전역 좌표(AX·CoreGraphics 와 같은 방향)다.
enum WindowManager {
    struct ScreenInfo {
        /// 왼쪽에서 오른쪽(같으면 위에서 아래) 순서의 번호
        let index: Int
        let name: String
        let full: CGRect
        /// 메뉴바와 Dock 을 뺀 영역
        let visible: CGRect
    }

    /// 화면에 보이는 창 하나 (배치도·레이아웃 저장용)
    struct WindowSnapshot: Identifiable {
        let id: CGWindowID
        let pid: pid_t
        let app: String
        let bundleId: String
        let title: String
        let frame: CGRect
        let display: Int
    }

    struct ControlError: Error {
        let message: String
    }

    static let permissionMessage =
        "Rising Kit needs Accessibility permission (System Settings > Privacy & Security > Accessibility)."

    /// 정렬 전 원래 위치 (되돌리기용). 창이 닫히면 다음 정리 때 빠진다.
    private static var savedFrames: [(window: AXUIElement, frame: CGRect)] = []

    static var hasPermission: Bool { AXIsProcessTrusted() }

    /// 권한이 없으면 시스템 안내 창을 띄우고 false.
    static func ensurePermission() -> Bool {
        if AXIsProcessTrusted() { return true }
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        return false
    }

    // MARK: - 맨 앞 창 (단축키·메뉴·런처)

    static func apply(_ placement: Placement) {
        guard ensurePermission(), let window = focusedWindow(), let current = frame(of: window),
              let screen = screen(containing: current) else { NSSound.beep(); return }
        remember(window, frame: current)
        // 이미 그 절반에 있으면 그쪽 옆 화면의 반대쪽 절반으로 넘긴다 (Magnet 과 같게)
        let all = screens()
        if let hop = DisplayHop.next(placement, window: current, from: screen.index,
                                     screens: all.map(\.full), visible: all.map(\.visible)) {
            setFrame(hop.placement.rect(in: all[hop.screen].visible, current: current), of: window)
            return
        }
        setFrame(placement.rect(in: screen.visible, current: current), of: window)
    }

    static func apply(_ zone: Zone) {
        guard ensurePermission(), let window = focusedWindow(), let current = frame(of: window),
              let screen = zone.display.flatMap({ self.screen(at: $0) }) ?? screen(containing: current)
        else { NSSound.beep(); return }
        remember(window, frame: current)
        setFrame(zone.rect.absolute(in: screen.visible), of: window)
    }

    /// offset +1 은 오른쪽(다음) 디스플레이, -1 은 왼쪽(이전) 디스플레이.
    static func moveToDisplay(offset: Int) {
        let all = screens()
        guard ensurePermission(), let window = focusedWindow(), let current = frame(of: window),
              all.count > 1, let from = screen(containing: current) else { NSSound.beep(); return }
        let to = all[((from.index + offset) % all.count + all.count) % all.count]
        let target = DisplayMove.remap(current, from: from.visible, to: to.visible)
        remember(window, frame: current)
        setFrame(target, of: window)
    }

    static func restore() {
        guard ensurePermission(), let window = focusedWindow(),
              let index = savedFrames.firstIndex(where: { CFEqual($0.window, window) }) else {
            NSSound.beep(); return
        }
        setFrame(savedFrames[index].frame, of: window)
        savedFrames.remove(at: index)
    }

    // MARK: - 화면

    static func screens() -> [ScreenInfo] {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return [] }
        func flip(_ r: CGRect) -> CGRect {
            CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
        }
        return NSScreen.screens
            .map { (name: $0.localizedName, full: flip($0.frame), visible: flip($0.visibleFrame)) }
            .sorted { $0.full.minX != $1.full.minX ? $0.full.minX < $1.full.minX : $0.full.minY < $1.full.minY }
            .enumerated()
            .map { ScreenInfo(index: $0.offset, name: $0.element.name, full: $0.element.full, visible: $0.element.visible) }
    }

    /// 번호에 해당하는 화면. 모니터가 빠져서 번호가 없으면 마지막 화면.
    static func screen(at index: Int) -> ScreenInfo? {
        let all = screens()
        return all.indices.contains(index) ? all[index] : all.last
    }

    /// 사각형과 가장 많이 겹치는 화면.
    static func screen(containing rect: CGRect) -> ScreenInfo? {
        let all = screens()
        func area(_ s: ScreenInfo) -> CGFloat {
            let i = s.full.intersection(rect)
            return i.isNull ? 0 : i.width * i.height
        }
        return all.max(by: { area($0) < area($1) }) ?? all.first
    }

    // MARK: - 창 목록

    /// 지금 화면에 보이는 일반 앱 창들, 앞에 있는 창부터.
    /// 위치는 권한 없이도 알 수 있고, 제목은 손쉬운 사용 권한이 있을 때만 채워진다.
    static func snapshot() -> [WindowSnapshot] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var axCache: [pid_t: [(title: String, frame: CGRect)]] = [:]
        var out: [WindowSnapshot] = []

        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let number = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.width >= 100, bounds.height >= 60,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular
            else { continue }

            if axCache[pid] == nil {
                axCache[pid] = hasPermission
                    ? windows(of: axApplication(app)).compactMap { w in
                        frame(of: w).map { (string(w, kAXTitleAttribute) ?? "", $0) }
                    }
                    : []
            }
            let title = axCache[pid]?.first(where: { near($0.frame, bounds) })?.title ?? ""
            out.append(WindowSnapshot(
                id: number, pid: pid, app: app.localizedName ?? "", bundleId: app.bundleIdentifier ?? "",
                title: title, frame: bounds, display: screen(containing: bounds)?.index ?? 0))
        }
        return out
    }

    /// 배치도에서 고른 창을 옮긴다. 옮겼으면 true.
    @discardableResult
    static func move(_ snapshot: WindowSnapshot, to rect: CGRect) -> Bool {
        guard ensurePermission(), let app = NSRunningApplication(processIdentifier: snapshot.pid),
              let window = windows(of: axApplication(app)).first(where: {
                  frame(of: $0).map { near($0, snapshot.frame) } == true
              }) else { return false }
        remember(window, frame: snapshot.frame)
        setFrame(rect, of: window)
        return true
    }

    private static func near(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 2 && abs(a.minY - b.minY) <= 2
            && abs(a.width - b.width) <= 2 && abs(a.height - b.height) <= 2
    }

    // MARK: - 레이아웃 적용

    /// 레이아웃의 각 항목을 실행 중인 앱의 창에 적용한다.
    /// 반환: 옮긴 창 수, 실행 중이 아니거나 창이 없어 건너뛴 앱 이름.
    static func apply(_ layout: Layout) -> (moved: Int, skipped: [String]) {
        guard ensurePermission() else { return (0, layout.items.map(\.app)) }
        var moved = 0
        var skipped: [String] = []
        var used: [AXUIElement] = []
        var cache: [String: [AXUIElement]] = [:]

        for item in layout.items {
            let running = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == item.bundleId }
            if cache[item.bundleId] == nil {
                cache[item.bundleId] = running.map { app in
                    windows(of: axApplication(app)).filter { isStandard($0) && !isMinimized($0) && frame(of: $0) != nil }
                } ?? []
            }
            let free = (cache[item.bundleId] ?? []).filter { w in !used.contains { CFEqual($0, w) } }
            // 제목이 같은 창을 먼저, 없으면 남은 창 중 첫 번째
            let match = free.first { !item.title.isEmpty && string($0, kAXTitleAttribute) == item.title } ?? free.first
            guard let window = match, let current = frame(of: window), let screen = screen(at: item.display) else {
                if !skipped.contains(item.app) { skipped.append(item.app) }
                continue
            }
            used.append(window)
            remember(window, frame: current)
            setFrame(item.rect.absolute(in: screen.visible), of: window)
            if layout.activate == true {
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                running?.activate()
            }
            moved += 1
        }
        return (moved, skipped)
    }

    // MARK: - 외부 제어 (MCP)

    /// 일반 앱들의 모든 창 (최소화된 창 포함).
    static func describeWindows() -> [[String: Any]] {
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        var out: [[String: Any]] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let axApp = axApplication(app)
            let focused = element(axApp, kAXFocusedWindowAttribute)
            for window in windows(of: axApp) where isStandard(window) {
                guard let frame = frame(of: window) else { continue }
                out.append([
                    "app": app.localizedName ?? "",
                    "bundleId": app.bundleIdentifier ?? "",
                    "title": string(window, kAXTitleAttribute) ?? "",
                    "frame": dict(frame),
                    "display": screen(containing: frame)?.index ?? 0,
                    "minimized": isMinimized(window),
                    "focused": app.processIdentifier == front && focused.map { CFEqual($0, window) } == true,
                ])
            }
        }
        return out
    }

    static func describeScreens() -> [[String: Any]] {
        screens().map {
            ["index": $0.index, "name": $0.name, "frame": dict($0.full), "visibleFrame": dict($0.visible)]
        }
    }

    /// 특정 앱의 창(없으면 맨 앞 창)을 배치한다. 적용 후 실제 창 위치를 돌려준다.
    static func place(
        appName: String?, titleContains: String?, placement: Placement?, frame target: CGRect?,
        display: Int?, activate: Bool
    ) -> Result<[String: Any], ControlError> {
        guard ensurePermission() else { return .failure(ControlError(message: permissionMessage)) }
        let app: NSRunningApplication
        if let appName, !appName.isEmpty {
            let needle = appName.lowercased()
            let regular = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
            guard let found = regular.first(where: {
                $0.localizedName?.lowercased() == needle || $0.bundleIdentifier?.lowercased() == needle
            }) ?? regular.first(where: { $0.localizedName?.lowercased().contains(needle) == true }) else {
                return .failure(ControlError(message: "No running app matches \"\(appName)\"."))
            }
            app = found
        } else {
            guard let front = NSWorkspace.shared.frontmostApplication else {
                return .failure(ControlError(message: "No frontmost app."))
            }
            app = front
        }

        let axApp = axApplication(app)
        let all = windows(of: axApp)
        let window: AXUIElement?
        if let titleContains, !titleContains.isEmpty {
            window = all.first { string($0, kAXTitleAttribute)?.localizedCaseInsensitiveContains(titleContains) == true }
        } else {
            window = frontWindow(of: axApp) ?? all.first
        }
        guard let window, let current = self.frame(of: window) else {
            return .failure(ControlError(message: "No matching window in \(app.localizedName ?? "app")."))
        }
        if let display, !screens().indices.contains(display) {
            return .failure(ControlError(message: "No display \(display). There are \(screens().count) display(s), numbered from 0."))
        }

        let destination: CGRect
        if let target {
            destination = target
        } else if let placement, let screen = display.flatMap({ self.screen(at: $0) }) ?? screen(containing: current) {
            destination = placement.rect(in: screen.visible, current: current)
        } else if let display, let to = screen(at: display), let from = screen(containing: current) {
            destination = DisplayMove.remap(current, from: from.visible, to: to.visible)
        } else {
            return .failure(ControlError(message: "Give a placement, a display, or x/y/width/height."))
        }
        remember(window, frame: current)
        setFrame(destination, of: window)
        if activate {
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            app.activate()
        }
        let actual = self.frame(of: window) ?? destination
        return .success([
            "app": app.localizedName ?? "",
            "title": string(window, kAXTitleAttribute) ?? "",
            "requested": dict(destination),
            // 앱이 최소 크기 등으로 요청을 그대로 받아들이지 않을 수 있다
            "frame": dict(actual),
            "display": screen(containing: actual)?.index ?? 0,
        ])
    }

    private static func dict(_ r: CGRect) -> [String: Int] {
        ["x": Int(r.minX), "y": Int(r.minY), "width": Int(r.width), "height": Int(r.height)]
    }

    // MARK: - AX

    private static func axApplication(_ app: NSRunningApplication) -> AXUIElement {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        // 응답 없는 앱 하나 때문에 전체가 멈추지 않게 한다
        AXUIElementSetMessagingTimeout(axApp, 0.5)
        return axApp
    }

    private static func element(_ parent: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func windows(of axApp: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    /// 일반 창 또는 대화상자인지 (Finder 바탕화면, 숨은 보조 창 등은 제외).
    private static func isStandard(_ window: AXUIElement) -> Bool {
        let subrole = string(window, kAXSubroleAttribute)
        return subrole == (kAXStandardWindowSubrole as String) || subrole == (kAXDialogSubrole as String)
    }

    private static func isMinimized(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &value)
        return (value as? Bool) ?? false
    }

    static func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return frontWindow(of: axApplication(app))
    }

    /// 앱의 맨 앞 일반 창. Finder 는 창을 눌러 놓아도 "포커스된 창"으로 바탕화면(모든 모니터를 덮는
    /// 보이지 않는 창)을 돌려줄 때가 있어, 일반 창이 아니면 주 창 · 첫 일반 창으로 넘어간다.
    private static func frontWindow(of axApp: AXUIElement) -> AXUIElement? {
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            if let window = element(axApp, attribute), isStandard(window) { return window }
        }
        return windows(of: axApp).first { isStandard($0) && !isMinimized($0) }
            ?? element(axApp, kAXFocusedWindowAttribute)
    }

    static func frame(of window: AXUIElement) -> CGRect? {
        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let posValue, let sizeValue else { return nil }
        var pos = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posValue as! AXValue, .cgPoint, &pos),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: pos, size: size)
    }

    static func setFrame(_ rect: CGRect, of window: AXUIElement) {
        var pos = rect.origin
        var size = rect.size
        guard let posValue = AXValueCreate(.cgPoint, &pos),
              let sizeValue = AXValueCreate(.cgSize, &size) else { return }

        // 다른 접근성 도구가 앱에 AXEnhancedUserInterface 를 켜 두면 연달아 보낸 위치·크기 변경 중
        // 일부가 무시된다 (위치만 바뀌고 크기는 그대로 남는 식). 옮기는 동안만 끄고 되돌린다.
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        let axApp = AXUIElementCreateApplication(pid)
        let enhancedKey = "AXEnhancedUserInterface" as CFString
        var enhancedValue: CFTypeRef?
        AXUIElementCopyAttributeValue(axApp, enhancedKey, &enhancedValue)
        let enhanced = (enhancedValue as? Bool) ?? false
        if enhanced { AXUIElementSetAttributeValue(axApp, enhancedKey, kCFBooleanFalse) }
        defer { if enhanced { AXUIElementSetAttributeValue(axApp, enhancedKey, kCFBooleanTrue) } }

        // 크기 → 위치 → 크기: 처음 크기 변경은 지금 화면에 맞게 잘릴 수 있으므로,
        // 새 위치(다른 디스플레이일 수 있음)로 옮긴 뒤 한 번 더 맞춘다.
        // 요청을 늦게 처리하는 앱(Electron 등)은 한 번에 안 맞을 수 있어, 어긋나 있으면 잠깐 뒤 다시 보낸다.
        for attempt in 0..<3 {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
            if let now = frame(of: window), near(now, rect) { break }
            if attempt < 2 { usleep(70_000) }
        }
    }

    static func remember(_ window: AXUIElement, frame: CGRect) {
        // 이미 닫힌 창은 정리
        savedFrames.removeAll { self.frame(of: $0.window) == nil }
        if !savedFrames.contains(where: { CFEqual($0.window, window) }) {
            savedFrames.append((window, frame))
        }
    }
}

