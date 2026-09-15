import Foundation

/// A linear, point-in-time estimate of whether current usage will exhaust
/// before the quota window resets.
public struct UsagePaceEstimate: Sendable {
    public let expectedRemainingPercent: Double
    public let deficitPercent: Double
    public let estimatedSecondsUntilEmpty: TimeInterval?
    public let willLastToReset: Bool

    public init?(
        remainingPercent: Double,
        durationMinutes: Double,
        resetsAt: Date,
        now: Date)
    {
        guard remainingPercent.isFinite, remainingPercent >= 0, remainingPercent <= 100,
              durationMinutes.isFinite, durationMinutes > 0
        else { return nil }

        let duration = durationMinutes * 60
        guard duration.isFinite else { return nil }

        let timeUntilReset = resetsAt.timeIntervalSince(now)
        guard timeUntilReset.isFinite, timeUntilReset > 0, timeUntilReset <= duration else {
            return nil
        }

        let elapsed = duration - timeUntilReset
        guard elapsed > 0 else { return nil }

        let expectedRemaining = (timeUntilReset / duration) * 100
        let deficit = max(0, expectedRemaining - remainingPercent)
        let usedPercent = 100 - remainingPercent

        let estimatedSeconds: TimeInterval?
        if usedPercent > 0 {
            let usageRate = usedPercent / elapsed
            estimatedSeconds = usageRate > 0
                ? remainingPercent / usageRate
                : nil
        } else {
            estimatedSeconds = nil
        }

        self.expectedRemainingPercent = expectedRemaining
        self.deficitPercent = deficit
        self.estimatedSecondsUntilEmpty = estimatedSeconds
        self.willLastToReset = estimatedSeconds.map { $0 >= timeUntilReset } ?? true
    }
}
