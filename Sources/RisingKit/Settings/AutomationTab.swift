import AppKit
import RisingKitCore
import SwiftUI

/// 데일리 스크럼 초안과 파일 정리.
struct AutomationTab: View {
    @ObservedObject private var settings = SettingsModel.shared
    @State private var draft = ""
    @State private var draftNote = ""
    @State private var building = false
    @State private var foldersText = ""
    @State private var repos: [ScrumService.Repo] = []
    @State private var selectedRepos: Set<String> = []
    @State private var identityText = ""
    @State private var plan = TidyService.Plan()
    @State private var tidyNote = ""
    @State private var bank: BankSecurityService.Status?
    @State private var bankBusy = false
    @State private var bankNote = ""

    var body: some View {
        let config = ConfigStore.shared.config
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("데일리 스크럼 초안")
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    SettingRow(symbol: "list.bullet.clipboard", title: "어제 한 일을 커밋에서 모으기",
                               detail: "직전 근무일과 오늘, 고른 저장소에서 내가 쓴 커밋만 모읍니다. 읽기만 합니다") {
                        ShortcutField(commandID: "scrum.copy")
                        Button(building ? "만드는 중…" : "초안 만들기") { buildDraft() }
                            .buttonStyle(KitButtonStyle(prominent: true))
                            .disabled(building)
                    }
                    Divider()
                    SettingRow(symbol: "folder", title: "저장소를 찾아볼 폴더", detail: "쉼표로 구분 · 네 단계 아래까지 찾습니다") {
                        TextField("~/orca/projects, ~/Desktop", text: $foldersText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 330)
                            .onSubmit(saveFolders)
                        Button("저장", action: saveFolders)
                    }
                    Divider()
                    repoPicker
                    if !draft.isEmpty {
                        Divider()
                        ScrollView {
                            Text(draft)
                                .font(.system(size: 12, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                        }
                        .frame(height: 170)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.05)))
                        HStack {
                            Text(draftNote).font(.system(size: 11)).foregroundStyle(.secondary)
                            Spacer()
                            Button { copy(draft) } label: { Label("복사", systemImage: "doc.on.doc") }
                        }
                    }
                }
                .controlSize(.small)
            }

            SectionTitle("다운로드 · 스크린샷 정리")
            Card {
                VStack(spacing: 6) {
                    SettingRow(symbol: "camera.viewfinder", title: "오래된 스크린샷",
                               detail: "\(TidyService.screenshotFolder.lastPathComponent) → \(Tidy.screenshotArchive)/2026-11 식으로 옮깁니다") {
                        dayPicker(get: { config.tidyScreenshotDays }, set: { value in ConfigStore.shared.update { $0.tidyScreenshotDays = value } },
                                  choices: [3, 7, 14, 30])
                        toggle(get: { config.tidyScreenshots }, set: { value in ConfigStore.shared.update { $0.tidyScreenshots = value } })
                    }
                    Divider()
                    SettingRow(symbol: "arrow.down.circle", title: "오래된 다운로드",
                               detail: "다운로드 → \(Tidy.downloadArchive)/2026-10 식으로 옮깁니다 (파일만, 폴더는 그대로)") {
                        dayPicker(get: { config.tidyDownloadDays }, set: { value in ConfigStore.shared.update { $0.tidyDownloadDays = value } },
                                  choices: [14, 30, 60, 90])
                        toggle(get: { config.tidyDownloads }, set: { value in ConfigStore.shared.update { $0.tidyDownloads = value } })
                    }
                    Divider()
                    SettingRow(symbol: "clock.arrow.circlepath", title: "매일 자동으로 정리",
                               detail: "하루에 한 번, Rising Kit 이 켜져 있을 때 실행합니다") {
                        toggle(get: { config.tidyAuto }, set: { value in ConfigStore.shared.update { $0.tidyAuto = value } })
                    }
                    Divider()
                    SettingRow(symbol: "tray.full",
                               title: plan.count == 0 ? "지금 정리할 것이 없습니다"
                                                      : "지금 정리하면 스크린샷 \(plan.screenshots.count)개, 다운로드 \(plan.downloads.count)개",
                               detail: tidyNote.isEmpty ? "옮기기만 하고 지우지 않습니다. 마지막 정리는 되돌릴 수 있습니다" : tidyNote) {
                        ShortcutField(commandID: "tidy.run")
                        if TidyService.canUndo {
                            Button("되돌리기") {
                                inBackground({ TidyService.undo() }) { restored in
                                    tidyNote = "\(restored)개를 제자리로 돌려놓았습니다"
                                }
                            }
                        }
                        Button("지금 정리") {
                            inBackground({ TidyService.run() }) { result in
                                tidyNote = "스크린샷 \(result.screenshots)개, 다운로드 \(result.downloads)개를 옮겼습니다"
                            }
                        }
                        .buttonStyle(KitButtonStyle(prominent: true))
                        .disabled(plan.count == 0)
                    }
                }
                .controlSize(.small)
            }

            SectionTitle("은행 보안 프로그램")
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    SettingRow(symbol: bank?.isOn == false ? "shield.slash" : "lock.shield",
                               title: bankTitle,
                               detail: bankNote.isEmpty
                                   ? "인터넷 뱅킹을 할 때만 켜 두세요. 프로그램은 지우지 않고 백그라운드 실행만 내렸다 올립니다. 관리자 암호를 묻습니다"
                                   : bankNote) {
                        ShortcutField(commandID: "bank.toggle")
                        if let bank, !bank.jobs.isEmpty {
                            Button(bankBusy ? "바꾸는 중…" : (bank.isOn ? "모두 끄기" : "모두 켜기")) { flipBank(on: !bank.isOn) }
                                .buttonStyle(KitButtonStyle(prominent: !bank.isOn))
                                .disabled(bankBusy)
                        }
                    }
                    if let bank, !bank.jobs.isEmpty {
                        Divider()
                        // 같은 제품의 항목은 한 줄로 묶어 보여 준다
                        let vendors = Dictionary(grouping: bank.jobs, by: \.vendor).sorted { $0.key < $1.key }
                        ForEach(vendors, id: \.key) { vendor, jobs in
                            let on = jobs.filter { bank.loaded.contains($0.label) }.count
                            HStack(spacing: 8) {
                                Circle().fill(on > 0 ? Color.green : Color.secondary.opacity(0.4)).frame(width: 7, height: 7)
                                Text(vendor).font(.system(size: 12))
                                Spacer()
                                Text(on > 0 ? "실행 중 \(on)/\(jobs.count)" : "꺼짐")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            .padding(.leading, 30)
                        }
                    }
                }
                .controlSize(.small)
            }
        }
        .id(settings.revision)
        .onAppear {
            loadRepos()
            refreshBank()
            foldersText = ConfigStore.shared.config.scrumFolders.joined(separator: ", ")
            refreshPlan()
        }
        .onChange(of: settings.revision) { _, _ in
            refreshPlan()
            refreshBank()
        }
    }

    private func toggle(get: @escaping () -> Bool, set: @escaping (Bool) -> Void) -> some View {
        Toggle("", isOn: Binding(get: get, set: set)).toggleStyle(.switch).labelsHidden()
    }

    private func dayPicker(get: @escaping () -> Int, set: @escaping (Int) -> Void, choices: [Int]) -> some View {
        Picker("", selection: Binding(get: get, set: set)) {
            ForEach(choices, id: \.self) { Text("\($0)일 지난 것").tag($0) }
        }
        .labelsHidden()
        .frame(width: 120)
    }

    /// 스크럼에 넣을 저장소 고르기. 소유자별로 묶어 보여 준다.
    @ViewBuilder private var repoPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("넣을 저장소").font(.system(size: 13))
                Text(repos.isEmpty ? "찾는 중…" : "\(selectedRepos.count)개 선택")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button("모두 선택") { setRepos(repos.map(\.key)) }
                Button("모두 해제") { setRepos([]) }
            }
            let owners = Dictionary(grouping: repos, by: \.owner).sorted { $0.key < $1.key }
            ForEach(owners, id: \.key) { owner, list in
                VStack(alignment: .leading, spacing: 3) {
                    Text(owner).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary)
                    // 이름이 짧은 것이 많아 여러 칸으로 나눠 보여 준다
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 3) {
                        ForEach(list) { repo in
                            let on = selectedRepos.contains(repo.key)
                            HStack(spacing: 5) {
                                Image(systemName: on ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 13))
                                    .foregroundStyle(on ? Color.accentColor : Color.secondary)
                                Text(repo.name).font(.system(size: 12)).lineLimit(1)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { toggleRepo(repo.key) }
                        }
                    }
                }
            }
            if !identityText.isEmpty {
                Text("내 커밋으로 보는 작성자: \(identityText)")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
            }
        }
        .padding(.leading, 30)
    }

    private func setRepos(_ keys: [String]) {
        selectedRepos = Set(keys)
        ConfigStore.shared.update { $0.scrumRepos = keys }
    }

    private func toggleRepo(_ key: String) {
        if selectedRepos.contains(key) { selectedRepos.remove(key) } else { selectedRepos.insert(key) }
        let chosen = repos.map(\.key).filter(selectedRepos.contains)
        ConfigStore.shared.update { $0.scrumRepos = chosen }
    }

    private func loadRepos() {
        DispatchQueue.global(qos: .userInitiated).async {
            let found = ScrumService.repositories()
            let me = ScrumService.identity(for: found)
            DispatchQueue.main.async {
                repos = found
                selectedRepos = ScrumService.selectedKeys(among: found)
                identityText = (me.names.sorted() + me.emails.sorted()).joined(separator: ", ")
            }
        }
    }

    private var bankTitle: String {
        guard let bank else { return "확인하는 중…" }
        if bank.jobs.isEmpty { return "설치된 은행 보안 프로그램이 없습니다" }
        return bank.isOn ? "켜져 있음 · \(bank.jobs.count)개 중 \(bank.running)개 실행 중" : "꺼져 있음 · \(bank.jobs.count)개 모두 내려감"
    }

    private func refreshBank() {
        DispatchQueue.global(qos: .utility).async {
            let status = BankSecurityService.status()
            DispatchQueue.main.async { bank = status }
        }
    }

    private func flipBank(on: Bool) {
        bankBusy = true
        BankSecurityService.set(on: on) { ok in
            bankBusy = false
            bankNote = ok ? (on ? "켰습니다. 은행 사이트를 새로 고침해 주세요" : "껐습니다. 은행을 볼 때 다시 켜면 됩니다")
                          : "바꾸지 못했습니다 (관리자 암호 입력이 취소됨)"
            refreshBank()
        }
    }

    /// 파일을 옮기는 일은 화면 밖에서 하고, 끝나면 안내를 바꾸고 목록을 다시 읽는다.
    private func inBackground<T>(_ work: @escaping () -> T, then: @escaping (T) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let result = work()
            DispatchQueue.main.async {
                then(result)
                refreshPlan()
            }
        }
    }

    private func refreshPlan() {
        // 폴더를 읽는 일은 화면을 그리는 흐름 밖에서 한다
        DispatchQueue.global(qos: .utility).async {
            let fresh = TidyService.plan()
            DispatchQueue.main.async { plan = fresh }
        }
    }

    private func buildDraft() {
        building = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = ScrumService.draft()
            DispatchQueue.main.async {
                draft = result.text
                draftNote = "저장소 \(result.repositories)개에서 내 커밋 \(result.commits)개"
                building = false
            }
        }
    }

    private func saveFolders() {
        let folders = foldersText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !folders.isEmpty else { return }
        ConfigStore.shared.update { $0.scrumFolders = folders }
        loadRepos()
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        draftNote = "복사했습니다"
    }
}
