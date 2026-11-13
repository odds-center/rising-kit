import AppKit
import RisingKitCore

/// 날씨를 볼 도시. 설정에 저장된다.
struct WeatherLocation: Codable, Equatable {
    var name: String
    var latitude: Double
    var longitude: Double
    var timeZone: String

    static let seoul = WeatherLocation(name: "서울", latitude: 37.5665, longitude: 126.978, timeZone: "Asia/Seoul")
}

/// 현재 날씨와 예보를 받아 온다.
/// 예보는 노르웨이 기상청(api.met.no), 도시 검색은 Open-Meteo 지오코딩을 쓴다. 둘 다 키가 필요 없다.
/// 밖으로 나가는 정보는 도시 좌표(소수 둘째 자리까지)와 검색한 도시 이름뿐이다.
final class WeatherService {
    static let shared = WeatherService()

    private(set) var report: WeatherReport?
    private(set) var updatedAt: Date?
    private(set) var lastError: String?
    /// 새 날씨를 받았거나 실패했을 때 메인 스레드에서 호출된다.
    var onUpdate: (() -> Void)?

    private var timer: Timer?
    private var loading = false

    var location: WeatherLocation { ConfigStore.shared.config.weather ?? .seoul }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 20 * 60, repeats: true) { [weak self] _ in self?.refresh() }
        // 잠자기에서 깨어나면 오래된 날씨일 수 있다
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self?.refresh() }
        }
    }

    /// 마지막으로 받은 지 15분이 넘었으면 다시 받는다 (메뉴를 열 때).
    func refreshIfStale() {
        if let updatedAt, Date().timeIntervalSince(updatedAt) < 15 * 60 { return }
        refresh()
    }

    func refresh() {
        guard !loading else { return }
        loading = true
        let location = self.location
        DispatchQueue.global(qos: .utility).async {
            let result = Self.fetch(location)
            DispatchQueue.main.async {
                self.loading = false
                // 받는 사이에 도시가 바뀌었으면 버리고 새 도시로 다시 받는다
                guard location == self.location else { self.refresh(); return }
                self.apply(result)
            }
        }
    }

    /// 도시 이름으로 찾아 바꾸고 날씨를 새로 받는다. 호출한 스레드를 잠시 막는다.
    func setCity(_ query: String) -> Result<WeatherLocation, WeatherError> {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: "10"),
            URLQueryItem(name: "language", value: "ko"),
        ]
        guard let url = components.url else { return .failure(WeatherError("Bad city name.")) }
        switch Self.get(url) {
        case .failure(let error): return .failure(error)
        case .success(let data):
            guard let place = GeoPlace.best(from: data) else {
                return .failure(WeatherError("No place found for \"\(query)\"."))
            }
            let location = WeatherLocation(
                name: place.name, latitude: place.latitude, longitude: place.longitude,
                timeZone: place.timeZone.isEmpty ? TimeZone.current.identifier : place.timeZone)
            let result = Self.fetch(location)
            ConfigStore.shared.update { $0.weather = location }
            apply(result)
            return .success(location)
        }
    }

    /// 지금 바로 받아 온다 (MCP 용). 호출한 스레드를 잠시 막는다.
    func refreshNow() {
        apply(Self.fetch(location))
    }

    private func apply(_ result: Result<WeatherReport, WeatherError>) {
        switch result {
        case .success(let report):
            self.report = report
            updatedAt = Date()
            lastError = nil
        case .failure(let error):
            // 이전에 받은 날씨는 그대로 두고 오류만 기록한다
            lastError = error.message
        }
        onUpdate?()
    }

    // MARK: - 네트워크

    struct WeatherError: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }

    private static func fetch(_ location: WeatherLocation) -> Result<WeatherReport, WeatherError> {
        // 좌표는 소수 둘째 자리(약 1km)까지만 보낸다
        let url = URL(string: String(
            format: "https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=%.2f&lon=%.2f",
            location.latitude, location.longitude))!
        switch get(url) {
        case .failure(let error): return .failure(error)
        case .success(let data):
            let zone = TimeZone(identifier: location.timeZone) ?? .current
            do {
                return .success(try WeatherReport.parse(data, timeZone: zone, now: Date()))
            } catch {
                return .failure(WeatherError("Unexpected forecast format."))
            }
        }
    }

    private static func get(_ url: URL) -> Result<Data, WeatherError> {
        var request = URLRequest(url: url, timeoutInterval: 12)
        // met.no 는 어떤 프로그램인지 밝히는 User-Agent 를 요구한다 (사용자 정보는 넣지 않는다)
        request.setValue("RisingKit/0.1 (macOS menu bar utility)", forHTTPHeaderField: "User-Agent")
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<Data, WeatherError> = .failure(WeatherError("No response."))
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                result = .failure(WeatherError(error.localizedDescription))
            } else if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                result = .failure(WeatherError("HTTP \(http.statusCode)"))
            } else if let data {
                result = .success(data)
            }
            semaphore.signal()
        }.resume()
        semaphore.wait()
        return result
    }

    // MARK: - 표시

    /// 메뉴바에 올릴 아이콘. 날씨를 아직 모르면 기본 아이콘(해돋이).
    func statusImage() -> NSImage {
        guard let report else { return StatusIcon.make() }
        let config = NSImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        guard let image = NSImage(
            systemSymbolName: report.kind.sfSymbol(night: report.isNight),
            accessibilityDescription: report.kind.label)?.withSymbolConfiguration(config) else {
            return StatusIcon.make()
        }
        image.isTemplate = true
        return image
    }

    /// "서울 · 흐림 15°"
    var summary: String {
        guard let report else {
            return lastError == nil ? "\(location.name) · 날씨 불러오는 중…" : "\(location.name) · 날씨를 불러오지 못함"
        }
        return "\(location.name) · \(report.kind.label) \(Self.degrees(report.temperature))"
    }

    static func degrees(_ value: Double) -> String {
        value.isNaN ? "–" : "\(Int(value.rounded()))°"
    }

    /// "오늘", "내일", 그 뒤로는 "토요일"
    static func dayLabel(_ date: String, index: Int) -> String {
        if index == 0 { return "오늘" }
        if index == 1 { return "내일" }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let parsed = parser.date(from: date) else { return date }
        let out = DateFormatter()
        out.locale = Locale(identifier: "ko_KR")
        out.dateFormat = "EEEE"
        return out.string(from: parsed)
    }
}
