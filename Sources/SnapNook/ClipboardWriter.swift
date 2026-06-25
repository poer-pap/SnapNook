import AppKit

enum ClipboardWriter {
    @discardableResult
    static func copy(image: NSImage, pngData: Data) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let item = NSPasteboardItem()
        item.setData(pngData, forType: .png)

        if let tiffData = image.tiffRepresentation {
            item.setData(tiffData, forType: .tiff)
        }

        return pasteboard.writeObjects([item])
    }

    @discardableResult
    static func copy(text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }
}
