import AppKit
import RisingKitCore
import ServiceManagement
import SwiftUI

// MARK: - 창 정렬

struct WindowTab: View {
    @ObservedObject private var settings = SettingsModel.shared

    private static let groups: [(String, [Placement])] = [
        ("절반", [.leftHalf, .rightHalf, .topHalf, .bottomHalf]),
        ("1/4", [.topLeft, .topRight, .bottomLeft, .bottomRight]),
        ("1/3 · 2/3", [.leftThird, .centerThird, .rightThird, .leftTwoThirds, .centerTwoThirds, .rightTwoThirds]),
        ("전체 · 가운데", [.maximize, .center]),
    ]

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        let config = ConfigStore.shared.config
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Self.groups, id: \.0) { title, placements in
                VStack(alignment: .leading, spacing: 6) {
                    SectionTitle(title)
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                        ForEach(placements, id: \.rawValue) { placement in
                            placementCell(placement)
                        }
                    }
                }
            }

            SectionTitle("옮기기")
            Card {
                VStack(spacing: 4) {
                    commandRow("window.nextDisplay")
                    commandRow("window.prevDisplay")
                    commandRow("window.restore")
                }
            }

            SectionTitle("동작")
            Card {
                VStack(spacing: 6) {
                    SettingRow(symbol: "arrow.up.left.and.arrow.down.right", title: "끌어서 가장자리에 붙이기",
                               detail: "창을 끌어 화면 가장자리에 대면 절반·1/4·최대화·1/3 로 맞춥니다") {
                        Toggle("", isOn: Binding(
                            get: { config.dragSnap },
                            set: { value in ConfigStore.shared.update { $0.dragSnap = value } }))
                            .toggleStyle(.switch).labelsHidden().controlSize(.small)
                    }
                    Divider()
                    SettingRow(symbol: "minus.circle", title: "창 단축키를 쓰지 않는 앱",
                               detail: config.ignoredApps.isEmpty
                                   ? "없음 · 메뉴바 아이콘 메뉴에서 맨 앞 앱을 추가할 수 있습니다"
                                   : "이 앱이 앞에 있으면 단축키가 그 앱으로 전달됩니다") { EmptyView() }
                    ForEach(config.ignoredApps, id: \.self) { bundleId in
                        HStack {
                            Text(Self.appName(bundleId)).font(.system(size: 12))
                            Text(bundleId).font(.system(size: 11)).foregroundStyle(.tertiary)
                            Spacer()
                            Button("빼기") { ConfigStore.shared.update { $0.ignoredApps.removeAll { $0 == bundleId } } }
                                .controlSize(.small)
                        }
                        .padding(.leading, 30)
                    }
                }
            }

            HStack {
                Spacer()
                Button("창 정렬 단축키를 모두 기본값으로") {
                    ConfigStore.shared.update { config in
                        for command in Commands.window { config.shortcuts.removeValue(forKey: command.id) }
                    }
                }
                .controlSize(.small)
            }
        }
        .id(settings.revision)
    }

    private func placementCell(_ placement: Placement) -> some View {
        let id = "window." + placement.rawValue
        let title = Commands.window.first { $0.id == id }?.title ?? placement.rawValue
        return HStack(spacing: 9) {
            PlacementGlyph(placement: placement)
            Text(title.hasPrefix("창 ") ? String(title.dropFirst(2)) : title)
                .font(.system(size: 12.5))
                .lineLimit(1)
            Spacer(minLength: 4)
            ShortcutField(commandID: id)
        }
        .padding(.horizontal, 10)
        .frame(height: 42)
        .background(RoundedRectangle(cornerRadius: Design.corner, style: .continuous).fill(Design.cardFill))
        .overlay(RoundedRectangle(cornerRadius: Design.corner, style: .continuous).strokeBorder(Design.cardStroke))
    }

    private static func appName(_ bundleId: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return bundleId }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

/// 명령 하나: 아이콘, 이름, 단축키.
@ViewBuilder func commandRow(_ id: String, detail: String = "") -> some View {
    if let command = Commands.all.first(where: { $0.id == id }) {
        SettingRow(symbol: command.symbol, title: command.title, detail: detail) {
            ShortcutField(commandID: id)
        }
    }
}

// MARK: - 단축키

struct ShortcutsTab: View {
    @ObservedObject private var settings = SettingsModel.shared

    var body: some View {
        let config = ConfigStore.shared.config
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("열기")
            Card {
                VStack(spacing: 4) {
                    commandRow("launcher.toggle", detail: "앱, 설정, 파일, 명령, 계산, 날짜 검색")
                    commandRow("map.toggle", detail: "이 창의 배치도 화면을 엽니다")
                }
            }

            SectionTitle("도구")
            Card {
                VStack(spacing: 4) {
                    commandRow("clipboard.open", detail: "복사했던 글·파일·이미지를 찾아 다시 붙여 넣습니다")
                    ForEach(Commands.tools, id: \.id) { command in commandRow(command.id) }
                }
            }

            SectionTitle("빠른 토글")
            Card {
                VStack(spacing: 4) {
                    ForEach(Commands.toggles, id: \.id) { command in commandRow(command.id) }
                }
            }

            SectionTitle("저장한 배치")
            Card {
                if config.layouts.isEmpty {
                    Text("없음 · 디스플레이 배치도에서 만듭니다").font(.system(size: 12)).foregroundStyle(.tertiary)
                } else {
                    VStack(spacing: 4) {
                        ForEach(config.layouts, id: \.name) { layout in
                            SettingRow(symbol: layout.items.count == 1 ? "macwindow" : "rectangle.3.group.fill",
                                       title: layout.name, detail: "창 \(layout.items.count)개") {
                                ShortcutField(commandID: "layout:" + layout.name)
                                Button { Layouts.delete(name: layout.name) } label: { Image(systemName: "trash") }
                                    .buttonStyle(.borderless)
                                    .help("삭제")
                            }
                        }
                    }
                }
            }

            SectionTitle("사용자 영역")
            Card {
                if config.zones.isEmpty {
                    Text("없음 · Claude 에게 \"가운데 70% 영역을 만들어 줘\"처럼 말하면 만들어집니다")
                        .font(.system(size: 12)).foregroundStyle(.tertiary)
                } else {
                    VStack(spacing: 4) {
                        ForEach(config.zones, id: \.name) { zone in
                            SettingRow(symbol: "rectangle.dashed", title: zone.name,
                                       detail: String(format: "가로 %.0f%% · 세로 %.0f%%", zone.rect.width * 100, zone.rect.height * 100)) {
                                ShortcutField(commandID: "zone:" + zone.name)
                                Button {
                                    ConfigStore.shared.update { config in
                                        config.zones.removeAll { $0.name == zone.name }
                                        config.shortcuts.removeValue(forKey: "zone:" + zone.name)
                                    }
                                } label: { Image(systemName: "trash") }
                                    .buttonStyle(.borderless)
                                    .help("삭제")
                            }
                        }
                    }
                }
            }
        }
        .id(settings.revision)
    }
}

// MARK: - 메모리 · CPU

/// 사용량을 주기적으로 읽어 화면에 넘긴다. `ps` 실행은 백그라운드에서 한다
/// (화면을 그리는 도중에 프로세스를 실행하고 기다리면 SwiftUI 가 다시 들어와 충돌한다).
final class UsageModel: ObservableObject {
    @Published private(set) var apps: [AppUsage] = []
    @Published private(set) var memory: SystemStats.Memory?
    @Published private(set) var cpu: Double?
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.sample() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func sample() {
        DispatchQueue.global(qos: .utility).async {
            let apps = SystemStats.shared.apps()
            let memory = SystemStats.shared.memory()
            DispatchQueue.main.async {
                self.apps = apps
                self.memory = memory
                self.cpu = SystemStats.shared.cpuPercent
            }
        }
    }
}

struct SystemTab: View {
    @StateObject private var usage = UsageModel()

    var body: some View {
        let apps = usage.apps
        let memory = usage.memory
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Card {
                    gauge(title: "메모리",
                          value: memory.map { "\(ProcessUsage.formatMemory(bytes: $0.used)) / \(ProcessUsage.formatMemory(bytes: $0.total))" } ?? "–",
                          fraction: memory.map { Double($0.used) / Double(max($0.total, 1)) } ?? 0,
                          note: memory.map { "압력 \($0.pressureText) · 스왑 \(ProcessUsage.formatMemory(bytes: $0.swapUsed))" } ?? "",
                          warn: (memory?.pressureLevel ?? 1) > 1)
                }
                Card {
                    gauge(title: "CPU", value: usage.cpu.map { String(format: "%.0f%%", $0) } ?? "측정 중…",
                          fraction: (usage.cpu ?? 0) / 100, note: "최근 5초 평균 · 전체 코어 기준", warn: false)
                }
            }
            HStack(alignment: .top, spacing: 12) {
                usageList("메모리를 많이 쓰는 앱", ProcessUsage.topByMemory(apps, 8)) { $0.memoryText } fraction: { app, top in
                    Double(app.memoryKB) / Double(max(top.memoryKB, 1))
                }
                usageList("CPU 를 많이 쓰는 앱", ProcessUsage.topByCPU(apps, 8)) { $0.cpuText } fraction: { app, top in
                    app.cpu / max(top.cpu, 1)
                }
            }
            Text("브라우저처럼 프로세스가 여러 개인 앱은 하나로 합쳤습니다. 앱별 CPU 는 코어 하나가 100% 입니다. 보기만 하며 아무것도 종료하지 않습니다.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        // 이 탭이 보이는 동안만 3초마다 다시 읽는다
        .onAppear { usage.start() }
        .onDisappear { usage.stop() }
    }

    private func gauge(title: String, value: String, fraction: Double, note: String, warn: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(value).font(.system(size: 17, weight: .semibold).monospacedDigit())
            }
            bar(fraction, color: warn ? .orange : .accentColor, height: 7)
            Text(note).font(.system(size: 11)).foregroundStyle(warn ? Color.orange : Color.secondary)
        }
    }

    private func bar(_ fraction: Double, color: Color, height: CGFloat) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(color).frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: height)
    }

    private func usageList(
        _ title: String, _ apps: [AppUsage], value: @escaping (AppUsage) -> String,
        fraction: @escaping (AppUsage, AppUsage) -> Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(title)
            Card(padding: 12) {
                VStack(spacing: 7) {
                    ForEach(apps, id: \.name) { app in
                        VStack(spacing: 3) {
                            HStack {
                                Text(app.name).font(.system(size: 12)).lineLimit(1)
                                if app.processes > 1 {
                                    Text("\(app.processes)").font(.system(size: 10)).foregroundStyle(.tertiary)
                                }
                                Spacer()
                                Text(value(app)).font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary)
                            }
                            bar(apps.first.map { fraction(app, $0) } ?? 0, color: Color.accentColor.opacity(0.75), height: 3)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 일반

struct GeneralTab: View {
    @ObservedObject private var settings = SettingsModel.shared
    @State private var city = ""
    @State private var cityError = ""

    private var updateTitle: String {
        let updater = Updater.shared
        if let next = updater.available { return updater.busy ? "\(next.version) 받는 중…" : "새 버전 \(next.version)" }
        return "자동 업데이트 · 지금 \(updater.current)"
    }

    private var updateDetail: String {
        let updater = Updater.shared
        if let error = updater.lastError { return error }
        var text = "켜 두면 새 버전이 나올 때 알아서 받아 설치하고 다시 시작합니다"
        if let checked = updater.lastChecked {
            let formatter = DateFormatter()
            formatter.dateFormat = "M월 d일 HH:mm"
            text += " · 마지막 확인 \(formatter.string(from: checked))"
        }
        return text
    }

    var body: some View {
        let weather = WeatherService.shared
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("업데이트")
            Card {
                SettingRow(symbol: "arrow.triangle.2.circlepath", title: updateTitle, detail: updateDetail) {
                    Button(Updater.shared.available == nil ? "지금 확인" : "지금 설치") {
                        if Updater.shared.available == nil { Updater.shared.check(userInitiated: true) }
                        else { Updater.shared.install() }
                    }
                    .disabled(Updater.shared.busy)
                    Toggle("", isOn: Binding(
                        get: { ConfigStore.shared.config.autoUpdate },
                        set: { value in ConfigStore.shared.update { $0.autoUpdate = value } }))
                        .toggleStyle(.switch).labelsHidden()
                }
                .controlSize(.small)
            }

            SectionTitle("클립보드 기록")
            Card {
                VStack(spacing: 6) {
                    SettingRow(symbol: "doc.on.clipboard", title: "복사한 내용 기록하기",
                               detail: "최근 200개 · 7일까지 이 맥에만 저장합니다. 비밀번호 관리자에서 복사한 것은 기록하지 않습니다") {
                        Toggle("", isOn: Binding(
                            get: { ConfigStore.shared.config.clipboardHistory },
                            set: { value in ConfigStore.shared.update { $0.clipboardHistory = value } }))
                            .toggleStyle(.switch).labelsHidden()
                    }
                    Divider()
                    SettingRow(symbol: "tray.full", title: "지금 \(ClipboardMonitor.shared.history.items.count)개 저장됨",
                               detail: "런처에서 ⇥ 로 \"클립보드\"를 고르거나 단축키로 엽니다") {
                        ShortcutField(commandID: "clipboard.open")
                        Button("기록 모두 지우기", role: .destructive) {
                            ClipboardMonitor.shared.clear()
                            settings.bump()
                        }
                    }
                }
                .controlSize(.small)
            }

            SectionTitle("빠른 토글")
            Card {
                VStack(spacing: 6) {
                    ForEach(Array(QuickToggle.allCases.enumerated()), id: \.element) { index, toggle in
                        if index > 0 { Divider() }
                        SettingRow(symbol: toggle.symbol, title: toggle.title, detail: toggle.detail) {
                            Toggle("", isOn: Binding(get: { toggle.isOn }, set: { value in
                                toggle.set(value)
                                // 다크 모드처럼 조금 뒤에 반영되는 것이 있어 잠깐 뒤 다시 그린다
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { settings.bump() }
                            }))
                            .toggleStyle(.switch).labelsHidden()
                        }
                    }
                }
                .controlSize(.small)
            }

            SectionTitle("소리 출력 장치")
            Card { audioCard.controlSize(.small) }

            SectionTitle("날씨")
            Card {
                VStack(spacing: 6) {
                    SettingRow(symbol: weather.report.map { $0.kind.sfSymbol(night: $0.isNight) } ?? "cloud",
                               title: weather.summary,
                               detail: cityError.isEmpty ? "메뉴바 아이콘이 이 도시의 현재 날씨로 바뀝니다" : cityError) {
                        TextField("도시 이름", text: $city)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 130)
                            .onSubmit(changeCity)
                        Button("변경", action: changeCity)
                            .disabled(city.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .controlSize(.small)
            }

            SectionTitle("도구")
            Card {
                VStack(spacing: 6) {
                    SettingRow(symbol: "doc.richtext", title: "PDF → PNG 해상도",
                               detail: "PDF 를 앱 아이콘에 끌어다 놓아도 변환됩니다") {
                        Picker("", selection: Binding(get: { PDFConverter.dpi }, set: { PDFConverter.dpi = $0; settings.bump() })) {
                            ForEach(PDFConverter.dpiChoices, id: \.self) { Text("\($0) DPI").tag($0) }
                        }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 210)
                        Button("변환…") { PDFConverter.pickAndConvert() }
                    }
                    Divider()
                    SettingRow(symbol: "speaker.wave.2", title: "좌우 음량 가운데로 고정", detail: balanceDetail) {
                        Toggle("", isOn: Binding(get: { BalanceLock.shared.enabled },
                                                 set: { BalanceLock.shared.enabled = $0; settings.bump() }))
                            .toggleStyle(.switch).labelsHidden()
                    }
                }
                .controlSize(.small)
            }

            SectionTitle("시작과 연결")
            Card {
                VStack(spacing: 6) {
                    SettingRow(symbol: "power", title: "로그인 시 실행") {
                        Toggle("", isOn: Binding(get: { SMAppService.mainApp.status == .enabled }, set: setLoginItem))
                            .toggleStyle(.switch).labelsHidden()
                    }
                    Divider()
                    SettingRow(symbol: "sparkles", title: "Claude 에 연결 (MCP)",
                               detail: "터미널에 붙여 넣으면 Claude 가 창 배치·단축키·레이아웃을 조절할 수 있습니다") {
                        Button("명령 복사") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(
                                #"claude mcp add rising-kit -s user -- "/Applications/Rising Kit.app/Contents/MacOS/RisingKit" --mcp"#,
                                forType: .string)
                        }
                    }
                    Divider()
                    SettingRow(symbol: "doc.text", title: "설정 파일", detail: "단축키, 배치, 영역, 날씨 도시가 저장됩니다") {
                        Button("Finder 에서 보기") {
                            if !FileManager.default.fileExists(atPath: ConfigStore.fileURL.path) {
                                ConfigStore.shared.update { _ in }
                            }
                            NSWorkspace.shared.activateFileViewerSelecting([ConfigStore.fileURL])
                        }
                    }
                }
                .controlSize(.small)
            }
        }
        .id(settings.revision)
    }

    /// 소리 출력: 지금 장치 고르기와, 연결이 바뀌어도 지킬 순서.
    @ViewBuilder private var audioCard: some View {
        let devices = AudioRouter.outputDevices()
        let current = AudioRouter.defaultOutput()
        let config = ConfigStore.shared.config
        VStack(alignment: .leading, spacing: 6) {
            SettingRow(symbol: "speaker.wave.2", title: "지금 출력: \(devices.first { $0.id == current }?.name ?? "없음")",
                       detail: "장치를 누르면 그쪽으로 바꿉니다 (효과음 출력도 함께)") { EmptyView() }
            HStack(spacing: 6) {
                ForEach(devices) { device in
                    Button(device.name + (device.isVirtual ? " (가상)" : "")) {
                        AudioRouter.shared.select(device)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { settings.bump() }
                    }
                    .buttonStyle(KitButtonStyle(prominent: device.id == current))
                }
            }
            .padding(.leading, 30)
            Divider()
            SettingRow(symbol: "pin", title: "연결이 바뀌어도 이 순서대로 고정",
                       detail: "모니터를 꽂거나 가상 오디오 장치가 끼어들어 출력이 바뀌면, 연결된 것 중 가장 위의 장치로 되돌립니다") {
                Toggle("", isOn: Binding(get: { config.audioPin }, set: { AudioRouter.shared.setPin($0) }))
                    .toggleStyle(.switch).labelsHidden()
            }
            if config.audioPin {
                ForEach(Array(config.audioPriority.enumerated()), id: \.element.uid) { index, choice in
                    let connected = devices.contains { $0.uid == choice.uid }
                    HStack(spacing: 8) {
                        Text("\(index + 1)").font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary).frame(width: 14)
                        Circle().fill(connected ? Color.green : Color.secondary.opacity(0.4)).frame(width: 7, height: 7)
                        Text(choice.name).font(.system(size: 12))
                        if !connected { Text("연결 안 됨").font(.system(size: 11)).foregroundStyle(.tertiary) }
                        Spacer()
                        Button { reorderAudio(choice.uid, -1) } label: { Image(systemName: "chevron.up") }
                            .disabled(index == 0)
                        Button { reorderAudio(choice.uid, 1) } label: { Image(systemName: "chevron.down") }
                            .disabled(index == config.audioPriority.count - 1)
                        Button { ConfigStore.shared.update { $0.audioPriority.removeAll { $0.uid == choice.uid } } } label: {
                            Image(systemName: "xmark")
                        }
                    }
                    .padding(.leading, 30)
                }
                // 순서에 없는 연결된 장치는 눌러서 추가한다
                let missing = devices.filter { device in !config.audioPriority.contains { $0.uid == device.uid } }
                if !missing.isEmpty {
                    HStack(spacing: 6) {
                        Text("순서에 추가").font(.system(size: 11)).foregroundStyle(.secondary)
                        ForEach(missing) { device in
                            Button("+ " + device.name) {
                                ConfigStore.shared.update { $0.audioPriority.append(AudioChoice(uid: device.uid, name: device.name)) }
                            }
                        }
                    }
                    .padding(.leading, 30)
                }
            }
        }
    }

    private func reorderAudio(_ uid: String, _ offset: Int) {
        ConfigStore.shared.update { config in
            let order = AudioPriority.move(uid, by: offset, in: config.audioPriority.map(\.uid))
            let byUID = Dictionary(config.audioPriority.map { ($0.uid, $0) }, uniquingKeysWith: { a, _ in a })
            config.audioPriority = order.compactMap { byUID[$0] }
        }
    }

    private var balanceDetail: String {
        guard let balance = BalanceLock.shared.currentBalance() else { return "지금 출력 장치에는 밸런스 조절이 없습니다" }
        let offset = Int(((balance - 0.5) * 200).rounded())
        return offset == 0 ? "현재 가운데" : "현재 \(offset < 0 ? "왼쪽" : "오른쪽") \(abs(offset))%"
    }

    private func changeCity() {
        let query = city.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        switch WeatherService.shared.setCity(query) {
        case .success:
            city = ""
            cityError = ""
        case .failure(let error):
            cityError = "바꾸지 못했습니다: \(error.message)"
        }
        settings.bump()
    }

    private func setLoginItem(_ on: Bool) {
        do {
            on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister()
        } catch {
            NSSound.beep()
        }
        settings.bump()
    }
}
