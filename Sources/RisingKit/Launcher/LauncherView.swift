import AppKit
import SwiftUI

struct LauncherView: View {
    @ObservedObject var model: LauncherModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            filterBar
            Divider().opacity(0.6)
            resultList
            Divider().opacity(0.6)
            footer
        }
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1))
        .onAppear { searchFocused = true }
        .onChange(of: model.focusToken) { _, _ in searchFocused = true }
    }

    // MARK: - 검색창

    private var searchBar: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("앱, 설정, 파일, 명령, 계산, 날짜 검색…", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($searchFocused)
            if !model.results.isEmpty {
                Text("\(model.results.count)")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
    }

    private var filterBar: some View {
        HStack(spacing: 4) {
            ForEach(LauncherFilter.allCases, id: \.rawValue) { filter in
                let active = filter == model.filter
                Text(filter.label)
                    .font(.system(size: 11.5, weight: active ? .semibold : .regular))
                    .foregroundStyle(active ? Color.primary : Color.secondary)
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    .background(Capsule().fill(Color.primary.opacity(active ? 0.13 : 0)))
                    .contentShape(Capsule())
                    .onTapGesture { model.filter = filter }
            }
            Spacer()
            Keycap("⇥")
            Text("종류 바꾸기").font(.system(size: 11)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    // MARK: - 결과

    @ViewBuilder private var resultList: some View {
        if model.results.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 22))
                    .foregroundStyle(.tertiary)
                Text(model.query.isEmpty ? "검색어를 입력하세요" : "결과 없음")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(model.results.enumerated()), id: \.element.id) { index, item in
                            // 묶음이 바뀌는 자리에 제목을 넣는다
                            if index == 0 || model.results[index - 1].section != item.section {
                                Text(item.section)
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.top, index == 0 ? 2 : 9)
                                    .padding(.bottom, 3)
                            }
                            LauncherRow(item: item, selected: index == model.selection)
                                .id(item.id)
                                .contentShape(Rectangle())
                                .onTapGesture { model.run(item) }
                        }
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 6)
                }
                .onChange(of: model.selection) { _, new in
                    guard model.results.indices.contains(new) else { return }
                    proxy.scrollTo(model.results[new].id)
                }
            }
        }
    }

    // MARK: - 아래 줄: 날씨와 지금 할 수 있는 동작

    private var footer: some View {
        HStack(spacing: 10) {
            let weather = WeatherService.shared
            if let report = weather.report {
                Image(systemName: report.kind.sfSymbol(night: report.isNight))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Text(model.notice.isEmpty ? weather.summary : model.notice)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let item = model.selected {
                hint(item.kind.actionLabel, "↩")
                if item.kind == .clip {
                    hint("기록에서 지우기", "⌘", "⌫")
                } else {
                    if item.path != nil { hint("Finder에서 보기", "⌘", "↩") }
                    hint(item.path == nil ? "이름 복사" : "경로 복사", "⌘", "⇧", "C")
                }
            }
            hint("닫기", "esc")
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(Color.primary.opacity(0.03))
    }

    private func hint(_ label: String, _ keys: String...) -> some View {
        HStack(spacing: 3) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            ForEach(keys, id: \.self) { Keycap($0) }
        }
    }
}

private struct LauncherRow: View {
    let item: LauncherItem
    let selected: Bool

    var body: some View {
        HStack(spacing: 9) {
            icon.frame(width: 20, height: 20)
            Text(item.title)
                .font(.system(size: 13))
                .lineLimit(1)
                .layoutPriority(1)
            if !item.subtitle.isEmpty {
                Text(item.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            HStack(spacing: 2) {
                ForEach(Array(item.keys.enumerated()), id: \.offset) { _, key in Keycap(key) }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(selected ? 0.12 : 0)))
    }

    @ViewBuilder private var icon: some View {
        switch item.icon {
        case .file(let path):
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .interpolation(.high)
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }
}

/// 키 하나를 작은 키캡 모양으로.
struct Keycap: View {
    let key: String
    init(_ key: String) { self.key = key }

    var body: some View {
        Text(key)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .frame(minWidth: 18, minHeight: 18)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.primary.opacity(0.09)))
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
