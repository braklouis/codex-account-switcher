import AppKit
import SwiftUI

/// Brand silhouettes sourced from CodexBar; template rendering follows light/dark appearance.
struct ProviderBrandIcon: View {
    let provider: String
    var body: some View {
        if let icon = Self.icons[provider] {
            Image(nsImage: icon).resizable().scaledToFit().accessibilityHidden(true)
        } else {
            Image(systemName: "square.dashed").resizable().scaledToFit().accessibilityHidden(true)
        }
    }
    private static let icons: [String: NSImage] = {
        let names = ["codex", "grok", "kimi", "openrouter", "claude", "cursor", "gemini", "qwen-cloud", "zai", "deepseek"]
        var result: [String: NSImage] = [:]
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: "ProviderIcons"),
                  let image = NSImage(contentsOf: url) else { continue }
            image.isTemplate = true
            result[name] = image
        }
        return result
    }()
}
