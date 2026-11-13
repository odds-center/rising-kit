import Foundation

/// 런처에 입력한 날짜·시간 질문에 답한다. ("오늘", "내일", "3일 후", "2주 전", "지금", 유닉스 시각 …)
public enum DateQuery {
    public struct Answer: Equatable {
        /// 보여 주고 복사할 값
        public let text: String
        /// 무엇에 대한 답인지
        public let label: String
    }

    public static func answer(
        _ input: String, now: Date = Date(), timeZone: TimeZone = .current,
        locale: Locale = Locale(identifier: "ko_KR")
    ) -> Answer? {
        let q = input.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = locale

        func format(_ date: Date, _ pattern: String) -> String {
            let f = DateFormatter()
            f.calendar = calendar
            f.timeZone = timeZone
            f.locale = locale
            f.dateFormat = pattern
            return f.string(from: date)
        }
        func day(_ offset: Int, _ label: String) -> Answer? {
            guard let date = calendar.date(byAdding: .day, value: offset, to: now) else { return nil }
            return Answer(text: format(date, "yyyy년 M월 d일 EEEE"), label: label)
        }

        switch q {
        case "오늘", "today", "날짜", "date": return day(0, "오늘")
        case "내일", "tomorrow": return day(1, "내일")
        case "모레": return day(2, "모레")
        case "어제", "yesterday": return day(-1, "어제")
        case "그저께", "그제": return day(-2, "그저께")
        case "지금", "시간", "now", "time":
            return Answer(text: format(now, "yyyy-MM-dd HH:mm:ss"), label: "현재 시각")
        case "주", "주차", "week":
            return Answer(text: "\(calendar.component(.yearForWeekOfYear, from: now))년 \(isoWeek(now, timeZone))주차", label: "이번 주")
        case "타임스탬프", "timestamp", "unix", "epoch":
            return Answer(text: String(Int(now.timeIntervalSince1970)), label: "유닉스 시각")
        default: break
        }

        // 유닉스 시각 → 날짜 (10자리 초, 13자리 밀리초)
        if q.count == 10 || q.count == 13, q.allSatisfy(\.isNumber), let value = Double(q) {
            let date = Date(timeIntervalSince1970: q.count == 13 ? value / 1000 : value)
            return Answer(text: format(date, "yyyy-MM-dd HH:mm:ss"), label: "유닉스 시각 \(q)")
        }

        // "3일 후", "2주 전", "10일뒤", "in 5 days", "3 days ago"
        if let (amount, unit, forward) = relative(q) {
            let days = unit == .week ? amount * 7 : amount
            let unitName = unit == .week ? "주" : "일"
            return day(forward ? days : -days, "\(amount)\(unitName) \(forward ? "후" : "전")")
        }
        return nil
    }

    private enum Unit { case day, week }

    private static func relative(_ q: String) -> (Int, Unit, Bool)? {
        let compact = q.replacingOccurrences(of: " ", with: "")
        let digits = compact.prefix(while: \.isNumber)
        if !digits.isEmpty, let amount = Int(digits), amount <= 100_000 {
            let rest = compact.dropFirst(digits.count)
            for (suffixes, unit, forward) in [
                (["일후", "일뒤", "daysfromnow", "dayslater"], Unit.day, true),
                (["일전", "daysago", "dayago"], Unit.day, false),
                (["주후", "주뒤", "weeksfromnow", "weekslater"], Unit.week, true),
                (["주전", "weeksago", "weekago"], Unit.week, false),
            ] where suffixes.contains(String(rest)) {
                return (amount, unit, forward)
            }
        }
        // "in 5 days", "in 2 weeks"
        if compact.hasPrefix("in") {
            let body = compact.dropFirst(2)
            let number = body.prefix(while: \.isNumber)
            if let amount = Int(number), amount <= 100_000 {
                switch String(body.dropFirst(number.count)) {
                case "day", "days": return (amount, .day, true)
                case "week", "weeks": return (amount, .week, true)
                default: break
                }
            }
        }
        return nil
    }

    private static func isoWeek(_ date: Date, _ timeZone: TimeZone) -> Int {
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = timeZone
        return iso.component(.weekOfYear, from: date)
    }
}
