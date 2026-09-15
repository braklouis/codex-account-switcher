import SwiftUI

/// Uses the system material, including its contrast and reduced-transparency behavior.
struct MenuGlassSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if reduceTransparency {
                content.background(Color(nsColor: .windowBackgroundColor))
            } else {
                content
                    .containerBackground(.clear, for: .window)
                    .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 22))
            }
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
    }
}
