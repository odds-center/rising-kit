import Darwin
import Foundation
import RisingKitCore

/// 메모리와 CPU 사용량을 읽는다 (보기만 한다. 아무것도 정리하거나 종료하지 않는다).
final class SystemStats {
    static let shared = SystemStats()

    struct Memory {
        /// 활성 상태 보기의 "사용된 메모리"와 같은 기준: 앱 메모리 + 와이어드 + 압축됨
        let used: UInt64
        let total: UInt64
        let swapUsed: UInt64
        /// 1 정상, 2 주의, 4 위험
        let pressureLevel: Int

        var pressureText: String {
            switch pressureLevel {
            case 4: return "위험"
            case 2: return "주의"
            default: return "정상"
            }
        }
    }

    private var timer: Timer?
    private var lastTicks: (busy: UInt64, total: UInt64)?
    /// 최근 5초 동안의 전체 CPU 사용률 (0~100). 아직 두 번 재지 못했으면 nil.
    private(set) var cpuPercent: Double?

    /// CPU 사용률은 두 시점의 차이로 구하므로 주기적으로 재 둔다.
    func start() {
        sampleCPU()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.sampleCPU() }
    }

    private func sampleCPU() {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        // cpu_ticks: (user, system, idle, nice)
        let user = UInt64(info.cpu_ticks.0), system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        let busy = user + system + nice
        let total = busy + idle
        if let last = lastTicks, total > last.total {
            cpuPercent = Double(busy - last.busy) / Double(total - last.total) * 100
        }
        lastTicks = (busy, total)
    }

    func memory() -> Memory? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let page = UInt64(vm_kernel_page_size)
        let appPages = UInt64(stats.internal_page_count) - min(UInt64(stats.purgeable_count), UInt64(stats.internal_page_count))
        let used = (appPages + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0)

        var level: Int32 = 1
        var levelSize = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &levelSize, nil, 0)

        return Memory(used: used, total: ProcessInfo.processInfo.physicalMemory,
                      swapUsed: swap.xsu_used, pressureLevel: Int(level))
    }

    /// 앱별 메모리·CPU. `ps` 를 한 번 실행한다.
    func apps() -> [AppUsage] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axo", "rss=,pcpu=,comm="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return [] }
        // 출력이 끝날 때까지 읽으면 충분하다. waitUntilExit 는 실행 루프를 돌려서 부르지 않는다.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return ProcessUsage.group(String(decoding: data, as: UTF8.self))
    }

    /// "메모리 11.2 / 18.0 GB · 스왑 3.1 GB"
    var memorySummary: String {
        guard let m = memory() else { return "메모리 정보를 읽지 못함" }
        var text = "메모리 \(ProcessUsage.formatMemory(bytes: m.used).replacingOccurrences(of: " GB", with: "")) / "
            + "\(ProcessUsage.formatMemory(bytes: m.total))"
        if m.swapUsed > 64 * 1024 * 1024 { text += " · 스왑 \(ProcessUsage.formatMemory(bytes: m.swapUsed))" }
        if m.pressureLevel > 1 { text += " · 압력 \(m.pressureText)" }
        return text
    }

    var cpuSummary: String {
        guard let cpuPercent else { return "CPU 측정 중…" }
        return String(format: "CPU %.0f%%", cpuPercent)
    }
}
