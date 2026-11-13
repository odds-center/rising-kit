import AppKit
import RisingKitCore

/// 메뉴, 전역 단축키, 런처, MCP 가 함께 쓰는 명령 하나.
struct Command {
    let id: String
    let title: String
    let symbol: String
    /// 런처 검색용 추가 단어 (영문 등)
    let keywords: [String]
    /// 기본 단축키 ("ctrl+opt+left"). 설정에서 바꾸거나 끌 수 있다.
    let defaultShortcut: String?
    let run: () -> Void

    /// 설정을 반영한 현재 단축키. 꺼져 있거나 없으면 nil.
    var combo: KeyCombo? {
        if let custom = ConfigStore.shared.config.shortcuts[id] {
            return custom.isEmpty ? nil : KeyCombo(custom)
        }
        return defaultShortcut.flatMap { KeyCombo($0) }
    }
}

enum Commands {
    /// 앱 시작 시 AppDelegate 가 채운다.
    static var toggleLauncher: () -> Void = {}
    static var toggleMap: () -> Void = {}
    static var openClipboard: () -> Void = {}
    static var openUninstaller: () -> Void = {}

    static let window: [Command] = {
        func place(_ p: Placement, _ title: String, _ symbol: String, _ kw: [String], _ key: String) -> Command {
            Command(id: "window.\(p.rawValue)", title: title, symbol: symbol,
                    keywords: kw + ["window", "창"], defaultShortcut: "ctrl+opt+" + key) { WindowManager.apply(p) }
        }
        return [
            place(.leftHalf, "창 왼쪽 절반", "rectangle.lefthalf.filled", ["left half"], "left"),
            place(.rightHalf, "창 오른쪽 절반", "rectangle.righthalf.filled", ["right half"], "right"),
            place(.topHalf, "창 위쪽 절반", "rectangle.tophalf.filled", ["top half"], "up"),
            place(.bottomHalf, "창 아래쪽 절반", "rectangle.bottomhalf.filled", ["bottom half"], "down"),
            place(.topLeft, "창 왼쪽 위", "rectangle.inset.topleft.filled", ["top left quarter"], "u"),
            place(.topRight, "창 오른쪽 위", "rectangle.inset.topright.filled", ["top right quarter"], "i"),
            place(.bottomLeft, "창 왼쪽 아래", "rectangle.inset.bottomleft.filled", ["bottom left quarter"], "j"),
            place(.bottomRight, "창 오른쪽 아래", "rectangle.inset.bottomright.filled", ["bottom right quarter"], "k"),
            place(.leftThird, "창 왼쪽 1/3", "rectangle.leadingthird.inset.filled", ["left third"], "d"),
            place(.centerThird, "창 가운데 1/3", "rectangle.center.inset.filled", ["center third"], "f"),
            place(.rightThird, "창 오른쪽 1/3", "rectangle.trailingthird.inset.filled", ["right third"], "g"),
            place(.leftTwoThirds, "창 왼쪽 2/3", "rectangle.leadinghalf.filled", ["left two thirds"], "e"),
            place(.centerTwoThirds, "창 가운데 2/3", "rectangle.center.inset.filled", ["center two thirds"], "r"),
            place(.rightTwoThirds, "창 오른쪽 2/3", "rectangle.trailinghalf.filled", ["right two thirds"], "t"),
            place(.maximize, "창 최대화", "rectangle.fill", ["maximize", "full"], "return"),
            place(.center, "창 가운데로", "rectangle.center.inset.filled", ["center"], "c"),
            Command(id: "window.nextDisplay", title: "창을 다음 디스플레이로", symbol: "rectangle.on.rectangle",
                    keywords: ["next display", "monitor", "모니터", "window", "창"],
                    defaultShortcut: "ctrl+opt+cmd+right") { WindowManager.moveToDisplay(offset: 1) },
            Command(id: "window.prevDisplay", title: "창을 이전 디스플레이로", symbol: "rectangle.on.rectangle",
                    keywords: ["previous display", "monitor", "모니터", "window", "창"],
                    defaultShortcut: "ctrl+opt+cmd+left") { WindowManager.moveToDisplay(offset: -1) },
            Command(id: "window.restore", title: "창 원래 위치로", symbol: "arrow.uturn.backward",
                    keywords: ["restore", "undo", "되돌리기", "window", "창"],
                    defaultShortcut: "ctrl+opt+delete") { WindowManager.restore() },
        ]
    }()

    static let app: [Command] = [
        Command(id: "launcher.toggle", title: "런처 열기", symbol: "magnifyingglass",
                keywords: ["launcher"], defaultShortcut: "opt+space") { toggleLauncher() },
        Command(id: "map.toggle", title: "디스플레이 배치도", symbol: "rectangle.3.group",
                keywords: ["map", "display", "monitor", "layout", "모니터", "배치"],
                defaultShortcut: "ctrl+opt+m") { toggleMap() },
        Command(id: "clipboard.open", title: "클립보드 기록", symbol: "doc.on.clipboard",
                keywords: ["clipboard", "history", "복사", "붙여넣기"],
                defaultShortcut: "ctrl+opt+v") { openClipboard() },
    ]

    static let tools: [Command] = [
        Command(id: "screenshot.region", title: "영역 스크린샷 → 클립보드", symbol: "camera.viewfinder",
                keywords: ["screenshot", "capture", "캡처", "화면"], defaultShortcut: "ctrl+opt+s"
        ) { Screenshot.captureRegionToClipboard() },
        Command(id: "screenshot.ocr", title: "화면 글자 복사 (OCR)", symbol: "text.viewfinder",
                keywords: ["ocr", "text", "글자 인식", "텍스트 추출"], defaultShortcut: "ctrl+opt+o"
        ) { Screenshot.copyTextFromRegion() },
        Command(id: "color.pick", title: "화면에서 색상 추출", symbol: "eyedropper",
                keywords: ["color picker", "색", "컬러", "hex", "스포이드"], defaultShortcut: nil
        ) { ColorPicker.pick() },
        Command(id: "scrum.copy", title: "데일리 스크럼 초안 복사", symbol: "list.bullet.clipboard",
                keywords: ["scrum", "daily", "standup", "스탠드업", "회의록", "커밋"], defaultShortcut: nil
        ) { ScrumService.copyDraft() },
        Command(id: "tidy.run", title: "다운로드 · 스크린샷 정리", symbol: "tray.full",
                keywords: ["tidy", "clean", "organize", "정돈", "파일 정리"], defaultShortcut: nil
        ) { TidyService.runAndReport() },
        Command(id: "bank.toggle", title: "은행 보안 프로그램 켜기/끄기", symbol: "lock.shield",
                keywords: ["bank", "security", "뱅킹", "nprotect", "ahnlab", "veraport", "보안 프로그램", "키보드 보안"],
                defaultShortcut: nil
        ) { BankSecurityService.toggleAndReport() },
        Command(id: "uninstall.open", title: "앱 삭제…", symbol: "trash",
                keywords: ["uninstall", "remove app", "앱 제거", "앱 지우기"], defaultShortcut: nil
        ) { openUninstaller() },
        Command(id: "pdf.convert", title: "PDF → PNG 변환…", symbol: "doc.richtext",
                keywords: ["pdf", "png", "image", "이미지", "변환", "convert"], defaultShortcut: nil
        ) { PDFConverter.pickAndConvert() },
        Command(id: "balance.center", title: "좌우 음량 지금 가운데로", symbol: "speaker.wave.2",
                keywords: ["balance", "sound", "audio", "소리", "밸런스", "균형"], defaultShortcut: nil
        ) { BalanceLock.shared.centerIfNeeded() },
        Command(id: "balance.toggle", title: "좌우 음량 고정 켜기/끄기", symbol: "lock",
                keywords: ["balance lock", "sound", "소리", "밸런스", "균형"], defaultShortcut: nil
        ) { BalanceLock.shared.enabled.toggle() },
    ]

    /// 설정에 저장된 레이아웃과 사용자 영역으로 만든 명령.
    static var custom: [Command] {
        let config = ConfigStore.shared.config
        let layouts = config.layouts.map { layout in
            Command(id: "layout:" + layout.name, title: "레이아웃: " + layout.name, symbol: "rectangle.3.group.fill",
                    keywords: ["layout", "레이아웃", "배치"], defaultShortcut: nil) { Layouts.apply(layout) }
        }
        let zones = config.zones.map { zone in
            Command(id: "zone:" + zone.name, title: "영역: " + zone.name, symbol: "rectangle.dashed",
                    keywords: ["zone", "영역", "window", "창"], defaultShortcut: nil) { WindowManager.apply(zone) }
        }
        return layouts + zones
    }

    /// 빠른 토글 (잠자기 방지 등)
    static let toggles: [Command] = QuickToggle.allCases.map { toggle in
        Command(id: "toggle." + toggle.rawValue, title: toggle.title, symbol: toggle.symbol,
                keywords: toggle.keywords + ["toggle", "토글"], defaultShortcut: nil) { toggle.toggle() }
    }

    static var all: [Command] { app + window + tools + toggles + custom }

    /// 같은 단축키를 이미 쓰고 있는 다른 명령.
    static func conflict(for combo: KeyCombo, excluding id: String) -> Command? {
        all.first { $0.id != id && $0.combo == combo }
    }
}
