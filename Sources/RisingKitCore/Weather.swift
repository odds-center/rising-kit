import Foundation

/// 날씨 종류. 노르웨이 기상청(met.no) 예보의 symbol_code 를 묶은 것.
public enum WeatherKind: String {
    case clear, fair, partlyCloudy, cloudy, fog, lightRain, rain, heavyRain, sleet, snow, thunder, unknown

    /// "partlycloudy_night", "heavyrainshowersandthunder_day" 같은 코드에서 종류를 뽑는다.
    public init(symbolCode: String) {
        let code = symbolCode.split(separator: "_").first.map(String.init) ?? symbolCode
        if code.contains("thunder") { self = .thunder }
        else if code.contains("sleet") { self = .sleet }
        else if code.contains("snow") { self = .snow }
        else if code.hasPrefix("heavyrain") { self = .heavyRain }
        else if code.hasPrefix("lightrain") { self = .lightRain }
        else if code.hasPrefix("rain") { self = .rain }
        else if code == "fog" { self = .fog }
        else if code == "cloudy" { self = .cloudy }
        else if code == "partlycloudy" { self = .partlyCloudy }
        else if code == "fair" { self = .fair }
        else if code == "clearsky" { self = .clear }
        else { self = .unknown }
    }

    public var label: String {
        switch self {
        case .clear: return "맑음"
        case .fair: return "대체로 맑음"
        case .partlyCloudy: return "구름 조금"
        case .cloudy: return "흐림"
        case .fog: return "안개"
        case .lightRain: return "약한 비"
        case .rain: return "비"
        case .heavyRain: return "강한 비"
        case .sleet: return "진눈깨비"
        case .snow: return "눈"
        case .thunder: return "뇌우"
        case .unknown: return "알 수 없음"
        }
    }

    /// 메뉴바·메뉴에 쓸 SF Symbol 이름.
    public func sfSymbol(night: Bool) -> String {
        switch self {
        case .clear: return night ? "moon.stars.fill" : "sun.max.fill"
        case .fair, .partlyCloudy: return night ? "cloud.moon.fill" : "cloud.sun.fill"
        case .cloudy: return "cloud.fill"
        case .fog: return "cloud.fog.fill"
        case .lightRain: return "cloud.drizzle.fill"
        case .rain: return "cloud.rain.fill"
        case .heavyRain: return "cloud.heavyrain.fill"
        case .sleet: return "cloud.sleet.fill"
        case .snow: return "cloud.snow.fill"
        case .thunder: return "cloud.bolt.rain.fill"
        case .unknown: return "questionmark.circle"
        }
    }
}

public struct WeatherReport {
    public struct Day: Equatable {
        /// 현지 날짜 "2026-11-13"
        public let date: String
        public let kind: WeatherKind
        public let low: Double
        public let high: Double
        /// 그날 예상 강수량 (mm)
        public let precipitation: Double
    }

    public let temperature: Double
    public let humidity: Double
    /// m/s
    public let wind: Double
    public let kind: WeatherKind
    public let isNight: Bool
    /// 오늘부터 최대 4일
    public let days: [Day]

    public enum ParseError: Error { case empty }

    /// met.no locationforecast/2.0/compact 응답을 읽는다.
    /// `timeZone` 은 그 지역의 시간대(하루를 나누는 기준), `now` 는 현재 시각.
    public static func parse(_ data: Data, timeZone: TimeZone, now: Date) throws -> WeatherReport {
        struct Response: Decodable {
            struct Properties: Decodable { let timeseries: [Entry] }
            struct Entry: Decodable { let time: Date; let data: EntryData }
            struct EntryData: Decodable {
                let instant: Instant
                let next_1_hours: Period?
                let next_6_hours: Period?
                let next_12_hours: Period?
            }
            struct Instant: Decodable { let details: [String: Double] }
            struct Period: Decodable {
                struct Summary: Decodable { let symbol_code: String }
                let summary: Summary?
                let details: [String: Double]?
            }
            let properties: Properties
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let series = try decoder.decode(Response.self, from: data).properties.timeseries
        // 지금과 가장 가까운 시각의 항목이 현재 날씨
        guard let current = series.min(by: {
            abs($0.time.timeIntervalSince(now)) < abs($1.time.timeIntervalSince(now))
        }) else { throw ParseError.empty }

        func symbol(_ e: Response.Entry) -> String? {
            (e.data.next_1_hours ?? e.data.next_6_hours ?? e.data.next_12_hours)?.summary?.symbol_code
        }
        let currentSymbol = symbol(current) ?? ""

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: now)

        var order: [String] = []
        var groups: [String: [Response.Entry]] = [:]
        for entry in series {
            let key = formatter.string(from: entry.time)
            guard key >= today else { continue }
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(entry)
        }
        let days: [Day] = order.prefix(4).compactMap { key in
            guard let entries = groups[key] else { return nil }
            let temps = entries.compactMap { $0.data.instant.details["air_temperature"] }
            guard let low = temps.min(), let high = temps.max() else { return nil }
            // 그날을 대표하는 날씨는 정오에 가장 가까운 시각의 예보
            let noon = entries.min(by: {
                abs(calendar.component(.hour, from: $0.time) - 12) < abs(calendar.component(.hour, from: $1.time) - 12)
            })
            let code = noon.flatMap { ($0.data.next_6_hours ?? $0.data.next_1_hours ?? $0.data.next_12_hours)?.summary?.symbol_code }
            // 1시간 단위 값이 있으면 그것을, 없으면(먼 날짜) 6시간 단위 값을 더한다
            let rain = entries.reduce(0.0) { sum, e in
                sum + ((e.data.next_1_hours ?? e.data.next_6_hours)?.details?["precipitation_amount"] ?? 0)
            }
            return Day(date: key, kind: WeatherKind(symbolCode: code ?? ""), low: low, high: high,
                       precipitation: (rain * 10).rounded() / 10)
        }

        let details = current.data.instant.details
        return WeatherReport(
            temperature: details["air_temperature"] ?? .nan,
            humidity: details["relative_humidity"] ?? .nan,
            wind: details["wind_speed"] ?? .nan,
            kind: WeatherKind(symbolCode: currentSymbol),
            isNight: currentSymbol.hasSuffix("_night"),
            days: days)
    }
}

/// 도시 검색 결과 하나.
public struct GeoPlace: Equatable {
    public let name: String
    public let region: String
    public let country: String
    public let latitude: Double
    public let longitude: Double
    public let timeZone: String

    /// Open-Meteo 지오코딩 응답에서 가장 그럴듯한 곳을 고른다:
    /// 산·강 같은 지형이 아닌 거주지를 우선하고, 그중 인구가 많은 곳.
    public static func best(from data: Data) -> GeoPlace? {
        struct Response: Decodable {
            struct Result: Decodable {
                let name: String
                let latitude: Double
                let longitude: Double
                let feature_code: String?
                let population: Int?
                let admin1: String?
                let country: String?
                let timezone: String?
            }
            let results: [Result]?
        }
        guard let results = (try? JSONDecoder().decode(Response.self, from: data))?.results, !results.isEmpty else {
            return nil
        }
        func rank(_ r: Response.Result) -> (Int, Int) {
            ((r.feature_code ?? "").hasPrefix("PPL") ? 1 : 0, r.population ?? 0)
        }
        let best = results.enumerated().max { a, b in
            let (ra, rb) = (rank(a.element), rank(b.element))
            // 순위가 같으면 검색 결과에서 먼저 나온 쪽
            return ra != rb ? ra < rb : a.offset > b.offset
        }!.element
        return GeoPlace(name: best.name, region: best.admin1 ?? "", country: best.country ?? "",
                        latitude: best.latitude, longitude: best.longitude, timeZone: best.timezone ?? "")
    }
}
