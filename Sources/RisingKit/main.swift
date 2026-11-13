import AppKit
import RisingKitCore
import SwiftUI

// 명령줄 모드: RisingKit --pdf2png [--dpi 150] 파일.pdf ...
let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.first == "--pdf2png" {
    var dpi = PDFConverter.dpi
    var files: [URL] = []
    var rest = arguments.dropFirst()
    while let arg = rest.popFirst() {
        if arg == "--dpi", let value = rest.popFirst(), let parsed = Int(value), parsed > 0 {
            dpi = parsed
        } else {
            files.append(URL(fileURLWithPath: arg))
        }
    }
    guard !files.isEmpty else {
        FileHandle.standardError.write("사용법: RisingKit --pdf2png [--dpi 150] 파일.pdf ...\n".data(using: .utf8)!)
        exit(2)
    }
    let result = PDFConverter.convert(files, dpi: dpi)
    result.written.forEach { print($0.path) }
    result.failed.forEach { FileHandle.standardError.write("실패: \($0)\n".data(using: .utf8)!) }
    exit(result.failed.isEmpty ? 0 : 1)
}

// 명령줄에서 런처 검색 결과 확인: RisingKit --search 검색어
if arguments.first == "--search" {
    let model = LauncherModel()
    model.index.loadNow()
    model.loadCommands()
    let query = arguments.dropFirst().joined(separator: " ")
    for item in model.search(query).prefix(12) {
        print("\(item.title)  [\(item.section)\(item.subtitle.isEmpty ? "" : " · " + item.subtitle)]")
    }
    if let port = PortParser.query(query) {
        for item in LauncherModel.portItems(PortTools.users(of: port), asked: port).prefix(8) {
            print("\(item.title)  [포트 · \(item.subtitle)]")
        }
        exit(0)
    }
    for path in FileSearch.find(query) { print("\((path as NSString).lastPathComponent)  [파일 · \(path)]") }
    exit(0)
}

// 런처 화면을 실제로 띄우지 않고 PNG 로 그려 본다 (디자인 확인용):
//   RisingKit --render-launcher 출력.png [검색어]
if arguments.first == "--render-launcher", arguments.count >= 2 {
    _ = NSApplication.shared
    let model = LauncherModel()
    model.index.loadNow()
    model.prepareForShow()
    model.query = arguments.dropFirst(2).joined(separator: " ")
    let size = NSSize(width: 700, height: 468)
    let host = NSHostingView(rootView: LauncherView(model: model).background(Color(nsColor: .windowBackgroundColor)))
    host.frame = NSRect(origin: .zero, size: size)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    // 파일 검색 결과와 지연 로딩되는 줄이 채워질 시간을 준다
    RunLoop.main.run(until: Date().addingTimeInterval(1.2))
    host.layoutSubtreeIfNeeded()
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { exit(1) }
    host.cacheDisplay(in: host.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: arguments[1]))
    exit(0)
}

// 설정 창의 탭 하나를 PNG 로 그려 본다:  RisingKit --render-settings 출력.png map|window|shortcuts|system|general
if arguments.first == "--render-settings", arguments.count >= 3,
   let tab = SettingsModel.Tab(rawValue: arguments[2]) {
    _ = NSApplication.shared
    let settings = SettingsModel.shared
    settings.tab = tab
    settings.map.refresh()
    SystemStats.shared.start()
    let host = NSHostingView(rootView: MainView(settings: settings))
    host.frame = NSRect(x: 0, y: 0, width: 940, height: 640)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    RunLoop.main.run(until: Date().addingTimeInterval(tab == .system ? 5.6 : 0.8))
    host.layoutSubtreeIfNeeded()
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { exit(1) }
    host.cacheDisplay(in: host.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: arguments[1]))
    exit(0)
}

// 이미지 파일의 글자를 읽어 출력한다:  RisingKit --ocr 이미지.png
if arguments.first == "--ocr", arguments.count >= 2 {
    Screenshot.recognizeText(in: URL(fileURLWithPath: arguments[1])).forEach { print($0) }
    exit(0)
}

// 앱을 지우면 함께 지워질 항목을 보여 준다 (보기만 함):  RisingKit --leftovers 앱이름
if arguments.first == "--leftovers", arguments.count >= 2 {
    let name = arguments.dropFirst().joined(separator: " ")
    guard let app = Uninstaller.apps().first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
        print("앱을 찾지 못했습니다: \(name)")
        exit(1)
    }
    print("\(app.name)  \(app.bundleId)")
    for entry in Uninstaller.entries(for: app) {
        print("  \(Leftovers.formatSize(Uninstaller.size(of: entry.path)))\t\(entry.path)")
    }
    exit(0)
}

// 스크럼 초안을 출력한다 (읽기만 함):  RisingKit --scrum
if arguments.first == "--scrum" {
    let repos = ScrumService.repositories()
    let chosen = ScrumService.selectedKeys(among: repos)
    let me = ScrumService.identity(for: repos)
    FileHandle.standardError.write("찾은 저장소: \(repos.map { (chosen.contains($0.key) ? "✓" : "·") + $0.key }.joined(separator: " "))\n".data(using: .utf8)!)
    FileHandle.standardError.write("내 이름 \(me.names.sorted()) · 이메일 \(me.emails.count)개\n".data(using: .utf8)!)
    let draft = ScrumService.draft()
    print(draft.text)
    FileHandle.standardError.write("저장소 \(draft.repositories)개, 커밋 \(draft.commits)개\n".data(using: .utf8)!)
    exit(0)
}

// 정리하면 옮겨질 파일을 보여 준다 (옮기지 않음):  RisingKit --tidy-preview
if arguments.first == "--tidy-preview" {
    let plan = TidyService.plan()
    print("스크린샷 \(plan.screenshots.count)개 (폴더: \(TidyService.screenshotFolder.path))")
    plan.screenshots.prefix(5).forEach { print("  \($0.from.lastPathComponent) → \($0.to.deletingLastPathComponent().lastPathComponent)/") }
    print("다운로드 \(plan.downloads.count)개")
    plan.downloads.prefix(5).forEach { print("  \($0.from.lastPathComponent) → \($0.to.deletingLastPathComponent().lastPathComponent)/") }
    exit(0)
}

// 은행 보안 프로그램 항목과 상태를 보여 준다 (바꾸지 않음):  RisingKit --bank-status
if arguments.first == "--bank-status" {
    let status = BankSecurityService.status()
    print("등록 \(status.jobs.count)개, 실행 중 \(status.running)개")
    for job in status.jobs {
        print("  \(status.loaded.contains(job.label) ? "켜짐" : "꺼짐")  \(job.isSystem ? "시스템" : "사용자")  \(job.vendor)  (\(job.label))")
    }
    exit(0)
}

if arguments.first == "--mcp" {
    MCPServer.run()
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
