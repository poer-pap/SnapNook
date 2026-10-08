import AppKit
import OSLog
import QuartzCore
import UniformTypeIdentifiers

private let previewLogger = Logger(subsystem: "com.ethan.snapnook", category: "ScreenshotPreview")

final class ScreenshotPreviewController {
    private final class Card {
        let id = UUID()
        let item: ScreenshotPreviewItem
        let view: ScreenshotPreviewView
        var displayID: NSNumber
        var isRemoving = false

        init(item: ScreenshotPreviewItem, displayID: NSNumber) {
            self.item = item
            self.displayID = displayID
            view = ScreenshotPreviewView(item: item)
        }
    }

    private let writer = ScreenshotWriter()
    private var cards: [Card] = []
    private var lists: [NSNumber: ScreenshotPreviewList] = [:]
    private var editorControllers: [ScreenshotEditorWindowController] = []
    private var screenObserver: NSObjectProtocol?
    private var isHiddenForCapture = false
    private var draggingView: ScreenshotPreviewView?

    var isDragging: Bool { draggingView != nil }

    init() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, !self.isDragging else { return }
            self.updateLists()
        }
    }

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    func show(item: ScreenshotPreviewItem) {
        guard let screen = Self.screen(for: item) ?? NSScreen.screens.first,
              let displayID = Self.displayID(for: screen) else { return }
        let card = Card(item: item, displayID: displayID)
        cards.append(card)
        card.view.onCopy = { [weak self, weak card] in
            guard let self, let card, !card.isRemoving else { return }
            guard ClipboardWriter.copy(image: card.item.image, pngData: card.item.pngData) else {
                AlertPresenter.show(message: "Copy failed.", informativeText: "SnapNook could not copy the captured image.")
                return
            }
            self.remove(id: card.id)
        }
        card.view.onSave = { [weak self, weak card] in
            guard let card else { return }
            self?.presentSavePanel(id: card.id)
        }
        card.view.onEdit = { [weak self, weak card] in
            guard let self, let card, !card.isRemoving else { return }
            self.openEditor(for: card.item)
            self.remove(id: card.id)
        }
        card.view.onClose = { [weak self, weak card] in
            guard let card else { return }
            self?.remove(id: card.id)
        }
        card.view.onDragStarted = { [weak self, weak card] in
            self?.draggingView = card?.view
        }
        card.view.onDragEnded = { [weak self, weak card] accepted in
            // Keep the source alive until AppKit has finished delivering the drag callback.
            DispatchQueue.main.async { [weak self, card] in
                guard let self else { return }
                self.draggingView = nil
                if accepted, let card { self.remove(id: card.id) }
                self.updateLists()
            }
        }
        updateLists(latestID: card.id, animate: true)
    }

    func hideForCapture() {
        isHiddenForCapture = true
        for list in lists.values { list.panel.orderOut(nil) }
    }

    func restoreAfterCapture() {
        guard isHiddenForCapture else { return }
        isHiddenForCapture = false
        for list in lists.values { list.panel.orderFrontRegardless() }
    }

    private func remove(id: UUID) {
        guard let card = cards.first(where: { $0.id == id }), !card.isRemoving,
              draggingView !== card.view else { return }
        card.isRemoving = true
        card.view.isEnabled = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.45
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            card.view.animator().alphaValue = 0
            card.view.animator().setFrameOrigin(NSPoint(x: -ScreenshotPreviewPanel.previewPanelSize.width, y: card.view.frame.minY))
        } completionHandler: { [weak self, card] in
            guard let self, self.cards.contains(where: { $0.id == id }) else { return }
            card.view.removeFromSuperview()
            self.cards.removeAll { $0.id == id }
            self.updateLists(animate: true)
        }
    }

    private func updateLists(latestID: UUID? = nil, animate: Bool = false) {
        guard !isDragging, let mainScreen = NSScreen.screens.first,
              let mainID = Self.displayID(for: mainScreen) else { return }
        let screens = NSScreen.screens
        let connectedIDs = Set(screens.compactMap(Self.displayID))
        for card in cards where !connectedIDs.contains(card.displayID) { card.displayID = mainID }

        let usedIDs = Set(cards.map(\.displayID))
        for id in Array(lists.keys) where !usedIDs.contains(id) {
            let list = lists.removeValue(forKey: id)
            list?.panel.orderOut(nil)
            DispatchQueue.main.async { list?.panel.closeIfNeeded() }
        }
        for screen in screens {
            guard let id = Self.displayID(for: screen), usedIDs.contains(id) else { continue }
            let list = lists[id] ?? ScreenshotPreviewList()
            lists[id] = list
            let screenCards = cards.filter { $0.displayID == id }
            let latest = screenCards.first { $0.id == latestID }
            list.layout(views: screenCards.map(\.view), screen: screen, animate: animate, scrollToNewest: latest != nil)
            if let latest {
                if !isHiddenForCapture { latest.view.animateAppearance() }
            }
            if !isHiddenForCapture { list.panel.orderFrontRegardless() }
        }
    }

    private func presentSavePanel(id: UUID) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let card = self.cards.first(where: { $0.id == id }), !card.isRemoving else { return }
            NSApp.activate(ignoringOtherApps: true)
            let savePanel = NSSavePanel()
            savePanel.canCreateDirectories = true
            savePanel.isExtensionHidden = false
            savePanel.nameFieldStringValue = ScreenshotWriter.filename(createdAt: card.item.createdAt)
            savePanel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
            savePanel.allowedContentTypes = [.png]
            savePanel.begin { [weak self] response in
                guard let self, let current = self.cards.first(where: { $0.id == id }), !current.isRemoving,
                      response == .OK, let fileURL = savePanel.url else { return }
                do {
                    try self.writer.write(data: current.item.pngData, to: fileURL)
                    self.remove(id: id)
                } catch {
                    previewLogger.error("Screenshot preview save failed: \(error.localizedDescription, privacy: .public).")
                    AlertPresenter.show(message: "Save failed.", informativeText: error.localizedDescription)
                }
            }
        }
    }

    private func openEditor(for item: ScreenshotPreviewItem) {
        let controller = ScreenshotEditorWindowController(item: item)
        controller.onClose = { [weak self, weak controller] in
            guard let self, let controller else { return }
            self.editorControllers.removeAll { $0 === controller }
        }
        editorControllers.append(controller)
        controller.showEditor()
    }

    private static func displayID(for screen: NSScreen) -> NSNumber? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
    }

    private static func screen(for item: ScreenshotPreviewItem) -> NSScreen? {
        if let rect = item.captureRect,
           let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: rect.midX, y: rect.midY)) }) {
            return screen
        }
        return NSScreen.screens.first { $0.frame.intersects(item.screenFrame) }
    }
}

private final class ScreenshotPreviewList {
    let panel = ScreenshotPreviewPanel(contentRect: .zero)
    private let scrollView = NSScrollView()
    private let documentView = PreviewListDocumentView()
    private static let shadowInset: CGFloat = 10

    init() {
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = documentView
        panel.contentView = scrollView
    }

    func layout(views: [ScreenshotPreviewView], screen: NSScreen, animate: Bool, scrollToNewest: Bool) {
        let size = ScreenshotPreviewPanel.previewPanelSize
        let contentHeight = CGFloat(views.count) * (size.height + 10) - 10 + Self.shadowInset * 2
        let height = min(contentHeight, max(1, screen.visibleFrame.height - 40))
        let width = size.width + Self.shadowInset * 2
        let previousOffset = scrollView.contentView.bounds.origin.y
        let previousFrames = views.reduce(into: [ObjectIdentifier: NSRect]()) { frames, view in
            if let window = view.window {
                frames[ObjectIdentifier(view)] = window.convertToScreen(view.convert(view.bounds, to: nil))
            }
        }
        panel.setFrame(NSRect(x: screen.visibleFrame.minX + 40 - Self.shadowInset,
                              y: screen.visibleFrame.minY + 20 - Self.shadowInset,
                              width: width, height: height), display: true)
        documentView.setFrameSize(NSSize(width: width, height: contentHeight))
        let maxOffset = max(0, contentHeight - scrollView.contentSize.height)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: scrollToNewest ? maxOffset : min(previousOffset, maxOffset)))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        for (index, view) in views.enumerated() {
            let isNew = view.superview !== documentView
            if isNew {
                view.removeFromSuperview()
                documentView.addSubview(view)
            }
            let origin = NSPoint(x: Self.shadowInset, y: Self.shadowInset + CGFloat(index) * (size.height + 10))
            if animate, let previousFrame = previousFrames[ObjectIdentifier(view)], view.isEnabled {
                view.frame = documentView.convert(panel.convertFromScreen(previousFrame), from: nil)
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.18
                    view.animator().setFrameOrigin(origin)
                }
            } else if view.isEnabled {
                view.setFrameOrigin(origin)
            }
        }
    }
}

private final class PreviewListDocumentView: NSView {
    override var isFlipped: Bool { true }
}
