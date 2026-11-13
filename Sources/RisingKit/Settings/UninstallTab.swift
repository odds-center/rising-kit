import AppKit
import RisingKitCore
import SwiftUI

final class UninstallModel: ObservableObject {
    @Published private(set) var apps: [Uninstaller.AppInfo] = []
    @Published var query = ""
    @Published private(set) var selected: Uninstaller.AppInfo?
    @Published private(set) var entries: [Uninstaller.Entry] = []
    /// 휴지통으로 보낼 항목 (경로)
    @Published var checked: Set<String> = []
    @Published private(set) var measuring = false
    @Published var message = ""
    private var scanToken = 0

    var filtered: [Uninstaller.AppInfo] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return apps }
        return apps.filter { Fuzzy.score(query: q, candidate: $0.name) != nil || $0.bundleId.localizedCaseInsensitiveContains(q) }
    }

    var checkedSize: Int64 { entries.filter { checked.contains($0.path) }.reduce(0) { $0 + $1.size } }

    func reload() {
        apps = Uninstaller.apps()
        if let selected, !apps.contains(selected) { select(nil) }
    }

    func select(_ app: Uninstaller.AppInfo?) {
        scanToken += 1
        let token = scanToken
        selected = app
        message = ""
        guard let app else { entries = []; checked = []; return }
        entries = Uninstaller.entries(for: app)
        checked = Set(entries.map(\.path))
        // 크기 재기는 오래 걸릴 수 있어 백그라운드에서
        measuring = true
        let paths = entries.map(\.path)
        DispatchQueue.global(qos: .userInitiated).async {
            let sizes = paths.map { Uninstaller.size(of: $0) }
            DispatchQueue.main.async {
                guard token == self.scanToken else { return }
                for (index, size) in sizes.enumerated() where self.entries.indices.contains(index) {
                    self.entries[index].size = size
                }
                self.measuring = false
            }
        }
    }

    func trashChecked() {
        guard let app = selected else { return }
        let paths = entries.map(\.path).filter(checked.contains)
        guard !paths.isEmpty else { return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\(app.name) 항목 \(paths.count)개를 휴지통으로 옮길까요?"
        alert.informativeText = "합계 \(Leftovers.formatSize(checkedSize)). 휴지통을 비우기 전까지는 Finder 의 \"되돌려 놓기\"로 복구할 수 있습니다."
        alert.addButton(withTitle: "취소")
        alert.addButton(withTitle: "휴지통으로 이동")
        guard alert.runModal() == .alertSecondButtonReturn else { return }

        Uninstaller.trash(paths) { [weak self] failed in
            guard let self else { return }
            let moved = paths.count - failed.count
            self.reload()
            if failed.isEmpty {
                self.select(nil)
                self.message = "\(app.name): \(moved)개를 휴지통으로 옮겼습니다"
            } else {
                self.select(self.apps.first { $0.path == app.path })
                self.message = "\(moved)개를 옮겼고 \(failed.count)개는 옮기지 못했습니다 (권한이 필요한 항목)"
            }
        }
    }
}

struct UninstallTab: View {
    @StateObject private var model = UninstallModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                appList.frame(width: 250)
                detail
            }
            .frame(height: 430)
            if !model.message.isEmpty {
                Text(model.message).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .onAppear { model.reload() }
    }

    private var appList: some View {
        Card(padding: 8) {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.secondary)
                    TextField("앱 검색", text: $model.query).textFieldStyle(.plain).font(.system(size: 12))
                }
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.06)))
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 1) {
                        ForEach(model.filtered) { app in
                            let active = app == model.selected
                            HStack(spacing: 8) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                                    .resizable().frame(width: 20, height: 20)
                                Text(app.name).font(.system(size: 12.5)).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 8)
                            .frame(height: 28)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(active ? 0.12 : 0)))
                            .contentShape(Rectangle())
                            .onTapGesture { model.select(app) }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if let app = model.selected {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable().frame(width: 36, height: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.name).font(.system(size: 15, weight: .semibold))
                            Text(app.bundleId).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    if app.isRunning {
                        Label("실행 중입니다. 먼저 앱을 종료해 주세요.", systemImage: "exclamationmark.triangle")
                            .font(.system(size: 12)).foregroundStyle(.orange)
                    }
                    Divider()
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 4) {
                            ForEach(model.entries) { entry in entryRow(entry) }
                        }
                    }
                    Divider()
                    HStack {
                        Text(model.measuring ? "크기 계산 중…" : "선택 합계 \(Leftovers.formatSize(model.checkedSize))")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer()
                        Button(role: .destructive) { model.trashChecked() } label: {
                            Label("휴지통으로 이동", systemImage: "trash")
                        }
                        .disabled(model.checked.isEmpty || app.isRunning)
                    }
                }
            }
        } else {
            Card {
                VStack(spacing: 8) {
                    Image(systemName: "trash").font(.system(size: 26)).foregroundStyle(.tertiary)
                    Text("왼쪽에서 지울 앱을 고르세요").font(.system(size: 13)).foregroundStyle(.secondary)
                    Text("앱과 함께 남는 설정·캐시 파일을 찾아 보여 줍니다.\n고른 것만 휴지통으로 옮기며, 영구 삭제는 하지 않습니다.")
                        .font(.system(size: 11)).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func entryRow(_ entry: Uninstaller.Entry) -> some View {
        let on = model.checked.contains(entry.path)
        return HStack(spacing: 8) {
            Image(systemName: on ? "checkmark.square.fill" : "square")
                .font(.system(size: 14))
                .foregroundStyle(on ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text((entry.path as NSString).lastPathComponent).font(.system(size: 12.5)).lineLimit(1)
                Text(((entry.path as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 10.5)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(entry.isApp ? "앱" : "남은 파일").font(.system(size: 10.5)).foregroundStyle(.secondary)
            Text(model.measuring && entry.size == 0 ? "…" : Leftovers.formatSize(entry.size))
                .font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture {
            if on { model.checked.remove(entry.path) } else { model.checked.insert(entry.path) }
        }
    }
}
