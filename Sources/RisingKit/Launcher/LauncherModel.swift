import AppKit
import RisingKitCore

struct LauncherItem: Identifiable {
    enum Icon {
        /// 파일·폴더·앱의 Finder 아이콘
        case file(path: String)
        case symbol(String)
    }

    enum Kind {
        case result, app, setting, command, system, folder, file, web, clip

        /// 목록에서 묶어 보여 줄 때의 제목
        var section: String {
            switch self {
            case .result: return "결과"
            case .app: return "응용 프로그램"
            case .setting: return "시스템 설정"
            case .command: return "명령"
            case .system: return "시스템"
            case .folder: return "폴더"
            case .file: return "파일"
            case .web: return "웹"
            case .clip: return "클립보드"
            }
        }

        /// Enter 를 눌렀을 때 일어나는 일
        var actionLabel: String {
            switch self {
            case .result: return "복사"
            case .command, .system: return "실행"
            case .web: return "검색"
            case .clip: return "붙여넣기"
            default: return "열기"
            }
        }

        /// 자주 쓴 항목으로 셀 대상인지 (그때그때 달라지는 결과·파일·웹은 제외)
        var tracksUsage: Bool {
            switch self {
            case .app, .setting, .command, .system, .folder: return true
            case .result, .file, .web, .clip: return false
            }
        }
    }

    let id: String
    let kind: Kind
    let title: String
    /// 제목 옆에 흐리게 붙는 설명 (경로 등)
    var subtitle = ""
    /// 단축키 키캡: ["⌃", "⌥", "←"]
    var keys: [String] = []
    let icon: Icon
    let keywords: [String]
    /// 종류를 나타내는 넓은 단어("설정", "폴더"). 맞아도 낮은 점수만 준다.
    var tags: [String] = []
    /// Finder 에서 보여 줄 수 있는 경로 (앱·파일·폴더)
    var path: String?
    /// 목록에서 속한 묶음. 검색할 때 채워진다.
    var section = ""
    let action: () -> Void
}

/// 런처 위쪽의 종류 고르기.
enum LauncherFilter: Int, CaseIterable {
    case all, clipboard, apps, settings, files, commands

    var label: String {
        switch self {
        case .all: return "전체"
        case .clipboard: return "클립보드"
        case .apps: return "앱"
        case .settings: return "설정"
        case .files: return "파일"
        case .commands: return "명령"
        }
    }

    func includes(_ kind: LauncherItem.Kind) -> Bool {
        switch self {
        case .all: return true
        case .clipboard: return kind == .clip
        case .apps: return kind == .app
        case .settings: return kind == .setting
        case .files: return kind == .file || kind == .folder
        case .commands: return kind == .command || kind == .system
        }
    }
}

/// 설치된 앱과 시스템 설정 항목의 목록. 런처를 열 때 오래됐으면 백그라운드에서 다시 훑는다.
final class AppIndex {
    private(set) var items: [LauncherItem] = []
    private var lastScan = Date.distantPast
    private var scanning = false

    private static let roots: [String] = [
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        "/System/Applications/Utilities",
        "/System/Library/CoreServices/Applications",
        NSHomeDirectory() + "/Applications",
    ]

    func refreshIfStale(completion: @escaping () -> Void) {
        guard !scanning, Date().timeIntervalSince(lastScan) > 60 else { return }
        scanning = true
        DispatchQueue.global(qos: .userInitiated).async {
            let found = Self.scan()
            DispatchQueue.main.async {
                self.items = found
                self.lastScan = Date()
                self.scanning = false
                completion()
            }
        }
    }

    /// 지금 바로 훑는다 (명령줄 검색용).
    func loadNow() {
        items = Self.scan()
        lastScan = Date()
    }

    private static func scan() -> [LauncherItem] {
        let fm = FileManager.default
        var paths = ["/System/Library/CoreServices/Finder.app"]
        for root in roots {
            guard let entries = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for entry in entries {
                let path = root + "/" + entry
                if entry.hasPrefix(".") { continue }  // 숨겨진 보조 앱
                if entry.hasSuffix(".app") {
                    paths.append(path)
                } else if let inner = try? fm.contentsOfDirectory(atPath: path) {
                    // 한 단계 아래 폴더 (예: /Applications/Python 3.13/IDLE.app)
                    paths += inner.filter { $0.hasSuffix(".app") && !$0.hasPrefix(".") }.map { path + "/" + $0 }
                }
            }
        }
        var seen = Set<String>()
        var items: [LauncherItem] = []
        for path in paths where seen.insert(path).inserted {
            let fileName = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            var display = fm.displayName(atPath: path)
            if display.hasSuffix(".app") { display = String(display.dropLast(4)) }
            let url = URL(fileURLWithPath: path)
            items.append(LauncherItem(
                id: "app:" + path, kind: .app, title: display, icon: .file(path: path),
                // 한글 이름으로 보이는 앱도 영어 파일 이름으로 찾을 수 있게
                keywords: display == fileName ? [] : [fileName], path: path,
                action: { NSWorkspace.shared.openApplication(at: url, configuration: .init()) }))
        }
        return items + LauncherSources.settingsPanes()
    }
}

final class LauncherModel: ObservableObject {
    @Published var query = "" { didSet { if query != oldValue { update() } } }
    @Published var filter = LauncherFilter.all { didSet { if filter != oldValue { update() } } }
    @Published private(set) var results: [LauncherItem] = []
    @Published var selection = 0
    /// 창이 열릴 때마다 바뀌어 검색창에 포커스를 다시 준다.
    @Published private(set) var focusToken = 0
    /// 아래 줄에 잠깐 보여 줄 안내 ("경로 복사됨")
    @Published var notice = ""

    var onClose: (() -> Void)?

    let index = AppIndex()
    private static let usageKey = "launcherUsage"
    private var usage: [String: Int] = UserDefaults.standard.dictionary(forKey: usageKey) as? [String: Int] ?? [:]

    /// 레이아웃·영역·단축키가 설정에서 바뀔 수 있으므로 열 때마다 다시 만든다.
    private var commandItems: [LauncherItem] = []
    /// 파일 검색은 늦게 도착하므로, 어느 검색어에 대한 결과인지 구분한다.
    private var searchToken = 0
    private var fileSearchWork: DispatchWorkItem?

    var selected: LauncherItem? { results.indices.contains(selection) ? results[selection] : nil }

    func loadCommands() {
        commandItems = Commands.all.filter { $0.id != "launcher.toggle" }.map { command in
            LauncherItem(
                id: "cmd:" + command.id, kind: .command, title: command.title,
                // 토글은 지금 켜져 있는지 함께 보여 준다
                subtitle: QuickToggle(rawValue: String(command.id.dropFirst(7)))
                    .flatMap { command.id.hasPrefix("toggle.") ? ($0.isOn ? "켜짐" : "꺼짐") : nil } ?? "",
                keys: command.combo?.displayParts ?? [], icon: .symbol(command.symbol),
                keywords: command.keywords, action: command.run)
        }
    }

    func prepareForShow(filter initial: LauncherFilter = .all) {
        loadCommands()
        notice = ""
        filter = initial
        query = ""
        focusToken += 1
        update()
        index.refreshIfStale { [weak self] in self?.update() }
    }

    func moveSelection(_ delta: Int) {
        guard !results.isEmpty else { return }
        selection = (selection + delta + results.count) % results.count
        notice = ""
    }

    func cycleFilter(_ delta: Int) {
        let all = LauncherFilter.allCases
        filter = all[(filter.rawValue + delta + all.count) % all.count]
    }

    func runSelected() {
        if let item = selected { run(item) }
    }

    func run(_ item: LauncherItem) {
        if item.kind.tracksUsage {
            usage[item.id, default: 0] += 1
            UserDefaults.standard.set(usage, forKey: Self.usageKey)
        }
        onClose?()
        // 런처가 닫힌 뒤 실행해야 창 명령이 원래 앞에 있던 창에 적용된다.
        DispatchQueue.main.async { item.action() }
    }

    /// 고른 항목을 Finder 에서 보여 준다 (경로가 있는 항목만).
    func revealSelected() {
        guard let path = selected?.path else { NSSound.beep(); return }
        onClose?()
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    /// 고른 클립보드 기록을 지운다.
    func deleteSelectedClip() {
        guard let item = selected, item.kind == .clip,
              let clip = ClipboardMonitor.shared.history.items.first(where: { "clip:" + $0.id == item.id }) else { return }
        ClipboardMonitor.shared.remove(clip)
        let keep = selection
        update()
        selection = min(keep, max(results.count - 1, 0))
        notice = "기록에서 지웠습니다"
    }

    /// 고른 항목의 경로(없으면 제목)를 복사한다.
    func copySelected() {
        guard let item = selected else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.path ?? item.title, forType: .string)
        notice = item.path == nil ? "이름 복사됨" : "경로 복사됨"
    }

    /// 검색어에 대한 결과 (파일 검색 제외). 화면 없이도 쓸 수 있다.
    /// 돌려주는 순서가 곧 화면 순서이며, 같은 묶음(section)끼리 붙어 있다.
    func search(_ rawQuery: String, filter: LauncherFilter = .all) -> [LauncherItem] {
        let q = rawQuery.trimmingCharacters(in: .whitespaces)
        if filter == .clipboard {
            return ClipboardMonitor.shared.history.search(q).map(Self.clipItem)
        }
        let pool = (index.items + commandItems + LauncherSources.systemCommands + LauncherSources.folders)
            .filter { filter.includes($0.kind) }
        var scored: [(item: LauncherItem, score: Int)] = []

        if q.isEmpty {
            for var item in pool {
                let count = usage[item.id] ?? 0
                if filter == .all {
                    // 검색어가 없으면 자주 쓴 항목을 먼저, 그다음 명령과 시스템 명령
                    if count > 0 {
                        item.section = "자주 사용"
                        scored.append((item, 1000 + count))
                    } else if item.kind == .command || item.kind == .system {
                        scored.append((item, 0))
                    }
                } else {
                    // 종류를 골랐으면 그 종류 전체를 훑어볼 수 있게 (자주 쓴 것 먼저)
                    scored.append((item, count))
                }
            }
        } else {
            for item in pool {
                // 제목이 맞으면 그 점수 그대로, 보조 단어로만 맞으면 조금 낮춘다
                let byTitle = Fuzzy.score(query: q, candidate: item.title)
                let byKeyword = item.keywords.compactMap { Fuzzy.score(query: q, candidate: $0) }.max().map { $0 - 60 }
                // 종류 단어("설정")로 찾으면 그 종류 전체가 나오되, 이름이 맞은 항목보다는 아래에
                let byTag = item.tags.contains { Fuzzy.score(query: q, candidate: $0) ?? 0 >= 600 } ? 250 : nil
                guard let best = [byTitle, byKeyword, byTag].compactMap({ $0 }).max() else { continue }
                scored.append((item, best + min(usage[item.id] ?? 0, 20) * 4))
            }
        }

        // 점수가 같으면 원래 순서(안정 정렬) 유지
        var items = scored.enumerated()
            .sorted { $0.element.score != $1.element.score ? $0.element.score > $1.element.score : $0.offset < $1.offset }
            .prefix(q.isEmpty ? 80 : 40).map(\.element.item)

        if !q.isEmpty, filter == .all {
            func copy(_ text: String) -> () -> Void {
                { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
            }
            // 개발용 변환 (uuid, b64, urlencode, md5, #색상 …)
            let dev = DevTools.answers(q).map { answer in
                LauncherItem(id: "dev:" + answer.label + answer.text, kind: .result, title: answer.text,
                             subtitle: answer.label, icon: .symbol(answer.color == nil ? "hammer" : "paintpalette"),
                             keywords: [], action: copy(answer.text))
            }
            items.insert(contentsOf: dev, at: 0)
            // 검색어가 들어 있는 최근 복사 내용 몇 개
            if q.count >= 2 {
                items += ClipboardMonitor.shared.history.search(q).prefix(3).map(Self.clipItem)
            }
            if let answer = DateQuery.answer(q) {
                items.insert(LauncherItem(
                    id: "date:" + answer.text, kind: .result, title: answer.text, subtitle: answer.label,
                    icon: .symbol("calendar"), keywords: [], action: copy(answer.text)), at: 0)
            }
            if let value = Calculator.evaluate(q) {
                let text = Calculator.format(value)
                items.insert(LauncherItem(
                    id: "calc:" + text, kind: .result, title: text, subtitle: "\(q) =",
                    icon: .symbol("equal.circle"), keywords: [], action: copy(text)), at: 0)
            }
            if let url = Self.webAddress(q) {
                items.append(LauncherItem(
                    id: "url:" + url.absoluteString, kind: .web, title: url.absoluteString, subtitle: "주소 열기",
                    icon: .symbol("safari"), keywords: [], action: { NSWorkspace.shared.open(url) }))
            }
            // 아무것도 못 찾았을 때도 갈 곳이 있도록 웹 검색을 둔다
            var components = URLComponents(string: "https://www.google.com/search")!
            components.queryItems = [URLQueryItem(name: "q", value: q)]
            if let url = components.url {
                items.append(LauncherItem(
                    id: "web:" + q, kind: .web, title: "\"\(q)\" 검색", subtitle: "Google",
                    icon: .symbol("globe"), keywords: [], action: { NSWorkspace.shared.open(url) }))
            }
        }
        return Self.grouped(items)
    }

    /// 같은 묶음끼리 모은다. 묶음의 순서는 가장 잘 맞은 항목이 처음 나온 순서, 묶음 안의 순서는 그대로.
    /// 웹은 언제나 맨 끝.
    static func grouped(_ items: [LauncherItem]) -> [LauncherItem] {
        var order: [String] = []
        var groups: [String: [LauncherItem]] = [:]
        for var item in items {
            if item.section.isEmpty { item.section = item.kind.section }
            if groups[item.section] == nil { order.append(item.section) }
            groups[item.section, default: []].append(item)
        }
        let webSection = LauncherItem.Kind.web.section
        let sections = order.filter { $0 != webSection } + order.filter { $0 == webSection }
        return sections.flatMap { groups[$0] ?? [] }
    }

    /// "github.com", "https://…" 처럼 주소로 보이면 URL 로 만든다.
    static func webAddress(_ q: String) -> URL? {
        guard !q.contains(" ") else { return nil }
        if q.hasPrefix("http://") || q.hasPrefix("https://") { return URL(string: q) }
        let host = q.split(separator: "/").first.map(String.init) ?? q
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2, parts.allSatisfy({ !$0.isEmpty }),
              let tld = parts.last, tld.count >= 2, tld.allSatisfy(\.isLetter),
              host.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }) else { return nil }
        return URL(string: "https://" + q)
    }

    static func clipItem(_ clip: ClipItem) -> LauncherItem {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.unitsStyle = .short
        let symbol: String
        switch clip.kind {
        case .text: symbol = "text.alignleft"
        case .file: symbol = "doc"
        case .image: symbol = "photo"
        }
        return LauncherItem(
            id: "clip:" + clip.id, kind: .clip, title: clip.preview,
            subtitle: formatter.localizedString(for: clip.date, relativeTo: Date()),
            icon: .symbol(symbol), keywords: [], action: { ClipboardMonitor.shared.paste(clip) })
    }

    static func portItems(_ users: [PortUser], asked port: Int) -> [LauncherItem] {
        if users.isEmpty, port != 0 {
            return [LauncherItem(id: "port:none", kind: .result, title: "\(port)번 포트를 쓰는 프로세스가 없습니다",
                                 icon: .symbol("network"), keywords: [], section: "포트", action: {})]
        }
        return users.map { user in
            LauncherItem(id: "port:\(user.pid):\(user.port)", kind: .system,
                         title: ":\(user.port)  \(user.command)", subtitle: "PID \(user.pid) · Enter 로 종료",
                         icon: .symbol("network"), keywords: [], section: "포트",
                         action: { PortTools.confirmAndKill(user) })
        }
    }

    static func fileItem(_ path: String) -> LauncherItem {
        let url = URL(fileURLWithPath: path)
        let parent = (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
        return LauncherItem(
            id: "file:" + path, kind: .file, title: url.lastPathComponent, subtitle: parent,
            icon: .file(path: path), keywords: [], path: path, action: { NSWorkspace.shared.open(url) })
    }

    private func update() {
        searchToken += 1
        let token = searchToken
        let q = query.trimmingCharacters(in: .whitespaces)
        results = search(q, filter: filter)
        selection = 0
        notice = ""

        // 느린 조회(파일 검색, 포트 조회)는 입력이 잠깐 멈췄을 때만, 백그라운드에서
        fileSearchWork?.cancel()
        let port = filter == .all ? PortParser.query(q) : nil
        let wantsFiles = (filter == .all || filter == .files) && q.count >= 2 && Calculator.evaluate(q) == nil
        guard port != nil || wantsFiles else { return }
        let limit = filter == .files ? 30 : 6
        let work = DispatchWorkItem { [weak self] in
            let extra: [LauncherItem]
            if let port {
                extra = Self.portItems(PortTools.users(of: port), asked: port)
            } else {
                extra = FileSearch.find(q, limit: limit).map(Self.fileItem)
            }
            DispatchQueue.main.async {
                guard let self, token == self.searchToken, !extra.isEmpty else { return }
                // 고른 항목이 바뀌지 않도록 지금 고른 것을 기억했다가 되찾는다
                let selectedID = self.selected?.id
                // 포트 결과는 물어본 것 자체이므로 맨 위에 둔다
                let merged = Self.grouped(port != nil ? extra + self.results : self.results + extra)
                self.results = merged
                self.selection = port != nil ? 0 : (merged.firstIndex { $0.id == selectedID } ?? 0)
            }
        }
        fileSearchWork = work
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.18, execute: work)
    }
}
