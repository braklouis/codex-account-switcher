import AppKit
import SwiftUI

/// Override only this scroll view, even when macOS is set to always show scrollbars.
struct AutoHidingScrollbars: NSViewRepresentable {
    func makeNSView(context: Context) -> ScrollbarProbe { ScrollbarProbe() }
    func updateNSView(_ view: ScrollbarProbe, context: Context) { view.configure() }

    final class ScrollbarProbe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in self?.configure() }
        }
        func configure() {
            guard let scroll = enclosingScrollView else { return }
            scroll.scrollerStyle = .overlay
            scroll.autohidesScrollers = true
        }
    }
}
