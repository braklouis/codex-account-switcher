import Foundation

public struct AlertThresholds: Codable {
    public var notified: Set<Int> = []
    public var reset: Double?
    public var previous: Double?
    public init() {}
    public mutating func evaluate(remaining: Double, resetsAt: Double?) -> Int? {
        if reset != resetsAt || (resetsAt == nil && remaining > (previous ?? 100) + 10) {
            notified = []
        }
        reset = resetsAt
        previous = remaining
        let crossed = [75, 50, 25].filter { remaining < Double($0) && !notified.contains($0) }
        // A large jump produces one notification for the lowest crossed threshold.
        for value in crossed { notified.insert(value) }
        return crossed.min()
    }
}
