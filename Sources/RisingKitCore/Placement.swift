import CoreGraphics

/// 창을 화면의 어느 영역에 놓을지.
public enum Placement: String, CaseIterable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case leftThird, centerThird, rightThird
    case leftTwoThirds, centerTwoThirds, rightTwoThirds
    case maximize, center

    /// `visible`(메뉴바·Dock 을 뺀 화면 영역) 안에서 창이 차지할 사각형.
    /// 좌표는 왼쪽 위가 원점이다 (손쉬운 사용 API 와 같은 방향).
    public func rect(in visible: CGRect, current: CGRect) -> CGRect {
        let v = visible
        let halfW = (v.width / 2).rounded(.down)
        let halfH = (v.height / 2).rounded(.down)
        let thirdW = (v.width / 3).rounded(.down)

        switch self {
        case .leftHalf:
            return CGRect(x: v.minX, y: v.minY, width: halfW, height: v.height)
        case .rightHalf:
            return CGRect(x: v.minX + halfW, y: v.minY, width: v.width - halfW, height: v.height)
        case .topHalf:
            return CGRect(x: v.minX, y: v.minY, width: v.width, height: halfH)
        case .bottomHalf:
            return CGRect(x: v.minX, y: v.minY + halfH, width: v.width, height: v.height - halfH)
        case .topLeft:
            return CGRect(x: v.minX, y: v.minY, width: halfW, height: halfH)
        case .topRight:
            return CGRect(x: v.minX + halfW, y: v.minY, width: v.width - halfW, height: halfH)
        case .bottomLeft:
            return CGRect(x: v.minX, y: v.minY + halfH, width: halfW, height: v.height - halfH)
        case .bottomRight:
            return CGRect(x: v.minX + halfW, y: v.minY + halfH, width: v.width - halfW, height: v.height - halfH)
        case .leftThird:
            return CGRect(x: v.minX, y: v.minY, width: thirdW, height: v.height)
        case .centerThird:
            return CGRect(x: v.minX + thirdW, y: v.minY, width: thirdW, height: v.height)
        case .rightThird:
            return CGRect(x: v.minX + thirdW * 2, y: v.minY, width: v.width - thirdW * 2, height: v.height)
        case .leftTwoThirds:
            return CGRect(x: v.minX, y: v.minY, width: thirdW * 2, height: v.height)
        case .centerTwoThirds:
            return CGRect(x: v.minX + ((v.width - thirdW * 2) / 2).rounded(.down), y: v.minY,
                          width: thirdW * 2, height: v.height)
        case .rightTwoThirds:
            return CGRect(x: v.minX + thirdW, y: v.minY, width: v.width - thirdW, height: v.height)
        case .maximize:
            return v
        case .center:
            let w = min(current.width, v.width)
            let h = min(current.height, v.height)
            return CGRect(
                x: (v.minX + (v.width - w) / 2).rounded(),
                y: (v.minY + (v.height - h) / 2).rounded(),
                width: w, height: h)
        }
    }
}

public enum DisplayMove {
    /// 다른 화면으로 옮긴 사각형.
    /// 절반 · 1/4 · 1/3 · 최대화처럼 정해진 자리에 있던 창은 새 화면에서도 같은 자리로 간다.
    /// 그 밖의 창은 크기를 그대로 두고(새 화면보다 크면 줄여서) 화면 안 상대 위치만 맞춘다.
    /// 화면 비율대로 늘리면 세로 모니터로 옮길 때 창이 길쭉하게 늘어나기 때문이다.
    public static func remap(_ rect: CGRect, from: CGRect, to: CGRect) -> CGRect {
        guard from.width > 0, from.height > 0 else { return to }
        func near(_ a: CGRect, _ b: CGRect) -> Bool {
            abs(a.minX - b.minX) <= 2 && abs(a.minY - b.minY) <= 2
                && abs(a.width - b.width) <= 2 && abs(a.height - b.height) <= 2
        }
        if let snapped = Placement.allCases.first(where: { $0 != .center && near($0.rect(in: from, current: rect), rect) }) {
            return snapped.rect(in: to, current: rect)
        }
        let w = min(rect.width, to.width)
        let h = min(rect.height, to.height)
        // 창 가운데가 화면에서 놓였던 비율 자리에 오게
        var x = to.minX + (rect.midX - from.minX) / from.width * to.width - w / 2
        var y = to.minY + (rect.midY - from.minY) / from.height * to.height - h / 2
        x = min(max(x, to.minX), to.maxX - w)
        y = min(max(y, to.minY), to.maxY - h)
        return CGRect(x: x.rounded(), y: y.rounded(), width: w.rounded(), height: h.rounded())
    }
}

/// Magnet 처럼 이미 그 절반에 있는 창에 같은 단축키를 한 번 더 누르면 그쪽 옆 화면으로 넘긴다.
/// 오른쪽 절반 + 오른쪽 → 오른쪽 화면의 왼쪽 절반, 위쪽 절반 + 위 → 위 화면의 아래쪽 절반.
public enum DisplayHop {
    public struct Hop: Equatable {
        public let screen: Int
        public let placement: Placement
    }

    /// `screens` 는 화면 전체 영역, `visible` 은 같은 순서의 메뉴바 · Dock 을 뺀 영역 (왼쪽 위가 원점).
    /// 넘길 일이 아니면(아직 그 자리가 아니거나 그쪽에 화면이 없으면) nil.
    public static func next(
        _ placement: Placement, window: CGRect, from: Int, screens: [CGRect], visible: [CGRect]
    ) -> Hop? {
        guard screens.indices.contains(from), visible.indices.contains(from) else { return nil }
        let opposite: Placement
        let dx: Int, dy: Int
        switch placement {
        case .leftHalf: (opposite, dx, dy) = (.rightHalf, -1, 0)
        case .rightHalf: (opposite, dx, dy) = (.leftHalf, 1, 0)
        case .topHalf: (opposite, dx, dy) = (.bottomHalf, 0, -1)
        case .bottomHalf: (opposite, dx, dy) = (.topHalf, 0, 1)
        default: return nil
        }
        let here = placement.rect(in: visible[from], current: window)
        guard abs(here.minX - window.minX) <= 3, abs(here.minY - window.minY) <= 3,
              abs(here.width - window.width) <= 3, abs(here.height - window.height) <= 3 else { return nil }
        guard let target = neighbor(of: from, dx: dx, dy: dy, window: window, screens: screens) else { return nil }
        return Hop(screen: target, placement: opposite)
    }

    /// `from` 화면의 그쪽 가장자리에 맞닿은 화면. 여럿이면 창과 가장 많이 겹치는(가까운) 화면.
    static func neighbor(of from: Int, dx: Int, dy: Int, window: CGRect, screens: [CGRect]) -> Int? {
        let a = screens[from]
        func overlap(_ lo1: CGFloat, _ hi1: CGFloat, _ lo2: CGFloat, _ hi2: CGFloat) -> CGFloat { min(hi1, hi2) - max(lo1, lo2) }
        var best: (index: Int, score: CGFloat)?
        for (i, b) in screens.enumerated() where i != from {
            let touches: Bool
            let score: CGFloat
            if dx != 0 {
                touches = dx > 0 ? abs(b.minX - a.maxX) <= 2 : abs(b.maxX - a.minX) <= 2
                guard overlap(a.minY, a.maxY, b.minY, b.maxY) > 0 else { continue }
                score = overlap(window.minY, window.maxY, b.minY, b.maxY) - abs(window.midY - b.midY) / 10_000
            } else {
                touches = dy > 0 ? abs(b.minY - a.maxY) <= 2 : abs(b.maxY - a.minY) <= 2
                guard overlap(a.minX, a.maxX, b.minX, b.maxX) > 0 else { continue }
                score = overlap(window.minX, window.maxX, b.minX, b.maxX) - abs(window.midX - b.midX) / 10_000
            }
            guard touches else { continue }
            if best == nil || score > best!.score { best = (i, score) }
        }
        return best?.index
    }
}
