import Foundation

/// 복사했던 항목 하나.
public struct ClipItem: Codable, Equatable, Identifiable {
    public enum Kind: String, Codable { case text, file, image }

    public let id: String
    public let kind: Kind
    /// 글이면 그 내용, 파일이면 경로들(줄바꿈으로 구분), 이미지면 "1200 × 800" 같은 설명
    public let text: String
    /// 이미지를 저장해 둔 파일 이름 (이미지일 때만)
    public let imageFile: String?
    public var date: Date

    public init(id: String, kind: Kind, text: String, imageFile: String? = nil, date: Date) {
        self.id = id; self.kind = kind; self.text = text; self.imageFile = imageFile; self.date = date
    }

    /// 목록에 보여 줄 한 줄 (앞뒤 공백을 빼고 줄바꿈은 ⏎ 로)
    public var preview: String {
        switch kind {
        case .image: return "이미지 \(text)"
        case .file:
            let names = text.split(separator: "\n").map { ($0 as NSString).lastPathComponent }
            return names.count == 1 ? names[0] : "\(names[0]) 외 \(names.count - 1)개"
        case .text:
            let flat = text.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ⏎ ")
                .replacingOccurrences(of: "\t", with: " ")
            return flat.count > 200 ? String(flat.prefix(200)) + "…" : flat
        }
    }
}

/// 클립보드 기록. 개수와 보관 기간에 한도가 있고, 같은 내용을 다시 복사하면 맨 위로 올린다.
public struct ClipHistory: Codable, Equatable {
    public static let maxItems = 200
    public static let maxAge: TimeInterval = 7 * 24 * 60 * 60
    /// 이보다 긴 글은 저장하지 않는다 (큰 파일 내용을 통째로 복사한 경우)
    public static let maxTextLength = 100_000

    /// 최근 것이 앞
    public private(set) var items: [ClipItem] = []

    public init() {}

    /// 새로 복사한 항목을 넣는다. 한도 때문에 빠진 항목들을 돌려준다 (이미지 파일 정리용).
    @discardableResult
    public mutating func add(_ item: ClipItem) -> [ClipItem] {
        if item.kind == .text {
            let trimmed = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, item.text.count <= Self.maxTextLength else { return [] }
        }
        var removed: [ClipItem] = []
        // 같은 내용이 이미 있으면 그것을 빼고 새로 맨 위에 둔다
        if item.kind != .image, let index = items.firstIndex(where: { $0.kind == item.kind && $0.text == item.text }) {
            removed.append(items.remove(at: index))
        }
        items.insert(item, at: 0)
        if items.count > Self.maxItems {
            removed += items[Self.maxItems...]
            items.removeSubrange(Self.maxItems...)
        }
        return removed
    }

    /// 보관 기간이 지난 항목을 지우고 그 항목들을 돌려준다.
    @discardableResult
    public mutating func prune(now: Date) -> [ClipItem] {
        let expired = items.filter { now.timeIntervalSince($0.date) > Self.maxAge }
        items.removeAll { now.timeIntervalSince($0.date) > Self.maxAge }
        return expired
    }

    @discardableResult
    public mutating func remove(id: String) -> ClipItem? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        return items.remove(at: index)
    }

    @discardableResult
    public mutating func clear() -> [ClipItem] {
        let all = items
        items = []
        return all
    }

    /// 검색어가 들어 있는 항목 (대소문자 구분 없음). 검색어가 비면 전부.
    public func search(_ query: String) -> [ClipItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return items }
        return items.filter { $0.text.localizedCaseInsensitiveContains(q) }
    }
}
