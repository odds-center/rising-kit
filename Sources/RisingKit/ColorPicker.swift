import AppKit

/// 화면의 한 점을 골라 그 색을 #RRGGBB 로 복사한다 (macOS 의 색상 추출 도구 사용).
enum ColorPicker {
    private static var sampler: NSColorSampler?

    static func pick() {
        let sampler = NSColorSampler()
        self.sampler = sampler  // 고르는 동안 살아 있게 붙잡아 둔다
        sampler.show { color in
            self.sampler = nil
            guard let color = color?.usingColorSpace(.sRGB) else { return }  // 취소됨
            let hex = String(format: "#%02X%02X%02X",
                             Int((color.redComponent * 255).rounded()),
                             Int((color.greenComponent * 255).rounded()),
                             Int((color.blueComponent * 255).rounded()))
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(hex, forType: .string)
            Toast.show("\(hex) 를 복사했습니다", symbol: "eyedropper")
        }
    }
}
