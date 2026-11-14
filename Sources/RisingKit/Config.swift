import Foundation
import RisingKitCore

/// 저장된 창 배치 하나: 어느 앱의 창이 어느 디스플레이의 어디에 놓이는지.
struct Layout: Codable {
    struct Item: Codable {
        var bundleId: String
        var app: String
        /// 같은 앱의 창이 여러 개일 때 구분용. 일치하는 제목이 없으면 순서대로 짝짓는다.
        var title: String
        /// 왼쪽에서 오른쪽 순서로 매긴 디스플레이 번호 (0부터)
        var display: Int
        var rect: FractionRect
    }

    var name: String
    var items: [Item]
    /// 적용할 때 창을 맨 앞으로 가져올지. "이 앱을 여기로" 식의 단축키에 쓴다.
    var activate: Bool? = nil
}

/// 사용자 정의 영역: 맨 앞 창을 화면의 지정한 비율 위치에 놓는다.
struct Zone: Codable {
    var name: String
    /// nil 이면 창이 지금 있는 디스플레이
    var display: Int?
    var rect: FractionRect
}

/// 소리 출력 순서에 넣어 둔 장치 (연결돼 있지 않을 때도 이름을 보여 주려고 이름을 함께 둔다).
struct AudioChoice: Codable, Equatable {
    var uid: String
    var name: String
}

struct Config: Codable {
    /// 명령 id → 단축키 문자열. 빈 문자열은 "단축키 없음". 없는 항목은 기본값을 쓴다.
    var shortcuts: [String: String] = [:]
    var layouts: [Layout] = []
    var zones: [Zone] = []
    /// 날씨를 볼 도시. 없으면 서울.
    var weather: WeatherLocation?
    /// 창 단축키와 끌어 붙이기를 쓰지 않을 앱의 번들 id
    var ignoredApps: [String] = []
    /// 창을 화면 가장자리로 끌면 붙이기
    var dragSnap = true
    /// 복사한 내용을 기록해 둘지
    var clipboardHistory = true
    /// 스크럼 초안을 만들 때 저장소를 찾아볼 폴더
    var scrumFolders = ["~/orca/projects", "~/orca/workspaces", "~/Desktop", "~/Documents"]
    /// 스크럼에서 저장소 이름 대신 쓸 이름 (저장소 이름 → 부르는 이름)
    var scrumNames: [String: String] = [:]
    /// 스크럼에 넣을 저장소 ("소유자/이름"). nil 이면 찾은 저장소 전부.
    var scrumRepos: [String]?
    /// 내 커밋으로 볼 추가 이메일·이름 (git 설정의 이름과 이메일은 자동으로 포함)
    var scrumAuthors: [String] = []
    /// 소리 출력을 아래 순서대로 고정할지, 그리고 그 순서 (앞이 우선)
    var audioPin = false
    var audioPriority: [AudioChoice] = []
    /// 파일 정리: 무엇을, 며칠 지난 것부터, 자동으로 할지
    var tidyScreenshots = true
    var tidyDownloads = true
    var tidyScreenshotDays = 7
    var tidyDownloadDays = 30
    var tidyAuto = false
    /// 새 버전이 나오면 알아서 받아 설치하고 다시 시작할지 (끄면 알리기만)
    var autoUpdate = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shortcuts = try c.decodeIfPresent([String: String].self, forKey: .shortcuts) ?? [:]
        layouts = try c.decodeIfPresent([Layout].self, forKey: .layouts) ?? []
        zones = try c.decodeIfPresent([Zone].self, forKey: .zones) ?? []
        weather = try c.decodeIfPresent(WeatherLocation.self, forKey: .weather)
        ignoredApps = try c.decodeIfPresent([String].self, forKey: .ignoredApps) ?? []
        dragSnap = try c.decodeIfPresent(Bool.self, forKey: .dragSnap) ?? true
        clipboardHistory = try c.decodeIfPresent(Bool.self, forKey: .clipboardHistory) ?? true
        scrumFolders = try c.decodeIfPresent([String].self, forKey: .scrumFolders) ?? scrumFolders
        scrumNames = try c.decodeIfPresent([String: String].self, forKey: .scrumNames) ?? [:]
        scrumRepos = try c.decodeIfPresent([String].self, forKey: .scrumRepos)
        scrumAuthors = try c.decodeIfPresent([String].self, forKey: .scrumAuthors) ?? []
        audioPin = try c.decodeIfPresent(Bool.self, forKey: .audioPin) ?? false
        audioPriority = try c.decodeIfPresent([AudioChoice].self, forKey: .audioPriority) ?? []
        tidyScreenshots = try c.decodeIfPresent(Bool.self, forKey: .tidyScreenshots) ?? true
        tidyDownloads = try c.decodeIfPresent(Bool.self, forKey: .tidyDownloads) ?? true
        tidyScreenshotDays = try c.decodeIfPresent(Int.self, forKey: .tidyScreenshotDays) ?? 7
        tidyDownloadDays = try c.decodeIfPresent(Int.self, forKey: .tidyDownloadDays) ?? 30
        tidyAuto = try c.decodeIfPresent(Bool.self, forKey: .tidyAuto) ?? false
        autoUpdate = try c.decodeIfPresent(Bool.self, forKey: .autoUpdate) ?? true
    }
}

/// ~/Library/Application Support/RisingKit/config.json
final class ConfigStore {
    static let shared = ConfigStore()

    static let fileURL: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("RisingKit/config.json")

    private(set) var config = Config()
    /// 설정이 바뀔 때마다 호출된다 (단축키 재등록 등).
    var onChange: (() -> Void)?

    private init() {
        guard let data = try? Data(contentsOf: Self.fileURL) else { return }
        do {
            config = try JSONDecoder().decode(Config.self, from: data)
        } catch {
            // 깨진 설정을 덮어써 버리지 않도록 옆에 보관한다
            let backup = Self.fileURL.deletingLastPathComponent().appendingPathComponent("config.broken.json")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.copyItem(at: Self.fileURL, to: backup)
            NSLog("RisingKit: config.json 을 읽지 못해 기본값으로 시작합니다 (\(error.localizedDescription))")
        }
    }

    func update(_ change: (inout Config) -> Void) {
        change(&config)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try FileManager.default.createDirectory(
                at: Self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(config).write(to: Self.fileURL, options: .atomic)
        } catch {
            NSLog("RisingKit: 설정 저장 실패 (\(error.localizedDescription))")
        }
        onChange?()
    }
}
