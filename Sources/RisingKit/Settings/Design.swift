import AppKit
import RisingKitCore
import SwiftUI

/// 설정 창과 런처가 함께 쓰는 모양새.
enum Design {
    static let cardFill = Color.primary.opacity(0.045)
    static let cardStroke = Color.primary.opacity(0.08)
    static let corner: CGFloat = 10
}

/// 내용을 담는 둥근 상자.
struct Card<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Design.corner, style: .continuous).fill(Design.cardFill))
            .overlay(RoundedRectangle(cornerRadius: Design.corner, style: .continuous).strokeBorder(Design.cardStroke))
    }
}

/// 묶음 제목.
struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 2)
    }
}

/// 카드 안의 한 줄: 왼쪽에 아이콘·제목·설명, 오른쪽에 조작부.
struct SettingRow<Trailing: View>: View {
    let symbol: String
    let title: String
    var detail = ""
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13))
                if !detail.isEmpty {
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
        .frame(minHeight: 30)
    }
}

/// 창이 화면의 어디에 놓이는지 보여 주는 작은 그림.
struct PlacementGlyph: View {
    let placement: Placement
    var size = CGSize(width: 34, height: 24)

    var body: some View {
        let unit = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        let inner = unit.insetBy(dx: 2.5, dy: 2.5)
        // "가운데"는 크기를 유지하는 배치라서 그림에서는 작은 창으로 나타낸다
        let sample = CGRect(x: 0, y: 0, width: inner.width * 0.5, height: inner.height * 0.55)
        let r = placement.rect(in: inner, current: sample)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.7), lineWidth: 1.2)
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.accentColor)
                .frame(width: max(r.width, 2), height: max(r.height, 2))
                .offset(x: r.minX, y: r.minY)
        }
        .frame(width: size.width, height: size.height)
    }
}

/// 명령의 단축키를 보여 주고, 누르면 새 조합을 받는다.
struct ShortcutField: View {
    let commandID: String
    @ObservedObject private var recorder = ShortcutRecorder.shared
    @ObservedObject private var settings = SettingsModel.shared

    private var command: Command? { Commands.all.first { $0.id == commandID } }

    var body: some View {
        let recording = recorder.activeID == commandID
        let keys = command?.combo?.displayParts ?? []
        HStack(spacing: 2) {
            if recording {
                Text("입력 대기…").font(.system(size: 11, weight: .medium)).foregroundStyle(Color.accentColor)
            } else if keys.isEmpty {
                Text("없음").font(.system(size: 11)).foregroundStyle(.tertiary)
            } else {
                ForEach(Array(keys.enumerated()), id: \.offset) { _, key in Keycap(key) }
            }
        }
        .padding(.horizontal, 6)
        .frame(minWidth: 74, minHeight: 26)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(recording ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.05)))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(recording ? Color.accentColor : Color.clear, lineWidth: 1.2))
        .contentShape(Rectangle())
        .onTapGesture { recording ? recorder.cancel() : recorder.beginCommand(commandID) }
        .help("눌러서 단축키 바꾸기")
        .contextMenu {
            Button("단축키 지우기") { ConfigStore.shared.update { $0.shortcuts[commandID] = "" } }
            if command?.defaultShortcut != nil {
                Button("기본값으로") { ConfigStore.shared.update { $0.shortcuts.removeValue(forKey: commandID) } }
            }
        }
        .id(settings.revision)  // 설정이 바뀌면 다시 그린다
    }
}

/// 설정 창 전체가 함께 보는 상태.
final class SettingsModel: ObservableObject {
    static let shared = SettingsModel()

    enum Tab: String, CaseIterable {
        case map, window, shortcuts, automation, system, uninstall, general

        var title: String {
            switch self {
            case .map: return "디스플레이 배치도"
            case .window: return "창 정렬"
            case .shortcuts: return "단축키"
            case .automation: return "자동화"
            case .system: return "메모리 · CPU"
            case .uninstall: return "앱 삭제"
            case .general: return "일반"
            }
        }

        var subtitle: String {
            switch self {
            case .map: return "창을 끌어 원하는 모니터와 자리에 놓고, 배치와 단축키로 저장합니다"
            case .window: return "맨 앞 창을 화면의 정해진 자리에 맞춥니다"
            case .shortcuts: return "런처, 레이아웃, 도구의 단축키"
            case .automation: return "데일리 스크럼 초안, 파일 정리, 은행 보안 프로그램"
            case .system: return "지금 메모리와 CPU 를 누가 쓰는지"
            case .uninstall: return "앱과 함께 남는 설정·캐시까지 찾아 휴지통으로 보냅니다"
            case .general: return "클립보드, 빠른 토글, 날씨, PDF, 음량, 시작 옵션"
            }
        }

        var symbol: String {
            switch self {
            case .map: return "rectangle.3.group"
            case .window: return "rectangle.split.2x1"
            case .shortcuts: return "keyboard"
            case .automation: return "wand.and.stars"
            case .system: return "memorychip"
            case .uninstall: return "trash"
            case .general: return "gearshape"
            }
        }
    }

    @Published var tab = Tab.map
    /// 설정이나 날씨가 바뀔 때마다 올라가서 화면을 다시 그리게 한다.
    @Published private(set) var revision = 0

    let map = MapModel()

    func bump() {
        revision += 1
        map.reloadLayouts()
    }
}

/// 설정 창의 버튼. 시스템 기본 버튼(흰 알약 모양) 대신 창의 카드와 같은 결로 맞춘다.
struct KitButtonStyle: ButtonStyle {
    /// 그 화면에서 가장 중요한 동작이면 강조색으로 채운다
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        KitButtonBody(configuration: configuration, prominent: prominent)
    }

    private struct KitButtonBody: View {
        let configuration: Configuration
        let prominent: Bool
        @Environment(\.isEnabled) private var enabled
        @State private var hovering = false

        var body: some View {
            let destructive = configuration.role == .destructive
            let foreground: Color = prominent ? .white : destructive ? .red : .primary
            let fill: Color = prominent
                ? Color.accentColor.opacity(configuration.isPressed ? 0.75 : hovering ? 0.9 : 1)
                : Color.primary.opacity(configuration.isPressed ? 0.16 : hovering ? 0.11 : 0.07)
            configuration.label
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(foreground)
                .labelStyle(KitLabelStyle())
                .padding(.horizontal, 10)
                .frame(minHeight: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(fill))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.primary.opacity(prominent ? 0 : 0.08)))
                .opacity(enabled ? 1 : 0.4)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}

/// 버튼 안의 아이콘과 글자 간격을 좁게.
private struct KitLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.system(size: 11, weight: .medium))
            configuration.title
        }
    }
}
