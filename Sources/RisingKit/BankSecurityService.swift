import AppKit
import RisingKitCore

/// 은행 보안 프로그램의 백그라운드 항목을 찾아 한 번에 끄고 켠다.
enum BankSecurityService {
    struct Status {
        let jobs: [BankSecurity.Job]
        /// 지금 올라와 있는 항목의 이름표
        let loaded: Set<String>

        var running: Int { loaded.count }
        var isOn: Bool { !loaded.isEmpty }
    }

    /// 등록된 항목과 지금 상태. launchctl 을 여러 번 실행하므로 백그라운드에서 부른다.
    static func status() -> Status {
        let jobs = discover()
        let uid = Int(getuid())
        var loaded = Set<String>()
        for job in jobs where BankSecurity.isSafe(job) {
            let target = job.isSystem ? "system/\(job.label)" : "gui/\(uid)/\(job.label)"
            if run("/bin/launchctl", ["print", target]) == 0 { loaded.insert(job.label) }
        }
        return Status(jobs: jobs, loaded: loaded)
    }

    /// launchd 에 등록된 은행 보안 프로그램 항목들.
    static func discover() -> [BankSecurity.Job] {
        let folders: [(String, Bool)] = [
            ("/Library/LaunchDaemons", true),
            ("/Library/LaunchAgents", false),
            (NSHomeDirectory() + "/Library/LaunchAgents", false),
        ]
        var jobs: [BankSecurity.Job] = []
        for (folder, isSystem) in folders {
            for entry in (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [] where entry.hasSuffix(".plist") {
                let path = folder + "/" + entry
                // 이름표는 파일 안의 Label 이 기준이다 (파일 이름과 다를 수 있다)
                let label = (NSDictionary(contentsOfFile: path)?["Label"] as? String) ?? String(entry.dropLast(6))
                if BankSecurity.isSecurityJob(label: label) {
                    jobs.append(BankSecurity.Job(label: label, plistPath: path, isSystem: isSystem))
                }
            }
        }
        return jobs.sorted { $0.label < $1.label }
    }

    /// 전부 켜거나 끈다. 시스템 항목이 있으면 macOS 가 관리자 암호를 묻는다.
    /// 끝나면 주 스레드에서 `completion` 을 부른다 (false 는 암호 입력을 취소했거나 실패).
    static func set(on: Bool, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let current = status()
            // 이미 원하는 상태인 항목은 건드리지 않는다
            let targets = current.jobs.filter { current.loaded.contains($0.label) != on }
            let uid = Int(getuid())
            let userCommands = BankSecurity.commands(for: targets.filter { !$0.isSystem }, turnOn: on, uid: uid)
            let systemCommands = BankSecurity.commands(for: targets.filter(\.isSystem), turnOn: on, uid: uid)

            for command in userCommands {
                let parts = command.split(separator: " ").map(String.init)
                _ = run(parts[0], Array(parts.dropFirst()))
            }
            var ok = true
            if !systemCommands.isEmpty {
                // 하나가 실패해도(이미 내려가 있는 경우 등) 나머지를 계속하도록 ; 로 잇는다
                let script = systemCommands.joined(separator: "; ") + "; true"
                ok = runAsAdministrator(script)
            }
            DispatchQueue.main.async { completion(ok) }
        }
    }

    /// 메뉴·런처에서 부르는 형태: 지금 상태를 뒤집고 결과를 알려 준다.
    static func toggleAndReport() {
        DispatchQueue.global(qos: .userInitiated).async {
            let turnOn = !status().isOn
            set(on: turnOn) { ok in
                Toast.show(ok ? (turnOn ? "은행 보안 프로그램을 켰습니다" : "은행 보안 프로그램을 껐습니다")
                              : "바꾸지 못했습니다 (관리자 암호 입력이 취소됨)",
                           symbol: turnOn ? "lock.shield" : "shield.slash")
                SettingsModel.shared.bump()
            }
        }
    }

    @discardableResult
    private static func run(_ path: String, _ arguments: [String]) -> Int32 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return -1 }
        let done = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in done.signal() }
        if task.isRunning { done.wait() }
        return task.terminationStatus
    }

    /// macOS 의 관리자 암호 창을 거쳐 실행한다. 명령은 `BankSecurity.commands` 가 만든,
    /// 안전한 글자만으로 된 것이어야 한다.
    private static func runAsAdministrator(_ shell: String) -> Bool {
        let escaped = shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with prompt \"Rising Kit 이 은행 보안 프로그램을 켜거나 끄려고 합니다.\" with administrator privileges"
        return run("/usr/bin/osascript", ["-e", source]) == 0
    }
}
