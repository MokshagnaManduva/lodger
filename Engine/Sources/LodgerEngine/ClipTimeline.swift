import Foundation

/// The same discrete, duration-based clock used by Core Animation. Reverse legs
/// hold the end frames across the turnaround; finite clips keep their last frame.
public struct ClipTimeline {
    public struct Sample {
        public let index: Int
        public let nextBoundary: TimeInterval?
    }
    private let durations: [Double]
    private let loop: Pack.Loop

    public init(clip: Pack.Clip, defaultFrameMs: Int) {
        durations = clip.durations(default: defaultFrameMs).map { Double($0) / 1000 }
        loop = clip.loop
    }

    /// First boundary that changes the hit result at one fixed pixel. Identical
    /// silhouettes and unchanged runs of frames cost no wakes.
    public func nextChange(at elapsed: TimeInterval, values: [Bool]) -> TimeInterval? {
        guard values.count == durations.count, values.contains(true), values.contains(false) else { return nil }
        let order = Array(durations.indices) + (loop == .pingpong ? Array(durations.indices.reversed()) : [])
        let total = order.reduce(0.0) { $0 + durations[$1] }
        guard total > 0 else { return nil }
        let time = max(0, elapsed)
        if loop == .none && time >= total { return nil }
        let phase = loop == .none ? time : time.truncatingRemainder(dividingBy: total)
        var end = 0.0
        for (position, index) in order.enumerated() {
            end += durations[index]
            guard phase < end else { continue }
            var delay = end - phase
            for step in 1...order.count {
                let next = position + step
                if loop == .none && next >= order.count { return nil }
                let nextIndex = order[next % order.count]
                if values[nextIndex] != values[index] { return max(0.000_001, delay) }
                delay += durations[nextIndex]
            }
            return nil
        }
        return nil
    }

    public func sample(at elapsed: TimeInterval) -> Sample {
        guard durations.count > 1 else { return Sample(index: 0, nextBoundary: nil) }
        let order = Array(durations.indices) + (loop == .pingpong ? Array(durations.indices.reversed()) : [])
        let total = order.reduce(0.0) { $0 + durations[$1] }
        guard total > 0 else { return Sample(index: 0, nextBoundary: nil) }
        let time = max(0, elapsed)
        if loop == .none && time >= total { return Sample(index: durations.count - 1, nextBoundary: nil) }
        let phase = loop == .none ? time : time.truncatingRemainder(dividingBy: total)
        var end = 0.0
        for (position, index) in order.enumerated() {
            end += durations[index]
            if phase < end {
                // Do not wake at a ping-pong turnaround that holds the same frame.
                var boundary = end
                var next = position + 1
                while next < order.count && order[next] == index {
                    boundary += durations[order[next]]
                    next += 1
                }
                if next == order.count {
                    if loop == .none { return Sample(index: index, nextBoundary: nil) }
                    if order[0] == index { boundary += durations[index] }
                }
                return Sample(index: index, nextBoundary: max(0.000_001, boundary - phase))
            }
        }
        return Sample(index: durations.count - 1, nextBoundary: nil)
    }
}
