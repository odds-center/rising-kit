import AppKit
import RisingKitCore

/// 앱과, 앱이 남긴 설정·캐시를 찾아 휴지통으로 보낸다. 영구 삭제는 하지 않는다.
enum Uninstaller {
    struct AppInfo: Identifiable, Equatable {
        let path: String
        let name: String
        let bundleId: String
        var id: String { path }
        var isRunning: Bool {
            NSWorkspace.shared.runningApplications.contains { $0.bundleURL?.path == path }
        }
    }

    struct Entry: Identifiable, Equatable {
        let path: String
        /// 앱 자체인지, 남은 파일인지
        let isApp: Bool
        var size: Int64
        var id: String { path }
    }

    /// 지울 수 있는 앱 목록 (시스템 앱과 Rising Kit 자신은 제외).
    static func apps() -> [AppInfo] {
        let fm = FileManager.default
        var out: [AppInfo] = []
        for root in ["/Applications", NSHomeDirectory() + "/Applications"] {
            for entry in (try? fm.contentsOfDirectory(atPath: root)) ?? [] where entry.hasSuffix(".app") && !entry.hasPrefix(".") {
                let path = root + "/" + entry
                guard let bundle = Bundle(path: path), let bundleId = bundle.bundleIdentifier,
                      bundleId != Bundle.main.bundleIdentifier, !bundleId.hasPrefix("com.apple.") else { continue }
                var name = fm.displayName(atPath: path)
                if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
                out.append(AppInfo(path: path, name: name, bundleId: bundleId))
            }
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// 앱과 그 앱이 ~/Library 에 남긴 것들. 크기는 아직 재지 않은 상태(0)로 돌려준다.
    static func entries(for app: AppInfo) -> [Entry] {
        let fm = FileManager.default
        // 폴더 이름 맞춤에는 번역되지 않은 원래 이름(파일 이름)도 써 본다
        let fileName = ((app.path as NSString).lastPathComponent as NSString).deletingPathExtension
        var out = [Entry(path: app.path, isApp: true, size: 0)]
        let library = NSHomeDirectory() + "/Library"
        for folder in Leftovers.libraryFolders {
            let dir = library + "/" + folder
            for entry in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] {
                if Leftovers.matches(entry: entry, in: folder, bundleId: app.bundleId, appName: fileName)
                    || Leftovers.matches(entry: entry, in: folder, bundleId: app.bundleId, appName: app.name) {
                    out.append(Entry(path: dir + "/" + entry, isApp: false, size: 0))
                }
            }
        }
        return out
    }

    /// 파일이나 폴더가 디스크에서 차지하는 크기. 큰 폴더는 오래 걸릴 수 있어 백그라운드에서 부른다.
    static func size(of path: String) -> Int64 {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDirectory) else { return 0 }
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        func allocated(_ url: URL) -> Int64 {
            Int64((try? url.resourceValues(forKeys: keys))?.totalFileAllocatedSize ?? 0)
        }
        let url = URL(fileURLWithPath: path)
        guard isDirectory.boolValue,
              let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: []) else {
            return allocated(url)
        }
        var total: Int64 = 0
        for case let file as URL in enumerator { total += allocated(file) }
        return total
    }

    /// 휴지통으로 옮긴다. 옮기지 못한 경로들을 돌려준다.
    /// 직접 옮기지 못한 것(관리자 권한이 필요한 앱 등)은 Finder 에 맡겨 암호를 물어보게 한다.
    static func trash(_ paths: [String], completion: @escaping (_ failed: [String]) -> Void) {
        var needFinder: [URL] = []
        for path in paths {
            let url = URL(fileURLWithPath: path)
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            } catch {
                needFinder.append(url)
            }
        }
        guard !needFinder.isEmpty else { completion([]); return }
        NSWorkspace.shared.recycle(needFinder) { _, _ in
            let failed = needFinder.map(\.path).filter { FileManager.default.fileExists(atPath: $0) }
            DispatchQueue.main.async { completion(failed) }
        }
    }
}

/// 어떤 프로세스가 포트를 쓰는지 찾고, 원하면 종료한다.
enum PortTools {
    /// 열려 있는 TCP 포트. `port` 가 0 이면 전부. 호출한 스레드를 잠시 막는다.
    static func users(of port: Int) -> [PortUser] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        // +c 0: 프로세스 이름을 자르지 않고 전부 보여 준다
        task.arguments = ["+c", "0", "-nP", port == 0 ? "-iTCP" : "-iTCP:\(port)", "-sTCP:LISTEN"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return PortParser.parse(String(decoding: data, as: UTF8.self))
    }

    /// 확인을 받은 뒤 프로세스를 종료한다.
    static func confirmAndKill(_ user: PortUser) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\(user.command) (PID \(user.pid)) 을 종료할까요?"
        alert.informativeText = "\(user.port)번 포트를 쓰고 있는 프로세스입니다. 저장하지 않은 작업은 사라질 수 있습니다."
        alert.addButton(withTitle: "취소")
        alert.addButton(withTitle: "종료")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        if kill(pid_t(user.pid), SIGTERM) == 0 {
            Toast.show("\(user.command) 종료 신호를 보냈습니다", symbol: "xmark.circle")
        } else {
            Toast.show("종료하지 못했습니다 (권한 없음)", symbol: "exclamationmark.triangle")
        }
    }
}
