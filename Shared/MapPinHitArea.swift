import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Match centered saved symbols to their actual frame; native pointed markers
/// retain their above-coordinate touch area.
enum MapPinHitArea {
    static func savedIconSide(symbolSize: Double) -> Double {
        max(44, symbolSize + 8)
    }

    static func bounds(anchor: CGPoint, savedSymbolSize: Double?) -> CGRect {
        if let savedSymbolSize {
            let side = savedIconSide(symbolSize: savedSymbolSize)
            return CGRect(x: anchor.x - side / 2, y: anchor.y - side / 2,
                          width: side, height: side)
        }
        return CGRect(x: anchor.x - 28, y: anchor.y - 64, width: 56, height: 80)
    }
}
