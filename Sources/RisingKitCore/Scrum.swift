import Foundation

/// 데일리 스크럼 초안: 직전 근무일에 남긴 커밋을 프로젝트별로 모아 글로 만든다.
public enum Scrum {
    public struct Commit: Equatable {
        public let hash: String
        public let subject: String
        public let project: String

        public init(hash: String, subject: String, project: String) {
            self.hash = hash; self.subject = subject; self.project = project
        }
    }

    public struct LogEntry: Equatable {
        public let hash: String
        public let author: String
        public let email: String
        public let subject: String
    }

    /// "내 커밋"을 가려내는 기준: 내 이름들과 이메일들.
    public struct Identity: Equatable {
        public var names: Set<String>
        public var emails: Set<String>

        public init(names: Set<String>, emails: Set<String>) {
            self.names = Set(names.map { $0.lowercased() }.filter { !$0.isEmpty })
            self.emails = Set(emails.map { $0.lowercased() }.filter { !$0.isEmpty })
        }
    }

    /// 이 커밋의 작성자가 나인지.
    /// 이메일이 내 것이거나, 이름이 내 이름과 같거나, GitHub 익명 주소
    /// (`12345+이름@users.noreply.github.com`)의 이름 부분이 내 이름이면 내 커밋이다.
    public static func isMine(author: String, email: String, identity: Identity) -> Bool {
        let mail = email.lowercased()
        if identity.emails.contains(mail) { return true }
        if identity.names.contains(author.lowercased()) { return true }
        let suffix = "@users.noreply.github.com"
        if mail.hasSuffix(suffix) {
            let local = String(mail.dropLast(suffix.count))
            let login = local.split(separator: "+").last.map(String.init) ?? local
            if identity.names.contains(login) { return true }
        }
        return false
    }

    /// 원격 주소에서 "소유자/이름"을 뽑는다.
    /// "git@github.com:acme/web.git", "https://github.com/acme/web" → ("acme", "web")
    public static func repositoryKey(remote: String) -> (owner: String, name: String)? {
        var s = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasSuffix("/") { s.removeLast() }
        if s.hasSuffix(".git") { s.removeLast(4) }
        let parts = s.split(whereSeparator: { $0 == "/" || $0 == ":" })
        guard parts.count >= 2, let name = parts.last, !name.isEmpty else { return nil }
        let owner = parts[parts.count - 2]
        // "https://host/name" 처럼 소유자 자리에 호스트가 오는 경우는 소유자가 없는 것으로 본다
        guard !owner.isEmpty, !owner.contains("."), !owner.contains("@") else { return nil }
        return (String(owner), String(name))
    }

    /// `date` 바로 전 근무일의 시작 시각 (월요일이면 금요일, 주말이면 금요일).
    public static func previousWorkday(before date: Date, calendar: Calendar) -> Date {
        var day = calendar.startOfDay(for: date)
        repeat {
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        } while calendar.isDateInWeekend(day)
        return day
    }

    /// "[26.11.12 (목)]"
    public static func header(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .weekday], from: date)
        let weekdays = ["일", "월", "화", "수", "목", "금", "토"]
        let weekday = weekdays[((c.weekday ?? 1) - 1) % 7]
        return String(format: "[%02d.%02d.%02d (%@)]", (c.year ?? 0) % 100, c.month ?? 0, c.day ?? 0, weekday)
    }

    /// 커밋 제목에서 스크럼에 필요 없는 머리말을 뗀다:
    /// "feat(api): 로그인" → "로그인", "0.2.6: 버튼 이동" → "버튼 이동", "[web] 수정" → "수정"
    public static func cleanSubject(_ subject: String) -> String {
        var s = subject.trimmingCharacters(in: .whitespaces)
        // 관례적 커밋 종류
        if let colon = s.firstIndex(of: ":") {
            let head = s[..<colon].lowercased()
            let type = head.split(separator: "(").first.map(String.init)?.replacingOccurrences(of: "!", with: "") ?? ""
            let types: Set<String> = ["feat", "fix", "chore", "docs", "refactor", "test", "style", "perf", "build", "ci", "revert", "wip", "hotfix"]
            let isVersion = !head.isEmpty && head.allSatisfy { $0.isNumber || $0 == "." || $0 == "v" } && head.contains(".")
            if types.contains(type) || isVersion {
                s = String(s[s.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            }
        }
        // 대괄호 꼬리표
        if s.hasPrefix("["), let close = s.firstIndex(of: "]"), s.distance(from: s.startIndex, to: close) <= 20 {
            let rest = String(s[s.index(after: close)...]).trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty { s = rest }
        }
        return s.isEmpty ? subject.trimmingCharacters(in: .whitespaces) : s
    }

    /// `git log --format=%x1e%H%x09%an%x09%ae%x09%s` 출력을 읽는다.
    public static func parseLog(_ output: String) -> [LogEntry] {
        output.split(separator: "\u{1e}").compactMap { block in
            let line = block.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
            // 제목에 탭이 있어도 잘리지 않게 앞의 세 칸만 나눈다
            let fields = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 4, fields[0].count >= 7, fields[0].allSatisfy(\.isHexDigit) else { return nil }
            return LogEntry(hash: fields[0], author: fields[1], email: fields[2], subject: fields[3])
        }
    }

    /// 스크럼 글을 만든다. 프로젝트는 커밋이 많은 순서, 같은 제목은 한 번만.
    public static func compose(
        doneDate: Date, done: [Commit], todayDate: Date, today: [Commit], calendar: Calendar, maxPerProject: Int = 8
    ) -> String {
        var out = [header(doneDate, calendar: calendar)]
        out += lines(done, maxPerProject: maxPerProject, empty: "(커밋 없음)")
        out.append("")
        out.append(header(todayDate, calendar: calendar))
        out += lines(today, maxPerProject: maxPerProject, empty: "")
        return out.joined(separator: "\n").trimmingCharacters(in: .newlines) + "\n"
    }

    /// 한 줄에 읽기 좋게 긴 제목은 줄인다.
    static func shorten(_ subject: String, limit: Int = 80) -> String {
        subject.count > limit ? String(subject.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…" : subject
    }

    private static func lines(_ commits: [Commit], maxPerProject: Int, empty: String) -> [String] {
        guard !commits.isEmpty else { return empty.isEmpty ? [] : [empty] }
        var order: [String] = []
        var subjects: [String: [String]] = [:]
        for commit in commits {
            let subject = shorten(cleanSubject(commit.subject))
            if subjects[commit.project] == nil { order.append(commit.project) }
            if subjects[commit.project]?.contains(subject) != true {
                subjects[commit.project, default: []].append(subject)
            }
        }
        // 커밋이 많은 프로젝트부터 (같으면 먼저 나온 순서)
        let sorted = order.enumerated().sorted {
            let (a, b) = (subjects[$0.element]?.count ?? 0, subjects[$1.element]?.count ?? 0)
            return a != b ? a > b : $0.offset < $1.offset
        }.map(\.element)
        var out: [String] = []
        for project in sorted {
            let all = subjects[project] ?? []
            for subject in all.prefix(maxPerProject) { out.append("\(project) - \(subject)") }
            if all.count > maxPerProject { out.append("\(project) - 외 \(all.count - maxPerProject)건") }
        }
        return out
    }
}
