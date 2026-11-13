import AppKit
import RisingKitCore
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let launcher = LauncherController()
    private let mainWindow = MainWindowController()
    /// 시스템이 거부해서 등록하지 못한 단축키
    private var failedHotKeys: [String] = []
    /// 맨 앞 앱이 무시 목록에 있어 창 단축키를 풀어 둔 상태인지
    private var windowKeysSuspended = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = StatusIcon.make()
        WeatherService.shared.onUpdate = { [weak self] in
            self?.statusItem.button?.image = WeatherService.shared.statusImage()
            self?.statusItem.button?.toolTip = WeatherService.shared.summary
            SettingsModel.shared.bump()
        }
        WeatherService.shared.start()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        Commands.toggleLauncher = { [weak self] in self?.launcher.toggle() }
        Commands.toggleMap = { [weak self] in self?.mainWindow.toggle(.map) }
        Commands.openClipboard = { [weak self] in self?.launcher.show(filter: .clipboard) }
        Commands.openUninstaller = { [weak self] in self?.mainWindow.show(.uninstall) }
        ConfigStore.shared.onChange = { [weak self] in
            self?.registerHotKeys()
            SettingsModel.shared.bump()
        }
        registerHotKeys()

        // 무시하는 앱이 앞에 올 때는 창 단축키를 풀어 그 앱이 같은 키를 쓸 수 있게 한다
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, DragSnap.frontAppIgnored != self.windowKeysSuspended else { return }
            self.registerHotKeys()
        }

        SystemStats.shared.start()
        ClipboardMonitor.shared.start()
        AudioRouter.shared.start()
        TidyService.startAutomatic()
        DragSnap.shared.start()
        BalanceLock.shared.startIfEnabled()
        Control.startServer()
    }

    /// 설정이 바뀔 때마다 전역 단축키를 처음부터 다시 등록한다.
    private func registerHotKeys() {
        HotKeyCenter.shared.unregisterAll()
        failedHotKeys = []
        // 설정 창에서 새 단축키를 받는 중에는 풀어 둔 채로 둔다 (끝나면 다시 불린다)
        guard !ShortcutRecorder.shared.isRecording else { return }
        windowKeysSuspended = DragSnap.frontAppIgnored
        for command in Commands.all {
            guard let combo = command.combo else { continue }
            if windowKeysSuspended, command.id.hasPrefix("window.") || command.id.hasPrefix("zone:") { continue }
            if !HotKeyCenter.shared.register(combo, handler: command.run) {
                failedHotKeys.append("\(command.title) (\(combo.display))")
            }
        }
    }

    /// Finder 에서 PDF 를 앱 아이콘에 끌어다 놓거나 "다음으로 열기"로 넘겼을 때.
    func application(_ application: NSApplication, open urls: [URL]) {
        let pdfs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
        if !pdfs.isEmpty { PDFConverter.convertAndReveal(pdfs) }
    }

    // MARK: - 메뉴 (열 때마다 현재 상태로 다시 만든다)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        addWeatherItems(to: menu)
        addUsageItems(to: menu)
        menu.addItem(.separator())

        for command in Commands.app { menu.addItem(commandItem(command)) }
        menu.addItem(.separator())

        let windowMenu = NSMenu()
        for command in Commands.window {
            windowMenu.addItem(commandItem(command))
            if ["window.bottomHalf", "window.bottomRight", "window.rightThird", "window.rightTwoThirds", "window.center"].contains(command.id) {
                windowMenu.addItem(.separator())
            }
        }
        menu.addItem(submenu("창 정렬", windowMenu, "rectangle.split.2x1"))

        let custom = Commands.custom
        if !custom.isEmpty {
            let customMenu = NSMenu()
            custom.forEach { customMenu.addItem(commandItem($0)) }
            menu.addItem(submenu("레이아웃 · 영역", customMenu, "rectangle.3.group.fill"))
        }

        if let front = NSWorkspace.shared.frontmostApplication, let bundleId = front.bundleIdentifier,
           bundleId != Bundle.main.bundleIdentifier {
            let ignore = item("\(front.localizedName ?? bundleId) 에서는 창 단축키 끄기", #selector(toggleIgnoreApp(_:)), "minus.circle")
            ignore.representedObject = bundleId
            ignore.state = ConfigStore.shared.config.ignoredApps.contains(bundleId) ? .on : .off
            menu.addItem(ignore)
        }

        if !WindowManager.hasPermission {
            menu.addItem(item("창 정렬에 손쉬운 사용 권한 필요…", #selector(requestAccessibility), "exclamationmark.triangle"))
        }
        menu.addItem(.separator())

        // 소리 출력 장치 고르기
        let devices = AudioRouter.outputDevices()
        let currentOutput = AudioRouter.defaultOutput()
        let audioMenu = NSMenu()
        for device in devices {
            let entry = item(device.name + (device.isVirtual ? " (가상)" : ""), #selector(selectOutput(_:)))
            entry.representedObject = device.uid
            entry.state = device.id == currentOutput ? .on : .off
            audioMenu.addItem(entry)
        }
        audioMenu.addItem(.separator())
        let pin = item("정해 둔 순서대로 고정", #selector(toggleAudioPin))
        pin.state = AudioRouter.shared.pinEnabled ? .on : .off
        audioMenu.addItem(pin)
        let outputName = devices.first { $0.id == currentOutput }?.name ?? "없음"
        menu.addItem(submenu("소리 출력: \(outputName)", audioMenu, "speaker.wave.2"))

        let toolsMenu = NSMenu()
        Commands.tools.forEach { toolsMenu.addItem(commandItem($0)) }
        menu.addItem(submenu("도구", toolsMenu, "wrench.and.screwdriver"))

        let toggleMenu = NSMenu()
        for toggle in QuickToggle.allCases {
            let entry = item(toggle.title, #selector(flipToggle(_:)), toggle.symbol)
            entry.representedObject = toggle.rawValue
            entry.state = toggle.isOn ? .on : .off
            toggleMenu.addItem(entry)
        }
        menu.addItem(submenu("빠른 토글", toggleMenu, "switch.2"))
        menu.addItem(.separator())

        if !failedHotKeys.isEmpty {
            let sub = NSMenu()
            failedHotKeys.forEach { sub.addItem(disabled($0)) }
            menu.addItem(submenu("등록 못 한 단축키 \(failedHotKeys.count)개", sub, "exclamationmark.triangle"))
        }

        let settingsItem = item("설정…", #selector(openSettings), "gearshape")
        settingsItem.keyEquivalent = ","
        settingsItem.keyEquivalentModifierMask = [.command]
        menu.addItem(settingsItem)

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        menu.addItem(disabled("Rising Kit \(version)", "info.circle"))
        let quit = NSMenuItem(title: "Rising Kit 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.image = symbol("xmark.rectangle")
        menu.addItem(quit)
    }

    private func addWeatherItems(to menu: NSMenu) {
        let weather = WeatherService.shared
        weather.refreshIfStale()

        let report = weather.report
        let symbolName = report.map { $0.kind.sfSymbol(night: $0.isNight) } ?? "cloud"
        let sub = NSMenu()
        if let report {
            var detail = "습도 \(Int(report.humidity.rounded()))% · 바람 \(String(format: "%.1f", report.wind))m/s"
            if let updated = weather.updatedAt {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "ko_KR")
                formatter.dateFormat = "a h:mm"
                detail += " · \(formatter.string(from: updated)) 기준"
            }
            sub.addItem(disabled(detail, "humidity"))
            sub.addItem(.separator())
            for (index, day) in report.days.enumerated() {
                var line = "\(WeatherService.dayLabel(day.date, index: index))  \(day.kind.label)  "
                    + "\(WeatherService.degrees(day.low)) / \(WeatherService.degrees(day.high))"
                if day.precipitation >= 0.1 { line += "  비 \(String(format: "%.1f", day.precipitation))mm" }
                sub.addItem(disabled(line, day.kind.sfSymbol(night: false)))
            }
            sub.addItem(.separator())
        }
        if let error = weather.lastError {
            sub.addItem(disabled("최근 갱신 실패: \(error)", "exclamationmark.triangle"))
        }
        sub.addItem(item("도시 변경…", #selector(changeWeatherCity), "mappin.and.ellipse"))
        sub.addItem(item("지금 새로 고침", #selector(refreshWeather), "arrow.clockwise"))
        menu.addItem(submenu(weather.summary, sub, symbolName))
    }

    /// 메모리·CPU 사용량 (보기 전용). 하위 메뉴에 많이 쓰는 앱을 보여 준다.
    private func addUsageItems(to menu: NSMenu) {
        let stats = SystemStats.shared
        let apps = stats.apps()

        let memoryMenu = NSMenu()
        if let m = stats.memory() {
            memoryMenu.addItem(disabled("메모리 압력 \(m.pressureText) · 스왑 \(ProcessUsage.formatMemory(bytes: m.swapUsed))", "gauge.with.dots.needle.50percent"))
            memoryMenu.addItem(.separator())
        }
        for app in ProcessUsage.topByMemory(apps, 8) {
            memoryMenu.addItem(disabled("\(app.memoryText)   \(app.name)\(app.processes > 1 ? " (\(app.processes))" : "")"))
        }
        menu.addItem(submenu(stats.memorySummary, memoryMenu, "memorychip"))

        let cpuMenu = NSMenu()
        cpuMenu.addItem(disabled("앱별 수치는 코어 하나 기준 (100% = 코어 1개)", "info.circle"))
        cpuMenu.addItem(.separator())
        for app in ProcessUsage.topByCPU(apps, 8) where app.cpu >= 0.5 {
            cpuMenu.addItem(disabled("\(app.cpuText)   \(app.name)\(app.processes > 1 ? " (\(app.processes))" : "")"))
        }
        menu.addItem(submenu(stats.cpuSummary, cpuMenu, "cpu"))
    }

    @objc private func refreshWeather() { WeatherService.shared.refresh() }

    @objc private func changeWeatherCity() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "날씨를 볼 도시"
        alert.informativeText = "도시 이름을 입력하세요. (예: 부산, Tokyo)"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = WeatherService.shared.location.name
        alert.accessoryView = field
        alert.addButton(withTitle: "변경")
        alert.addButton(withTitle: "취소")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let query = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        if case .failure(let error) = WeatherService.shared.setCity(query) {
            let failed = NSAlert()
            failed.alertStyle = .warning
            failed.messageText = "도시를 바꾸지 못했습니다"
            failed.informativeText = error.message
            failed.runModal()
        }
    }

    private func balanceStatus() -> String {
        guard let balance = BalanceLock.shared.currentBalance() else {
            return "현재 출력 장치는 균형 조절을 지원하지 않음"
        }
        let offset = Int(((balance - 0.5) * 200).rounded())
        if offset == 0 { return "현재 균형: 가운데" }
        return "현재 균형: \(offset < 0 ? "왼쪽" : "오른쪽") \(abs(offset))%"
    }

    /// 메뉴 항목마다 아이콘을 넣어야 글자 시작 위치가 한 줄로 맞는다
    /// (아이콘이 있는 항목과 없는 항목이 섞이면 들여쓰기가 달라진다).
    private func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }

    private func item(_ title: String, _ action: Selector, _ symbolName: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = symbolName.flatMap(symbol)
        return item
    }

    private func disabled(_ title: String, _ symbolName: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.image = symbolName.flatMap(symbol)
        return item
    }

    private func submenu(_ title: String, _ menu: NSMenu, _ symbolName: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        item.image = symbol(symbolName)
        return item
    }

    private func commandItem(_ command: Command) -> NSMenuItem {
        let entry = item(command.title, #selector(runCommand(_:)))
        entry.representedObject = command.id
        entry.image = symbol(command.symbol)
        if let combo = command.combo {
            entry.keyEquivalent = combo.menuKey
            entry.keyEquivalentModifierMask = combo.modifierFlags
        }
        return entry
    }

    // MARK: - 동작

    @objc private func openSettings() { mainWindow.show(.window) }

    @objc private func runCommand(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        Commands.all.first { $0.id == id }?.run()
    }

    @objc private func selectOutput(_ sender: NSMenuItem) {
        guard let uid = sender.representedObject as? String,
              let device = AudioRouter.outputDevices().first(where: { $0.uid == uid }) else { return }
        AudioRouter.shared.select(device)
    }

    @objc private func toggleAudioPin() { AudioRouter.shared.setPin(!AudioRouter.shared.pinEnabled) }

    @objc private func flipToggle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        QuickToggle(rawValue: raw)?.toggle()
    }

    @objc private func toggleDragSnap() {
        ConfigStore.shared.update { $0.dragSnap.toggle() }
    }

    @objc private func toggleIgnoreApp(_ sender: NSMenuItem) {
        guard let bundleId = sender.representedObject as? String else { return }
        ConfigStore.shared.update { config in
            if let index = config.ignoredApps.firstIndex(of: bundleId) {
                config.ignoredApps.remove(at: index)
            } else {
                config.ignoredApps.append(bundleId)
            }
        }
    }

    @objc private func requestAccessibility() { _ = WindowManager.ensurePermission() }

    @objc private func convertPDF() { PDFConverter.pickAndConvert() }

    @objc private func setDPI(_ sender: NSMenuItem) { PDFConverter.dpi = sender.tag }

    @objc private func toggleBalanceLock() { BalanceLock.shared.enabled.toggle() }

    @objc private func revealConfig() {
        // 아직 저장한 적이 없으면 기본 내용으로 파일을 만든 뒤 보여준다
        if !FileManager.default.fileExists(atPath: ConfigStore.fileURL.path) {
            ConfigStore.shared.update { _ in }
        }
        NSWorkspace.shared.activateFileViewerSelecting([ConfigStore.fileURL])
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "로그인 항목을 바꾸지 못했습니다"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}
