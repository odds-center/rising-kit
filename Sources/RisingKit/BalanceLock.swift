import CoreAudio
import Foundation

/// 출력 장치의 좌우 음량 균형이 틀어지면 가운데(0.5)로 되돌린다.
/// 블루투스 이어폰을 다시 연결할 때 균형이 한쪽으로 쏠리는 문제를 막는다.
final class BalanceLock {
    static let shared = BalanceLock()

    private static let defaultsKey = "balanceLockEnabled"
    private var timer: Timer?
    private var watchedDevice: AudioObjectID = 0
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var watchedAddress: AudioObjectPropertyAddress?

    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.defaultsKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.defaultsKey)
            newValue ? start() : stop()
        }
    }

    /// 장치의 좌우 균형 속성 (0.0 왼쪽 ~ 0.5 가운데 ~ 1.0 오른쪽).
    /// 헤드폰·내장 스피커 같은 실제 장치는 스테레오 팬('span')을 쓰고, 일부 가상 장치는
    /// 가상 메인 밸런스('vmbc')만 가진다. 시스템 설정 > 사운드의 "밸런스" 슬라이더가 이 값이다.
    private static func balanceAddress(for device: AudioObjectID) -> AudioObjectPropertyAddress? {
        for selector in [kAudioDevicePropertyStereoPan, AudioObjectPropertySelector(0x766D_6263)] {
            var address = AudioObjectPropertyAddress(
                mSelector: selector, mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain)
            if AudioObjectHasProperty(device, &address) { return address }
        }
        return nil
    }

    private static var defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    func startIfEnabled() {
        // 기본 출력 장치가 바뀌면(이어폰 연결 등) 새 장치를 감시한다.
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &Self.defaultOutputAddress, .main
        ) { [weak self] _, _ in
            guard let self, self.enabled else { return }
            self.watchCurrentDevice()
            self.centerIfNeeded()
        }
        if enabled { start() }
    }

    private func start() {
        watchCurrentDevice()
        centerIfNeeded()
        // 변경 알림을 보내지 않는 장치를 위한 보조 확인
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.centerIfNeeded()
        }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        unwatch()
    }

    /// 현재 균형 값. 장치가 균형 조절을 지원하지 않으면 nil.
    func currentBalance() -> Float? {
        guard let device = Self.defaultOutputDevice(), var address = Self.balanceAddress(for: device) else {
            return nil
        }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    /// 균형을 가운데로 맞춘다. 실제로 값을 바꿨으면 true.
    @discardableResult
    func centerIfNeeded() -> Bool {
        guard let device = Self.defaultOutputDevice(), var address = Self.balanceAddress(for: device),
              let balance = currentBalance(), abs(balance - 0.5) > 0.005 else { return false }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else {
            return false
        }
        var center: Float32 = 0.5
        return AudioObjectSetPropertyData(
            device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &center) == noErr
    }

    private func watchCurrentDevice() {
        guard let device = Self.defaultOutputDevice(), device != watchedDevice else { return }
        unwatch()
        guard var address = Self.balanceAddress(for: device) else { return }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, self.enabled else { return }
            self.centerIfNeeded()
        }
        if AudioObjectAddPropertyListenerBlock(device, &address, .main, listener) == noErr {
            watchedDevice = device
            watchedAddress = address
            deviceListener = listener
        }
    }

    private func unwatch() {
        if watchedDevice != 0, let listener = deviceListener, var address = watchedAddress {
            AudioObjectRemovePropertyListenerBlock(watchedDevice, &address, .main, listener)
        }
        watchedDevice = 0
        watchedAddress = nil
        deviceListener = nil
    }

    private static func defaultOutputDevice() -> AudioObjectID? {
        var device = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &defaultOutputAddress, 0, nil, &size, &device)
        return status == noErr && device != 0 ? device : nil
    }
}
