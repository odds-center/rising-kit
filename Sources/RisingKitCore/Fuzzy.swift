import Foundation

/// 런처 검색 점수. 높을수록 잘 맞는다. 안 맞으면 nil.
public enum Fuzzy {
    public static func score(query: String, candidate: String) -> Int? {
        let q = normalize(query)
        let c = normalize(candidate)
        guard !q.isEmpty else { return 0 }
        guard !c.isEmpty else { return nil }

        if c == q { return 1000 }
        // 이름이 짧을수록(검색어가 이름의 더 큰 부분일수록) 위로: "chrome" 은
        // "Chrome Remote Desktop Host Uninstaller" 보다 "Google Chrome" 이 먼저다.
        let extra = min((c.count - q.count) * 3, 200)
        if c.hasPrefix(q) { return 900 - extra }
        // 단어 첫머리 일치: "studio" → "Android Studio"
        let words = c.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" || $0 == "." })
        if words.dropFirst().contains(where: { $0.hasPrefix(q) }) { return 850 - extra }
        // 머리글자 일치: "vsc" → "Visual Studio Code"
        if words.count > 1, String(words.compactMap(\.first)).hasPrefix(q) { return 700 }
        if c.contains(q) { return 600 }
        // 한글 초성 일치: "ㅋㅌ" → "카카오톡"
        if q.allSatisfy({ isChoseong($0) || $0 == " " }), choseong(of: c).contains(q) { return 550 }
        // 글자 순서만 맞는 경우: "gkrn" → "GitKraken"
        // 글자 사이가 너무 벌어지면 우연히 맞은 것이므로 버린다
        // 또 검색어 첫 글자가 이름이나 단어의 첫 글자여야 한다 ("ocr" 로 "Docker" 가 나오지 않게)
        if q.count >= 3, let first = q.first, c.first == first || words.contains(where: { $0.first == first }),
           let gaps = subsequenceGaps(q, in: c), gaps <= q.count * 2 { return 300 - gaps * 5 }
        return nil
    }

    static func normalize(_ s: String) -> String {
        s.precomposedStringWithCanonicalMapping.lowercased().trimmingCharacters(in: .whitespaces)
    }

    private static let choseongTable: [Character] = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")

    static func isChoseong(_ ch: Character) -> Bool { choseongTable.contains(ch) }

    /// 한글 음절은 초성으로 바꾸고 나머지 글자는 그대로 둔다.
    static func choseong(of s: String) -> String {
        String(s.map { ch -> Character in
            guard let u = ch.unicodeScalars.first, ch.unicodeScalars.count == 1,
                  (0xAC00...0xD7A3).contains(u.value) else { return ch }
            return choseongTable[Int((u.value - 0xAC00) / 588)]
        })
    }

    /// q 의 글자가 c 안에 순서대로 모두 나오면, 그 사이에 건너뛴 글자 수.
    private static func subsequenceGaps(_ q: String, in c: String) -> Int? {
        var gaps = 0
        var started = false
        var qi = q.startIndex
        for ch in c {
            guard qi < q.endIndex else { break }
            if ch == q[qi] {
                qi = q.index(after: qi)
                started = true
            } else if started {
                gaps += 1
            }
        }
        return qi == q.endIndex ? gaps : nil
    }
}
