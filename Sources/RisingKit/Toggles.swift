import AppKit

/// 메뉴·런처·설정에서 켜고 끄는 스위치.
enum QuickToggle: String, CaseIterable {
    case keepAwake, darkMode, hideDesktopIcons, showHiddenFiles

    var title: String {
        switch self {
        case .keepAwake: return "잠자기 방지"
        case .darkMode: return "다크 모드"
        case .hideDesktopIcons: return "바탕화면 아이콘 숨기기"
        case .showHiddenFiles: return "숨김 파일 보기"
        }
    }

    var detail: String {
        switch self {
        case .keepAwake: return "켜 둔 동안 화면과 맥이 잠들지 않습니다. Rising Kit 을 끄면 함께 풀립니다"
        case .darkMode: return "처음 쓸 때 macOS 가 자동화 권한을 물어봅니다"
        case .hideDesktopIcons: return "Finder 를 다시 시작합니다 (열려 있던 Finder 창은 닫힙니다)"
        case .showHiddenFiles: return "Finder 를 다시 시작합니다 (열려 있던 Finder 창은 닫힙니다)"
        }
    }

    var symbol: String {
        switch self {
        case .keepAwake: return "cup.and.saucer"
        case .darkMode: return "circle.lefthalf.filled"
        case .hideDesktopIcons: return "eye.slash"
        case .showHiddenFiles: return "doc.badge.ellipsis"
        }
    }

    var keywords: [String] {
        switch self {
        case .keepAwake: return ["keep awake", "caffeinate", "카페인", "절전 방지"]
        case .darkMode: return ["dark mode", "light mode", "라이트 모드", "화면 모드"]
        case .hideDesktopIcons: return ["hide desktop icons", "데스크탑 아이콘"]
        case .showHiddenFiles: return ["show hidden files", "dotfiles", "숨긴 파일"]
        }
    }

    private static var awakeProcess: Process?
    private static let finder = "com.apple.finder"

    var isOn: Bool {
        switch self {
        case .keepAwake:
            return Self.awakeProcess?.isRunning == true
        case .darkMode:
            return UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        case .hideDesktopIcons:
            // 값이 없으면 아이콘을 보여 주는 것이 기본
            return (Self.finderDefault("CreateDesktop") ?? true) == false
        case .showHiddenFiles:
            return Self.finderDefault("AppleShowAllFiles") ?? false
        }
    }

    func toggle() { set(!isOn) }

    func set(_ on: Bool) {
        switch self {
        case .keepAwake:
            Self.awakeProcess?.terminate()
            Self.awakeProcess = nil
            if on {
                // -d 화면, -i 시스템 잠자기 방지. -w 로 Rising Kit 이 끝나면 같이 끝나게 한다
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
                task.arguments = ["-d", "-i", "-w", String(ProcessInfo.processInfo.processIdentifier)]
                if (try? task.run()) != nil { Self.awakeProcess = task }
            }
        case .darkMode:
            Self.run("/usr/bin/osascript", [
                "-e", "tell application \"System Events\" to tell appearance preferences to set dark mode to \(on)",
            ])
        case .hideDesktopIcons:
            Self.writeFinderDefault("CreateDesktop", !on)
        case .showHiddenFiles:
            Self.writeFinderDefault("AppleShowAllFiles", on)
        }
    }

    private static func finderDefault(_ key: String) -> Bool? {
        // CFPreferences 는 다른 앱의 설정을 캐시 없이 읽게 해 준다
        CFPreferencesAppSynchronize(finder as CFString)
        guard let value = CFPreferencesCopyAppValue(key as CFString, finder as CFString) else { return nil }
        if let bool = value as? Bool { return bool }
        if let string = value as? String { return ["1", "true", "yes"].contains(string.lowercased()) }
        return nil
    }

    private static func writeFinderDefault(_ key: String, _ value: Bool) {
        run("/usr/bin/defaults", ["write", finder, key, "-bool", value ? "true" : "false"], wait: true)
        run("/usr/bin/killall", ["Finder"])
    }

    private static func run(_ path: String, _ arguments: [String], wait: Bool = false) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return }
        if wait {
            // 실행 루프를 돌리지 않고 기다린다 (화면을 그리는 중에 불려도 안전하게)
            let done = DispatchSemaphore(value: 0)
            task.terminationHandler = { _ in done.signal() }
            if task.isRunning { _ = done.wait(timeout: .now() + 3) }
        }
    }
}
