import Foundation

/// 앱 하나가 쓰는 메모리와 CPU (보조 프로세스를 합친 값).
public struct AppUsage: Equatable {
    public let name: String
    /// 실제 사용 메모리 (KB)
    public let memoryKB: Int
    /// CPU 사용률. 코어 하나를 다 쓰면 100 이라서 100 을 넘을 수 있다.
    public let cpu: Double
    public let processes: Int

    public var memoryText: String { ProcessUsage.formatMemory(kilobytes: memoryKB) }
    public var cpuText: String { String(format: "%.0f%%", cpu) }
}

public enum ProcessUsage {
    /// `ps -axo rss=,pcpu=,comm=` 출력을 앱 단위로 묶는다.
    /// 브라우저처럼 탭마다 프로세스가 따로 뜨는 앱은 바깥 .app 이름으로 합친다.
    public static func group(_ psOutput: String) -> [AppUsage] {
        var memory: [String: Int] = [:]
        var cpu: [String: Double] = [:]
        var count: [String: Int] = [:]
        for line in psOutput.split(separator: "\n") {
            let fields = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard fields.count == 3, let rss = Int(fields[0]), let pcpu = Double(fields[1]) else { continue }
            let name = appName(fromCommand: String(fields[2]))
            memory[name, default: 0] += rss
            cpu[name, default: 0] += pcpu
            count[name, default: 0] += 1
        }
        return memory.keys.map {
            AppUsage(name: $0, memoryKB: memory[$0] ?? 0, cpu: cpu[$0] ?? 0, processes: count[$0] ?? 0)
        }
    }

    /// 실행 파일 경로에서 앱 이름을 뽑는다. 경로에 .app 이 있으면 가장 바깥 앱, 없으면 실행 파일 이름.
    static func appName(fromCommand command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        for component in trimmed.split(separator: "/") where component.hasSuffix(".app") {
            return String(component.dropLast(4))
        }
        return trimmed.split(separator: "/").last.map(String.init) ?? trimmed
    }

    public static func topByMemory(_ apps: [AppUsage], _ limit: Int) -> [AppUsage] {
        Array(apps.sorted { $0.memoryKB != $1.memoryKB ? $0.memoryKB > $1.memoryKB : $0.name < $1.name }.prefix(limit))
    }

    public static func topByCPU(_ apps: [AppUsage], _ limit: Int) -> [AppUsage] {
        Array(apps.sorted { $0.cpu != $1.cpu ? $0.cpu > $1.cpu : $0.name < $1.name }.prefix(limit))
    }

    /// 1GB 이상은 "2.6 GB", 그 아래는 "340 MB"
    public static func formatMemory(kilobytes: Int) -> String {
        let mb = Double(kilobytes) / 1024
        return mb >= 1024 ? String(format: "%.1f GB", mb / 1024) : String(format: "%.0f MB", mb)
    }

    public static func formatMemory(bytes: UInt64) -> String {
        formatMemory(kilobytes: Int(bytes / 1024))
    }
}
