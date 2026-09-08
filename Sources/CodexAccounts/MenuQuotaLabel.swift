import SwiftUI
import AppKit
import SwitcherCore

struct MenuQuotaLabel: View {
    @ObservedObject var store: AccountStore
    @ObservedObject private var preferences = AppPreferences.shared
    private var profile: Profile? { store.profiles.first { $0.snapshot?.identity == store.activeIdentity } }
    private var summary: MenuQuotaSummary {
        guard let profile else { return MenuQuotaSummary(quota: nil) }
        return MenuQuotaSummary(quota: store.quotas[profile.id], unavailable: store.quotaErrors[profile.id] != nil)
    }
    var body: some View {
            let short = valid(summary.shortTerm, now: Date())
            let week = valid(summary.weekly, now: Date())
            Image(nsImage: StatusQuotaDrawing.image(style: preferences.menuQuotaStyle,
                short: short?.remaining, weekly: week?.remaining, shortLabel: label(short)))
                .accessibilityLabel(L10n.isEnglish ? "Codex remaining: short-term \(value(short)), weekly \(value(week))" : "Codex 剩余额度：短期 \(value(short))，每周 \(value(week))")
                .help(L10n.isEnglish ? "Short-term \(value(short)) · Weekly \(value(week)). Click for details." : "\(profile?.name ?? L10n.text("未保存当前账号")) · 短期 \(value(short)) · 每周 \(value(week))。点击查看详情。")
    }
    private func valid(_ window: QuotaWindow?, now: Date) -> QuotaWindow? {
        guard let window else { return nil }
        if let reset = window.resetsAt, reset <= now.timeIntervalSince1970 { return nil }
        return window
    }
    private func label(_ window: QuotaWindow?) -> String {
        guard let mins = window?.windowDurationMins else { return L10n.isEnglish ? "S" : "短" }
        return mins % 60 == 0 ? "\(mins / 60)h" : "\(mins)m"
    }
    private func value(_ window: QuotaWindow?) -> String { window.map { "\(Int($0.remaining))%" } ?? L10n.text("暂不可用") }
}

/// Rasterize into a native status-item image: macOS menu labels otherwise flatten custom SwiftUI layouts.
/// Draws at the backing scale chosen by AppKit, retaining crisp two-row text on Retina screens.
@MainActor enum StatusQuotaDrawing {
    private static var cache: [String: NSImage] = [:]
    static func image(style: String, short: Double?, weekly: Double?, shortLabel: String = "5h") -> NSImage {
        let key = "\(L10n.isEnglish)|\(style)|\(String(describing: short))|\(String(describing: weekly))|\(shortLabel)|\(NSApp.effectiveAppearance.name.rawValue)"
        if let cached = cache[key] { return cached }
        let numbers = style != "bars"
        let bars = style != "numbers"
        let width: CGFloat = 18 + (numbers ? 34 : 0) + (bars ? 43 : 0) + (numbers && bars ? 4 : 0)
        let image = NSImage(size: NSSize(width: width, height: 22))
        image.lockFocus()
            let candidates: [(String, Double?, NSColor)] = [
                (shortLabel, short, NSColor(srgbRed: 0.55, green: 0.87, blue: 0.98, alpha: 1)),
                (L10n.isEnglish ? "W" : "周", weekly, NSColor(srgbRed: 0.77, green: 0.70, blue: 0.98, alpha: 1))
            ]
            let available = candidates.filter { $0.1 != nil }
            // Some plans expose only a weekly window. Do not draw a phantom
            // short-term meter or borrow a different model's quota.
            let rows = available.isEmpty ? [("", nil as Double?, NSColor.secondaryLabelColor)] : available
            for (index, item) in rows.enumerated() {
                let (name, value, color) = item
                let y: CGFloat = rows.count == 1 ? 5.5 : (index == 0 ? 11 : 0)
                let textColor = value == nil ? NSColor.secondaryLabelColor : color
                let small = NSFont.systemFont(ofSize: 8, weight: .semibold)
                (name as NSString).draw(in: NSRect(x: 0, y: y + 1, width: 19, height: 10), withAttributes: [.font: small, .foregroundColor: textColor])
                if numbers {
                    let text = value.map { "\(Int(max(0, min(100, $0))))%" } ?? "—"
                    let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .right
                    (text as NSString).draw(in: NSRect(x: 18, y: y - 1, width: 34, height: 12),
                        withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold), .foregroundColor: textColor, .paragraphStyle: paragraph])
                }
                if bars && value != nil {
                    let x: CGFloat = numbers ? 56 : 18
                    let proportion = max(0, min(100, value ?? 0)) / 100
                    for segment in 0..<8 {
                        let rect = NSRect(x: x + CGFloat(segment) * 5.25, y: y + 1, width: 3.75, height: 8)
                        color.withAlphaComponent(0.22).setFill()
                        NSBezierPath(roundedRect: rect, xRadius: 1.1, yRadius: 1.1).fill()
                        let fraction = max(0, min(1, proportion * 8 - Double(segment)))
                        if fraction > 0 {
                            color.setFill()
                            NSBezierPath(roundedRect: NSRect(x: rect.minX, y: rect.minY, width: rect.width * fraction, height: rect.height), xRadius: 0.7, yRadius: 0.7).fill()
                        }
                    }
                }
                if !numbers && value == nil {
                    ("—" as NSString).draw(at: NSPoint(x: 25, y: y), withAttributes: [.font: small, .foregroundColor: textColor])
                }
            }
        image.unlockFocus()
        image.isTemplate = false
        if cache.count >= 64 { cache.removeAll(keepingCapacity: true) }
        cache[key] = image
        return image
    }
}

struct MenuQuotaPreview: View {
    let style: String
    var body: some View {
        HStack(spacing: 12) {
            Text(L10n.text("样式预览")).font(.caption).foregroundStyle(.secondary)
            Image(nsImage: StatusQuotaDrawing.image(style: style, short: 68, weekly: 92))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
            Text(L10n.text("示例数据")).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
