import CoreGraphics

/// 화면 영역에 대한 비율(0~1)로 나타낸 사각형. 해상도가 다른 화면에도 같은 배치를 적용할 수 있다.
public struct FractionRect: Codable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }

    /// 실제 사각형이 `area` 안에서 차지하는 비율. 화면 밖으로 나간 부분은 잘라 낸다.
    public init(_ rect: CGRect, in area: CGRect) {
        guard area.width > 0, area.height > 0 else { self.init(x: 0, y: 0, width: 1, height: 1); return }
        let w = min(max(rect.width / area.width, 0.05), 1)
        let h = min(max(rect.height / area.height, 0.05), 1)
        let x = min(max((rect.minX - area.minX) / area.width, 0), 1 - w)
        let y = min(max((rect.minY - area.minY) / area.height, 0), 1 - h)
        func r(_ v: CGFloat) -> Double { (Double(v) * 10000).rounded() / 10000 }
        self.init(x: r(x), y: r(y), width: r(w), height: r(h))
    }

    public var isValid: Bool {
        x >= 0 && y >= 0 && width > 0 && height > 0 && x + width <= 1.0001 && y + height <= 1.0001
    }

    public func absolute(in area: CGRect) -> CGRect {
        CGRect(
            x: (area.minX + area.width * x).rounded(),
            y: (area.minY + area.height * y).rounded(),
            width: (area.width * width).rounded(),
            height: (area.height * height).rounded())
    }
}

public enum DropZone {
    /// 배치도에서 창을 화면 위에 끌어다 놓은 지점(화면 안 0~1 좌표)에 해당하는 배치.
    /// 가장자리는 절반, 모서리는 1/4, 가운데는 최대화.
    public static func placement(atUnitX x: Double, y: Double) -> Placement {
        let left = x < 0.25, right = x > 0.75
        let top = y < 0.3, bottom = y > 0.7
        switch (left, right, top, bottom) {
        case (true, _, true, _): return .topLeft
        case (true, _, _, true): return .bottomLeft
        case (true, _, _, _): return .leftHalf
        case (_, true, true, _): return .topRight
        case (_, true, _, true): return .bottomRight
        case (_, true, _, _): return .rightHalf
        case (_, _, true, _): return .topHalf
        case (_, _, _, true): return .bottomHalf
        default: return .maximize
        }
    }
}

extension DropZone {
    /// 배치도에서 창을 놓은 지점(화면 안 0~1 좌표)이 가장자리에 가까울 때만 붙일 배치를 돌려준다.
    /// 가운데 쪽에 놓으면 nil — 그때는 놓은 자리 그대로 둔다.
    /// 왼쪽·오른쪽 끝 = 절반(위아래 끝에서는 1/4), 위쪽 끝 = 최대화, 아래쪽 끝 = 1/3.
    public static func edgePlacement(atUnitX x: Double, y: Double, margin: Double = 0.07) -> Placement? {
        let left = x < margin, right = x > 1 - margin
        let top = y < margin, bottom = y > 1 - margin
        // 모서리는 가장자리보다 넉넉하게 잡는다
        let nearTop = y < 0.22, nearBottom = y > 0.78
        if left { return nearTop ? .topLeft : nearBottom ? .bottomLeft : .leftHalf }
        if right { return nearTop ? .topRight : nearBottom ? .bottomRight : .rightHalf }
        if top { return .maximize }
        if bottom { return x < 1.0 / 3 ? .leftThird : x > 2.0 / 3 ? .rightThird : .centerThird }
        return nil
    }
}

public enum EdgeSnap {
    /// 창을 끌던 마우스가 화면 가장자리에 닿았을 때의 배치. 가장자리가 아니면 nil.
    /// `point` 와 `screen` 은 왼쪽 위가 원점인 전역 좌표.
    /// 왼쪽·오른쪽 = 절반(위아래 끝에서는 1/4), 위 = 최대화(좌우 끝에서는 1/4), 아래 = 1/3.
    public static func placement(at point: CGPoint, in screen: CGRect, edge: CGFloat = 6) -> Placement? {
        let atLeft = point.x <= screen.minX + edge
        let atRight = point.x >= screen.maxX - edge
        let atTop = point.y <= screen.minY + edge
        let atBottom = point.y >= screen.maxY - edge
        let nearTop = point.y < screen.minY + screen.height * 0.2
        let nearBottom = point.y > screen.maxY - screen.height * 0.2
        let nearLeft = point.x < screen.minX + screen.width * 0.2
        let nearRight = point.x > screen.maxX - screen.width * 0.2

        if atLeft { return nearTop ? .topLeft : nearBottom ? .bottomLeft : .leftHalf }
        if atRight { return nearTop ? .topRight : nearBottom ? .bottomRight : .rightHalf }
        if atTop { return nearLeft ? .topLeft : nearRight ? .topRight : .maximize }
        if atBottom {
            let x = (point.x - screen.minX) / screen.width
            return x < 1.0 / 3 ? .leftThird : x > 2.0 / 3 ? .rightThird : .centerThird
        }
        return nil
    }
}

/// 배치도에서 창을 자유롭게 옮기고 크기를 바꿀 때의 계산.
public enum FreePlacement {
    /// 사각형이 영역 안에 들어오게 한다: 영역보다 크면 줄이고, 밖으로 나갔으면 안으로 민다.
    public static func fit(_ rect: CGRect, in area: CGRect, minSize: CGSize = CGSize(width: 200, height: 120)) -> CGRect {
        let width = min(max(rect.width, min(minSize.width, area.width)), area.width)
        let height = min(max(rect.height, min(minSize.height, area.height)), area.height)
        let x = min(max(rect.minX, area.minX), area.maxX - width)
        let y = min(max(rect.minY, area.minY), area.maxY - height)
        return CGRect(x: x.rounded(), y: y.rounded(), width: width.rounded(), height: height.rounded())
    }

    /// 끌기 시작한 점과 지금 점으로 만든 사각형 (어느 방향으로 끌어도 된다).
    public static func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    /// 오른쪽 아래 모서리를 끌어 크기를 바꾼 사각형 (왼쪽 위는 그대로).
    public static func resized(_ rect: CGRect, by delta: CGSize, in area: CGRect,
                               minSize: CGSize = CGSize(width: 200, height: 120)) -> CGRect {
        // CGRect 는 음수 크기를 양수로 바꿔 돌려주므로 숫자로 직접 계산한다
        let width = min(max(rect.width + delta.width, minSize.width), max(area.maxX - rect.minX, minSize.width))
        let height = min(max(rect.height + delta.height, minSize.height), max(area.maxY - rect.minY, minSize.height))
        return CGRect(x: rect.minX, y: rect.minY, width: width.rounded(), height: height.rounded())
    }
}
