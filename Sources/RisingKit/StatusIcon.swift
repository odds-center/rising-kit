import AppKit

/// 메뉴바 아이콘: 수평선 위로 떠오르는 해. 템플릿 이미지라 밝은/어두운 메뉴바에 맞춰 색이 바뀐다.
enum StatusIcon {
    /// 메뉴바 높이(24pt)를 거의 다 쓰는 26x22pt. `scale` 은 미리보기용 확대 배율.
    static func make(scale s: CGFloat = 1) -> NSImage {
        let image = NSImage(size: NSSize(width: 26 * s, height: 22 * s), flipped: false) { _ in
            NSColor.black.setFill()
            NSColor.black.setStroke()

            // 수평선
            NSBezierPath(roundedRect: NSRect(x: 1 * s, y: 1.5 * s, width: 24 * s, height: 2.6 * s),
                         xRadius: 1.3 * s, yRadius: 1.3 * s).fill()

            // 해 (위쪽 반원)
            let center = NSPoint(x: 13 * s, y: 6.4 * s)
            let sun = NSBezierPath()
            sun.move(to: NSPoint(x: center.x - 6.6 * s, y: center.y))
            sun.appendArc(withCenter: center, radius: 6.6 * s, startAngle: 180, endAngle: 0, clockwise: true)
            sun.close()
            sun.fill()

            // 햇살
            let rays = NSBezierPath()
            rays.lineWidth = 2.3 * s
            rays.lineCapStyle = .round
            for degrees in [20.0, 55.0, 90.0, 125.0, 160.0] {
                let a = degrees * .pi / 180
                rays.move(to: NSPoint(x: center.x + cos(a) * 9.4 * s, y: center.y + sin(a) * 9.4 * s))
                rays.line(to: NSPoint(x: center.x + cos(a) * 12.4 * s, y: center.y + sin(a) * 12.4 * s))
            }
            rays.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Rising Kit"
        return image
    }
}
