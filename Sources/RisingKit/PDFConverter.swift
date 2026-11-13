import AppKit
import PDFKit

/// PDF 의 각 페이지를 PNG 파일로 저장한다.
enum PDFConverter {
    static let dpiChoices = [72, 150, 300]
    private static let dpiKey = "pdfDPI"

    static var dpi: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: dpiKey)
            return v > 0 ? v : 150
        }
        set { UserDefaults.standard.set(newValue, forKey: dpiKey) }
    }

    struct Result {
        var written: [URL] = []
        var failed: [String] = []
    }

    /// 한 쪽짜리 PDF 는 같은 폴더에 `이름.png`, 여러 쪽이면 `이름-png/이름-001.png` 로 저장한다.
    /// 이미 있는 파일은 덮어쓰지 않고 이름 뒤에 번호를 붙인다.
    static func convert(_ urls: [URL], dpi: Int) -> Result {
        var result = Result()
        let fm = FileManager.default
        for url in urls {
            guard let doc = PDFDocument(url: url), doc.pageCount > 0, !doc.isLocked else {
                result.failed.append(url.lastPathComponent)
                continue
            }
            let base = url.deletingPathExtension().lastPathComponent
            let parent = url.deletingLastPathComponent()
            let digits = max(3, String(doc.pageCount).count)
            var folder: URL?
            if doc.pageCount > 1 {
                let dir = unique(parent.appendingPathComponent("\(base)-png", isDirectory: true))
                do { try fm.createDirectory(at: dir, withIntermediateDirectories: true) } catch {
                    result.failed.append(url.lastPathComponent)
                    continue
                }
                folder = dir
            }
            for index in 0..<doc.pageCount {
                guard let page = doc.page(at: index), let data = png(of: page, dpi: dpi) else {
                    result.failed.append("\(url.lastPathComponent) \(index + 1)쪽")
                    continue
                }
                let out: URL
                if let folder {
                    let number = String(format: "%0\(digits)d", index + 1)
                    out = folder.appendingPathComponent("\(base)-\(number).png")
                } else {
                    out = unique(parent.appendingPathComponent("\(base).png"))
                }
                do {
                    try data.write(to: out, options: .withoutOverwriting)
                    result.written.append(out)
                } catch {
                    result.failed.append("\(url.lastPathComponent) \(index + 1)쪽")
                }
            }
        }
        return result
    }

    private static func png(of page: PDFPage, dpi: Int) -> Data? {
        let scale = CGFloat(dpi) / 72
        var bounds = page.bounds(for: .cropBox)
        if page.rotation % 180 != 0 {
            bounds = CGRect(x: 0, y: 0, width: bounds.height, height: bounds.width)
        }
        let width = Int((bounds.width * scale).rounded())
        let height = Int((bounds.height * scale).rounded())
        guard width > 0, height > 0,
              let ctx = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.interpolationQuality = .high
        ctx.scaleBy(x: scale, y: scale)
        page.draw(with: .cropBox, to: ctx)
        guard let image = ctx.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = NSSize(width: bounds.width, height: bounds.height)  // PNG 에 DPI 기록
        return rep.representation(using: .png, properties: [:])
    }

    private static func unique(_ url: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        let parent = url.deletingLastPathComponent()
        for n in 2...9999 {
            let name = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            let candidate = parent.appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
        }
        return url
    }

    // MARK: - UI

    /// 파일 선택 창을 띄워 변환한다.
    static func pickAndConvert() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "PNG 로 변환할 PDF 선택"
        panel.prompt = "변환"
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        convertAndReveal(panel.urls)
    }

    /// 백그라운드에서 변환한 뒤 결과를 Finder 에서 보여준다.
    static func convertAndReveal(_ urls: [URL]) {
        let dpi = self.dpi
        DispatchQueue.global(qos: .userInitiated).async {
            let result = convert(urls, dpi: dpi)
            DispatchQueue.main.async {
                if !result.written.isEmpty {
                    // 여러 쪽이면 폴더를, 한 쪽이면 파일을 선택해 보여준다
                    var targets: [URL] = []
                    for url in result.written {
                        let parent = url.deletingLastPathComponent()
                        let target = parent.lastPathComponent.hasSuffix("-png") ? parent : url
                        if !targets.contains(target) { targets.append(target) }
                    }
                    NSWorkspace.shared.activateFileViewerSelecting(targets)
                }
                if !result.failed.isEmpty {
                    NSApp.activate(ignoringOtherApps: true)
                    let alert = NSAlert()
                    alert.alertStyle = .warning
                    alert.messageText = "변환하지 못한 항목이 있습니다"
                    alert.informativeText = result.failed.prefix(10).joined(separator: "\n")
                    alert.runModal()
                }
            }
        }
    }
}
