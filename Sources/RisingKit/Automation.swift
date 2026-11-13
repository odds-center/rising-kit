import AppKit
import RisingKitCore

// MARK: - 데일리 스크럼 초안

/// 내 저장소들에서 직전 근무일의 커밋을 모아 스크럼 글 초안을 만든다. 읽기만 한다.
enum ScrumService {
    struct Draft {
        let text: String
        let commits: Int
        let repositories: Int
    }

    /// 찾은 저장소 하나. 같은 원격을 가리키는 복제본·워크트리는 하나로 묶는다.
    struct Repo: Identifiable, Equatable {
        /// "소유자/이름" (예: "acme/web"). 원격이 없으면 "로컬/폴더이름"
        let key: String
        let owner: String
        let name: String
        let paths: [String]
        var id: String { key }
    }

    static var folders: [String] { ConfigStore.shared.config.scrumFolders }

    /// 스크럼에 넣기로 고른 저장소의 키들. 고른 적이 없으면 찾은 저장소 전부.
    /// (어떤 저장소를 넣을지는 사람마다 다르므로 코드가 아니라 설정 파일에 둔다.)
    static func selectedKeys(among repos: [Repo]) -> Set<String> {
        if let chosen = ConfigStore.shared.config.scrumRepos { return Set(chosen) }
        return Set(repos.map(\.key))
    }

    /// "내 커밋"을 가려낼 이름과 이메일: git 전역 설정 + 저장소별 설정 + 설정에 적어 둔 것.
    static func identity(for repos: [Repo]) -> Scrum.Identity {
        var names: Set<String> = [git(nil, ["config", "--global", "user.name"]).trimmingCharacters(in: .whitespacesAndNewlines)]
        var emails: Set<String> = [git(nil, ["config", "--global", "user.email"]).trimmingCharacters(in: .whitespacesAndNewlines)]
        for repo in repos {
            guard let path = repo.paths.first else { continue }
            emails.insert(git(path, ["config", "user.email"]).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        for extra in ConfigStore.shared.config.scrumAuthors {
            if extra.contains("@") { emails.insert(extra) } else { names.insert(extra) }
        }
        return Scrum.Identity(names: names, emails: emails)
    }

    /// 초안을 만든다. git 을 여러 번 실행하므로 백그라운드에서 부른다.
    /// `only` 를 주면 그 저장소들만 (없으면 설정에서 고른 것).
    static func draft(now: Date = Date(), only: Set<String>? = nil) -> Draft {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let doneDay = Scrum.previousWorkday(before: now, calendar: calendar)
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = calendar.timeZone

        let all = repositories()
        let keys = only ?? selectedKeys(among: all)
        let repos = all.filter { keys.contains($0.key) }
        let me = identity(for: repos)

        var seen = Set<String>()
        var done: [Scrum.Commit] = []
        var todays: [Scrum.Commit] = []
        for repo in repos {
            // 설정에서 저장소 이름을 평소 부르는 이름으로 바꿔 둘 수 있다 (scrumNames)
            let label = ConfigStore.shared.config.scrumNames[repo.name] ?? repo.name
            // 직전 근무일 시작부터 지금까지 (월요일이면 금·토·일 커밋이 모두 "한 일"에 들어간다)
            func commits(since: Date, until: Date) -> [Scrum.Commit] {
                var out: [Scrum.Commit] = []
                for path in repo.paths {
                    let log = git(path, ["log", "--all", "--no-merges",
                                         "--since=" + formatter.string(from: since), "--until=" + formatter.string(from: until),
                                         "--format=%x1e%H%x09%an%x09%ae%x09%s"])
                    for entry in Scrum.parseLog(log)
                    // 내가 쓴 커밋만, 그리고 복제본·워크트리가 공유하는 커밋은 한 번만
                    where Scrum.isMine(author: entry.author, email: entry.email, identity: me) && seen.insert(entry.hash).inserted {
                        out.append(Scrum.Commit(hash: entry.hash, subject: entry.subject, project: label))
                    }
                }
                return out
            }
            done += commits(since: doneDay, until: today)
            todays += commits(since: today, until: now)
        }

        let text = Scrum.compose(doneDate: doneDay, done: done, todayDate: today, today: todays, calendar: calendar)
        return Draft(text: text, commits: done.count + todays.count, repositories: repos.count)
    }

    /// 초안을 만들어 클립보드에 넣고 알려 준다.
    static func copyDraft() {
        Toast.show("스크럼 초안을 만드는 중…", symbol: "list.bullet.clipboard")
        DispatchQueue.global(qos: .userInitiated).async {
            let draft = self.draft()
            DispatchQueue.main.async {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(draft.text, forType: .string)
                Toast.show("스크럼 초안을 복사했습니다 (저장소 \(draft.repositories)개, 커밋 \(draft.commits)개)",
                           symbol: "list.bullet.clipboard")
            }
        }
    }

    /// 설정한 폴더 아래의 git 저장소들 (네 단계 깊이까지), 원격 주소 기준으로 묶어서.
    static func repositories() -> [Repo] {
        let fm = FileManager.default
        let skip: Set<String> = ["node_modules", "Library", "build", "dist", "Pods", "vendor", "target", "DerivedData"]
        var found: [String] = []
        func walk(_ url: URL, depth: Int) {
            if fm.fileExists(atPath: url.appendingPathComponent(".git").path) {
                found.append(url.path)
                return  // 저장소 안쪽은 더 보지 않는다
            }
            guard depth < 4, let entries = try? fm.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return }
            for entry in entries where (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                && !skip.contains(entry.lastPathComponent) {
                walk(entry, depth: depth + 1)
            }
        }
        for folder in folders {
            walk(URL(fileURLWithPath: (folder as NSString).expandingTildeInPath), depth: 0)
        }

        var order: [String] = []
        var grouped: [String: (owner: String, name: String, paths: [String])] = [:]
        for path in found {
            let remote = git(path, ["remote", "get-url", "origin"])
            let owner: String, name: String
            if let key = Scrum.repositoryKey(remote: remote) {
                (owner, name) = (key.owner, key.name)
            } else {
                // 원격이 없는 저장소: 워크트리 폴더 이름이 아니라 원래 저장소 폴더 이름을 쓴다
                let common = git(path, ["rev-parse", "--path-format=absolute", "--git-common-dir"])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                owner = "로컬"
                name = common.hasSuffix("/.git")
                    ? ((common as NSString).deletingLastPathComponent as NSString).lastPathComponent
                    : (path as NSString).lastPathComponent
            }
            let key = owner + "/" + name
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: (owner, name, [])].paths.append(path)
        }
        return order.compactMap { key in
            grouped[key].map { Repo(key: key, owner: $0.owner, name: $0.name, paths: $0.paths) }
        }
        .sorted { $0.owner != $1.owner ? $0.owner < $1.owner : $0.name < $1.name }
    }

    private static func git(_ directory: String?, _ arguments: [String]) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = (directory.map { ["-C", $0] } ?? []) + arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return "" }
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }
}

// MARK: - 다운로드 · 스크린샷 정리

/// 오래된 스크린샷과 다운로드 항목을 달별 폴더로 옮긴다. 지우지 않으며, 마지막 정리는 되돌릴 수 있다.
enum TidyService {
    struct Planned {
        let from: URL
        let to: URL
    }

    struct Plan {
        var screenshots: [Planned] = []
        var downloads: [Planned] = []
        var count: Int { screenshots.count + downloads.count }
    }

    private static let undoKey = "tidyLastMoves"
    private static let lastRunKey = "tidyLastRunDay"
    private static var timer: Timer?

    /// macOS 가 스크린샷을 저장하는 폴더 (따로 정하지 않았으면 데스크탑)
    static var screenshotFolder: URL {
        if let custom = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"), !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath)
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    static var downloadsFolder: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }

    /// 지금 정리하면 옮겨질 것들. 아무것도 옮기지 않는다.
    static func plan(now: Date = Date()) -> Plan {
        let config = ConfigStore.shared.config
        let calendar = Calendar.current
        var plan = Plan()
        if config.tidyScreenshots {
            let folder = screenshotFolder
            let moves = Tidy.planScreenshots(items(in: folder), olderThanDays: config.tidyScreenshotDays, now: now, calendar: calendar)
            plan.screenshots = moves.map { move in
                Planned(from: folder.appendingPathComponent(move.name),
                        to: folder.appendingPathComponent(Tidy.screenshotArchive).appendingPathComponent(move.folder)
                            .appendingPathComponent(move.name))
            }
        }
        if config.tidyDownloads {
            let folder = downloadsFolder
            let moves = Tidy.planDownloads(items(in: folder), olderThanDays: config.tidyDownloadDays, now: now, calendar: calendar)
            plan.downloads = moves.map { move in
                Planned(from: folder.appendingPathComponent(move.name),
                        to: folder.appendingPathComponent(Tidy.downloadArchive).appendingPathComponent(move.folder)
                            .appendingPathComponent(move.name))
            }
        }
        return plan
    }

    /// 정리를 실행한다. 옮긴 수를 돌려준다.
    @discardableResult
    static func run(now: Date = Date()) -> (screenshots: Int, downloads: Int) {
        let plan = self.plan(now: now)
        var record: [[String]] = []
        func move(_ items: [Planned]) -> Int {
            var moved = 0
            for item in items {
                let destination = unique(item.to)
                do {
                    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try FileManager.default.moveItem(at: item.from, to: destination)
                    record.append([item.from.path, destination.path])
                    moved += 1
                } catch {
                    NSLog("RisingKit: 정리 중 옮기지 못함 \(item.from.lastPathComponent) (\(error.localizedDescription))")
                }
            }
            return moved
        }
        let result = (move(plan.screenshots), move(plan.downloads))
        if !record.isEmpty { UserDefaults.standard.set(record, forKey: undoKey) }
        UserDefaults.standard.set(dayStamp(now), forKey: lastRunKey)
        return result
    }

    /// 마지막 정리에서 옮긴 것들을 제자리로 돌려놓는다. 되돌린 수를 돌려준다.
    @discardableResult
    static func undo() -> Int {
        guard let record = UserDefaults.standard.array(forKey: undoKey) as? [[String]] else { return 0 }
        var restored = 0
        for pair in record where pair.count == 2 {
            let from = URL(fileURLWithPath: pair[1]), to = URL(fileURLWithPath: pair[0])
            // 원래 자리에 같은 이름이 새로 생겼으면 덮어쓰지 않고 그대로 둔다
            guard FileManager.default.fileExists(atPath: from.path), !FileManager.default.fileExists(atPath: to.path) else { continue }
            if (try? FileManager.default.moveItem(at: from, to: to)) != nil { restored += 1 }
        }
        UserDefaults.standard.removeObject(forKey: undoKey)
        return restored
    }

    static var canUndo: Bool { UserDefaults.standard.array(forKey: undoKey) != nil }

    /// 명령·메뉴에서 부르는 형태: 실행하고 결과를 알려 준다.
    static func runAndReport() {
        DispatchQueue.global(qos: .utility).async {
            let result = run()
            DispatchQueue.main.async {
                let total = result.screenshots + result.downloads
                Toast.show(total == 0 ? "정리할 파일이 없습니다"
                                      : "스크린샷 \(result.screenshots)개, 다운로드 \(result.downloads)개를 정리했습니다",
                           symbol: "tray.full")
                SettingsModel.shared.bump()
            }
        }
    }

    /// "매일 자동으로"가 켜져 있으면 하루에 한 번 정리한다.
    static func startAutomatic() {
        let check = {
            guard ConfigStore.shared.config.tidyAuto,
                  UserDefaults.standard.string(forKey: lastRunKey) != dayStamp(Date()) else { return }
            DispatchQueue.global(qos: .utility).async { run() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: check)
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in check() }
    }

    private static func dayStamp(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func items(in folder: URL) -> [Tidy.Item] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .addedToDirectoryDateKey, .creationDateKey, .contentModificationDateKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys) else {
            return []
        }
        return entries.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            let arrived = values.addedToDirectoryDate ?? values.creationDate
            guard let date = [arrived, values.contentModificationDate].compactMap({ $0 }).max() else { return nil }
            return Tidy.Item(name: url.lastPathComponent, isDirectory: values.isDirectory ?? false, date: date)
        }
    }

    /// 같은 이름이 이미 있으면 "이름 2.png" 식으로 비켜 준다.
    private static func unique(_ url: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        for n in 2...9999 {
            let candidate = url.deletingLastPathComponent()
                .appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            if !fm.fileExists(atPath: candidate.path) { return candidate }
        }
        return url
    }
}
