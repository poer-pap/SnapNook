import Foundation

enum EditorTool: String, CaseIterable {
    case select = "Select"
    case crop = "Crop"
    case arrow = "Arrow"
    case rectangle = "Rectangle"
    case text = "Text"
    case highlight = "Highlight"
    case blur = "Blur"
    case mosaic = "Mosaic"

    static let toolbarTools: [EditorTool] = [
        .select,
        .crop,
        .rectangle,
        .arrow,
        .text,
        .highlight,
        .blur,
        .mosaic
    ]
}
