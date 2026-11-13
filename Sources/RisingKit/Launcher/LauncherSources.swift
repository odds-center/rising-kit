import AppKit
import Carbon.HIToolbox

/// 런처가 찾아 주는 것 중 앱·명령이 아닌 것들: 시스템 설정 항목, 시스템 명령, 자주 가는 폴더.
enum LauncherSources {
    private static let settingsApp = "/System/Applications/System Settings.app"

    // MARK: - 시스템 설정 항목

    /// 이 맥에 설치된 시스템 설정 패널을 훑는다. 이름은 각 패널이 가진 번역에서 가져온다.
    static func settingsPanes() -> [LauncherItem] {
        let root = "/System/Library/ExtensionKit/Extensions"
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: root) else { return [] }
        let language = Locale.preferredLanguages.first.map { String($0.prefix(2)) } ?? "en"
        var items: [LauncherItem] = []

        for entry in entries where entry.hasSuffix(".appex") {
            let contents = "\(root)/\(entry)/Contents"
            guard let info = NSDictionary(contentsOfFile: contents + "/Info.plist"),
                  let attributes = info["EXAppExtensionAttributes"] as? [String: Any],
                  attributes["EXExtensionPointIdentifier"] as? String == "com.apple.Settings.extension.ui",
                  let bundleId = info["CFBundleIdentifier"] as? String else { continue }

            let table = NSDictionary(contentsOfFile: contents + "/Resources/InfoPlist.loctable") as? [String: Any]
            func name(_ lang: String) -> String? {
                guard let strings = table?[lang] as? [String: Any] else { return nil }
                return (strings["CFBundleDisplayName"] ?? strings["CFBundleName"]) as? String
            }
            let english = name("en") ?? (info["CFBundleDisplayName"] as? String)
            // 번역된 이름이 없는 패널(내부용 이름만 가진 것)은 보여 주지 않는다
            guard let title = name(language) ?? fallbackNames[bundleId] ?? english,
                  !title.isEmpty, !title.contains("Extension"), !title.contains("Settings") else { continue }

            items.append(LauncherItem(
                id: "pref:" + bundleId, kind: .setting, title: title, icon: .file(path: settingsApp),
                keywords: [english].compactMap { $0 }.filter { $0 != title }, tags: ["설정", "settings"],
                action: { open("x-apple.systempreferences:" + bundleId) }))
        }

        // 자주 찾는 개인정보 보호 하위 항목
        for (title, anchor, keywords) in [
            ("손쉬운 사용 권한", "Privacy_Accessibility", ["accessibility permission"]),
            ("화면 및 시스템 오디오 녹음 권한", "Privacy_ScreenCapture", ["screen recording"]),
            ("전체 디스크 접근 권한", "Privacy_AllFiles", ["full disk access"]),
            ("자동화 권한", "Privacy_Automation", ["automation"]),
            ("마이크 권한", "Privacy_Microphone", ["microphone"]),
            ("카메라 권한", "Privacy_Camera", ["camera"]),
        ] {
            items.append(LauncherItem(
                id: "pref:" + anchor, kind: .setting, title: title, subtitle: "개인정보 보호 및 보안",
                icon: .file(path: settingsApp), keywords: keywords, tags: ["설정", "settings", "privacy", "권한"],
                action: { open("x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?" + anchor) }))
        }
        return items
    }

    /// 번역표에 이름이 없는 패널의 한국어 이름
    private static let fallbackNames = ["com.apple.Battery-Settings.extension": "배터리"]

    private static func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }

    // MARK: - 시스템 명령

    static let systemCommands: [LauncherItem] = {
        func item(_ id: String, _ title: String, _ symbol: String, _ keywords: [String], _ action: @escaping () -> Void) -> LauncherItem {
            LauncherItem(id: "sys:" + id, kind: .system, title: title, icon: .symbol(symbol), keywords: keywords, action: action)
        }
        return [
            item("lock", "화면 잠금", "lock.fill", ["lock screen", "잠그기"]) {
                // 시스템의 화면 잠금 단축키 ⌃⌘Q 를 보낸다
                postKey(CGKeyCode(kVK_ANSI_Q), flags: [.maskControl, .maskCommand])
            },
            item("sleep", "잠자기", "moon.zzz.fill", ["sleep", "절전"]) { run("/usr/bin/pmset", ["sleepnow"]) },
            item("displaysleep", "디스플레이 끄기", "display", ["display sleep", "화면 끄기", "모니터 끄기"]) {
                run("/usr/bin/pmset", ["displaysleepnow"])
            },
            item("screensaver", "화면 보호기 시작", "sparkles.tv", ["screen saver"]) {
                run("/usr/bin/open", ["-a", "ScreenSaverEngine"])
            },
            // 아래 셋은 macOS 가 직접 확인 창을 띄운다
            item("restart", "재시동…", "arrow.clockwise.circle", ["restart", "reboot", "재부팅", "다시 시작"]) {
                script(#"tell application "loginwindow" to «event aevtrrst»"#)
            },
            item("shutdown", "시스템 종료…", "power", ["shut down", "shutdown", "끄기", "전원"]) {
                script(#"tell application "loginwindow" to «event aevtrsdn»"#)
            },
            item("logout", "로그아웃…", "rectangle.portrait.and.arrow.right", ["log out", "logout"]) {
                script(#"tell application "loginwindow" to «event aevtrlgo»"#)
            },
            item("emptytrash", "휴지통 비우기…", "trash", ["empty trash", "bin"]) {
                NSApp.activate(ignoringOtherApps: true)
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "휴지통을 비울까요?"
                alert.informativeText = "휴지통의 항목이 영구적으로 삭제됩니다. 되돌릴 수 없습니다."
                alert.addButton(withTitle: "취소")
                alert.addButton(withTitle: "비우기")
                if alert.runModal() == .alertSecondButtonReturn {
                    script(#"tell application "Finder" to empty trash"#)
                }
            },
        ]
    }()

    // MARK: - 폴더

    static let folders: [LauncherItem] = {
        let home = NSHomeDirectory()
        return [
            ("다운로드", home + "/Downloads", ["downloads"]),
            ("문서", home + "/Documents", ["documents"]),
            ("데스크탑", home + "/Desktop", ["desktop", "바탕화면"]),
            ("홈", home, ["home"]),
            ("응용 프로그램", "/Applications", ["applications", "앱 폴더"]),
            ("휴지통", home + "/.Trash", ["trash", "bin"]),
        ].map { title, path, keywords in
            LauncherItem(id: "folder:" + path, kind: .folder, title: title,
                         subtitle: (path as NSString).abbreviatingWithTildeInPath, icon: .file(path: path),
                         keywords: keywords, tags: ["폴더", "folder"], path: path,
                         action: { NSWorkspace.shared.open(URL(fileURLWithPath: path)) })
        }
    }()

    // MARK: - 도우미

    private static func run(_ path: String, _ arguments: [String]) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments
        try? task.run()
    }

    private static func script(_ source: String) {
        run("/usr/bin/osascript", ["-e", source])
    }

    private static func postKey(_ key: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }
}

/// 파일 이름 검색 (Spotlight 색인 사용).
enum FileSearch {
    /// 홈 폴더에서 이름에 `query` 가 들어간 파일·폴더를 최대 `limit` 개 찾는다. 호출한 스레드를 막는다.
    static func find(_ query: String, limit: Int = 6) -> [String] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        task.arguments = ["-onlyin", NSHomeDirectory(), "-name", query]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return [] }

        // 결과가 아주 많을 수 있으므로 후보를 어느 정도만 모은 뒤 끝낸다
        let deadline = Date().addingTimeInterval(1.5)
        var buffer = Data()
        var candidates: [String] = []
        let home = NSHomeDirectory()
        // 빌드 산출물·패키지 캐시·라이브러리 안쪽은 찾으려는 파일이 아닌 경우가 대부분이다
        let noise = ["/Library/", "/node_modules/", ".app/", "/go/pkg/", "/build/", "/dist/", "/release/",
                     "/storybook-static/", "/vendor/", "/vendors/", "/target/", "/Pods/", "/DerivedData/"]
        while candidates.count < 80, Date() < deadline {
            let chunk = pipe.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self)
                buffer.removeSubrange(buffer.startIndex...newline)
                let relative = line.hasPrefix(home) ? String(line.dropFirst(home.count)) : line
                if relative.contains("/.") || noise.contains(where: { (relative + "/").contains($0) }) { continue }
                candidates.append(line)
            }
        }
        task.terminate()

        // 이름이 검색어로 시작하는 것, 그다음 홈에서 가까운(얕은) 것을 먼저
        let needle = query.precomposedStringWithCanonicalMapping.lowercased()
        func rank(_ path: String) -> (Int, Int) {
            let name = (path as NSString).lastPathComponent.precomposedStringWithCanonicalMapping.lowercased()
            let nameRank = name == needle ? 0 : name.hasPrefix(needle) ? 1 : 2
            return (nameRank, path.split(separator: "/").count)
        }
        return Array(candidates.sorted { rank($0) < rank($1) }.prefix(limit))
    }
}
