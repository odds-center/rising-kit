import Foundation

/// 오래된 스크린샷과 다운로드 파일을 달별 폴더로 옮길 계획을 세운다. (옮기기만 하고 지우지 않는다.)
public enum Tidy {
    public struct Item: Equatable {
        public let name: String
        public let isDirectory: Bool
        /// 그 폴더에 들어온 날(없으면 만든 날)과 마지막으로 고친 날 중 늦은 쪽
        public let date: Date

        public init(name: String, isDirectory: Bool, date: Date) {
            self.name = name; self.isDirectory = isDirectory; self.date = date
        }
    }

    public struct Move: Equatable {
        public let name: String
        /// 옮겨 갈 달 폴더 이름 "2026-11"
        public let folder: String
    }

    /// 정리한 파일을 모아 두는 폴더 이름 (이 폴더 자체는 다시 정리하지 않는다)
    public static let screenshotArchive = "스크린샷 모음"
    public static let downloadArchive = "지난 다운로드"

    /// macOS 가 붙이는 이름의 스크린샷·화면 기록인지 (사용자가 이름을 바꾼 파일은 건드리지 않는다).
    public static func isScreenshot(_ name: String) -> Bool {
        let lower = name.precomposedStringWithCanonicalMapping.lowercased()
        let prefixes = ["스크린샷 ", "screenshot ", "화면 기록 ", "screen recording ", "스크린샷_", "screenshot_"]
        guard prefixes.contains(where: lower.hasPrefix) else { return false }
        let ext = (lower as NSString).pathExtension
        return ["png", "jpg", "jpeg", "heic", "tiff", "gif", "mov", "mp4"].contains(ext)
    }

    /// 아직 받는 중인 파일
    public static func isInProgressDownload(_ name: String) -> Bool {
        let ext = (name.lowercased() as NSString).pathExtension
        return ["crdownload", "download", "part", "partial", "tmp", "opdownload"].contains(ext)
    }

    public static func monthFolder(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    /// `days` 일보다 오래된 스크린샷.
    public static func planScreenshots(_ items: [Item], olderThanDays days: Int, now: Date, calendar: Calendar) -> [Move] {
        items.filter { !$0.isDirectory && isScreenshot($0.name) && isOld($0.date, days, now) }
            .map { Move(name: $0.name, folder: monthFolder($0.date, calendar: calendar)) }
    }

    /// `days` 일보다 오래된 다운로드 파일. 폴더(앱이 받는 폴더로 쓰고 있을 수 있다), 숨김 파일,
    /// 받는 중인 파일은 제외.
    public static func planDownloads(_ items: [Item], olderThanDays days: Int, now: Date, calendar: Calendar) -> [Move] {
        items.filter { item in
            let name = item.name.precomposedStringWithCanonicalMapping
            return !item.isDirectory && !name.hasPrefix(".")
                && !isInProgressDownload(name) && isOld(item.date, days, now)
        }
        .map { Move(name: $0.name, folder: monthFolder($0.date, calendar: calendar)) }
    }

    private static func isOld(_ date: Date, _ days: Int, _ now: Date) -> Bool {
        now.timeIntervalSince(date) > Double(max(days, 0)) * 86400
    }
}
