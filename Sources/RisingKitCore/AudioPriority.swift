import Foundation

/// 소리 출력 장치를 정해 둔 순서대로 고르는 규칙.
public enum AudioPriority {
    /// 우선순위 목록에서, 지금 연결돼 있는 것 중 가장 앞의 장치.
    /// 목록의 장치가 하나도 연결돼 있지 않으면 nil (그때는 건드리지 않는다).
    public static func preferred(priority: [String], available: [String]) -> String? {
        priority.first { available.contains($0) }
    }

    /// 바꿔야 할 장치. 이미 그 장치를 쓰고 있으면 nil.
    public static func change(priority: [String], available: [String], current: String?) -> String? {
        guard let target = preferred(priority: priority, available: available), target != current else { return nil }
        return target
    }

    /// 사용자가 직접 고른 장치를 목록 맨 앞으로 옮긴다 (없으면 추가).
    public static func promote(_ uid: String, in priority: [String]) -> [String] {
        [uid] + priority.filter { $0 != uid }
    }

    /// 목록에서 한 칸 위/아래로 옮긴다.
    public static func move(_ uid: String, by offset: Int, in priority: [String]) -> [String] {
        guard let index = priority.firstIndex(of: uid) else { return priority }
        let target = min(max(index + offset, 0), priority.count - 1)
        var out = priority
        out.remove(at: index)
        out.insert(uid, at: target)
        return out
    }
}
