import AppKit
import SwiftUI

enum AppWindowLayout {
    static let navigationRailWidth: CGFloat = 56

    static let searchPanelMinimumWidth: CGFloat = 320
    static let searchPanelIdealWidth: CGFloat = 360
    static let searchPanelMaximumWidth: CGFloat = 430

    static let resultsPanelMinimumWidth: CGFloat = 520
    static let resultsPanelIdealWidth: CGFloat = 680

    static let detailPanelMinimumWidth: CGFloat = 340
    static let detailPanelIdealWidth: CGFloat = 400
    static let detailPanelMaximumWidth: CGFloat = 460

    static let splitHandleReserveWidth: CGFloat = 40

    static let minimumWidth: CGFloat = 1280
    static let minimumHeight: CGFloat = 760
    static let defaultWidth: CGFloat = 1380
    static let defaultHeight: CGFloat = 860

    static var minimumContentSize: CGSize {
        CGSize(width: minimumWidth, height: minimumHeight)
    }
}

struct WindowSizeConstraintView: NSViewRepresentable {
    let minimumContentSize: CGSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            applyConstraint(to: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            applyConstraint(to: nsView.window)
        }
    }

    private func applyConstraint(to window: NSWindow?) {
        guard let window else { return }

        let minimumFrameSize = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: minimumContentSize)
        ).size
        window.contentMinSize = minimumContentSize
        window.minSize = minimumFrameSize

        var frame = window.frame
        let targetWidth = max(frame.width, minimumFrameSize.width)
        let targetHeight = max(frame.height, minimumFrameSize.height)
        guard targetWidth != frame.width || targetHeight != frame.height else { return }

        frame.origin.y -= targetHeight - frame.height
        frame.size = NSSize(width: targetWidth, height: targetHeight)
        window.setFrame(frame, display: true, animate: false)
    }
}
