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
        let now = store.menuClock
        let short = valid(summary.shortTerm, now: now)
        let week = valid(summary.weekly, now: now)
        let selected = short ?? week
        Image(nsImage: StatusQuotaDrawing.image(style: preferences.menuQuotaStyle,
            short: short?.remaining, weekly: week?.remaining,
            countdown: countdown(selected, now: now), timeRemaining: timeRemaining(selected, now: now)))
            .accessibilityLabel(L10n.isEnglish ? "Remaining quota \(value(selected)); \(countdown(selected, now: now)) until reset" : "剩余额度 \(value(selected))；距重置 \(countdown(selected, now: now))")
            .help(L10n.isEnglish ? "Time until reset. Left bar: time remaining; right bar: quota remaining. Short-term \(value(short)) · Weekly \(value(week))" : "距重置剩余时间。左条：剩余时间；右条：剩余额度。短期 \(value(short)) · 每周 \(value(week))")
    }
    private func timeRemaining(_ window: QuotaWindow?, now: Date) -> Double? {
        guard let window, let minutes = window.windowDurationMins, minutes > 0,
              let reset = window.resetsAt else { return nil }
        return max(0, min(100, (reset - now.timeIntervalSince1970) / (Double(minutes) * 60) * 100))
    }
    private func countdown(_ window: QuotaWindow?, now: Date) -> String {
        guard let window, let minutes = window.windowDurationMins, let reset = window.resetsAt else { return "—" }
        let days = minutes >= 1440
        let divisor = days ? 86400.0 : 3600.0
        let total = Double(minutes) * 60 / divisor
        let left = min(total, max(0, reset - now.timeIntervalSince1970) / divisor)
        let unit = L10n.isEnglish ? (days ? "d" : "h") : (days ? "天" : "小时")
        return String(format: "%.1f%@", locale: Locale(identifier: "en_US_POSIX"), left, unit)
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
    static func image(style: String, short: Double?, weekly: Double?, countdown: String = "4.3h", timeRemaining: Double? = nil) -> NSImage {
        let remaining = short ?? weekly
        let timeSegments = timeRemaining
        let key = "\(String(describing: timeSegments))|\(style)|\(String(describing: short))|\(String(describing: weekly))|\(countdown)|\(NSApp.effectiveAppearance.name.rawValue)"
        if let cached = cache[key] { return cached }
        let color = NSColor(srgbRed: 0.04, green: 0.36, blue: 0.25, alpha: 1)
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
        let topAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: remaining == nil ? NSColor.secondaryLabelColor : color
        ]
        let showText = style != "bars"
        let showBars = style != "numbers"
        let textWidth: CGFloat = showText ? max(36, ceil((countdown as NSString).size(withAttributes: topAttributes).width) + 2) : 0
        let barsX: CGFloat = showText ? textWidth + 5 : 0
        let width = showBars ? barsX + 12 : textWidth
        let image = NSImage(size: NSSize(width: width, height: 22))
        image.lockFocus()
        let alignment = NSMutableParagraphStyle(); alignment.alignment = .right
        var top = topAttributes; top[.paragraphStyle] = alignment
        if showText {
            (countdown as NSString).draw(in: NSRect(x: 0, y: 11, width: textWidth, height: 11), withAttributes: top)
            let value = remaining.map { "\(Int(max(0, min(100, $0))))%" } ?? "—"
            (value as NSString).draw(in: NSRect(x: 0, y: 0, width: textWidth, height: 12), withAttributes: [
                .font: font,
                .foregroundColor: remaining == nil ? NSColor.secondaryLabelColor : color,
                .paragraphStyle: alignment
            ])
        }
        if showBars {
            for (index, percentage) in [timeRemaining, remaining].enumerated() {
                let rect = NSRect(x: barsX + CGFloat(index) * 7, y: 2, width: 5, height: 18)
                let outline = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
                color.withAlphaComponent(0.18).setFill()
                outline.fill()
                if let percentage {
                    NSGraphicsContext.saveGraphicsState()
                    outline.addClip()
                    color.setFill()
                    NSBezierPath(rect: NSRect(x: rect.minX, y: rect.minY, width: rect.width,
                        height: rect.height * max(0, min(100, percentage)) / 100)).fill()
                    NSGraphicsContext.restoreGraphicsState()
                }
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
            Image(nsImage: StatusQuotaDrawing.image(style: style, short: 68, weekly: 92, timeRemaining: 86))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
            Text(L10n.text("示例数据")).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
