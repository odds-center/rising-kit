import AppKit
import RisingKitCore

/// 실행 중인 앱과 `--mcp` 프로세스 사이의 요청/응답 통로 (Mach 메시지 포트).
/// 창 제어는 손쉬운 사용 권한을 가진 앱 본체가 해야 하므로, MCP 프로세스는 요청만 넘긴다.
enum Control {
    static let portName = "com.oddscenter.risingkit.control" as CFString
    private static var port: CFMessagePort?

    // MARK: - 앱 쪽 (서버)

    /// 파일·git·프로세스 목록을 읽는 느린 도구. 요청을 받는 스레드에서 바로 처리해서,
    /// 폴더 접근 권한 창이 떠 있거나 저장소가 많아도 앱(메뉴·단축키)이 멈추지 않게 한다.
    private static let backgroundTools: Set<String> = ["scrum_draft", "tidy_files", "system_usage", "pdf_to_png"]

    static func startServer() {
        // 요청은 전용 스레드의 실행 루프에서 받는다
        let thread = Thread {
            let callback: CFMessagePortCallBack = { _, _, data, _ in
                var response: [String: Any] = ["error": "Malformed request."]
                if let data = data as Data?,
                   let request = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                    if Control.backgroundTools.contains(request["tool"] as? String ?? "") {
                        response = Control.handle(request)
                    } else {
                        // 창 제어와 화면에 관련된 것은 주 스레드에서
                        response = DispatchQueue.main.sync { Control.handle(request) }
                    }
                }
                guard let out = try? JSONSerialization.data(withJSONObject: response) else { return nil }
                return Unmanaged.passRetained(out as CFData)
            }
            var context = CFMessagePortContext()
            guard let port = CFMessagePortCreateLocal(nil, portName, callback, &context, nil),
                  let source = CFMessagePortCreateRunLoopSource(nil, port, 0) else {
                NSLog("RisingKit: 제어 포트를 열지 못했습니다 (이미 실행 중인 Rising Kit 이 있을 수 있음)")
                return
            }
            Control.port = port
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
            CFRunLoopRun()
        }
        thread.name = "RisingKit.Control"
        thread.start()
    }

    /// 요청 하나를 처리한다. 성공하면 `result`, 실패하면 `error` 키를 담아 돌려준다.
    static func handle(_ request: [String: Any]) -> [String: Any] {
        let args = request["arguments"] as? [String: Any] ?? [:]
        switch request["tool"] as? String {
        case "list_windows":
            guard WindowManager.ensurePermission() else {
                return ["error": "Rising Kit needs Accessibility permission (System Settings > Privacy & Security > Accessibility)."]
            }
            return ["result": ["windows": WindowManager.describeWindows(), "displays": WindowManager.describeScreens()]]

        case "place_window":
            var placement: Placement?
            if let name = args["placement"] as? String {
                guard let parsed = Placement(rawValue: name) else {
                    return ["error": "Unknown placement \"\(name)\". Use one of: \(Placement.allCases.map(\.rawValue).joined(separator: ", "))."]
                }
                placement = parsed
            }
            var frame: CGRect?
            if let x = number(args["x"]), let y = number(args["y"]),
               let w = number(args["width"]), let h = number(args["height"]) {
                guard w > 0, h > 0 else { return ["error": "width and height must be positive."] }
                frame = CGRect(x: x, y: y, width: w, height: h)
            }
            switch WindowManager.place(
                appName: args["app"] as? String, titleContains: args["title"] as? String,
                placement: placement, frame: frame, display: number(args["display"]).map { Int($0) },
                activate: args["activate"] as? Bool ?? false) {
            case .success(let info): return ["result": info]
            case .failure(let error): return ["error": error.message]
            }

        case "audio_balance":
            let lock = BalanceLock.shared
            switch args["action"] as? String ?? "status" {
            case "status": break
            case "center": lock.centerIfNeeded()
            case "lock": lock.enabled = true
            case "unlock": lock.enabled = false
            default: return ["error": "action must be status, center, lock, or unlock."]
            }
            var result: [String: Any] = ["lockEnabled": lock.enabled]
            if let balance = lock.currentBalance() {
                result["balance"] = Double(balance)  // 0.0 왼쪽, 0.5 가운데, 1.0 오른쪽
            } else {
                result["note"] = "The current output device has no adjustable balance."
            }
            return ["result": result]

        case "pdf_to_png":
            guard let paths = args["paths"] as? [String], !paths.isEmpty else {
                return ["error": "paths must be a non-empty array of PDF file paths."]
            }
            let dpi = number(args["dpi"]).map { Int($0) } ?? PDFConverter.dpi
            guard (18...1200).contains(dpi) else { return ["error": "dpi must be between 18 and 1200."] }
            let urls = paths.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            let converted = PDFConverter.convert(urls, dpi: dpi)
            return ["result": ["written": converted.written.map(\.path), "failed": converted.failed, "dpi": dpi]]

        case "scrum_draft":
            // repositories 를 주면 그 저장소들만, 없으면 설정에서 고른 것
            let only = (args["repositories"] as? [String]).map(Set.init)
            let draft = ScrumService.draft(only: only)
            let all = ScrumService.repositories()
            let chosen = only ?? ScrumService.selectedKeys(among: all)
            return ["result": ["text": draft.text, "commits": draft.commits, "repositories": draft.repositories,
                               "included": all.map(\.key).filter(chosen.contains),
                               "available": all.map(\.key)]]

        case "tidy_files":
            func rows(_ items: [TidyService.Planned]) -> [[String: String]] {
                items.prefix(200).map { ["from": $0.from.path, "to": $0.to.path] }
            }
            switch args["action"] as? String ?? "preview" {
            case "preview":
                let plan = TidyService.plan()
                return ["result": ["screenshots": rows(plan.screenshots), "downloads": rows(plan.downloads),
                                   "count": plan.count]]
            case "run":
                let result = TidyService.run()
                return ["result": ["movedScreenshots": result.screenshots, "movedDownloads": result.downloads]]
            case "undo":
                return ["result": ["restored": TidyService.undo()]]
            default:
                return ["error": "action must be preview, run, or undo."]
            }

        case "system_usage":
            let stats = SystemStats.shared
            let apps = stats.apps()
            func rows(_ list: [AppUsage]) -> [[String: Any]] {
                list.map { ["app": $0.name, "memoryMB": $0.memoryKB / 1024, "cpuPercent": ($0.cpu * 10).rounded() / 10,
                            "processes": $0.processes] }
            }
            var result: [String: Any] = [
                "topByMemory": rows(ProcessUsage.topByMemory(apps, 10)),
                "topByCPU": rows(ProcessUsage.topByCPU(apps, 10)),
            ]
            if let m = stats.memory() {
                result["memory"] = ["usedMB": Int(m.used / 1_048_576), "totalMB": Int(m.total / 1_048_576),
                                    "swapUsedMB": Int(m.swapUsed / 1_048_576), "pressure": m.pressureText]
            }
            if let cpu = stats.cpuPercent { result["cpuPercent"] = (cpu * 10).rounded() / 10 }
            return ["result": result]

        case "weather":
            let service = WeatherService.shared
            if let city = (args["city"] as? String)?.trimmingCharacters(in: .whitespaces), !city.isEmpty {
                if case .failure(let error) = service.setCity(city) { return ["error": error.message] }
            } else {
                service.refreshNow()
            }
            guard let report = service.report else {
                return ["error": "Could not load the weather: \(service.lastError ?? "unknown error")."]
            }
            var result: [String: Any] = [
                "city": service.location.name,
                "condition": report.kind.label,
                "temperatureC": report.temperature,
                "humidityPercent": report.humidity,
                "windMetersPerSecond": report.wind,
                "night": report.isNight,
                "days": report.days.map { day in
                    ["date": day.date, "condition": day.kind.label, "lowC": day.low, "highC": day.high,
                     "precipitationMm": day.precipitation] as [String: Any]
                },
            ]
            // 이번 갱신이 실패했으면 위 값은 이전에 받은 것이다
            if let error = service.lastError { result["staleBecause"] = error }
            return ["result": result]

        case "run_command":
            guard let id = args["command"] as? String, let command = Commands.all.first(where: { $0.id == id }) else {
                return ["error": "Unknown command. Call list_shortcuts for the valid command ids."]
            }
            // 응답을 먼저 돌려준 뒤 실행한다 (파일 선택 창처럼 오래 걸리는 명령이 있다)
            DispatchQueue.main.async { command.run() }
            return ["result": ["started": id]]

        case "list_shortcuts":
            return ["result": ["shortcuts": Commands.all.map { command -> [String: Any] in
                var entry: [String: Any] = ["command": command.id, "title": command.title]
                entry["shortcut"] = command.combo?.string ?? NSNull()
                entry["default"] = command.defaultShortcut ?? NSNull()
                return entry
            }]]

        case "set_shortcut":
            guard let id = args["command"] as? String, let command = Commands.all.first(where: { $0.id == id }) else {
                return ["error": "Unknown command. Call list_shortcuts for the valid command ids."]
            }
            let raw = (args["shortcut"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            if raw == "default" {
                ConfigStore.shared.update { $0.shortcuts.removeValue(forKey: id) }
            } else if raw.isEmpty {
                ConfigStore.shared.update { $0.shortcuts[id] = "" }
            } else {
                guard let combo = KeyCombo(raw) else {
                    return ["error": "Cannot parse \"\(raw)\". Use modifiers ctrl/opt/cmd/shift joined by + and one key, e.g. \"ctrl+opt+1\". At least one of ctrl/opt/cmd is required unless the key is F1-F12."]
                }
                if let other = Commands.conflict(for: combo, excluding: id) {
                    return ["error": "\(combo.string) is already used by \"\(other.id)\" (\(other.title)). Change or clear that one first."]
                }
                ConfigStore.shared.update { $0.shortcuts[id] = combo.string }
            }
            var result: [String: Any] = ["command": id]
            result["shortcut"] = command.combo?.string ?? NSNull()
            return ["result": result]

        case "list_layouts":
            let config = ConfigStore.shared.config
            return ["result": [
                "layouts": config.layouts.map { layout -> [String: Any] in
                    var entry: [String: Any] = [
                        "name": layout.name,
                        "items": layout.items.map { item in
                            ["app": item.app, "bundleId": item.bundleId, "title": item.title,
                             "display": item.display, "rect": fraction(item.rect)] as [String: Any]
                        },
                    ]
                    entry["shortcut"] = config.shortcuts["layout:" + layout.name].flatMap { $0.isEmpty ? nil : $0 } ?? NSNull()
                    return entry
                },
                "zones": config.zones.map { zone -> [String: Any] in
                    var entry: [String: Any] = ["name": zone.name, "rect": fraction(zone.rect)]
                    entry["display"] = zone.display ?? NSNull()
                    entry["shortcut"] = config.shortcuts["zone:" + zone.name].flatMap { $0.isEmpty ? nil : $0 } ?? NSNull()
                    return entry
                },
            ]]

        case "save_layout":
            guard let name = (args["name"] as? String)?.trimmingCharacters(in: .whitespaces), !name.isEmpty else {
                return ["error": "name is required."]
            }
            let layout: Layout
            if let rawItems = args["items"] as? [[String: Any]] {
                var items: [Layout.Item] = []
                for raw in rawItems {
                    guard let rect = fractionRect(raw["rect"]) else {
                        return ["error": "Each item needs rect {x, y, width, height} as fractions (0-1) of the display's usable area, staying inside it."]
                    }
                    guard let query = (raw["bundleId"] as? String) ?? (raw["app"] as? String), !query.isEmpty else {
                        return ["error": "Each item needs app (name) or bundleId."]
                    }
                    guard let app = runningApp(matching: query), let bundleId = app.bundleIdentifier else {
                        return ["error": "\"\(query)\" is not running, so its identity cannot be resolved. Start the app, then save again."]
                    }
                    items.append(Layout.Item(
                        bundleId: bundleId, app: app.localizedName ?? query, title: raw["title"] as? String ?? "",
                        display: number(raw["display"]).map { Int($0) } ?? 0, rect: rect))
                }
                guard !items.isEmpty else { return ["error": "items is empty."] }
                layout = Layout(name: name, items: items, activate: args["activate"] as? Bool)
            } else {
                guard WindowManager.ensurePermission() else { return ["error": WindowManager.permissionMessage] }
                layout = Layouts.capture(name: name)
                guard !layout.items.isEmpty else { return ["error": "No visible windows to capture."] }
            }
            Layouts.save(layout)
            return ["result": ["name": name, "windows": layout.items.count,
                               "hint": "Bind a hotkey with set_shortcut, command \"layout:\(name)\"."]]

        case "apply_layout":
            guard let name = args["name"] as? String,
                  let layout = ConfigStore.shared.config.layouts.first(where: { $0.name == name }) else {
                return ["error": "No layout with that name. Call list_layouts."]
            }
            guard WindowManager.ensurePermission() else { return ["error": WindowManager.permissionMessage] }
            let outcome = WindowManager.apply(layout)
            return ["result": ["moved": outcome.moved, "skippedApps": outcome.skipped]]

        case "delete_layout":
            guard let name = args["name"] as? String, Layouts.delete(name: name) else {
                return ["error": "No layout with that name."]
            }
            return ["result": ["deleted": name]]

        case "save_zone":
            guard let name = (args["name"] as? String)?.trimmingCharacters(in: .whitespaces), !name.isEmpty else {
                return ["error": "name is required."]
            }
            guard let rect = fractionRect(args["rect"]) else {
                return ["error": "rect {x, y, width, height} must be fractions (0-1) of the display's usable area, staying inside it."]
            }
            let zone = Zone(name: name, display: number(args["display"]).map { Int($0) }, rect: rect)
            ConfigStore.shared.update { config in
                if let index = config.zones.firstIndex(where: { $0.name == name }) {
                    config.zones[index] = zone
                } else {
                    config.zones.append(zone)
                }
            }
            return ["result": ["name": name, "hint": "Bind a hotkey with set_shortcut, command \"zone:\(name)\"."]]

        case "delete_zone":
            guard let name = args["name"] as? String,
                  ConfigStore.shared.config.zones.contains(where: { $0.name == name }) else {
                return ["error": "No zone with that name."]
            }
            ConfigStore.shared.update { config in
                config.zones.removeAll { $0.name == name }
                config.shortcuts.removeValue(forKey: "zone:" + name)
            }
            return ["result": ["deleted": name]]

        default:
            return ["error": "Unknown tool."]
        }
    }

    private static func fraction(_ r: FractionRect) -> [String: Double] {
        ["x": r.x, "y": r.y, "width": r.width, "height": r.height]
    }

    private static func fractionRect(_ value: Any?) -> FractionRect? {
        guard let dict = value as? [String: Any], let x = number(dict["x"]), let y = number(dict["y"]),
              let w = number(dict["width"]), let h = number(dict["height"]) else { return nil }
        let rect = FractionRect(x: x, y: y, width: w, height: h)
        return rect.isValid ? rect : nil
    }

    private static func runningApp(matching query: String) -> NSRunningApplication? {
        let needle = query.lowercased()
        let regular = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        return regular.first { $0.bundleIdentifier?.lowercased() == needle || $0.localizedName?.lowercased() == needle }
            ?? regular.first { $0.localizedName?.lowercased().contains(needle) == true }
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    // MARK: - MCP 프로세스 쪽 (클라이언트)

    /// 앱에 요청을 보낸다. 앱이 꺼져 있으면 한 번 실행을 시도한다.
    static func send(_ request: [String: Any]) -> [String: Any] {
        guard let data = try? JSONSerialization.data(withJSONObject: request) else {
            return ["error": "Could not encode request."]
        }
        var remote = CFMessagePortCreateRemote(nil, portName)
        if remote == nil {
            launchApp()
            for _ in 0..<25 where remote == nil {
                Thread.sleep(forTimeInterval: 0.2)
                remote = CFMessagePortCreateRemote(nil, portName)
            }
        }
        guard let remote else {
            return ["error": "Rising Kit is not running and could not be started. Open /Applications/Rising Kit.app first."]
        }
        var reply: Unmanaged<CFData>?
        let status = CFMessagePortSendRequest(
            remote, 0, data as CFData, 5, 120, CFRunLoopMode.defaultMode.rawValue, &reply)
        guard status == kCFMessagePortSuccess, let replyData = reply?.takeRetainedValue() as Data?,
              let response = (try? JSONSerialization.jsonObject(with: replyData)) as? [String: Any] else {
            return ["error": "Rising Kit did not answer (status \(status))."]
        }
        return response
    }

    private static func launchApp() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-g", "-b", "com.oddscenter.risingkit"]
        try? task.run()
        task.waitUntilExit()
    }
}
