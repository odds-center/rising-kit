import CryptoKit
import Foundation

/// 런처에서 바로 쓰는 개발용 변환: UUID, Base64, URL 인코딩, 해시, 색상.
public enum DevTools {
    public struct Answer: Equatable {
        public let text: String
        public let label: String
        /// 색상 답이면 0~1 범위의 (빨강, 초록, 파랑) — 색 견본을 그릴 때 쓴다
        public let color: RGB?

        public init(_ text: String, _ label: String, color: RGB? = nil) {
            self.text = text; self.label = label; self.color = color
        }
    }

    public struct RGB: Equatable {
        public let r: Double, g: Double, b: Double
    }

    /// 검색어가 개발용 명령이면 답을 돌려준다. 아니면 빈 배열.
    public static func answers(_ input: String, makeUUID: () -> String = { UUID().uuidString }) -> [Answer] {
        let q = input.trimmingCharacters(in: .whitespaces)
        let lower = q.lowercased()

        if lower == "uuid" {
            let id = makeUUID()
            return [Answer(id.lowercased(), "새 UUID"), Answer(id.uppercased(), "새 UUID (대문자)")]
        }
        if let color = colorAnswers(q) { return color }

        // "명령 내용" 꼴
        guard let space = q.firstIndex(of: " ") else { return [] }
        let command = q[..<space].lowercased()
        let body = String(q[q.index(after: space)...]).trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { return [] }
        let data = Data(body.utf8)

        switch command {
        case "b64", "base64":
            return [Answer(data.base64EncodedString(), "Base64 인코딩")]
        case "b64d", "base64d", "unbase64":
            // 줄바꿈·패딩 누락을 너그럽게 받아 준다
            var cleaned = body.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: " ", with: "")
            while cleaned.count % 4 != 0 { cleaned += "=" }
            guard let decoded = Data(base64Encoded: cleaned), let text = String(data: decoded, encoding: .utf8) else {
                return []
            }
            return [Answer(text, "Base64 디코딩")]
        case "urlencode", "urle":
            var allowed = CharacterSet.alphanumerics
            allowed.insert(charactersIn: "-._~")
            guard let encoded = body.addingPercentEncoding(withAllowedCharacters: allowed) else { return [] }
            return [Answer(encoded, "URL 인코딩")]
        case "urldecode", "urld":
            guard let decoded = body.removingPercentEncoding, decoded != body else { return [] }
            return [Answer(decoded, "URL 디코딩")]
        case "md5":
            return [Answer(hex(Insecure.MD5.hash(data: data)), "MD5")]
        case "sha1":
            return [Answer(hex(Insecure.SHA1.hash(data: data)), "SHA-1")]
        case "sha256", "sha":
            return [Answer(hex(SHA256.hash(data: data)), "SHA-256")]
        default:
            return []
        }
    }

    private static func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - 색상

    /// "#ff8800", "#f80", "rgb(255, 136, 0)" 를 서로 다른 표기로 바꾼다.
    static func colorAnswers(_ q: String) -> [Answer]? {
        guard let rgb = parseColor(q) else { return nil }
        let r = Int((rgb.r * 255).rounded()), g = Int((rgb.g * 255).rounded()), b = Int((rgb.b * 255).rounded())
        let hexText = String(format: "#%02X%02X%02X", r, g, b)
        let (h, s, l) = hsl(rgb)
        return [
            Answer(hexText, "HEX", color: rgb),
            Answer("rgb(\(r), \(g), \(b))", "RGB", color: rgb),
            Answer("hsl(\(h), \(s)%, \(l)%)", "HSL", color: rgb),
        ]
    }

    public static func parseColor(_ input: String) -> RGB? {
        let q = input.trimmingCharacters(in: .whitespaces).lowercased()
        if q.hasPrefix("#") {
            var digits = String(q.dropFirst())
            guard digits.allSatisfy(\.isHexDigit) else { return nil }
            if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
            guard digits.count == 6, let value = Int(digits, radix: 16) else { return nil }
            return RGB(r: Double((value >> 16) & 0xFF) / 255, g: Double((value >> 8) & 0xFF) / 255,
                       b: Double(value & 0xFF) / 255)
        }
        if q.hasPrefix("rgb("), q.hasSuffix(")") {
            let parts = q.dropFirst(4).dropLast().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            let values = parts.compactMap { Int($0) }
            guard parts.count == 3, values.count == 3, values.allSatisfy({ (0...255).contains($0) }) else { return nil }
            return RGB(r: Double(values[0]) / 255, g: Double(values[1]) / 255, b: Double(values[2]) / 255)
        }
        return nil
    }

    static func hsl(_ c: RGB) -> (Int, Int, Int) {
        let maxV = max(c.r, c.g, c.b), minV = min(c.r, c.g, c.b)
        let l = (maxV + minV) / 2
        guard maxV != minV else { return (0, 0, Int((l * 100).rounded())) }
        let d = maxV - minV
        let s = l > 0.5 ? d / (2 - maxV - minV) : d / (maxV + minV)
        var h: Double
        if maxV == c.r { h = (c.g - c.b) / d + (c.g < c.b ? 6 : 0) }
        else if maxV == c.g { h = (c.b - c.r) / d + 2 }
        else { h = (c.r - c.g) / d + 4 }
        h *= 60
        return (Int(h.rounded()) % 360, Int((s * 100).rounded()), Int((l * 100).rounded()))
    }
}

/// 어떤 프로세스가 포트를 열고 있는지.
public struct PortUser: Equatable {
    public let port: Int
    public let pid: Int
    public let command: String
}

public enum PortParser {
    /// 검색어가 포트 질문이면 포트 번호를, "ports" 처럼 전체를 묻는 것이면 0 을 돌려준다.
    /// ":3000", "port 3000", "포트 3000", "ports", "포트"
    public static func query(_ input: String) -> Int? {
        let q = input.trimmingCharacters(in: .whitespaces).lowercased()
        if q == "ports" || q == "포트" || q == "port" { return 0 }
        var rest: Substring
        if q.hasPrefix(":") { rest = q.dropFirst() }
        else if q.hasPrefix("port ") { rest = q.dropFirst(5) }
        else if q.hasPrefix("포트 ") { rest = q.dropFirst(3) }
        else { return nil }
        rest = rest.drop(while: { $0 == " " })
        guard !rest.isEmpty, rest.allSatisfy(\.isNumber), let port = Int(rest), (1...65535).contains(port) else {
            return nil
        }
        return port
    }

    /// `lsof -nP -iTCP -sTCP:LISTEN` 출력을 읽는다. 같은 프로세스·포트는 한 번만 (IPv4·IPv6 중복 제거).
    public static func parse(_ lsofOutput: String) -> [PortUser] {
        var seen = Set<String>()
        var out: [PortUser] = []
        for line in lsofOutput.split(separator: "\n").dropFirst() {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            // COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME (LISTEN)
            guard fields.count >= 9, let pid = Int(fields[1]) else { continue }
            let name = fields[8]
            guard let colon = name.lastIndex(of: ":"), let port = Int(name[name.index(after: colon)...]) else { continue }
            guard seen.insert("\(pid):\(port)").inserted else { continue }
            // lsof 는 공백을 \x20 으로 적는다
            out.append(PortUser(port: port, pid: pid, command: fields[0].replacingOccurrences(of: "\\x20", with: " ")))
        }
        return out.sorted { $0.port != $1.port ? $0.port < $1.port : $0.pid < $1.pid }
    }
}
