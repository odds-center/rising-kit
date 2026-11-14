import Foundation

/// "0.12.0" 같은 버전 문자열 비교.
public enum AppVersion {
    /// `a` 가 `b` 보다 새 버전인지. 앞의 "v" 는 무시하고, 숫자가 아닌 꼬리("-beta" 등)는 버린다.
    public static func isNewer(_ a: String, than b: String) -> Bool {
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    static func parts(_ s: String) -> [Int] {
        var text = s.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }
        return text.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }
}
