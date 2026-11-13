// 앱 아이콘(AppIcon.icns)을 그려서 만든다.  사용: swift scripts/make-icon.swift <출력 폴더>
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconset = outDir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(pixels)
    let inset = s * 0.09
    let body = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let shape = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)
    NSGradient(colors: [
        NSColor(red: 1.00, green: 0.55, blue: 0.20, alpha: 1),
        NSColor(red: 0.93, green: 0.22, blue: 0.36, alpha: 1),
    ])!.draw(in: shape, angle: -90)

    // 2x2 격자: 도구 네 개를 한데 묶었다는 뜻
    let grid = body.insetBy(dx: body.width * 0.23, dy: body.width * 0.23)
    let gap = grid.width * 0.12
    let cell = (grid.width - gap) / 2
    for row in 0..<2 {
        for col in 0..<2 {
            let r = NSRect(x: grid.minX + CGFloat(col) * (cell + gap),
                           y: grid.minY + CGFloat(row) * (cell + gap), width: cell, height: cell)
            // 오른쪽 위 칸만 반투명하게: "떠오르는" 방향 강조
            NSColor.white.withAlphaComponent(row == 1 && col == 1 ? 1.0 : 0.55).setFill()
            NSBezierPath(roundedRect: r, xRadius: cell * 0.24, yRadius: cell * 0.24).fill()
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
    try render(points * scale).write(to: iconset.appendingPathComponent(name))
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", outDir.appendingPathComponent("AppIcon.icns").path]
try task.run()
task.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
exit(task.terminationStatus)
