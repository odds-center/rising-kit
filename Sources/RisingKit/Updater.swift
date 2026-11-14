import AppKit
import RisingKitCore

/// GitHub 최신 릴리스를 보고 새 버전이면 디스크 이미지를 받아 앱을 바꾸고 다시 실행한다.
/// 켜고 조금 뒤와 6시간마다 확인한다. "자동 업데이트"가 꺼져 있으면 알리기만 한다.
final class Updater {
    static let shared = Updater()
    static let repo = "odds-center/rising-kit"

    /// 받을 수 있는 새 버전
    private(set) var available: (version: String, url: URL)?
    private(set) var lastChecked: Date?
    private(set) var busy = false
    private(set) var lastError: String?
    private var timer: Timer?

    var current: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { self.check(userInitiated: false) }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            self?.check(userInitiated: false)
        }
    }

    /// `userInitiated` 면 결과를 알리고, 새 버전이 있으면 바로 설치한다.
    func check(userInitiated: Bool) {
        guard !busy else { return }
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("RisingKit/\(current)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        if userInitiated { Toast.show("업데이트 확인 중…", symbol: "arrow.triangle.2.circlepath") }
        URLSession.shared.dataTask(with: request) { data, _, _ in
            DispatchQueue.main.async { self.handle(data, userInitiated: userInitiated) }
        }.resume()
    }

    private func handle(_ data: Data?, userInitiated: Bool) {
        lastChecked = Date()
        defer { SettingsModel.shared.bump() }
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let assets = json["assets"] as? [[String: Any]],
              let dmg = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".dmg") == true }),
              let link = dmg["browser_download_url"] as? String, let url = URL(string: link) else {
            lastError = "확인하지 못했습니다 (인터넷 연결이나 GitHub 응답)"
            if userInitiated { Toast.show("업데이트를 확인하지 못했습니다", symbol: "exclamationmark.triangle") }
            return
        }
        lastError = nil
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard AppVersion.isNewer(version, than: current) else {
            available = nil
            if userInitiated { Toast.show("최신 버전입니다 (\(current))", symbol: "checkmark.circle") }
            return
        }
        available = (version, url)
        if userInitiated || ConfigStore.shared.config.autoUpdate {
            install()
        } else {
            Toast.show("새 버전 \(version) 이 있습니다 · 메뉴에서 설치", symbol: "arrow.down.circle")
        }
    }

    /// 받아서 확인한 뒤, 이 앱이 끝나면 바꿔 넣고 다시 여는 작은 스크립트를 띄우고 종료한다.
    func install() {
        guard let available, !busy else { return }
        busy = true
        SettingsModel.shared.bump()
        Toast.show("Rising Kit \(available.version) 받는 중…", symbol: "arrow.down.circle")
        URLSession.shared.downloadTask(with: available.url) { file, _, _ in
            let result = Result { try Self.prepare(downloaded: file) }
            DispatchQueue.main.async {
                switch result {
                case .success(let staged):
                    self.relaunch(with: staged)
                case .failure(let error):
                    self.busy = false
                    self.lastError = "\(error.localizedDescription)"
                    SettingsModel.shared.bump()
                    Toast.show("업데이트하지 못했습니다", symbol: "exclamationmark.triangle")
                }
            }
        }.resume()
    }

    struct UpdateError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    /// 디스크 이미지를 열어 앱을 임시 폴더로 꺼내고, 같은 앱인지 · 서명이 맞는지 확인한다.
    private static func prepare(downloaded file: URL?) throws -> URL {
        guard let file else { throw UpdateError("받지 못했습니다") }
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("RisingKitUpdate-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        let dmg = work.appendingPathComponent("update.dmg")
        try fm.moveItem(at: file, to: dmg)
        let mount = work.appendingPathComponent("mnt")
        try run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path])
        defer { _ = try? run("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) }

        let staged = work.appendingPathComponent("Rising Kit.app")
        try fm.copyItem(at: mount.appendingPathComponent("Rising Kit.app"), to: staged)
        guard Bundle(url: staged)?.bundleIdentifier == Bundle.main.bundleIdentifier else {
            throw UpdateError("받은 앱이 Rising Kit 이 아닙니다")
        }
        try run("/usr/bin/codesign", ["--verify", "--deep", staged.path])
        _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staged.path])
        return staged
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) throws -> Int32 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: tool)
        task.arguments = arguments
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            throw UpdateError("\((tool as NSString).lastPathComponent) 실패 (\(task.terminationStatus))")
        }
        return task.terminationStatus
    }

    private func relaunch(with staged: URL) {
        // 이 앱이 끝날 때까지 기다렸다가 바꿔 넣는다. 실패하면 예전 앱을 되돌려 놓고 다시 연다.
        let script = """
        while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
        rm -rf "$2.old"
        if mv "$2" "$2.old" && mv "$3" "$2"; then rm -rf "$2.old"; else [ -d "$2" ] || mv "$2.old" "$2"; fi
        open "$2"
        rm -rf "$4"
        """
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", script, "sh", "\(getpid())", Bundle.main.bundlePath, staged.path,
                          staged.deletingLastPathComponent().path]
        do {
            try task.run()
        } catch {
            busy = false
            Toast.show("업데이트하지 못했습니다", symbol: "exclamationmark.triangle")
            return
        }
        Toast.show("Rising Kit \(available?.version ?? "") 으로 다시 시작합니다", symbol: "arrow.triangle.2.circlepath")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { NSApp.terminate(nil) }
    }
}
