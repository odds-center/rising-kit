import AppKit
import CoreAudio
import RisingKitCore

/// 소리 출력 장치 하나.
struct AudioDevice: Equatable, Identifiable {
    let id: AudioObjectID
    /// 다시 연결해도 변하지 않는 식별자
    let uid: String
    let name: String
    /// 실제 스피커가 아닌 가상 장치 (BoomAudio 같은 것)
    let isVirtual: Bool
}

/// 소리 출력 장치를 고르고, 정해 둔 순서대로 고정한다.
/// 모니터를 꽂거나 가상 오디오 장치가 끼어들어 기본 출력이 멋대로 바뀌는 것을 되돌린다.
final class AudioRouter {
    static let shared = AudioRouter()

    private static let system = AudioObjectID(kAudioObjectSystemObject)
    private var pending: DispatchWorkItem?

    var pinEnabled: Bool { ConfigStore.shared.config.audioPin }

    func start() {
        // 장치가 연결·해제되거나 기본 출력이 바뀔 때마다 순서를 다시 적용한다
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice] {
            var address = AudioObjectPropertyAddress(
                mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            AudioObjectAddPropertyListenerBlock(Self.system, &address, .main) { [weak self] _, _ in
                self?.scheduleEnforce()
            }
        }
        scheduleEnforce()
    }

    /// 연달아 오는 변경 알림을 한 번으로 모은다 (장치를 꽂으면 여러 번 온다).
    private func scheduleEnforce() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.enforce()
            SettingsModel.shared.bump()
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    /// 고정이 켜져 있으면, 연결된 장치 중 순서가 가장 앞선 것으로 맞춘다.
    private func enforce() {
        guard pinEnabled else { return }
        let devices = Self.outputDevices()
        let priority = ConfigStore.shared.config.audioPriority.map(\.uid)
        let current = Self.defaultOutput().flatMap { id in devices.first { $0.id == id }?.uid }
        guard let target = AudioPriority.change(priority: priority, available: devices.map(\.uid), current: current),
              let device = devices.first(where: { $0.uid == target }) else { return }
        Self.setDefaultOutput(device.id)
        Toast.show("소리 출력을 \(device.name) 로 되돌렸습니다", symbol: "speaker.wave.2")
    }

    /// 사용자가 직접 고른 장치로 바꾼다. 고정이 켜져 있으면 그 장치를 맨 앞 순위로 올린다.
    func select(_ device: AudioDevice) {
        Self.setDefaultOutput(device.id)
        if pinEnabled {
            ConfigStore.shared.update { config in
                let order = AudioPriority.promote(device.uid, in: config.audioPriority.map(\.uid))
                var byUID = Dictionary(config.audioPriority.map { ($0.uid, $0) }, uniquingKeysWith: { a, _ in a })
                byUID[device.uid] = AudioChoice(uid: device.uid, name: device.name)
                config.audioPriority = order.compactMap { byUID[$0] }
            }
        }
    }

    /// 고정을 켜고 끈다. 처음 켤 때 순서가 비어 있으면 지금 쓰는 장치부터 실제 장치들로 채운다.
    func setPin(_ on: Bool) {
        ConfigStore.shared.update { config in
            config.audioPin = on
            if on, config.audioPriority.isEmpty {
                let devices = Self.outputDevices().filter { !$0.isVirtual }
                let current = Self.defaultOutput()
                let ordered = devices.filter { $0.id == current } + devices.filter { $0.id != current }
                config.audioPriority = ordered.map { AudioChoice(uid: $0.uid, name: $0.name) }
            }
        }
        scheduleEnforce()
    }

    // MARK: - CoreAudio

    static func outputDevices() -> [AudioDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard outputChannels(id) > 0, let uid = string(id, kAudioDevicePropertyDeviceUID),
                  let name = string(id, kAudioObjectPropertyName) else { return nil }
            return AudioDevice(id: id, uid: uid, name: name,
                               isVirtual: uint32(id, kAudioDevicePropertyTransportType) == kAudioDeviceTransportTypeVirtual)
        }
    }

    static func defaultOutput() -> AudioObjectID? {
        let id = uint32(system, kAudioHardwarePropertyDefaultOutputDevice)
        return id == 0 ? nil : id
    }

    /// 소리 출력과 효과음 출력을 함께 바꾼다 (효과음만 다른 장치에 남는 일을 막는다).
    static func setDefaultOutput(_ id: AudioObjectID) {
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultSystemOutputDevice] {
            var address = AudioObjectPropertyAddress(
                mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var device = id
            AudioObjectSetPropertyData(system, &address, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &device)
        }
    }

    private static func uint32(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value)
        return value
    }

    private static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    private static func outputChannels(_ id: AudioObjectID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration, mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, buffer) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(buffer.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}
