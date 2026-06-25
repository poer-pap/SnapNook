import CoreGraphics

struct CropState {
    var rect: CGRect
    var isActive: Bool

    static func defaultRect(in imageBounds: CGRect) -> CGRect {
        guard imageBounds.width > 0, imageBounds.height > 0 else {
            return .zero
        }

        let width = imageBounds.width * 0.8
        let height = imageBounds.height * 0.8
        return CGRect(
            x: imageBounds.midX - width / 2,
            y: imageBounds.midY - height / 2,
            width: width,
            height: height
        ).integral
    }
}
