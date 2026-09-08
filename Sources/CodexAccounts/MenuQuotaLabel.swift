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
            countdown: countdown(selected, now: now)))
            .accessibilityLabel(L10n.isEnglish ? "Remaining quota \(value(selected)); \(countdown(selected, now: now)) until reset" : "剩余额度 \(value(selected))；距重置 \(countdown(selected, now: now))")
            .help(L10n.isEnglish ? "Time remaining / window duration. Short-term \(value(short)) · Weekly \(value(week))" : "距重置剩余时间 / 窗口总时长。短期 \(value(short)) · 每周 \(value(week))")
    }
    private func countdown(_ window: QuotaWindow?, now: Date) -> String {
        guard let window, let minutes = window.windowDurationMins, let reset = window.resetsAt else { return "—" }
        let days = minutes >= 1440
        let divisor = days ? 86400.0 : 3600.0
        let total = Double(minutes) * 60 / divisor
        let left = min(total, max(0, reset - now.timeIntervalSince1970) / divisor)
        let unit = L10n.isEnglish ? (days ? "days" : "hours") : (days ? "天" : "小时")
        return String(format: "%.1f/%.0f %@", locale: Locale(identifier: "en_US_POSIX"), left, total, unit)
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
    static func image(style: String, short: Double?, weekly: Double?, countdown: String = "4.3/5 hours") -> NSImage {
        let remaining = short ?? weekly
        let key = "\(style)|\(String(describing: short))|\(String(describing: weekly))|\(countdown)|\(NSApp.effectiveAppearance.name.rawValue)"
        if let cached = cache[key] { return cached }
        let color = NSColor(srgbRed: 0.40, green: 0.91, blue: 1.0, alpha: 1)
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
        let topAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: remaining == nil ? NSColor.secondaryLabelColor : color
        ]
        let width = max(58, ceil((countdown as NSString).size(withAttributes: topAttributes).width) + 4)
        let image = NSImage(size: NSSize(width: width, height: 22))
        image.lockFocus()
        let center = NSMutableParagraphStyle(); center.alignment = .center
        var top = topAttributes; top[.paragraphStyle] = center
        (countdown as NSString).draw(in: NSRect(x: 0, y: 11, width: width, height: 11), withAttributes: top)
        let value = remaining.map { "\(Int(max(0, min(100, $0))))%" } ?? "—"
        if style != "bars" || remaining == nil {
            (value as NSString).draw(in: NSRect(x: 0, y: style == "both" ? 1 : 0, width: width, height: 12), withAttributes: [
                .font: font,
                .foregroundColor: remaining == nil ? NSColor.secondaryLabelColor : color,
                .paragraphStyle: center
            ])
        }
        if style != "numbers", let remaining {
            let height: CGFloat = style == "bars" ? 5 : 1.5
            let rect = NSRect(x: 4, y: style == "bars" ? 3 : 0, width: width - 8, height: height)
            color.withAlphaComponent(0.22).setFill()
            NSBezierPath(roundedRect: rect, xRadius: height / 2, yRadius: height / 2).fill()
            color.setFill()
            NSBezierPath(roundedRect: NSRect(x: rect.minX, y: rect.minY, width: rect.width * max(0, min(100, remaining)) / 100, height: height), xRadius: height / 2, yRadius: height / 2).fill()
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
