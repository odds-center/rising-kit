import AppKit
import Carbon.HIToolbox
import RisingKitCore
import SwiftUI

/// Rising Kit 의 설정 창. 배치도, 창 정렬, 단축키, 사용량, 일반 설정을 한 창에 모았다.
final class MainWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var keyMonitor: Any?
    private let settings = SettingsModel.shared

    var isVisible: Bool { window?.isVisible ?? false }

    /// 이미 그 탭이 떠 있으면 닫고, 아니면 그 탭으로 연다.
    func toggle(_ tab: SettingsModel.Tab) {
        if isVisible, window?.isKeyWindow == true, settings.tab == tab {
            window?.close()
        } else {
            show(tab)
        }
    }

    func show(_ tab: SettingsModel.Tab) {
        let window = self.window ?? makeWindow()
        self.window = window
        settings.tab = tab
        settings.map.message = ""
        settings.map.refresh()
        settings.bump()
        if !window.isVisible { window.center() }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func windowWillClose(_ notification: Notification) {
        ShortcutRecorder.shared.cancel()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    func windowDidBecomeKey(_ notification: Notification) {
        // 다른 앱에서 창을 옮기고 돌아왔을 때 배치도가 예전 상태로 남지 않게
        settings.map.refresh()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 940, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "Rising Kit"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // 배경을 끌어 창을 옮기는 기능은 끈다: 켜 두면 배치도에서 창 그림을 끌 때 설정 창이 대신 움직인다.
        // 창은 맨 위 제목 줄 자리를 끌어서 옮긴다.
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 860, height: 560)
        window.delegate = self
        window.contentView = NSHostingView(rootView: MainView(settings: settings))
        return window
    }

    /// 배치도 탭에서는 조합 키 없이 Magnet 과 같은 글자·방향키로 고른 창을 배치한다.
    private static let placementKeys: [Int: Placement] = [
        kVK_LeftArrow: .leftHalf, kVK_RightArrow: .rightHalf, kVK_UpArrow: .topHalf, kVK_DownArrow: .bottomHalf,
        kVK_ANSI_U: .topLeft, kVK_ANSI_I: .topRight, kVK_ANSI_J: .bottomLeft, kVK_ANSI_K: .bottomRight,
        kVK_ANSI_D: .leftThird, kVK_ANSI_F: .centerThird, kVK_ANSI_G: .rightThird,
        kVK_ANSI_E: .leftTwoThirds, kVK_ANSI_R: .centerTwoThirds, kVK_ANSI_T: .rightTwoThirds,
        kVK_Return: .maximize, kVK_ANSI_C: .center,
    ]

    private static let digitKeys: [Int: Int] = [
        kVK_ANSI_1: 0, kVK_ANSI_2: 1, kVK_ANSI_3: 2, kVK_ANSI_4: 3, kVK_ANSI_5: 4,
        kVK_ANSI_6: 5, kVK_ANSI_7: 6, kVK_ANSI_8: 7, kVK_ANSI_9: 8,
    ]

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, event.window === window else { return event }
            // 단축키를 받는 중이면 누른 조합을 그대로 받아 적는다
            if ShortcutRecorder.shared.handle(event) { return nil }
            // 글자를 입력하는 중이면 편집 단축키만 전달하고 나머지는 건드리지 않는다
            if window.firstResponder is NSTextView { return EditKeys.handle(event) ? nil : event }

            let code = Int(event.keyCode)
            let modifiers = event.modifierFlags.intersection([.command, .control, .option])
            if code == kVK_Escape { window.close(); return nil }
            // ⌘1…⌘6 으로 탭 이동
            if modifiers == .command, let index = Self.digitKeys[code], SettingsModel.Tab.allCases.indices.contains(index) {
                self.settings.tab = SettingsModel.Tab.allCases[index]
                return nil
            }
            guard self.settings.tab == .map, modifiers.isEmpty else { return event }
            let map = self.settings.map
            if code == kVK_Tab {
                map.selectNext(event.modifierFlags.contains(.shift) ? -1 : 1)
                return nil
            }
            if let placement = Self.placementKeys[code] { map.place(placement); return nil }
            if let display = Self.digitKeys[code] { map.sendToDisplay(display); return nil }
            return event
        }
    }
}

struct MainView: View {
    @ObservedObject var settings: SettingsModel
    @ObservedObject private var recorder = ShortcutRecorder.shared
    @ObservedObject private var map = SettingsModel.shared.map

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(settings.tab.title).font(.system(size: 20, weight: .semibold))
                            Text(settings.tab.subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        content
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 34)
                    .padding(.bottom, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                statusBar
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 860, minHeight: 560)
        .buttonStyle(KitButtonStyle())
    }

    @ViewBuilder private var content: some View {
        switch settings.tab {
        case .map: MapTab(model: settings.map)
        case .window: WindowTab()
        case .shortcuts: ShortcutsTab()
        case .automation: AutomationTab()
        case .system: SystemTab()
        case .uninstall: UninstallTab()
        case .general: GeneralTab()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 26, height: 26)
                Text("Rising Kit").font(.system(size: 14, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .padding(.top, 40)
            .padding(.bottom, 14)

            ForEach(Array(SettingsModel.Tab.allCases.enumerated()), id: \.element) { index, tab in
                let active = tab == settings.tab
                HStack(spacing: 9) {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 13))
                        .frame(width: 20)
                        .foregroundStyle(active ? Color.accentColor : Color.secondary)
                    Text(tab.title).font(.system(size: 13, weight: active ? .medium : .regular))
                    Spacer()
                    Text("⌘\(index + 1)").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(active ? 0.1 : 0)))
                .contentShape(Rectangle())
                .onTapGesture {
                    ShortcutRecorder.shared.cancel()
                    settings.tab = tab
                }
            }
            Spacer()
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
            Text("버전 \(version)")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
        }
        .padding(.horizontal, 8)
        .frame(width: 210)
        .background(SidebarBackground())
    }

    /// 아래 줄: 단축키 입력 안내나 방금 한 일의 결과.
    private var statusBar: some View {
        let text = !recorder.message.isEmpty ? recorder.message : (settings.tab == .map ? map.message : "")
        return HStack(spacing: 8) {
            if recorder.isRecording {
                Image(systemName: "keyboard").foregroundStyle(Color.accentColor)
            }
            Text(text.isEmpty ? "단축키 칸을 누르면 새 조합을 받습니다 · esc 로 창 닫기" : text)
                .font(.system(size: 11.5))
                .foregroundStyle(recorder.isRecording ? Color.accentColor : (text.isEmpty ? Color.secondary.opacity(0.7) : Color.secondary))
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(height: 30)
        .background(Color.primary.opacity(0.035))
        .overlay(alignment: .top) { Divider().opacity(0.6) }
    }
}

private struct SidebarBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
