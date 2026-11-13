import Foundation

/// 런처 검색창에 입력한 수식을 계산한다. 수식이 아니면 nil.
/// 지원: + - * / % ^, 괄호, 단항 부호, 소수, × ÷ 기호, 천 단위 쉼표.
public enum Calculator {
    public static func evaluate(_ input: String) -> Double? {
        var parser = Parser(input)
        guard let value = parser.parseAll(), parser.sawOperator, value.isFinite else { return nil }
        return value
    }

    /// 결과를 사람이 읽기 좋게: 정수는 정수로, 소수는 불필요한 0 없이.
    public static func format(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 {
            return String(format: "%.0f", value)
        }
        var s = String(format: "%.10f", value)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    private struct Parser {
        private let chars: [Character]
        private var pos = 0
        var sawOperator = false

        init(_ s: String) {
            chars = Array(s.replacingOccurrences(of: ",", with: "")
                .replacingOccurrences(of: "×", with: "*")
                .replacingOccurrences(of: "÷", with: "/"))
        }

        mutating func parseAll() -> Double? {
            guard let v = expression() else { return nil }
            skipSpaces()
            return pos == chars.count ? v : nil
        }

        private mutating func skipSpaces() {
            while pos < chars.count, chars[pos] == " " { pos += 1 }
        }

        private mutating func take(_ c: Character) -> Bool {
            skipSpaces()
            guard pos < chars.count, chars[pos] == c else { return false }
            pos += 1
            return true
        }

        private mutating func expression() -> Double? {
            guard var left = term() else { return nil }
            while true {
                if take("+") {
                    guard let r = term() else { return nil }
                    left += r; sawOperator = true
                } else if take("-") {
                    guard let r = term() else { return nil }
                    left -= r; sawOperator = true
                } else { return left }
            }
        }

        private mutating func term() -> Double? {
            guard var left = unary() else { return nil }
            while true {
                if take("*") {
                    guard let r = unary() else { return nil }
                    left *= r; sawOperator = true
                } else if take("/") {
                    guard let r = unary(), r != 0 else { return nil }
                    left /= r; sawOperator = true
                } else if take("%") {
                    guard let r = unary(), r != 0 else { return nil }
                    left = left.truncatingRemainder(dividingBy: r); sawOperator = true
                } else { return left }
            }
        }

        private mutating func unary() -> Double? {
            if take("-") { return unary().map { -$0 } }
            if take("+") { return unary() }
            return power()
        }

        private mutating func power() -> Double? {
            guard let base = primary() else { return nil }
            if take("^") {
                guard let exp = unary() else { return nil }  // 오른쪽 결합
                sawOperator = true
                return pow(base, exp)
            }
            return base
        }

        private mutating func primary() -> Double? {
            if take("(") {
                guard let v = expression(), take(")") else { return nil }
                return v
            }
            skipSpaces()
            let start = pos
            while pos < chars.count, chars[pos].isNumber || chars[pos] == "." { pos += 1 }
            guard pos > start else { return nil }
            return Double(String(chars[start..<pos]))
        }
    }
}
