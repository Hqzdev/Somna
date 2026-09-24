//
//  Stats.swift
//  SomnaCore
//
//  Small, dependency-free statistics used by the v1 formulas.
//

import Foundation

nonisolated enum Stats {
    static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(max(value, lower), upper)
    }

    static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let s = values.sorted()
        let mid = s.count / 2
        return s.count % 2 == 0 ? (s[mid - 1] + s[mid]) / 2 : s[mid]
    }

    /// Mean absolute deviation from the median — used for regularity (R).
    static func meanAbsoluteDeviationFromMedian(_ values: [Double]) -> Double? {
        guard let m = median(values) else { return nil }
        return mean(values.map { abs($0 - m) })
    }

    /// Median absolute deviation — used for robust baselines.
    static func medianAbsoluteDeviation(_ values: [Double]) -> Double? {
        guard let m = median(values) else { return nil }
        return median(values.map { abs($0 - m) })
    }

    /// Linear-interpolated quantile, q in 0...1.
    static func quantile(_ values: [Double], _ q: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let s = values.sorted()
        if s.count == 1 { return s[0] }
        let pos = clamp(q, 0, 1) * Double(s.count - 1)
        let lo = Int(pos.rounded(.down))
        let hi = min(lo + 1, s.count - 1)
        let frac = pos - Double(lo)
        return s[lo] + (s[hi] - s[lo]) * frac
    }

    /// Weighted average over the components that exist; weights of missing
    /// components are dropped and the rest renormalized.
    /// Returns nil when fewer than `minimumComponents` are present.
    static func renormalizedAverage(_ components: [(value: Double?, weight: Double)],
                                    minimumComponents: Int) -> Double? {
        let present = components.compactMap { c -> (Double, Double)? in
            guard let v = c.value else { return nil }
            return (v, c.weight)
        }
        guard present.count >= minimumComponents else { return nil }
        let totalWeight = present.reduce(0) { $0 + $1.1 }
        guard totalWeight > 0 else { return nil }
        return present.reduce(0) { $0 + $1.0 * $1.1 } / totalWeight
    }

    /// Bootstrap interval of `median(a) − median(b)` with a fixed seed, so the
    /// same data always gives the same interval.
    static func bootstrapMedianDifference(_ a: [Double], _ b: [Double],
                                          resamples: Int = 600,
                                          coverage: Double = 0.8,
                                          seed: UInt64) -> (low: Double, high: Double)? {
        guard !a.isEmpty, !b.isEmpty, resamples > 10 else { return nil }
        var rng = SplitMix64(seed: seed)
        var diffs: [Double] = []
        diffs.reserveCapacity(resamples)
        for _ in 0..<resamples {
            let ra = (0..<a.count).map { _ in a[rng.nextInt(below: a.count)] }
            let rb = (0..<b.count).map { _ in b[rng.nextInt(below: b.count)] }
            if let ma = median(ra), let mb = median(rb) {
                diffs.append(ma - mb)
            }
        }
        let tail = (1 - coverage) / 2
        guard let low = quantile(diffs, tail), let high = quantile(diffs, 1 - tail) else { return nil }
        return (low, high)
    }

    static func bootstrapMedian(_ values: [Double], resamples: Int = 600,
                                seed: UInt64) -> (low: Double, high: Double)? {
        guard !values.isEmpty else { return nil }
        var rng = SplitMix64(seed: seed)
        var medians: [Double] = []
        for _ in 0..<resamples {
            let draw = (0..<values.count).map { _ in values[rng.nextInt(below: values.count)] }
            if let m = median(draw) { medians.append(m) }
        }
        guard let low = quantile(medians, 0.10), let high = quantile(medians, 0.90) else { return nil }
        return (low, high)
    }

    /// Exact two-sided sign test for paired nonzero differences.
    static func signTestTwoSided(_ differences: [Double]) -> Double? {
        let nonzero = differences.filter { abs($0) > 1e-9 }
        guard nonzero.count >= 8 else { return nil }
        let k = min(nonzero.filter { $0 > 0 }.count, nonzero.filter { $0 < 0 }.count)
        var combination = 1.0
        var sum = 1.0
        if k > 0 {
            for i in 1...k {
                combination *= Double(nonzero.count - i + 1) / Double(i)
                sum += combination
            }
        }
        return min(1, 2 * sum / pow(2, Double(nonzero.count)))
    }

    /// Stable 64-bit FNV-1a hash (Swift's `hashValue` changes between launches).
    static func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}

/// Deterministic pseudo-random generator for bootstrap intervals.
nonisolated struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func nextInt(below upper: Int) -> Int {
        guard upper > 0 else { return 0 }
        return Int(next() % UInt64(upper))
    }
}
