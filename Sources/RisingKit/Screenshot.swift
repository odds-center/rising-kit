import AppKit
import Vision

/// 화면의 한 영역을 찍어 클립보드에 올리거나, 그 안의 글자를 읽어 복사한다.
/// 영역 고르기는 macOS 의 화면 캡처 도구를 그대로 쓴다 (처음 쓸 때 화면 기록 권한을 물어본다).
enum Screenshot {
    /// 영역을 골라 이미지를 클립보드에 복사한다.
    static func captureRegionToClipboard() {
        let before = NSPasteboard.general.changeCount
        run(["-i", "-c"]) {
            // esc 로 취소하면 클립보드가 바뀌지 않는다
            if NSPasteboard.general.changeCount != before { Toast.show("스크린샷을 복사했습니다", symbol: "camera.viewfinder") }
        }
    }

    /// 영역을 골라 그 안의 글자를 복사한다.
    static func copyTextFromRegion() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("risingkit-ocr-\(UUID().uuidString).png")
        run(["-i", "-x", file.path]) {
            defer { try? FileManager.default.removeItem(at: file) }
            guard FileManager.default.fileExists(atPath: file.path) else { return }  // 취소됨
            let lines = recognizeText(in: file)
            guard !lines.isEmpty else {
                Toast.show("글자를 찾지 못했습니다", symbol: "text.viewfinder")
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
            Toast.show("글자 \(lines.count)줄을 복사했습니다", symbol: "text.viewfinder")
        }
    }

    /// 이미지 파일에서 글자를 읽는다 (한국어·영어). 위에서 아래 순서의 줄 목록.
    static func recognizeText(in url: URL) -> [String] {
        guard let image = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return []
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ko-KR", "en-US"]
        request.usesLanguageCorrection = true
        do {
            try VNImageRequestHandler(cgImage: image).perform([request])
        } catch {
            return []
        }
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }

    private static func run(_ arguments: [String], completion: @escaping () -> Void) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = arguments
        task.terminationHandler = { _ in DispatchQueue.main.async(execute: completion) }
        if (try? task.run()) == nil { NSSound.beep() }
    }
}

/// 화면 아래쪽에 잠깐 떴다 사라지는 알림.
enum Toast {
    private static var panel: NSPanel?
    private static var hideWork: DispatchWorkItem?

    static func show(_ text: String, symbol: String) {
        hideWork?.cancel()
        panel?.orderOut(nil)

        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = .white
        let stack = NSStackView(views: [icon, label])
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 16, bottom: 10, right: 18)

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true
        background.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        let size = stack.fittingSize

        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = background

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: (visible.midX - size.width / 2).rounded(), y: visible.minY + 90))
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        self.panel = panel

        let work = DispatchWorkItem {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                panel.animator().alphaValue = 0
            }, completionHandler: { panel.orderOut(nil) })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
    }
}
