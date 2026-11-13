import AppKit
import SwiftUI

/// 디스플레이 배치도: 모니터 배열 위에 창을 그리고, 끌거나 키로 배치한다.
struct MapTab: View {
    @ObservedObject var model: MapModel
    @ObservedObject private var recorder = ShortcutRecorder.shared
    @State private var newLayoutName = ""
    @State private var naming = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            toolbar
            Card(padding: 12) {
                GeometryReader { geo in MapCanvas(model: model, size: geo.size) }
                    .frame(minHeight: 250)
            }
            keyHints
            SectionTitle("저장한 배치와 단축키")
            layouts
        }
    }

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let window = model.selected {
                    if let icon = model.icon(for: window.pid) {
                        Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                    }
                    Text(window.app).font(.system(size: 13, weight: .semibold))
                    Text("\(window.display + 1)번 · \(MapModel.placementName(for: window.frame, in: model.visibleFrame(of: window)))")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    if !window.title.isEmpty {
                        Text(window.title).font(.system(size: 12)).foregroundStyle(.tertiary).lineLimit(1)
                    }
                } else {
                    Text("창을 골라 주세요").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                modePicker
                Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .help("창 목록 새로 고침")
            }
            .frame(height: 28)

            if !model.hasPermission {
                Button("손쉬운 사용 권한 허용…") { _ = WindowManager.ensurePermission() }
            } else if recorder.activeID == "map.rule" || recorder.activeID == "map.zone" {
                HStack(spacing: 8) {
                    Text("단축키를 누르세요…").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.accentColor)
                    Button("취소") { recorder.cancel() }
                }
            } else {
                HStack(spacing: 6) {
                    Text("이 자리를 단축키로").font(.system(size: 11)).foregroundStyle(.secondary)
                    Button { model.beginRecording() } label: { Label("이 앱을 여기로", systemImage: "macwindow") }
                        .buttonStyle(KitButtonStyle(prominent: true))
                        .disabled(model.selected == nil)
                        .help("고른 앱의 창을 지금 있는 모니터·위치·크기로 보내고 앞으로 가져오는 단축키")
                    Button { model.beginZoneRecordingForSelected() } label: { Label("어떤 창이든 여기로", systemImage: "rectangle.dashed") }
                        .disabled(model.selected == nil)
                        .help("그때 맨 앞에 있는 창을 이 자리로 보내는 단축키")
                    if model.drawn != nil {
                        Divider().frame(height: 16)
                        Text("그린 영역").font(.system(size: 11)).foregroundStyle(.secondary)
                        Button("고른 창을 영역으로") { model.moveSelectedIntoDrawn() }
                            .disabled(model.selected == nil)
                        Button { model.beginZoneRecordingForDrawn() } label: { Label("영역을 단축키로", systemImage: "keyboard") }
                        Button { model.drawn = nil } label: { Image(systemName: "xmark") }
                            .help("그린 영역 지우기")
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// 끌어 놓을 때 정해진 자리에 붙일지, 놓은 그대로 둘지.
    private var modePicker: some View {
        HStack(spacing: 2) {
            ForEach([(MapModel.Mode.snap, "붙이기"), (MapModel.Mode.free, "자유")], id: \.1) { mode, label in
                let active = model.mode == mode
                Text(label)
                    .font(.system(size: 11.5, weight: active ? .semibold : .regular))
                    .foregroundStyle(active ? Color.primary : Color.secondary)
                    .padding(.horizontal, 10)
                    .frame(height: 22)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(active ? 0.14 : 0)))
                    .contentShape(Rectangle())
                    .onTapGesture { model.mode = mode }
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
        .help("붙이기: 놓는 자리에 따라 절반·1/4·최대화 / 자유: 놓은 그대로, 빈 곳을 끌면 영역 그리기")
    }

    private var keyHints: some View {
        HStack(spacing: 12) {
            hint("절반", ["←", "→", "↑", "↓"])
            hint("1/4", ["U", "I", "J", "K"])
            hint("1/3", ["D", "F", "G"])
            hint("최대화", ["↩"])
            hint("모니터로", ["1–9"])
            hint("다음 창", ["⇥"])
            Text(model.mode == .free ? "· 창 모서리를 끌면 크기, 빈 곳을 끌면 영역" : "· 창 오른쪽 아래 모서리를 끌면 크기")
                .font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private func hint(_ label: String, _ keys: [String]) -> some View {
        HStack(spacing: 3) {
            ForEach(keys, id: \.self) { Keycap($0) }
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .fixedSize()
    }

    private var layouts: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.layouts.isEmpty {
                Text("아직 없습니다. 창을 원하는 대로 놓은 뒤 아래에서 저장하세요.")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.layouts, id: \.name) { layout in
                        layoutCard(layout)
                    }
                }
            }
            HStack(spacing: 8) {
                if naming {
                    TextField("배치 이름", text: $newLayoutName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                        .focused($nameFocused)
                        .onSubmit(commitName)
                    Button("저장", action: commitName)
                        .disabled(newLayoutName.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("취소") { naming = false; newLayoutName = "" }
                } else {
                    Button { naming = true; nameFocused = true } label: {
                        Label("지금 보이는 창 전체를 배치로 저장…", systemImage: "plus")
                    }
                }
                Spacer()
            }
            .controlSize(.small)
        }
    }

    private func layoutCard(_ layout: Layout) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: layout.items.count == 1 ? "macwindow" : "rectangle.3.group.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(layout.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
            }
            HStack(spacing: 6) {
                Text("창 \(layout.items.count)개").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                ShortcutField(commandID: "layout:" + layout.name)
            }
            HStack(spacing: 6) {
                Button("적용") { model.applyLayout(layout) }
                Button("삭제", role: .destructive) { model.deleteLayout(layout) }
            }
            .controlSize(.small)
        }
        .padding(10)
        .frame(width: 210, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Design.corner, style: .continuous).fill(Design.cardFill))
        .overlay(RoundedRectangle(cornerRadius: Design.corner, style: .continuous).strokeBorder(Design.cardStroke))
    }

    private func commitName() {
        model.saveLayout(name: newLayoutName)
        naming = false
        newLayoutName = ""
    }
}

/// 모든 디스플레이를 실제 배열대로 축소해 그리고, 그 위에 창을 올린다.
struct MapCanvas: View {
    @ObservedObject var model: MapModel
    let size: CGSize

    private var scale: CGFloat {
        let b = model.bounds
        guard !b.isNull, b.width > 0, b.height > 0 else { return 1 }
        return min(size.width / b.width, size.height / b.height)
    }

    private var offset: CGPoint {
        let b = model.bounds
        return CGPoint(x: (size.width - b.width * scale) / 2, y: (size.height - b.height * scale) / 2)
    }

    /// 전역 좌표 → 캔버스 좌표
    private func map(_ rect: CGRect) -> CGRect {
        let b = model.bounds
        return CGRect(x: (rect.minX - b.minX) * scale + offset.x, y: (rect.minY - b.minY) * scale + offset.y,
                      width: rect.width * scale, height: rect.height * scale)
    }

    /// 캔버스 좌표 → 전역 좌표
    private func unmap(_ point: CGPoint) -> CGPoint {
        let b = model.bounds
        return CGPoint(x: (point.x - offset.x) / scale + b.minX, y: (point.y - offset.y) / scale + b.minY)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(model.screens, id: \.index) { screen in
                let r = map(screen.full)
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.22), lineWidth: 1))
                    .frame(width: r.width, height: r.height)
                    .offset(x: r.minX, y: r.minY)
            }
            .contentShape(Rectangle())
            // 자유 모드에서 빈 곳을 끌면 영역을 그린다
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .named("map"))
                    .onChanged { value in
                        guard model.mode == .free else { return }
                        model.draw(from: unmap(value.startLocation), to: unmap(value.location))
                    }
                    .onEnded { _ in model.finishDrawing() })

            // 뒤에 있는 창부터 그려서 실제 겹침 순서와 같게 한다
            ForEach(model.windows.reversed()) { window in
                windowView(window)
            }

            // 창이 화면을 가득 채워도 보이도록 화면 이름표는 창 위에 그린다
            ForEach(model.screens, id: \.index) { screen in
                let r = map(screen.full)
                Text("\(screen.index + 1)  \(screen.name)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
                    .offset(x: r.minX + 6, y: r.maxY - 24)
                    .allowsHitTesting(false)
            }

            if let drawn = model.drawn {
                let r = map(drawn.rect)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.orange.opacity(0.18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(Color.orange, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])))
                    .overlay {
                        if r.width > 70, r.height > 26 {
                            Text("\(Int(drawn.rect.width)) × \(Int(drawn.rect.height))")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.orange)
                        }
                    }
                    .frame(width: r.width, height: r.height)
                    .offset(x: r.minX, y: r.minY)
                    .allowsHitTesting(false)
            }

            // 고른 창의 크기 조절 손잡이 (오른쪽 아래)
            if let window = model.selected, model.dragging == nil {
                let r = map(window.frame)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(width: 11, height: 11)
                    .offset(x: r.maxX - 8, y: r.maxY - 8)
                    .zIndex(2)
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .named("map"))
                            .onChanged { value in
                                let delta = CGSize(width: value.translation.width / scale, height: value.translation.height / scale)
                                model.dragging = (window.id, .zero, model.resizeTarget(for: window, translation: delta))
                            }
                            .onEnded { value in
                                let delta = CGSize(width: value.translation.width / scale, height: value.translation.height / scale)
                                let target = model.resizeTarget(for: window, translation: delta)
                                model.dragging = nil
                                model.move(window, to: target)
                            })
                    .help("끌어서 크기 바꾸기")
            }

            if let preview = model.dragging?.preview {
                let r = map(preview)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.accentColor.opacity(0.25))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])))
                    .frame(width: r.width, height: r.height)
                    .offset(x: r.minX, y: r.minY)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .coordinateSpace(name: "map")
    }

    /// 끌어 놓은 자리: 붙이기 모드면 절반·1/4 등으로, 자유 모드면 놓은 그대로.
    private func target(for window: WindowManager.WindowSnapshot, _ value: DragGesture.Value) -> CGRect? {
        switch model.mode {
        case .snap:
            return model.dropTarget(for: window, at: unmap(value.location))
        case .free:
            return model.freeTarget(for: window, translation: CGSize(
                width: value.translation.width / scale, height: value.translation.height / scale))
        }
    }

    private func windowView(_ window: WindowManager.WindowSnapshot) -> some View {
        let r = map(window.frame)
        let selected = window.id == model.selectedID
        let drag = model.dragging?.id == window.id ? model.dragging!.translation : .zero
        return RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color(nsColor: .windowBackgroundColor).opacity(0.94))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.28), lineWidth: selected ? 2 : 1))
            .overlay {
                VStack(spacing: 3) {
                    if let icon = model.icon(for: window.pid), r.height >= 26 {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: min(26, r.height * 0.5), height: min(26, r.height * 0.5))
                    }
                    if r.width >= 60, r.height >= 54 {
                        Text(window.app)
                            .font(.system(size: 10))
                            .lineLimit(1)
                            .padding(.horizontal, 4)
                    }
                }
            }
            .frame(width: max(r.width, 4), height: max(r.height, 4))
            .offset(x: r.minX + drag.width, y: r.minY + drag.height)
            .zIndex(model.dragging?.id == window.id ? 1 : 0)
            .help(window.title.isEmpty ? window.app : "\(window.app) — \(window.title)")
            .gesture(
                DragGesture(minimumDistance: 3, coordinateSpace: .named("map"))
                    .onChanged { value in
                        model.selectedID = window.id
                        model.dragging = (window.id, value.translation, target(for: window, value))
                    }
                    .onEnded { value in
                        let target = target(for: window, value)
                        model.dragging = nil
                        if let target { model.move(window, to: target) }
                    })
            .onTapGesture { model.selectedID = window.id }
    }
}
