import XCTest
@testable import RisingKitCore

final class PlacementTests: XCTestCase {
    // 메뉴바 아래부터 시작하는 1440x875 영역
    let visible = CGRect(x: 0, y: 25, width: 1440, height: 875)
    let current = CGRect(x: 100, y: 100, width: 800, height: 600)

    func testHalvesTileWithoutGapOrOverlap() {
        let l = Placement.leftHalf.rect(in: visible, current: current)
        let r = Placement.rightHalf.rect(in: visible, current: current)
        XCTAssertEqual(l, CGRect(x: 0, y: 25, width: 720, height: 875))
        XCTAssertEqual(l.maxX, r.minX)
        XCTAssertEqual(r.maxX, visible.maxX)
    }

    func testOddSizesStillCoverWholeScreen() {
        let odd = CGRect(x: 0, y: 0, width: 1001, height: 701)
        let t = Placement.topHalf.rect(in: odd, current: current)
        let b = Placement.bottomHalf.rect(in: odd, current: current)
        XCTAssertEqual(t.height + b.height, 701)
        let thirds = [Placement.leftThird, .centerThird, .rightThird].map { $0.rect(in: odd, current: current) }
        XCTAssertEqual(thirds[0].maxX, thirds[1].minX)
        XCTAssertEqual(thirds[1].maxX, thirds[2].minX)
        XCTAssertEqual(thirds[2].maxX, odd.maxX)
    }

    func testQuartersAndTwoThirds() {
        XCTAssertEqual(Placement.bottomRight.rect(in: visible, current: current),
                       CGRect(x: 720, y: 462, width: 720, height: 438))
        XCTAssertEqual(Placement.rightTwoThirds.rect(in: visible, current: current),
                       CGRect(x: 480, y: 25, width: 960, height: 875))
    }

    func testCenterKeepsSizeAndClampsToScreen() {
        XCTAssertEqual(Placement.center.rect(in: visible, current: current),
                       CGRect(x: 320, y: 163, width: 800, height: 600))
        let huge = CGRect(x: 0, y: 0, width: 5000, height: 5000)
        XCTAssertEqual(Placement.center.rect(in: visible, current: huge), visible)
    }

    func testEveryPlacementStaysInsideVisibleArea() {
        for p in Placement.allCases {
            XCTAssertTrue(visible.contains(p.rect(in: visible, current: current)), "\(p)")
        }
    }

    func testRemapToOtherDisplayKeepsProportions() {
        let from = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let to = CGRect(x: 1000, y: -200, width: 2000, height: 1600)
        let moved = DisplayMove.remap(CGRect(x: 500, y: 0, width: 500, height: 800), from: from, to: to)
        XCTAssertEqual(moved, CGRect(x: 2000, y: -200, width: 1000, height: 1600))
    }

    // 가로 모니터 → 세로 모니터
    let landscape = CGRect(x: 0, y: 30, width: 2560, height: 1410)
    let portrait = CGRect(x: 2560, y: -1890, width: 2160, height: 3810)

    func testFreeWindowKeepsItsSize() {
        let moved = DisplayMove.remap(CGRect(x: 845, y: 218, width: 870, height: 658), from: landscape, to: portrait)
        XCTAssertEqual(moved.size, CGSize(width: 870, height: 658))
        XCTAssertTrue(portrait.contains(moved))
    }

    func testTooBigWindowShrinksToFit() {
        let moved = DisplayMove.remap(CGRect(x: 100, y: 100, width: 2400, height: 1200), from: landscape, to: portrait)
        XCTAssertEqual(moved.width, 2160)
        XCTAssertEqual(moved.height, 1200)
        XCTAssertTrue(portrait.contains(moved))
    }

    func testSnappedWindowKeepsItsPlacement() {
        let left = Placement.leftHalf.rect(in: landscape, current: .zero)
        XCTAssertEqual(DisplayMove.remap(left, from: landscape, to: portrait), Placement.leftHalf.rect(in: portrait, current: .zero))
        XCTAssertEqual(DisplayMove.remap(landscape, from: landscape, to: portrait), portrait)
    }
}

final class CalculatorTests: XCTestCase {
    func testArithmeticAndPrecedence() {
        XCTAssertEqual(Calculator.evaluate("1 + 2 * 3"), 7)
        XCTAssertEqual(Calculator.evaluate("(1+2)*3"), 9)
        XCTAssertEqual(Calculator.evaluate("2^3^2"), 512)
        XCTAssertEqual(Calculator.evaluate("-2^2"), -4)
        XCTAssertEqual(Calculator.evaluate("10 % 3"), 1)
        XCTAssertEqual(Calculator.evaluate("1,200 × 3"), 3600)
        XCTAssertEqual(Calculator.evaluate("9 ÷ 2"), 4.5)
    }

    func testNonExpressionsAreRejected() {
        XCTAssertNil(Calculator.evaluate("42"))          // 연산자 없는 숫자는 수식이 아님
        XCTAssertNil(Calculator.evaluate("chrome"))
        XCTAssertNil(Calculator.evaluate("1 +"))
        XCTAssertNil(Calculator.evaluate("(1+2"))
        XCTAssertNil(Calculator.evaluate("1/0"))
        XCTAssertNil(Calculator.evaluate(""))
    }

    func testFormat() {
        XCTAssertEqual(Calculator.format(7), "7")
        XCTAssertEqual(Calculator.format(4.5), "4.5")
        XCTAssertEqual(Calculator.format(0.1 + 0.2), "0.3")
        XCTAssertEqual(Calculator.format(-1200), "-1200")
    }
}

final class FuzzyTests: XCTestCase {
    func testRankingOrder() {
        let exact = Fuzzy.score(query: "arc", candidate: "Arc")!
        let prefix = Fuzzy.score(query: "arc", candidate: "Archive Utility")!
        let word = Fuzzy.score(query: "studio", candidate: "Android Studio")!
        let initials = Fuzzy.score(query: "vsc", candidate: "Visual Studio Code")!
        let inner = Fuzzy.score(query: "kraken", candidate: "GitKraken")!
        let subseq = Fuzzy.score(query: "gkrn", candidate: "GitKraken")!
        XCTAssertGreaterThan(exact, prefix)
        XCTAssertGreaterThan(prefix, word)
        XCTAssertGreaterThan(word, initials)
        XCTAssertGreaterThan(initials, inner)
        XCTAssertGreaterThan(inner, subseq)
    }

    func testNoMatch() {
        XCTAssertNil(Fuzzy.score(query: "xyz", candidate: "Safari"))
        XCTAssertNil(Fuzzy.score(query: "irafas", candidate: "Safari"))
    }

    func testShorterNamesRankHigher() {
        // 이름 앞부분이 맞더라도 훨씬 긴 이름은 단어 첫머리가 맞은 짧은 이름보다 아래
        XCTAssertGreaterThan(Fuzzy.score(query: "chrome", candidate: "Google Chrome")!,
                             Fuzzy.score(query: "chrome", candidate: "Chrome Remote Desktop Host Uninstaller")!)
    }

    func testScatteredLettersDoNotMatch() {
        XCTAssertNil(Fuzzy.score(query: "readme", candidate: ".Karabiner-VirtualHIDDevice-Manager"))
        XCTAssertNil(Fuzzy.score(query: "gk", candidate: "GitKraken"))   // 두 글자는 순서 맞춤으로 찾지 않는다
        XCTAssertNotNil(Fuzzy.score(query: "gkrn", candidate: "GitKraken"))
        XCTAssertNil(Fuzzy.score(query: "ocr", candidate: "Docker"))     // 첫 글자가 단어 첫머리가 아니다
        XCTAssertNotNil(Fuzzy.score(query: "gtkr", candidate: "GitKraken"))
    }

    func testKorean() {
        XCTAssertNotNil(Fuzzy.score(query: "카카오", candidate: "카카오톡"))
        XCTAssertEqual(Fuzzy.score(query: "ㅋㅋㅇㅌ", candidate: "카카오톡"), 550)
        XCTAssertEqual(Fuzzy.score(query: "ㅊ ㅈㄹ", candidate: "창 정렬"), 550)
        XCTAssertNil(Fuzzy.score(query: "ㅎㅎ", candidate: "카카오톡"))
        // 분해된 자모(NFD)로 저장된 파일 이름도 맞아야 한다
        XCTAssertNotNil(Fuzzy.score(query: "플로우", candidate: "플로우웍스".decomposedStringWithCanonicalMapping))
    }
}

final class KeyComboTests: XCTestCase {
    func testParseAndCanonicalForm() {
        let combo = KeyCombo("Option + Ctrl + Left")
        XCTAssertEqual(combo?.keyCode, 123)
        XCTAssertEqual(combo?.string, "ctrl+opt+left")
        XCTAssertEqual(combo?.display, "⌃⌥←")
        XCTAssertEqual(KeyCombo("cmd+shift+enter")?.string, "cmd+shift+return")
        XCTAssertEqual(KeyCombo("alt+space")?.display, "⌥Space")
        XCTAssertEqual(KeyCombo("ctrl+opt+1")?.keyCode, 18)
        XCTAssertEqual(KeyCombo("f5")?.keyCode, 96)
    }

    func testRoundTrip() {
        for s in ["ctrl+opt+u", "ctrl+opt+cmd+right", "opt+space", "ctrl+opt+delete", "cmd+shift+f12"] {
            XCTAssertEqual(KeyCombo(s)?.string, s)
            XCTAssertEqual(KeyCombo(KeyCombo(s)!.string), KeyCombo(s))
        }
    }

    func testRejectsBadInput() {
        XCTAssertNil(KeyCombo("a"))               // 조합 키 없는 글자
        XCTAssertNil(KeyCombo("shift+a"))         // shift 만으로는 일반 입력과 겹친다
        XCTAssertNil(KeyCombo("ctrl+opt"))        // 키 없음
        XCTAssertNil(KeyCombo("ctrl+opt+a+b"))    // 키 두 개
        XCTAssertNil(KeyCombo("ctrl+nope"))
        XCTAssertNil(KeyCombo(""))
    }
}

final class GeometryTests: XCTestCase {
    let area = CGRect(x: 1440, y: 25, width: 2000, height: 1000)

    func testFractionRoundTrip() {
        let rect = CGRect(x: 2440, y: 25, width: 1000, height: 500)
        let f = FractionRect(rect, in: area)
        XCTAssertEqual(f, FractionRect(x: 0.5, y: 0, width: 0.5, height: 0.5))
        XCTAssertEqual(f.absolute(in: area), rect)
        // 해상도가 다른 화면에도 같은 비율로
        XCTAssertEqual(f.absolute(in: CGRect(x: 0, y: 0, width: 1000, height: 800)),
                       CGRect(x: 500, y: 0, width: 500, height: 400))
    }

    func testFractionClampsOffscreenWindows() {
        let f = FractionRect(CGRect(x: 1000, y: -500, width: 3000, height: 400), in: area)
        XCTAssertTrue(f.isValid)
        XCTAssertEqual(f.x, 0)
        XCTAssertEqual(f.width, 1)
        XCTAssertEqual(f.y, 0)
    }

    func testValidity() {
        XCTAssertTrue(FractionRect(x: 0, y: 0, width: 1, height: 1).isValid)
        XCTAssertFalse(FractionRect(x: 0.6, y: 0, width: 0.5, height: 1).isValid)
        XCTAssertFalse(FractionRect(x: 0, y: 0, width: 0, height: 1).isValid)
        XCTAssertFalse(FractionRect(x: -0.1, y: 0, width: 0.5, height: 1).isValid)
    }

    func testDropZones() {
        XCTAssertEqual(DropZone.placement(atUnitX: 0.5, y: 0.5), .maximize)
        XCTAssertEqual(DropZone.placement(atUnitX: 0.1, y: 0.5), .leftHalf)
        XCTAssertEqual(DropZone.placement(atUnitX: 0.9, y: 0.5), .rightHalf)
        XCTAssertEqual(DropZone.placement(atUnitX: 0.5, y: 0.1), .topHalf)
        XCTAssertEqual(DropZone.placement(atUnitX: 0.5, y: 0.9), .bottomHalf)
        XCTAssertEqual(DropZone.placement(atUnitX: 0.1, y: 0.1), .topLeft)
        XCTAssertEqual(DropZone.placement(atUnitX: 0.9, y: 0.1), .topRight)
        XCTAssertEqual(DropZone.placement(atUnitX: 0.1, y: 0.9), .bottomLeft)
        XCTAssertEqual(DropZone.placement(atUnitX: 0.9, y: 0.9), .bottomRight)
    }
}

final class WeatherTests: XCTestCase {
    func testSymbolCodes() {
        XCTAssertEqual(WeatherKind(symbolCode: "clearsky_day"), .clear)
        XCTAssertEqual(WeatherKind(symbolCode: "fair_night"), .fair)
        XCTAssertEqual(WeatherKind(symbolCode: "partlycloudy_day"), .partlyCloudy)
        XCTAssertEqual(WeatherKind(symbolCode: "cloudy"), .cloudy)
        XCTAssertEqual(WeatherKind(symbolCode: "lightrainshowers_night"), .lightRain)
        XCTAssertEqual(WeatherKind(symbolCode: "rainshowers_day"), .rain)
        XCTAssertEqual(WeatherKind(symbolCode: "heavyrain"), .heavyRain)
        XCTAssertEqual(WeatherKind(symbolCode: "heavyrainshowersandthunder_day"), .thunder)
        XCTAssertEqual(WeatherKind(symbolCode: "lightsleet"), .sleet)
        XCTAssertEqual(WeatherKind(symbolCode: "heavysnowshowers_day"), .snow)
        XCTAssertEqual(WeatherKind(symbolCode: "fog"), .fog)
        XCTAssertEqual(WeatherKind(symbolCode: ""), .unknown)
        XCTAssertEqual(WeatherKind.clear.sfSymbol(night: true), "moon.stars.fill")
        XCTAssertEqual(WeatherKind.clear.sfSymbol(night: false), "sun.max.fill")
    }

    private func entry(_ time: String, temp: Double, h1: String? = nil, h6: String? = nil, rain: Double = 0) -> String {
        var periods = ""
        if let h1 { periods += #","next_1_hours":{"summary":{"symbol_code":"\#(h1)"},"details":{"precipitation_amount":\#(rain)}}"# }
        if let h6 { periods += #","next_6_hours":{"summary":{"symbol_code":"\#(h6)"},"details":{"precipitation_amount":\#(rain)}}"# }
        return #"{"time":"\#(time)","data":{"instant":{"details":{"air_temperature":\#(temp),"relative_humidity":60,"wind_speed":2.5}}\#(periods)}}"#
    }

    func testParseGroupsDaysInLocalTime() throws {
        // 서울(UTC+9) 기준: 11-13 15:00Z 는 현지 11-14 00:00
        let json = #"{"properties":{"timeseries":["# + [
            entry("2026-11-13T04:00:00Z", temp: 15.1, h1: "cloudy"),
            entry("2026-11-13T05:00:00Z", temp: 16.0, h1: "lightrain", rain: 0.4),
            entry("2026-11-13T14:00:00Z", temp: 9.0, h1: "clearsky_night"),
            entry("2026-11-13T15:00:00Z", temp: 8.0, h1: "clearsky_night"),
            entry("2026-11-14T03:00:00Z", temp: 14.0, h1: "partlycloudy_day", rain: 1.2),
            entry("2026-11-14T06:00:00Z", temp: 17.5, h6: "rain", rain: 3.0),
        ].joined(separator: ",") + "]}}"
        let now = ISO8601DateFormatter().date(from: "2026-11-13T04:50:00Z")!
        let report = try WeatherReport.parse(Data(json.utf8), timeZone: TimeZone(identifier: "Asia/Seoul")!, now: now)

        // 04:50Z 에 가장 가까운 것은 05:00Z 항목
        XCTAssertEqual(report.temperature, 16.0)
        XCTAssertEqual(report.kind, .lightRain)
        XCTAssertFalse(report.isNight)
        XCTAssertEqual(report.days.map(\.date), ["2026-11-13", "2026-11-14"])
        XCTAssertEqual(report.days[0], .init(date: "2026-11-13", kind: .cloudy, low: 9.0, high: 16.0, precipitation: 0.4))
        // 현지 12시(03:00Z)가 대표 날씨, 강수량은 1.2 + 3.0
        XCTAssertEqual(report.days[1], .init(date: "2026-11-14", kind: .partlyCloudy, low: 8.0, high: 17.5, precipitation: 4.2))
    }

    func testParseNightAndBadInput() throws {
        let json = #"{"properties":{"timeseries":["# + entry("2026-11-13T14:00:00Z", temp: 9, h1: "clearsky_night") + "]}}"
        let now = ISO8601DateFormatter().date(from: "2026-11-13T14:10:00Z")!
        let report = try WeatherReport.parse(Data(json.utf8), timeZone: TimeZone(identifier: "Asia/Seoul")!, now: now)
        XCTAssertTrue(report.isNight)
        XCTAssertEqual(report.kind, .clear)
        XCTAssertThrowsError(try WeatherReport.parse(Data(#"{"properties":{"timeseries":[]}}"#.utf8), timeZone: .current, now: now))
        XCTAssertThrowsError(try WeatherReport.parse(Data("oops".utf8), timeZone: .current, now: now))
    }

    func testGeocodingPrefersCitiesOverTerrain() {
        // 실제 응답에서 "부산"을 검색하면 충청북도의 산이 먼저 나온다
        let json = #"""
        {"results":[
          {"name":"부산","latitude":37.04,"longitude":128.07,"feature_code":"MT","admin1":"충청북도","country":"대한민국","timezone":"Asia/Seoul"},
          {"name":"부산","latitude":35.30,"longitude":126.74,"feature_code":"PPL","admin1":"전라남도","country":"대한민국","timezone":"Asia/Seoul"},
          {"name":"부산광역시","latitude":35.10,"longitude":129.03,"feature_code":"PPLA","population":3285147,"admin1":"부산광역시","country":"대한민국","timezone":"Asia/Seoul"}
        ]}
        """#
        let place = GeoPlace.best(from: Data(json.utf8))
        XCTAssertEqual(place?.name, "부산광역시")
        XCTAssertEqual(place?.latitude, 35.10)
        XCTAssertEqual(place?.timeZone, "Asia/Seoul")
        XCTAssertNil(GeoPlace.best(from: Data(#"{"generationtime_ms":0.1}"#.utf8)))
    }
}

final class CenterTwoThirdsTests: XCTestCase {
    func testCenterTwoThirdsIsCentered() {
        let v = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let r = Placement.centerTwoThirds.rect(in: v, current: .zero)
        XCTAssertEqual(r, CGRect(x: 240, y: 25, width: 960, height: 875))
        XCTAssertEqual(r.minX - v.minX, v.maxX - r.maxX)
    }
}

final class EdgeSnapTests: XCTestCase {
    // 주 화면 오른쪽 위에 붙은 두 번째 화면 (좌표가 음수로 시작)
    let screen = CGRect(x: 1512, y: -194, width: 2560, height: 1440)

    func at(_ x: CGFloat, _ y: CGFloat) -> Placement? {
        EdgeSnap.placement(at: CGPoint(x: screen.minX + x, y: screen.minY + y), in: screen)
    }

    func testEdges() {
        XCTAssertEqual(at(2, 700), .leftHalf)
        XCTAssertEqual(at(2558, 700), .rightHalf)
        XCTAssertEqual(at(1280, 1), .maximize)
        XCTAssertEqual(at(400, 1439), .leftThird)
        XCTAssertEqual(at(1280, 1439), .centerThird)
        XCTAssertEqual(at(2200, 1439), .rightThird)
    }

    func testCorners() {
        XCTAssertEqual(at(2, 100), .topLeft)
        XCTAssertEqual(at(2, 1400), .bottomLeft)
        XCTAssertEqual(at(2558, 100), .topRight)
        XCTAssertEqual(at(2558, 1400), .bottomRight)
        XCTAssertEqual(at(200, 1), .topLeft)
        XCTAssertEqual(at(2400, 1), .topRight)
    }

    func testEdgesTouchingAnotherDisplayDoNotSnap() {
        // 주 화면 위에 화면 하나, 오른쪽에 세로 화면 하나
        let main = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let above = CGRect(x: 0, y: -1440, width: 2560, height: 1440)
        let right = CGRect(x: 2560, y: -1920, width: 2160, height: 3840)
        let others = [above, right]
        func at(_ x: CGFloat, _ y: CGFloat) -> Placement? { EdgeSnap.placement(at: CGPoint(x: x, y: y), in: main, others: others) }
        XCTAssertNil(at(1280, 1))        // 위 = 다른 화면으로 넘어가는 길
        XCTAssertNil(at(2558, 700))      // 오른쪽 = 세로 화면으로 넘어가는 길
        XCTAssertNil(at(2558, 1))
        XCTAssertEqual(at(2, 700), .leftHalf)      // 왼쪽 · 아래는 그대로 붙는다
        XCTAssertEqual(at(1280, 1439), .centerThird)
        XCTAssertEqual(at(2, 1), .topLeft)         // 왼쪽 위 모서리는 왼쪽 가장자리로 붙는다
    }

    func testAwayFromEdgesIsNil() {
        XCTAssertNil(at(1280, 700))
        XCTAssertNil(at(20, 700))
        XCTAssertNil(at(1280, 20))
    }
}

final class DateQueryTests: XCTestCase {
    // 2026-11-13 금요일 14:30:00 KST
    let now = ISO8601DateFormatter().date(from: "2026-11-13T05:30:00Z")!
    let seoul = TimeZone(identifier: "Asia/Seoul")!

    func ask(_ q: String) -> String? { DateQuery.answer(q, now: now, timeZone: seoul)?.text }

    func testNamedDays() {
        XCTAssertEqual(ask("오늘"), "2026년 11월 13일 금요일")
        XCTAssertEqual(ask("Today"), "2026년 11월 13일 금요일")
        XCTAssertEqual(ask("내일"), "2026년 11월 14일 토요일")
        XCTAssertEqual(ask("어제"), "2026년 11월 12일 목요일")
        XCTAssertEqual(ask("모레"), "2026년 11월 15일 일요일")
    }

    func testRelative() {
        XCTAssertEqual(ask("3일 후"), "2026년 11월 16일 월요일")
        XCTAssertEqual(ask("20일뒤"), "2026년 12월 3일 목요일")      // 달을 넘긴다
        XCTAssertEqual(ask("2주 전"), "2026년 10월 30일 금요일")
        XCTAssertEqual(ask("in 5 days"), "2026년 11월 18일 수요일")
        XCTAssertEqual(ask("3 days ago"), "2026년 11월 10일 화요일")
        XCTAssertEqual(DateQuery.answer("3일 후", now: now, timeZone: seoul)?.label, "3일 후")
    }

    func testTimeAndTimestamps() {
        XCTAssertEqual(ask("지금"), "2026-11-13 14:30:00")
        XCTAssertEqual(ask("timestamp"), "1794547800")
        XCTAssertEqual(ask("1794547800"), "2026-11-13 14:30:00")
        XCTAssertEqual(ask("1794547800000"), "2026-11-13 14:30:00")
        XCTAssertEqual(ask("week"), "2026년 46주차")
    }

    func testLocalDayNotUTCDay() {
        // UTC 로는 아직 11-13 이지만 서울은 이미 11-14
        let late = ISO8601DateFormatter().date(from: "2026-11-13T16:00:00Z")!
        XCTAssertEqual(DateQuery.answer("오늘", now: late, timeZone: seoul)?.text, "2026년 11월 14일 토요일")
    }

    func testNonDateQueries() {
        XCTAssertNil(ask("chrome"))
        XCTAssertNil(ask("12345"))        // 자릿수가 맞지 않는 숫자
        XCTAssertNil(ask("3일"))
        XCTAssertNil(ask(""))
    }
}

final class KeyComboFromEventTests: XCTestCase {
    func testFromKeyCode() {
        XCTAssertEqual(KeyCombo(keyCode: 18, control: true, option: true, command: false, shift: false)?.string, "ctrl+opt+1")
        XCTAssertEqual(KeyCombo(keyCode: 123, control: false, option: false, command: true, shift: true)?.string, "cmd+shift+left")
        XCTAssertNil(KeyCombo(keyCode: 0, control: false, option: false, command: false, shift: false))  // 조합 키 없음
        XCTAssertNil(KeyCombo(keyCode: 0, control: false, option: false, command: false, shift: true))   // shift 만
        XCTAssertNil(KeyCombo(keyCode: 999, control: true, option: false, command: false, shift: false)) // 모르는 키
    }
}

final class ProcessUsageTests: XCTestCase {
    let ps = """
     204800  12.5 /Applications/Dia.app/Contents/MacOS/Dia
     102400   3.0 /Applications/Dia.app/Contents/Frameworks/Dia Framework.framework/Helpers/Dia Helper (Renderer).app/Contents/MacOS/Dia Helper (Renderer)
      51200   0.0 /Applications/Dia.app/Contents/Frameworks/Dia Helper.app/Contents/MacOS/Dia Helper
    1572864 140.2 /Users/me/.local/bin/claude
       2048   0.1 /usr/libexec/logd
    garbage line
    """

    func testGroupsHelpersIntoOutermostApp() {
        let apps = ProcessUsage.group(ps)
        let dia = apps.first { $0.name == "Dia" }
        XCTAssertEqual(dia?.memoryKB, 358400)
        XCTAssertEqual(dia?.cpu, 15.5)
        XCTAssertEqual(dia?.processes, 3)
        XCTAssertEqual(apps.count, 3)   // Dia, claude, logd — 형식이 틀린 줄은 버린다
    }

    func testRanking() {
        let apps = ProcessUsage.group(ps)
        XCTAssertEqual(ProcessUsage.topByMemory(apps, 2).map(\.name), ["claude", "Dia"])
        XCTAssertEqual(ProcessUsage.topByCPU(apps, 5).map(\.name), ["claude", "Dia", "logd"])
    }

    func testFormatting() {
        XCTAssertEqual(ProcessUsage.formatMemory(kilobytes: 1572864), "1.5 GB")
        XCTAssertEqual(ProcessUsage.formatMemory(kilobytes: 358400), "350 MB")
        XCTAssertEqual(ProcessUsage.formatMemory(bytes: 19_327_352_832), "18.0 GB")
        XCTAssertEqual(ProcessUsage.group(ps).first { $0.name == "claude" }?.cpuText, "140%")
    }
}

final class ClipHistoryTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func item(_ text: String, _ offset: TimeInterval = 0, kind: ClipItem.Kind = .text) -> ClipItem {
        ClipItem(id: UUID().uuidString, kind: kind, text: text, date: t0.addingTimeInterval(offset))
    }

    func testNewestFirstAndDuplicatesMoveToTop() {
        var history = ClipHistory()
        history.add(item("a"))
        history.add(item("b", 1))
        let removed = history.add(item("a", 2))
        XCTAssertEqual(history.items.map(\.text), ["a", "b"])
        XCTAssertEqual(removed.map(\.text), ["a"])   // 예전 "a" 가 빠졌다
        XCTAssertEqual(history.items[0].date, t0.addingTimeInterval(2))
    }

    func testIgnoresEmptyAndHugeText() {
        var history = ClipHistory()
        history.add(item("   \n "))
        history.add(item(String(repeating: "x", count: ClipHistory.maxTextLength + 1)))
        XCTAssertTrue(history.items.isEmpty)
    }

    func testCountLimitDropsOldest() {
        var history = ClipHistory()
        for i in 0..<ClipHistory.maxItems { history.add(item("t\(i)", Double(i))) }
        let removed = history.add(item("newest", 9999))
        XCTAssertEqual(history.items.count, ClipHistory.maxItems)
        XCTAssertEqual(history.items.first?.text, "newest")
        XCTAssertEqual(removed.map(\.text), ["t0"])
    }

    func testPruneByAge() {
        var history = ClipHistory()
        history.add(item("old", 0))
        history.add(item("fresh", 6 * 86400))
        let expired = history.prune(now: t0.addingTimeInterval(7 * 86400 + 60))
        XCTAssertEqual(expired.map(\.text), ["old"])
        XCTAssertEqual(history.items.map(\.text), ["fresh"])
    }

    func testSearchAndPreview() {
        var history = ClipHistory()
        history.add(item("Hello\nWorld"))
        history.add(item("/Users/me/a.png\n/Users/me/b.png", 1, kind: .file))
        XCTAssertEqual(history.search("WORLD").count, 1)
        XCTAssertEqual(history.search("").count, 2)
        XCTAssertEqual(history.items[1].preview, "Hello ⏎ World")
        XCTAssertEqual(history.items[0].preview, "a.png 외 1개")
    }
}

final class LeftoversTests: XCTestCase {
    func match(_ entry: String, _ folder: String) -> Bool {
        Leftovers.matches(entry: entry, in: folder, bundleId: "com.postmanlabs.mac", appName: "Postman")
    }

    func testBundleIdMatches() {
        XCTAssertTrue(match("com.postmanlabs.mac", "Caches"))
        XCTAssertTrue(match("com.postmanlabs.mac.plist", "Preferences"))
        XCTAssertTrue(match("com.postmanlabs.mac.savedState", "Saved Application State"))
        XCTAssertTrue(match("com.postmanlabs.mac.ShipIt", "Caches"))
    }

    func testDoesNotMatchOtherApps() {
        XCTAssertFalse(match("com.postmanlabs.mac2", "Caches"))            // 다른 앱
        XCTAssertFalse(match("com.postmanlabs", "Caches"))                 // 회사 공용 폴더
        XCTAssertFalse(match("Postman Agent", "Application Support"))      // 이름이 비슷한 다른 앱
        XCTAssertFalse(match("Postman", "Preferences"))                    // 이름 맞춤은 정해진 폴더에서만
    }

    func testNameMatchOnlyInKnownFolders() {
        XCTAssertTrue(match("Postman", "Application Support"))
        XCTAssertTrue(match("postman", "Logs"))
    }

    func testRefusesWeakIdentifiers() {
        // 점이 하나뿐인 id, 애플 id, 너무 짧은 이름으로는 아무것도 고르지 않는다
        XCTAssertFalse(Leftovers.matches(entry: "foo.bar", in: "Caches", bundleId: "foo.bar", appName: "X"))
        XCTAssertFalse(Leftovers.matches(entry: "com.apple.Safari", in: "Caches", bundleId: "com.apple.Safari", appName: "Safari"))
        XCTAssertFalse(Leftovers.matches(entry: "Arc", in: "Application Support", bundleId: "company.thebrowser.Browser", appName: "Arc"))
    }

    func testSizeFormat() {
        XCTAssertEqual(Leftovers.formatSize(292_552_704), "279 MB")
        XCTAssertEqual(Leftovers.formatSize(3_221_225_472), "3.0 GB")
        XCTAssertEqual(Leftovers.formatSize(24_576), "24 KB")
        XCTAssertEqual(Leftovers.formatSize(0), "0 KB")
    }
}

final class DevToolsTests: XCTestCase {
    func first(_ q: String) -> String? { DevTools.answers(q).first?.text }

    func testEncodings() {
        XCTAssertEqual(first("b64 hello 한글"), "aGVsbG8g7ZWc6riA")
        XCTAssertEqual(first("b64d aGVsbG8g7ZWc6riA"), "hello 한글")
        XCTAssertEqual(first("b64d aGk"), "hi")                      // 패딩이 빠져도
        XCTAssertEqual(first("urlencode a b&c=한"), "a%20b%26c%3D%ED%95%9C")
        XCTAssertEqual(first("urldecode a%20b%26c"), "a b&c")
        XCTAssertNil(first("b64d !!!"))
    }

    func testHashes() {
        XCTAssertEqual(first("md5 hello"), "5d41402abc4b2a76b9719d911017c592")
        XCTAssertEqual(first("sha1 hello"), "aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d")
        XCTAssertEqual(first("sha256 hello"), "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    }

    func testUUIDAndNonCommands() {
        let answers = DevTools.answers("uuid", makeUUID: { "ABCDEF12-0000-4000-8000-000000000000" })
        XCTAssertEqual(answers.map(\.text), ["abcdef12-0000-4000-8000-000000000000", "ABCDEF12-0000-4000-8000-000000000000"])
        XCTAssertTrue(DevTools.answers("chrome").isEmpty)
        XCTAssertTrue(DevTools.answers("md5").isEmpty)
        XCTAssertTrue(DevTools.answers("hello world").isEmpty)
    }

    func testColors() {
        XCTAssertEqual(DevTools.answers("#ff8800").map(\.text), ["#FF8800", "rgb(255, 136, 0)", "hsl(32, 100%, 50%)"])
        XCTAssertEqual(first("#f80"), "#FF8800")
        XCTAssertEqual(first("rgb(0, 128, 255)"), "#0080FF")
        XCTAssertEqual(DevTools.answers("#808080").last?.text, "hsl(0, 0%, 50%)")
        XCTAssertTrue(DevTools.answers("#12").isEmpty)
        XCTAssertTrue(DevTools.answers("rgb(300, 0, 0)").isEmpty)
    }
}

final class PortParserTests: XCTestCase {
    func testQueries() {
        XCTAssertEqual(PortParser.query(":3000"), 3000)
        XCTAssertEqual(PortParser.query("port 8080"), 8080)
        XCTAssertEqual(PortParser.query("포트 5432"), 5432)
        XCTAssertEqual(PortParser.query("ports"), 0)
        XCTAssertNil(PortParser.query("port abc"))
        XCTAssertNil(PortParser.query(":99999"))
        XCTAssertNil(PortParser.query("3000"))
        XCTAssertNil(PortParser.query("portal"))
    }

    func testParseLsof() {
        let output = """
        COMMAND     PID       USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        node      41235 user         23u  IPv6 0x1234567890abcdef      0t0  TCP *:3000 (LISTEN)
        node      41235 user         24u  IPv4 0x1234567890abcdee      0t0  TCP *:3000 (LISTEN)
        postgres    812 user          7u  IPv6 0x1234567890abcdea      0t0  TCP [::1]:5432 (LISTEN)
        Google\\x20Chrome 900 user 9u IPv4 0x1 0t0 TCP 127.0.0.1:9222 (LISTEN)
        """
        XCTAssertEqual(PortParser.parse(output), [
            PortUser(port: 3000, pid: 41235, command: "node"),
            PortUser(port: 5432, pid: 812, command: "postgres"),
            PortUser(port: 9222, pid: 900, command: "Google Chrome"),
        ])
        XCTAssertTrue(PortParser.parse("").isEmpty)
    }
}

final class ScrumTests: XCTestCase {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()

    func date(_ s: String) -> Date { ISO8601DateFormatter().date(from: s + "T03:00:00Z")! }  // 현지 정오

    func testPreviousWorkdaySkipsWeekend() {
        // 2026-11-13 은 금요일
        XCTAssertEqual(Scrum.header(Scrum.previousWorkday(before: date("2026-11-13"), calendar: calendar), calendar: calendar), "[26.11.12 (목)]")
        // 월요일의 전 근무일은 금요일
        XCTAssertEqual(Scrum.header(Scrum.previousWorkday(before: date("2026-11-16"), calendar: calendar), calendar: calendar), "[26.11.13 (금)]")
        // 일요일에 만들면 금요일
        XCTAssertEqual(Scrum.header(Scrum.previousWorkday(before: date("2026-11-15"), calendar: calendar), calendar: calendar), "[26.11.13 (금)]")
    }

    func testCleanSubject() {
        XCTAssertEqual(Scrum.cleanSubject("feat(api): 로그인 추가"), "로그인 추가")
        XCTAssertEqual(Scrum.cleanSubject("fix!: 결제 오류"), "결제 오류")
        XCTAssertEqual(Scrum.cleanSubject("0.2.6: 작업 버튼을 탭 아래 줄로"), "작업 버튼을 탭 아래 줄로")
        XCTAssertEqual(Scrum.cleanSubject("[web] 폴더 관리"), "폴더 관리")
        XCTAssertEqual(Scrum.cleanSubject("알림 연동: 토큰 갱신"), "알림 연동: 토큰 갱신")   // 종류가 아닌 콜론은 그대로
        XCTAssertEqual(Scrum.cleanSubject("  그냥 제목 "), "그냥 제목")
    }

    func testParseLog() {
        let output = "\u{1e}abc1234def\tdev-kim\tme@example.com\tfeat: 슬랙 연동\n"
            + "\u{1e}9998887aaa\tAlex Park\talex@example.org\t문서\t수정\n"
        let entries = Scrum.parseLog(output)
        XCTAssertEqual(entries.map(\.hash), ["abc1234def", "9998887aaa"])
        XCTAssertEqual(entries[0], Scrum.LogEntry(hash: "abc1234def", author: "dev-kim", email: "me@example.com", subject: "feat: 슬랙 연동"))
        XCTAssertEqual(entries[1].subject, "문서\t수정")     // 제목 안의 탭은 그대로
        XCTAssertTrue(Scrum.parseLog("garbage").isEmpty)
    }

    func testIsMine() {
        let me = Scrum.Identity(names: ["dev-kim"], emails: ["Me@Example.com"])
        XCTAssertTrue(Scrum.isMine(author: "dev-kim", email: "me@example.com", identity: me))
        XCTAssertTrue(Scrum.isMine(author: "Someone", email: "ME@example.com", identity: me))           // 이메일이 내 것
        // GitHub 에서 만든 커밋은 익명 주소로 찍힌다
        XCTAssertTrue(Scrum.isMine(author: "GitHub", email: "12345678+dev-kim@users.noreply.github.com", identity: me))
        XCTAssertTrue(Scrum.isMine(author: "GitHub", email: "dev-kim@users.noreply.github.com", identity: me))
        // 동료의 커밋
        XCTAssertFalse(Scrum.isMine(author: "Alex Park", email: "alex@example.org", identity: me))
        XCTAssertFalse(Scrum.isMine(author: "teammate", email: "999+teammate@users.noreply.github.com", identity: me))
        XCTAssertFalse(Scrum.isMine(author: "someone", email: "someone@MacBook-Pro.local", identity: me))
        // 이름과 이메일을 모르면 아무것도 내 것으로 보지 않는다
        XCTAssertFalse(Scrum.isMine(author: "", email: "", identity: Scrum.Identity(names: [""], emails: [""])))
    }

    func testRepositoryKey() {
        XCTAssertEqual(Scrum.repositoryKey(remote: "git@github.com:acme/web.git")?.owner, "acme")
        XCTAssertEqual(Scrum.repositoryKey(remote: "git@github.com:acme/web.git")?.name, "web")
        XCTAssertEqual(Scrum.repositoryKey(remote: "https://github.com/odds-center/git-rising\n")?.owner, "odds-center")
        XCTAssertEqual(Scrum.repositoryKey(remote: "https://github.com/odds-center/git-rising.git/")?.name, "git-rising")
        XCTAssertNil(Scrum.repositoryKey(remote: ""))
        XCTAssertNil(Scrum.repositoryKey(remote: "https://example.com/solo"))
    }

    func testLongSubjectsAreShortened() {
        let long = String(repeating: "가", count: 120)
        let text = Scrum.compose(doneDate: date("2026-11-12"), done: [Scrum.Commit(hash: "1", subject: long, project: "p")],
                                 todayDate: date("2026-11-13"), today: [], calendar: calendar)
        let line = text.split(separator: "\n")[1]
        XCTAssertEqual(line.count, "p - ".count + 80)
        XCTAssertTrue(line.hasSuffix("…"))
    }

    func testCompose() {
        let done = [
            Scrum.Commit(hash: "1", subject: "feat: 로그인 화면 개편", project: "web"),
            Scrum.Commit(hash: "2", subject: "슬랙 연동", project: "api"),
            Scrum.Commit(hash: "3", subject: "fix: 결제 오류 수정", project: "web"),
            Scrum.Commit(hash: "4", subject: "feat: 로그인 화면 개편", project: "web"),  // 같은 제목
        ]
        let text = Scrum.compose(doneDate: date("2026-11-12"), done: done, todayDate: date("2026-11-13"),
                                 today: [], calendar: calendar)
        XCTAssertEqual(text, """
        [26.11.12 (목)]
        web - 로그인 화면 개편
        web - 결제 오류 수정
        api - 슬랙 연동

        [26.11.13 (금)]

        """)
    }

    func testComposeLimitsAndEmpty() {
        let many = (1...10).map { Scrum.Commit(hash: "\($0)", subject: "작업 \($0)", project: "docs") }
        let text = Scrum.compose(doneDate: date("2026-11-12"), done: many, todayDate: date("2026-11-13"),
                                 today: [], calendar: calendar, maxPerProject: 3)
        XCTAssertTrue(text.contains("docs - 작업 3\ndocs - 외 7건"))
        XCTAssertFalse(text.contains("작업 4"))
        let empty = Scrum.compose(doneDate: date("2026-11-12"), done: [], todayDate: date("2026-11-13"),
                                  today: [], calendar: calendar)
        XCTAssertTrue(empty.hasPrefix("[26.11.12 (목)]\n(커밋 없음)\n"))
    }
}

final class TidyTests: XCTestCase {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()
    let now = ISO8601DateFormatter().date(from: "2026-11-13T03:00:00Z")!

    func item(_ name: String, daysAgo: Double, dir: Bool = false) -> Tidy.Item {
        Tidy.Item(name: name, isDirectory: dir, date: now.addingTimeInterval(-daysAgo * 86400))
    }

    func testScreenshotNames() {
        XCTAssertTrue(Tidy.isScreenshot("스크린샷 2026-11-10 오전 8.09.34.png"))
        XCTAssertTrue(Tidy.isScreenshot("Screenshot 2026-11-10 at 8.09.34 AM.png"))
        XCTAssertTrue(Tidy.isScreenshot("화면 기록 2026-11-01 오후 3.00.00.mov"))
        // 파일 시스템이 자모를 분해해 저장해도
        XCTAssertTrue(Tidy.isScreenshot("스크린샷 2026-11-10.png".decomposedStringWithCanonicalMapping))
        XCTAssertFalse(Tidy.isScreenshot("로고 시안.png"))          // 이름을 바꾼 파일
        XCTAssertFalse(Tidy.isScreenshot("스크린샷 정리.txt"))
    }

    func testPlanScreenshots() {
        let moves = Tidy.planScreenshots([
            item("스크린샷 2026-11-01 오전 9.00.00.png", daysAgo: 12),
            item("스크린샷 2026-11-12 오전 9.00.00.png", daysAgo: 1),     // 아직 새것
            item("스크린샷 2026-10-20 오전 9.00.00.png", daysAgo: 24),
            item("보고서.pdf", daysAgo: 100),
            item("스크린샷 폴더.png", daysAgo: 100, dir: true),
        ], olderThanDays: 7, now: now, calendar: calendar)
        XCTAssertEqual(moves, [
            Tidy.Move(name: "스크린샷 2026-11-01 오전 9.00.00.png", folder: "2026-11"),
            Tidy.Move(name: "스크린샷 2026-10-20 오전 9.00.00.png", folder: "2026-10"),
        ])
    }

    func testPlanDownloadsSkipsWhatItShould() {
        let moves = Tidy.planDownloads([
            item("old.zip", daysAgo: 45),
            item("프로젝트 자료", daysAgo: 60, dir: true),
            item("fresh.dmg", daysAgo: 3),
            item(".DS_Store", daysAgo: 400),
            item("movie.mp4.crdownload", daysAgo: 90),
            item(Tidy.downloadArchive, daysAgo: 200, dir: true),
            item("exactly.txt", daysAgo: 30),          // 정확히 30일은 아직 아님
        ], olderThanDays: 30, now: now, calendar: calendar)
        // 폴더는 앱이 쓰고 있을 수 있어 옮기지 않는다
        XCTAssertEqual(moves.map(\.name), ["old.zip"])
        XCTAssertEqual(moves.map(\.folder), ["2026-09"])
    }

    func testMonthFolderUsesLocalTime() {
        // UTC 로는 10월 31일이지만 서울은 11월 1일
        let d = ISO8601DateFormatter().date(from: "2026-10-31T16:00:00Z")!
        XCTAssertEqual(Tidy.monthFolder(d, calendar: calendar), "2026-11")
    }
}

final class BankSecurityTests: XCTestCase {
    func testRecognizesBankModulesOnly() {
        for label in ["com.ahnlab.astxd", "com.ahnlab.astxagent", "com.astx.firewall.Agent", "com.astx.firewall.Daemon", "com.nprotect.nosintgdmn", "com.wizvera.veraport",
                      "com.wizvera.delfino", "com.raon.touchen.nxkey", "com.raon.agent.touchen.nxkey",
                      "com.raon.TouchEN_TEWeb_Agent", "com.raonwiz.raonk", "com.interezen.nwsdaemon",
                      "kr.co.iniline.crossex-service", "com.initech.INISAFECrossWebEXSvc",
                      "com.dreamsecurity.MagicLine4NX", "com.softforum.anysign"] {
            XCTAssertTrue(BankSecurity.isSecurityJob(label: label), label)
        }
        // 일반 백신이나 관계없는 프로그램은 건드리지 않는다
        for label in ["com.ahnlab.v3", "com.ahnlab.msp", "com.docker.vmnetd", "com.apple.mdworker", "com.bitwarden.desktop"] {
            XCTAssertFalse(BankSecurity.isSecurityJob(label: label), label)
        }
        XCTAssertEqual(BankSecurity.vendorName(for: "com.wizvera.delfino"), "Delfino")
    }

    func testCommands() {
        let agent = BankSecurity.Job(label: "com.wizvera.delfino", plistPath: "/Library/LaunchAgents/com.wizvera.delfino.plist", isSystem: false)
        let daemon = BankSecurity.Job(label: "com.ahnlab.astxd", plistPath: "/Library/LaunchDaemons/com.ahnlab.astxd.plist", isSystem: true)
        XCTAssertEqual(BankSecurity.commands(for: [agent, daemon], turnOn: false, uid: 501), [
            "/bin/launchctl disable gui/501/com.wizvera.delfino",
            "/bin/launchctl bootout gui/501/com.wizvera.delfino",
            "/bin/launchctl disable system/com.ahnlab.astxd",
            "/bin/launchctl bootout system/com.ahnlab.astxd",
        ])
        XCTAssertEqual(BankSecurity.commands(for: [daemon], turnOn: true, uid: 501), [
            "/bin/launchctl enable system/com.ahnlab.astxd",
            "/bin/launchctl bootstrap system /Library/LaunchDaemons/com.ahnlab.astxd.plist",
        ])
    }

    func testRefusesUnsafeNames() {
        // 셸에 끼어들 수 있는 문자가 든 이름이나 경로는 명령에 넣지 않는다
        let evil = BankSecurity.Job(label: "com.raon.x; rm -rf ~", plistPath: "/Library/LaunchAgents/a.plist", isSystem: false)
        let spaced = BankSecurity.Job(label: "com.raon.touchen", plistPath: "/Library/Launch Agents/a b.plist", isSystem: false)
        let quoted = BankSecurity.Job(label: "com.raon.touchen", plistPath: "/Library/LaunchAgents/a'$(id).plist", isSystem: false)
        XCTAssertTrue(BankSecurity.commands(for: [evil, spaced, quoted], turnOn: false, uid: 501).isEmpty)
    }
}

final class AudioPriorityTests: XCTestCase {
    let priority = ["airpods", "headphones", "speaker"]

    func testPicksFirstConnectedDevice() {
        XCTAssertEqual(AudioPriority.preferred(priority: priority, available: ["speaker", "headphones", "monitor"]), "headphones")
        XCTAssertEqual(AudioPriority.preferred(priority: priority, available: ["monitor", "speaker"]), "speaker")
        // 목록의 장치가 하나도 없으면 손대지 않는다
        XCTAssertNil(AudioPriority.preferred(priority: priority, available: ["monitor", "boom"]))
        XCTAssertNil(AudioPriority.preferred(priority: [], available: ["speaker"]))
    }

    func testChangeOnlyWhenNeeded() {
        // 모니터를 꽂아 기본값이 모니터로 바뀌었다 → 헤드폰으로 되돌린다
        XCTAssertEqual(AudioPriority.change(priority: priority, available: ["monitor", "headphones", "speaker"], current: "monitor"), "headphones")
        // 이미 맞는 장치면 그대로
        XCTAssertNil(AudioPriority.change(priority: priority, available: ["headphones", "speaker"], current: "headphones"))
        // 더 앞 순위(에어팟)가 연결되면 그쪽으로
        XCTAssertEqual(AudioPriority.change(priority: priority, available: ["airpods", "headphones"], current: "headphones"), "airpods")
    }

    func testPromoteAndMove() {
        XCTAssertEqual(AudioPriority.promote("speaker", in: priority), ["speaker", "airpods", "headphones"])
        XCTAssertEqual(AudioPriority.promote("monitor", in: priority), ["monitor", "airpods", "headphones", "speaker"])
        XCTAssertEqual(AudioPriority.move("speaker", by: -1, in: priority), ["airpods", "speaker", "headphones"])
        XCTAssertEqual(AudioPriority.move("airpods", by: -1, in: priority), priority)      // 맨 위에서 더 위로는 못 간다
        XCTAssertEqual(AudioPriority.move("airpods", by: 5, in: priority), ["headphones", "speaker", "airpods"])
        XCTAssertEqual(AudioPriority.move("nope", by: 1, in: priority), priority)
    }
}

final class FreePlacementTests: XCTestCase {
    let area = CGRect(x: 1512, y: -164, width: 2560, height: 1410)

    func testFitKeepsRectsThatAlreadyFit() {
        let rect = CGRect(x: 2000, y: 100, width: 800, height: 600)
        XCTAssertEqual(FreePlacement.fit(rect, in: area), rect)
    }

    func testFitPushesBackInside() {
        // 오른쪽 아래로 삐져나감
        XCTAssertEqual(FreePlacement.fit(CGRect(x: 3900, y: 1000, width: 800, height: 600), in: area),
                       CGRect(x: 3272, y: 646, width: 800, height: 600))
        // 왼쪽 위로 삐져나감
        XCTAssertEqual(FreePlacement.fit(CGRect(x: 1000, y: -400, width: 800, height: 600), in: area),
                       CGRect(x: 1512, y: -164, width: 800, height: 600))
    }

    func testFitShrinksOversizedAndEnforcesMinimum() {
        XCTAssertEqual(FreePlacement.fit(CGRect(x: 0, y: 0, width: 9000, height: 9000), in: area), area)
        let tiny = FreePlacement.fit(CGRect(x: 2000, y: 0, width: 10, height: 10), in: area)
        XCTAssertEqual(tiny.size, CGSize(width: 200, height: 120))
    }

    func testRectFromAnyDragDirection() {
        let a = CGPoint(x: 300, y: 400), b = CGPoint(x: 100, y: 150)
        XCTAssertEqual(FreePlacement.rect(from: a, to: b), CGRect(x: 100, y: 150, width: 200, height: 250))
        XCTAssertEqual(FreePlacement.rect(from: b, to: a), FreePlacement.rect(from: a, to: b))
    }

    func testResizeKeepsOriginAndStaysOnScreen() {
        let rect = CGRect(x: 2000, y: 0, width: 800, height: 600)
        XCTAssertEqual(FreePlacement.resized(rect, by: CGSize(width: 200, height: -100), in: area),
                       CGRect(x: 2000, y: 0, width: 1000, height: 500))
        // 화면 끝을 넘겨 키울 수 없다
        XCTAssertEqual(FreePlacement.resized(rect, by: CGSize(width: 9000, height: 9000), in: area),
                       CGRect(x: 2000, y: 0, width: 2072, height: 1246))
        // 최소 크기보다 줄일 수 없다
        XCTAssertEqual(FreePlacement.resized(rect, by: CGSize(width: -9000, height: -9000), in: area).size,
                       CGSize(width: 200, height: 120))
    }
}

final class EdgePlacementTests: XCTestCase {
    func testMiddleIsFree() {
        // 가운데 쪽 어디에 놓든 붙지 않는다 (놓은 자리 그대로)
        for (x, y) in [(0.5, 0.5), (0.2, 0.3), (0.8, 0.7), (0.1, 0.5), (0.5, 0.1), (0.9, 0.9)] {
            XCTAssertNil(DropZone.edgePlacement(atUnitX: x, y: y), "\(x),\(y)")
        }
    }

    func testEdgesSnap() {
        XCTAssertEqual(DropZone.edgePlacement(atUnitX: 0.02, y: 0.5), .leftHalf)
        XCTAssertEqual(DropZone.edgePlacement(atUnitX: 0.98, y: 0.5), .rightHalf)
        XCTAssertEqual(DropZone.edgePlacement(atUnitX: 0.5, y: 0.02), .maximize)
        XCTAssertEqual(DropZone.edgePlacement(atUnitX: 0.2, y: 0.98), .leftThird)
        XCTAssertEqual(DropZone.edgePlacement(atUnitX: 0.5, y: 0.98), .centerThird)
        XCTAssertEqual(DropZone.edgePlacement(atUnitX: 0.9, y: 0.98), .rightThird)
    }

    func testCornersSnapToQuarters() {
        XCTAssertEqual(DropZone.edgePlacement(atUnitX: 0.02, y: 0.1), .topLeft)
        XCTAssertEqual(DropZone.edgePlacement(atUnitX: 0.02, y: 0.9), .bottomLeft)
        XCTAssertEqual(DropZone.edgePlacement(atUnitX: 0.98, y: 0.1), .topRight)
        XCTAssertEqual(DropZone.edgePlacement(atUnitX: 0.98, y: 0.9), .bottomRight)
    }
}

final class DisplayHopTests: XCTestCase {
    // 지금 책상: 0 = Type-c (주 화면 위), 1 = Q27 (주 화면), 2 = V28UE (오른쪽 세로)
    let screens = [CGRect(x: 0, y: -1440, width: 2560, height: 1440),
                   CGRect(x: 0, y: 0, width: 2560, height: 1440),
                   CGRect(x: 2560, y: -1920, width: 2160, height: 3840)]
    let visible = [CGRect(x: 0, y: -1410, width: 2560, height: 1410),
                   CGRect(x: 0, y: 30, width: 2560, height: 1410),
                   CGRect(x: 2560, y: -1890, width: 2160, height: 3810)]

    func hop(_ p: Placement, _ window: CGRect, _ from: Int) -> DisplayHop.Hop? {
        DisplayHop.next(p, window: window, from: from, screens: screens, visible: visible)
    }

    func testRightHalfAgainGoesToTheRightDisplay() {
        let right = Placement.rightHalf.rect(in: visible[1], current: .zero)
        XCTAssertEqual(hop(.rightHalf, right, 1), .init(screen: 2, placement: .leftHalf))
    }

    func testNotYetInPlaceJustSnaps() {
        XCTAssertNil(hop(.rightHalf, CGRect(x: 100, y: 100, width: 800, height: 600), 1))
    }

    func testNoDisplayThatWayStays() {
        let left = Placement.leftHalf.rect(in: visible[1], current: .zero)
        XCTAssertNil(hop(.leftHalf, left, 1))
        let right = Placement.rightHalf.rect(in: visible[2], current: .zero)
        XCTAssertNil(hop(.rightHalf, right, 2))
    }

    func testLeftFromPortraitPicksTheDisplayTheWindowLinesUpWith() {
        let leftLow = CGRect(x: 2560, y: 30, width: 1080, height: 1000)     // 아래쪽 = Q27 높이
        let leftHigh = CGRect(x: 2560, y: -1400, width: 1080, height: 1000) // 위쪽 = Type-c 높이
        XCTAssertEqual(DisplayHop.neighbor(of: 2, dx: -1, dy: 0, window: leftLow, screens: screens), 1)
        XCTAssertEqual(DisplayHop.neighbor(of: 2, dx: -1, dy: 0, window: leftHigh, screens: screens), 0)
        let left = Placement.leftHalf.rect(in: visible[2], current: .zero)
        XCTAssertNotNil(hop(.leftHalf, left, 2))
    }

    func testRightFromTheTopDisplayGoesStraightRight() {
        // 위 모니터(Type-c)에서 오른쪽은 아래 모니터가 아니라 오른쪽 세로 모니터
        let window = CGRect(x: 300, y: -1200, width: 800, height: 500)
        XCTAssertEqual(DisplayHop.neighbor(of: 0, dx: 1, dy: 0, window: window, screens: screens), 2)
        XCTAssertNil(DisplayHop.neighbor(of: 0, dx: -1, dy: 0, window: window, screens: screens))
    }

    func testUpAndDownBetweenStackedDisplays() {
        let top = Placement.topHalf.rect(in: visible[1], current: .zero)
        XCTAssertEqual(hop(.topHalf, top, 1), .init(screen: 0, placement: .bottomHalf))
        let bottom = Placement.bottomHalf.rect(in: visible[0], current: .zero)
        XCTAssertEqual(hop(.bottomHalf, bottom, 0), .init(screen: 1, placement: .topHalf))
    }
}
