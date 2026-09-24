//
//  Charts.swift
//  Somna
//
//  Lightweight charts drawn with shapes from real nights: every chart shows
//  its time range, values and the personal baseline where it matters.
//

import SwiftUI
import Foundation

// MARK: - Score vs personal baseline

struct BaselineScale: View {
    @Environment(\.palette) private var p
    let value: Double
    let usualLow: Double
    let usualHigh: Double
    let baseline: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(p.line)
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(p.accentSoft)
                        .frame(width: max(4, w * (usualHigh - usualLow) / 100), height: 14)
                        .offset(x: w * usualLow / 100)
                    Rectangle()
                        .fill(p.accent)
                        .frame(width: 2, height: 18)
                        .offset(x: w * baseline / 100 - 1)
                    Circle()
                        .fill(p.fg)
                        .overlay(Circle().stroke(p.surface, lineWidth: 2))
                        .frame(width: 14, height: 14)
                        .offset(x: w * value / 100 - 7)
                }
                .frame(height: 18)
            }
            .frame(height: 18)

            HStack {
                Text("0")
                Spacer()
                Text("обычно \(Int(usualLow))–\(Int(usualHigh)) · медиана \(Int(baseline))")
                    .foregroundStyle(p.accent)
                Spacer()
                Text("100")
            }
            .font(SomnaFont.body(11, .medium))
            .foregroundStyle(p.fg3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Оценка \(Int(value)) из 100. Ваша медиана \(Int(baseline)), обычно от \(Int(usualLow)) до \(Int(usualHigh)).")
    }
}

// MARK: - Night strip: in bed → asleep → awake marks

struct NightStrip: View {
    @Environment(\.palette) private var p
    let night: SleepNight

    private var start: Date { min(night.inBedStart ?? night.sleepStart, night.sleepStart) }
    private var end: Date { max(night.inBedEnd ?? night.sleepEnd, night.sleepEnd) }
    private var total: Double { max(end.timeIntervalSince(start), 60) }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    if night.inBedStart != nil {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(p.cautionSoft)
                            .frame(width: w, height: 20)
                    }
                    RoundedRectangle(cornerRadius: 4)
                        .fill(p.fg)
                        .frame(width: max(2, w * night.sleepEnd.timeIntervalSince(night.sleepStart) / total), height: 20)
                        .offset(x: w * night.sleepStart.timeIntervalSince(start) / total)
                    ForEach(Array(awakes.enumerated()), id: \.offset) { _, a in
                        Capsule()
                            .fill(Brand.caution)
                            .frame(width: 3, height: 28)
                            .offset(x: w * a.timeIntervalSince(start) / total)
                    }
                }
                .frame(height: 28)
            }
            .frame(height: 28)
            HStack {
                Text(Fmt.time(start, night.timeZone))
                Spacer()
                Text(Fmt.time(end, night.timeZone))
            }
            .font(SomnaFont.body(11))
            .foregroundStyle(p.fg2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Сон с \(Fmt.time(night.sleepStart, night.timeZone)) до \(Fmt.time(night.sleepEnd, night.timeZone)), пробуждений: \(night.awakenings).")
    }

    private var awakes: [Date] {
        night.intervals.filter { $0.stage == .awake }.map(\.start)
    }
}

// MARK: - Hypnogram

struct HypnogramChart: View {
    @Environment(\.palette) private var p
    let night: SleepNight

    private let rowHeight: CGFloat = 52
    private let barHeight: CGFloat = 24

    /// Gaps up to this long between neighbouring stages are closed, longer ones stay visible.
    nonisolated private static let joinGap: TimeInterval = 10 * 60

    private var lanes: [SleepStage] {
        var result: [SleepStage] = [.awake, .rem, .core, .deep]
        if night.stages.unspecified > 0 { result.insert(.asleepUnspecified, at: 1) }
        if !night.stages.hasDetailedStages { result = [.awake, .asleepUnspecified] }
        return result
    }

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = night.timeZone
        return c
    }

    /// Whole hours around the night, like the Health app.
    private var axis: DateInterval {
        let start = calendar.dateInterval(of: .hour, for: night.sleepStart)?.start ?? night.sleepStart
        let end = calendar.dateInterval(of: .hour, for: night.sleepEnd.addingTimeInterval(-1))?.end ?? night.sleepEnd
        return DateInterval(start: start, end: max(end, start.addingTimeInterval(3600)))
    }

    /// Hour marks: every 3 h for a full night, denser for short sleep.
    private var ticks: [Date] {
        let axis = self.axis
        let hours = axis.duration / 3600
        let step = hours > 6 ? 3 : (hours > 3 ? 2 : 1)
        var result: [Date] = []
        var tick = axis.start
        while tick < axis.end {
            result.append(tick)
            guard let next = calendar.date(byAdding: .hour, value: step, to: tick) else { break }
            tick = next
        }
        return result
    }

    /// One continuous path through the night: same-stage neighbours merged,
    /// short unrecorded gaps closed so every block meets the next one.
    private var blocks: [SleepInterval] {
        let shown = Set(lanes)
        let sorted = night.intervals
            .filter { shown.contains($0.stage) && $0.end > night.sleepStart && $0.start < night.sleepEnd }
            .sorted { $0.start < $1.start }
        var result: [SleepInterval] = []
        for var item in sorted {
            item.start = max(item.start, night.sleepStart)
            item.end = min(item.end, night.sleepEnd)
            guard item.end > item.start else { continue }
            if var last = result.last {
                let gap = item.start.timeIntervalSince(last.end)
                if last.stage == item.stage && gap <= Self.joinGap {
                    last.end = max(last.end, item.end)
                    result[result.count - 1] = last
                    continue
                }
                if gap > 0 && gap <= Self.joinGap {
                    last.end = item.start
                    result[result.count - 1] = last
                } else if gap < 0 {
                    item.start = last.end
                    guard item.end > item.start else { continue }
                }
            }
            result.append(item)
        }
        return result
    }

    var body: some View {
        // Everything the canvas needs is captured as plain values.
        let blocks = self.blocks
        let lanes = self.lanes
        let axis = self.axis
        let ticks = self.ticks
        let colors = Dictionary(uniqueKeysWithValues: lanes.map { ($0, $0.color(p)) })
        let grid = p.lineStrong
        let rowHeight = self.rowHeight
        let barHeight = self.barHeight
        let softOpacity = p.isDark ? 0.38 : 0.3
        VStack(alignment: .leading, spacing: 6) {
            Canvas { context, size in
                Self.draw(in: &context, size: size, blocks: blocks, lanes: lanes, colors: colors,
                          axis: axis, ticks: ticks, grid: grid,
                          rowHeight: rowHeight, barHeight: barHeight, softOpacity: softOpacity)
            }
            .frame(height: rowHeight * CGFloat(lanes.count))
            .background(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(lanes, id: \.self) { stage in
                        Text(stage == .awake ? "Бодрствование" : stage.title)
                            .font(SomnaFont.body(12, .medium))
                            .foregroundStyle(p.fg3)
                            .padding(.leading, 8)
                            .padding(.top, 6)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .frame(height: rowHeight)
                    }
                }
            }
            GeometryReader { geo in
                ForEach(Array(ticks.enumerated()), id: \.offset) { _, tick in
                    Text(Fmt.time(tick, night.timeZone))
                        .font(SomnaFont.body(11))
                        .foregroundStyle(p.fg3)
                        .offset(x: geo.size.width * CGFloat(tick.timeIntervalSince(axis.start) / axis.duration) + 4)
                }
            }
            .frame(height: 14)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    nonisolated private static func draw(in context: inout GraphicsContext, size: CGSize,
                                         blocks: [SleepInterval], lanes: [SleepStage],
                                         colors: [SleepStage: Color], axis: DateInterval, ticks: [Date],
                                         grid: Color, rowHeight: CGFloat, barHeight: CGFloat,
                                         softOpacity: Double) {
        let rows = Dictionary(uniqueKeysWithValues: lanes.enumerated().map { ($0.element, $0.offset) })
        let halo: CGFloat = 2
        let ribbon: CGFloat = 4
        func x(_ date: Date) -> CGFloat { size.width * CGFloat(date.timeIntervalSince(axis.start) / axis.duration) }
        func color(_ stage: SleepStage) -> Color { colors[stage] ?? grid }
        /// Blocks sit a little below the row centre, under the row title.
        func midY(_ stage: SleepStage) -> CGFloat { CGFloat(rows[stage] ?? 0) * rowHeight + rowHeight * 0.62 }
        func rect(_ block: SleepInterval) -> CGRect {
            let left = x(block.start)
            let width = max(3, x(block.end) - left)
            return CGRect(x: min(left, size.width - width), y: midY(block.stage) - barHeight / 2,
                          width: width, height: barHeight)
        }

        // Grid: row separators, side borders, dashed hour lines.
        for index in 1...max(1, lanes.count) {
            var line = Path()
            let y = CGFloat(index) * rowHeight - 0.5
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(line, with: .color(grid), lineWidth: 1)
        }
        for edge in [CGFloat(0.5), size.width - 0.5] {
            var line = Path()
            line.move(to: CGPoint(x: edge, y: 0))
            line.addLine(to: CGPoint(x: edge, y: size.height))
            context.stroke(line, with: .color(grid), lineWidth: 1)
        }
        for tick in ticks.dropFirst() {
            var line = Path()
            let tx = x(tick)
            line.move(to: CGPoint(x: tx, y: 0))
            line.addLine(to: CGPoint(x: tx, y: size.height))
            context.stroke(line, with: .color(grid), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }

        // Soft track: halos around blocks and ribbons between them, drawn in one
        // layer so overlaps don't get darker.
        var soft = context
        soft.opacity = softOpacity
        soft.drawLayer { layer in
            for (a, b) in zip(blocks, blocks.dropFirst()) where a.stage != b.stage {
                guard b.start.timeIntervalSince(a.end) <= joinGap else { continue }
                let tx = min(max(x(b.start), ribbon / 2), size.width - ribbon / 2)
                let upper = midY(a.stage) < midY(b.stage) ? a.stage : b.stage
                let lower = upper == a.stage ? b.stage : a.stage
                let top = midY(upper)
                let bottom = midY(lower)
                let band = CGRect(x: tx - ribbon / 2, y: top, width: ribbon, height: bottom - top)
                layer.fill(Path(roundedRect: band, cornerRadius: ribbon / 2),
                           with: .linearGradient(Gradient(colors: [color(upper), color(lower)]),
                                                 startPoint: CGPoint(x: tx, y: top),
                                                 endPoint: CGPoint(x: tx, y: bottom)))
            }
            for block in blocks {
                let r = rect(block).insetBy(dx: -halo, dy: -halo)
                layer.fill(Path(roundedRect: r, cornerRadius: min(9, r.width / 2)), with: .color(color(block.stage)))
            }
        }

        // Solid blocks on top.
        for block in blocks {
            let r = rect(block)
            context.fill(Path(roundedRect: r, cornerRadius: min(6, r.width / 2)), with: .color(color(block.stage)))
        }
    }

    private var accessibilityText: String {
        let s = night.stages
        var parts: [String] = []
        if s.deep > 0 { parts.append("глубокий \(Fmt.duration(s.deep / 60))") }
        if s.rem > 0 { parts.append("REM \(Fmt.duration(s.rem / 60))") }
        if s.core > 0 { parts.append("основной \(Fmt.duration(s.core / 60))") }
        if s.unspecified > 0 { parts.append("без стадий \(Fmt.duration(s.unspecified / 60))") }
        parts.append("бодрствование \(Fmt.duration(night.awake / 60))")
        return "Стадии сна: " + parts.joined(separator: ", ")
    }
}

// MARK: - Heart rate during sleep with the usual band

struct HeartRateChart: View {
    @Environment(\.palette) private var p
    let rate: NightHeartRate
    let timeZone: TimeZone
    var bandLow: Double?
    var bandHigh: Double?

    private var values: [Double] { rate.series.compactMap { $0 } }
    private var minV: Double { floor(min(values.min() ?? rate.minimum, bandLow ?? .infinity, rate.minimum) - 2) }
    private var maxV: Double { ceil(max(values.max() ?? rate.average, bandHigh ?? -.infinity) + 2) }

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                GeometryReader { geo in
                    plot(size: geo.size)
                }
                .frame(height: 112)
                yAxis
                    .frame(width: 22, height: 112)
            }
            if let start = rate.seriesStart {
                HStack {
                    Text(Fmt.time(start, timeZone))
                    Spacer()
                    Text(Fmt.time(start.addingTimeInterval(Double(max(rate.series.count - 1, 0) * NightHeartRate.seriesStepMinutes * 60)), timeZone))
                }
                .font(SomnaFont.body(11))
                .foregroundStyle(p.fg3)
                .padding(.trailing, 28)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Пульс во сне: в среднем \(Int(rate.average.rounded())), минимум \(Int(rate.minimum.rounded())) ударов в минуту.")
    }

    private func y(_ v: Double, _ h: CGFloat) -> CGFloat {
        h * CGFloat((maxV - v) / max(maxV - minV, 1))
    }

    private func plot(size: CGSize) -> some View {
        let series = rate.series
        let count = max(series.count - 1, 1)
        return ZStack(alignment: .topLeading) {
            if let lo = bandLow, let hi = bandHigh {
                Rectangle()
                    .fill(p.accentSoft)
                    .frame(height: max(2, y(lo, size.height) - y(hi, size.height)))
                    .offset(y: y(hi, size.height))
            }
            Path { path in
                var moved = false
                for (i, v) in series.enumerated() {
                    guard let v else { moved = false; continue }
                    let pt = CGPoint(x: size.width * CGFloat(i) / CGFloat(count), y: y(v, size.height))
                    if moved { path.addLine(to: pt) } else { path.move(to: pt); moved = true }
                }
            }
            .stroke(p.fg, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private var yAxis: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                let ticks = [maxV - 2, (maxV + minV) / 2, minV + 2]
                ForEach(ticks.indices, id: \.self) { i in
                    let v = ticks[i]
                    Text("\(Int(v.rounded()))")
                        .font(SomnaFont.body(11))
                        .foregroundStyle(p.fg3)
                        .offset(y: y(v, geo.size.height) - 7)
                }
            }
        }
    }
}

// MARK: - Sleep balance, diverging bars

struct BalanceChart: View {
    @Environment(\.palette) private var p
    let entries: [BalanceEntry]

    private var scale: CGFloat {
        let peak = entries.map { abs($0.differenceMinutes) }.max() ?? 30
        return 60 / CGFloat(max(peak, 30))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                column(entry, isLast: index == entries.count - 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Баланс сна по ночам: \(entries.count) \(CoreFormat.plural(entries.count, "ночь", "ночи", "ночей")).")
    }

    private func column(_ entry: BalanceEntry, isLast: Bool) -> some View {
        // difference = goal − sleep: positive means short.
        let extra = -entry.differenceMinutes
        return VStack(spacing: 0) {
            VStack {
                Spacer(minLength: 0)
                if extra > 0 {
                    UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 1, bottomTrailingRadius: 1, topTrailingRadius: 4)
                        .fill(Brand.restore)
                        .frame(width: 14, height: min(44, CGFloat(extra) * scale))
                }
            }
            .frame(height: 44)
            Rectangle().fill(p.lineStrong).frame(height: 1)
            VStack {
                if extra < 0 {
                    UnevenRoundedRectangle(topLeadingRadius: 1, bottomLeadingRadius: 4, bottomTrailingRadius: 4, topTrailingRadius: 1)
                        .fill(isLast ? p.fg : Brand.caution)
                        .frame(width: 14, height: min(66, CGFloat(-extra) * scale))
                }
                Spacer(minLength: 0)
            }
            .frame(height: 66)
            Text(Fmt.dayNumber(entry.dayKey))
                .font(SomnaFont.body(11, isLast ? .semibold : .medium))
                .foregroundStyle(isLast ? p.fg : p.fg2)
            Text(Fmt.weekdayShort(entry.dayKey))
                .font(SomnaFont.body(10))
                .foregroundStyle(Fmt.isWeekend(entry.dayKey) ? p.accent : p.fg3)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Regularity: sleep onset → wake per night

struct RegularityChart: View {
    @Environment(\.palette) private var p
    let nights: [SleepNight]
    var medianBedtime: Double?
    var medianWake: Double?

    /// Visible window on the noon-to-noon scale, rounded to whole hours.
    private var window: (lo: Double, hi: Double) {
        let beds = nights.map(\.bedtimeScale)
        let wakes = nights.map { $0.wakeScale + 720 }
        let lo = ((beds.min() ?? 600) / 60).rounded(.down) * 60
        let hi = ((wakes.max() ?? 1140) / 60).rounded(.up) * 60
        return (lo, max(hi, lo + 360))
    }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                chart(size: geo.size)
            }
            .frame(height: 200)
            HStack(spacing: 0) {
                Color.clear.frame(width: 40, height: 1)
                ForEach(Array(nights.enumerated()), id: \.offset) { _, n in
                    Text(Fmt.weekdayShort(n.dayKey))
                        .font(SomnaFont.body(9))
                        .foregroundStyle(Fmt.isWeekend(n.dayKey) ? Brand.lilac : p.fg3)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard let b = medianBedtime, let w = medianWake else { return "Время сна по ночам" }
        return "Обычно засыпаете около \(Fmt.clock(ClockTime.minutesOfDay(fromBedtimeScale: b))) и просыпаетесь около \(Fmt.clock(w))."
    }

    private func chart(size: CGSize) -> some View {
        let (lo, hi) = window
        let span = hi - lo
        let plotW = size.width - 40
        let colW = plotW / CGFloat(max(nights.count, 1))
        let yOf: (Double) -> CGFloat = { v in size.height * CGFloat((v - lo) / span) }
        let step = span > 720 ? 240.0 : 120.0
        let marks = stride(from: lo, through: hi, by: step).map { $0 }
        return ZStack(alignment: .topLeading) {
            ForEach(marks, id: \.self) { m in
                Rectangle()
                    .fill(p.line)
                    .frame(width: plotW, height: 1)
                    .offset(x: 40, y: yOf(m))
                Text(Fmt.clock(ClockTime.minutesOfDay(fromBedtimeScale: m)))
                    .font(SomnaFont.body(10))
                    .foregroundStyle(p.fg3)
                    .offset(y: max(0, yOf(m) - 7))
            }
            if let b = medianBedtime, let w = medianWake {
                Rectangle()
                    .fill(p.accentSoft)
                    .frame(width: plotW, height: max(2, yOf(w + 720) - yOf(b)))
                    .offset(x: 40, y: yOf(b))
            }
            ForEach(Array(nights.enumerated()), id: \.offset) { index, n in
                let top = yOf(n.bedtimeScale)
                let bottom = yOf(n.wakeScale + 720)
                Capsule()
                    .fill(Fmt.isWeekend(n.dayKey) ? Brand.lilac : p.fg)
                    .frame(width: 10, height: max(10, bottom - top))
                    .offset(x: 40 + CGFloat(index) * colW + colW / 2 - 5, y: top)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}

// MARK: - Sparkline with norm band

struct Sparkline: View {
    @Environment(\.palette) private var p
    let values: [Double]
    let normLow: Double
    let normHigh: Double
    var color: Color?

    var body: some View {
        GeometryReader { geo in
            let lo = min(values.min() ?? 0, normLow)
            let hi = max(values.max() ?? 1, normHigh)
            let h = geo.size.height
            let w = geo.size.width
            let yOf: (Double) -> CGFloat = { v in (1 - CGFloat((v - lo) / max(hi - lo, 0.0001))) * (h - 4) + 2 }
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(p.accentSoft)
                    .frame(height: max(2, yOf(normLow) - yOf(normHigh)))
                    .offset(y: yOf(normHigh))
                Path { path in
                    for i in values.indices {
                        let pt = CGPoint(x: w * CGFloat(i) / CGFloat(max(values.count - 1, 1)), y: yOf(values[i]))
                        if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                    }
                }
                .stroke(color ?? p.fg, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: 72, height: 28)
        .accessibilityHidden(true)
    }
}

// MARK: - Comparison bar

struct ComparisonBar: View {
    @Environment(\.palette) private var p
    let label: String
    let value: String
    let fraction: Double
    let color: Color
    var height: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(SomnaFont.body(13))
                    .foregroundStyle(p.fg2)
                Spacer()
                Text(value)
                    .font(SomnaFont.body(13, .semibold))
                    .foregroundStyle(p.fg)
            }
            ProgressTrack(fraction: fraction, fill: color, height: height)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Likely range (forecast)

struct LikelyRange: View {
    @Environment(\.palette) private var p
    let low: Double
    let high: Double
    let point: Double
    var minV: Double = 50
    var maxV: Double = 100

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let x: (Double) -> CGFloat = { v in w * CGFloat((v - minV) / (maxV - minV)) }
            ZStack(alignment: .leading) {
                Capsule().fill(p.line).frame(height: 4)
                Capsule().fill(p.accentSoft).frame(width: x(high) - x(low), height: 8).offset(x: x(low))
                Circle().fill(p.accent).frame(width: 10, height: 10).offset(x: x(point) - 5)
            }
            .frame(height: 12)
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }
}

// MARK: - Sleep cycle curve (welcome)

struct SleepCycleCurve: View {
    @Environment(\.palette) private var p

    private let depths: [CGFloat] = [3, 2.8, 2.2, 1.9, 1.5]

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geo in
                curve(size: geo.size)
            }
            .frame(height: 176)
            HStack {
                Text("23:20").font(SomnaFont.body(12, .semibold)).foregroundStyle(p.fg2)
                Spacer()
                Text("5 циклов по ~90 мин").font(SomnaFont.body(12)).foregroundStyle(p.fg3)
                Spacer()
                Text("07:10").font(SomnaFont.body(12, .semibold)).foregroundStyle(p.fg2)
            }
            .padding(.leading, 60)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ночь из пяти циклов по 90 минут: к утру сон становится легче.")
    }

    private func curve(size: CGSize) -> some View {
        let top: CGFloat = 12
        let lane = (size.height - 24) / 3
        let x0: CGFloat = 60
        let cw = (size.width - x0 - 20) / 5
        let yOf: (CGFloat) -> CGFloat = { level in top + level * lane }
        let xEnd = x0 + 5 * cw
        return ZStack(alignment: .topLeading) {
            ForEach(0..<4, id: \.self) { i in
                Rectangle()
                    .fill(p.line)
                    .frame(width: size.width, height: 1)
                    .offset(y: yOf(CGFloat(i)))
                Text(["Бодрств.", "REM", "Основной", "Глубокий"][i])
                    .font(SomnaFont.body(10, .medium))
                    .foregroundStyle(p.fg3)
                    .offset(y: yOf(CGFloat(i)) + 4)
            }
            Path { path in
                path.move(to: CGPoint(x: x0, y: yOf(0.1)))
                for i in 0..<5 {
                    let xs = x0 + CGFloat(i) * cw
                    let xm = xs + cw * 0.45
                    let xe = xs + cw
                    let d = depths[i]
                    path.addCurve(to: CGPoint(x: xm, y: yOf(d)),
                                  control1: CGPoint(x: xs + cw * 0.2, y: yOf(i == 0 ? 0.1 : 1)),
                                  control2: CGPoint(x: xm - cw * 0.22, y: yOf(d)))
                    path.addCurve(to: CGPoint(x: xe, y: yOf(1)),
                                  control1: CGPoint(x: xm + cw * 0.22, y: yOf(d)),
                                  control2: CGPoint(x: xe - cw * 0.2, y: yOf(1)))
                }
                path.addCurve(to: CGPoint(x: xEnd + 14, y: yOf(0)),
                              control1: CGPoint(x: xEnd + 6, y: yOf(1)),
                              control2: CGPoint(x: xEnd + 8, y: yOf(0.15)))
            }
            .stroke(p.fg, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            ForEach(1..<5, id: \.self) { i in
                Circle()
                    .fill(p.surface)
                    .overlay(Circle().stroke(p.fg, lineWidth: 1.5))
                    .frame(width: 7, height: 7)
                    .offset(x: x0 + CGFloat(i) * cw - 3.5, y: yOf(1) - 3.5)
            }
            Circle()
                .fill(Brand.dawnGradient)
                .frame(width: 22, height: 22)
                .offset(x: xEnd + 14 - 11, y: yOf(0) - 11)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}

// MARK: - Wake window (alarm)

struct WakeWindowBar: View {
    @Environment(\.palette) private var p
    let latest: Int
    let window: Int

    private var start: Int { (latest - 60) / 30 * 30 }
    private let span = 90

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                let x: (Int) -> CGFloat = { m in w * CGFloat(m - start) / CGFloat(span) }
                ZStack(alignment: .leading) {
                    Capsule().fill(p.line).frame(height: 10)
                    if window > 0 {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Brand.dawnGradient)
                            .frame(width: max(8, x(latest) - x(latest - window)), height: 22)
                            .offset(x: x(latest - window))
                    }
                    Rectangle()
                        .fill(p.fg)
                        .frame(width: 2, height: 34)
                        .offset(x: x(latest) - 1)
                }
                .frame(height: 34)
            }
            .frame(height: 34)
            HStack {
                Text(Fmt.clock(start))
                Spacer()
                Text(Fmt.clock(start + 30))
                Spacer()
                Text(Fmt.clock(start + 60))
                Spacer()
                Text(Fmt.clock(start + 90))
            }
            .font(SomnaFont.body(11))
            .foregroundStyle(p.fg2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Будильник в \(Fmt.clock(latest)).")
    }
}

// MARK: - Interactive bedtime slider

/// Time in bed tonight. The soft band marks bedtimes that meet the sleep goal
/// for the chosen wake time; the pink tick is last night's actual bedtime.
struct BedtimeSlider: View {
    @Environment(\.palette) private var p
    @Binding var minutes: Int
    let lower: Int
    let upper: Int
    var goodLow: Int?
    var goodHigh: Int?
    var lastNight: Int?

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(p.line).frame(height: 6)
                    if let lo = goodLow, let hi = goodHigh, hi > lo {
                        Capsule()
                            .fill(p.restoreSoft)
                            .frame(width: max(6, x(min(hi, upper), w) - x(max(lo, lower), w)), height: 14)
                            .offset(x: x(max(lo, lower), w))
                    }
                    if let last = lastNight, last >= lower, last <= upper {
                        Capsule()
                            .fill(Brand.caution)
                            .frame(width: 2, height: 18)
                            .offset(x: x(last, w) - 1)
                    }
                    Circle()
                        .fill(p.fg)
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                        .frame(width: 28, height: 28)
                        .offset(x: x(minutes, w) - 14)
                }
                .frame(height: 32)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let ratio = min(max(value.location.x / max(w, 1), 0), 1)
                            let raw = Double(lower) + ratio * Double(upper - lower)
                            let snapped = Int((raw / 5).rounded()) * 5
                            if snapped != minutes { minutes = snapped }
                        }
                )
            }
            .frame(height: 32)
            HStack {
                ForEach(Array(ticks.enumerated()), id: \.offset) { i, t in
                    if i > 0 { Spacer() }
                    Text(Fmt.clock(t))
                }
            }
            .font(SomnaFont.body(11))
            .foregroundStyle(p.fg3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Время отхода ко сну")
        .accessibilityValue(Fmt.clock(minutes))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: minutes = min(upper, minutes + 5)
            case .decrement: minutes = max(lower, minutes - 5)
            @unknown default: break
            }
        }
        .haptic(.selection, trigger: minutes)
        .haptic(Haptic.soft, trigger: isGood) { _, entered in entered }
    }

    private var ticks: [Int] {
        let step = (upper - lower) / 4
        return (0...4).map { lower + $0 * step }
    }

    /// Crossing into the band that meets the goal gets its own soft pulse.
    private var isGood: Bool {
        guard let lo = goodLow, let hi = goodHigh else { return false }
        return minutes >= lo && minutes <= hi
    }

    private func x(_ m: Int, _ w: CGFloat) -> CGFloat {
        w * CGFloat(m - lower) / CGFloat(max(upper - lower, 1))
    }
}

// MARK: - Experiment days

struct ExperimentDays: View {
    @Environment(\.palette) private var p
    let total: Int
    let today: Int
    let missed: Set<Int>

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...total, id: \.self) { day in
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(fill(for: day))
                    .overlay {
                        if day == today {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(p.accent, lineWidth: 1.5)
                        }
                    }
                    .frame(height: 28)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("День \(today) из \(total). Пропущено дней: \(missed.count).")
    }

    private func fill(for day: Int) -> Color {
        if day == today { return p.accentSoft }
        if day > today { return p.line }
        return missed.contains(day) ? p.cautionSoft : Brand.restore
    }
}

// MARK: - Breathing circle (bedtime)

/// 4–6 breathing: 4 s inhale (circle grows), 6 s exhale (circle shrinks).
/// A very soft haptic marks each phase, so the guide works with eyes closed
/// and with Reduce Motion on (then only the haptics lead the rhythm).
struct BreathingCircle: View {
    @Environment(\.palette) private var p
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let active: Bool
    @State private var expanded = false
    @State private var phase = 0

    init(active: Bool) {
        self.active = active
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(p.lineStrong, lineWidth: 1.5)
            Circle()
                .fill(active ? p.accentSoft : p.lineStrong)
                .scaleEffect(expanded ? 0.86 : 0.42)
        }
        .frame(width: 52, height: 52)
        .haptic(Haptic.breath, trigger: phase) { _, _ in active }
        .task(id: active) {
            await breathe()
        }
        .accessibilityHidden(true)
    }

    private func breathe() async {
        guard active else {
            withAnimation(.easeOut(duration: 0.3)) { expanded = false }
            return
        }
        while !Task.isCancelled {
            phase += 1
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 4)) { expanded = true }
            try? await Task.sleep(for: .seconds(4))
            if Task.isCancelled { break }
            phase += 1
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 6)) { expanded = false }
            try? await Task.sleep(for: .seconds(6))
        }
    }
}
