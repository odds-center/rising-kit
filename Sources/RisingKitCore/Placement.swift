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
    /// 한 화면에서의 상대 위치·크기 비율을 유지한 채 다른 화면으로 옮긴 사각형.
    public static func remap(_ rect: CGRect, from: CGRect, to: CGRect) -> CGRect {
        guard from.width > 0, from.height > 0 else { return to }
        let w = min(rect.width / from.width, 1) * to.width
        let h = min(rect.height / from.height, 1) * to.height
        var x = to.minX + (rect.minX - from.minX) / from.width * to.width
        var y = to.minY + (rect.minY - from.minY) / from.height * to.height
        x = min(max(x, to.minX), to.maxX - w)
        y = min(max(y, to.minY), to.maxY - h)
        return CGRect(x: x.rounded(), y: y.rounded(), width: w.rounded(), height: h.rounded())
    }
}
