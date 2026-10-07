import CoreGraphics
import CoreVideo

enum ScrollingCaptureFrame {
    case image(CGImage)
    case pixelBuffer(CVPixelBuffer)
}
