//
//  WidgetViews.swift
//  SomnaWidgets
//
//  Home screen: small / medium / large, morning (night result) and evening
//  (tonight's plan). Layouts follow design board 21.
//

import SwiftUI
import WidgetKit

struct SomnaWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: SomnaEntry

    var body: some View {
        content
            .widgetURL(entry.link)
            .containerBackground(for: .widget) { background }
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryInline:
            InlineAccessoryView(entry: entry)
        case .accessoryCircular:
            CircularAccessoryView(entry: entry)
        case .accessoryRectangular:
            RectangularAccessoryView(entry: entry)
        case .systemMedium:
            if !entry.hasData { EmptyHomeView(entry: entry) }
            else if let night = entry.night { MediumNightView(entry: entry, night: night) }
            else { MediumPlanView(entry: entry) }
        case .systemLarge:
            if !entry.hasData { EmptyHomeView(entry: entry) }
            else if let night = entry.night { LargeNightView(entry: entry, night: night) }
            else { LargePlanView(entry: entry) }
        default:
            if !entry.hasData { EmptyHomeView(entry: entry) }
            else if let night = entry.night { SmallNightView(entry: entry, night: night) }
            else { SmallPlanView(entry: entry) }
        }
    }

    @ViewBuilder private var background: some View {
        switch family {
        case .accessoryInline, .accessoryCircular, .accessoryRectangular:
            Color.clear
        default:
            if renderingMode == .fullColor {
                LinearGradient(colors: [entry.palette.top, entry.palette.bottom],
                               startPoint: .topTrailing, endPoint: .bottomLeading)
            } else {
                Color.clear
            }
        }
    }
}

// MARK: - Building blocks

struct WidgetHeader: View {
    let entry: SomnaEntry
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(WBrand.orb)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(entry.isStale ? "Откройте Somna" : text)
                .font(WFont.body(13, .medium))
                .foregroundStyle(entry.palette.fg2)
                .lineLimit(1)
        }
    }
}

struct WidgetPill: View {
    let palette: WPalette
    let systemImage: String
    let text: String
    var size: CGFloat = 12

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(palette.accent)
                .widgetAccentable()
            Text(text)
                .font(WFont.body(size, .medium))
                .foregroundStyle(palette.fg)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.soft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct MetricLine: View {
    let palette: WPalette
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(WFont.body(13))
                .foregroundStyle(palette.fg2)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(value)
                .font(WFont.body(13, .semibold))
                .foregroundStyle(palette.fg)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

struct MetricColumn: View {
    let palette: WPalette
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(WFont.body(12))
                .foregroundStyle(palette.fg2)
                .lineLimit(1)
            Text(value)
                .font(WFont.body(15, .semibold))
                .foregroundStyle(palette.fg)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Stage proportions (deep, core, REM, awake), or sleep vs goal without stages.
struct StageBar: View {
    let night: WidgetSnapshot.Night
    let palette: WPalette

    var body: some View {
        GeometryReader { geo in
            if let s = night.stages {
                let parts: [(Int, Color)] = [(s.deep, palette.stageDeep), (s.core, WBrand.stageCore),
                                             (s.rem, WBrand.stageREM), (s.awake, WBrand.stageAwake)].filter { $0.0 > 0 }
                let total = max(1, parts.reduce(0) { $0 + $1.0 })
                let gaps = CGFloat(max(0, parts.count - 1)) * 2
                HStack(spacing: 2) {
                    ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                        Capsule()
                            .fill(part.1)
                            .frame(width: max(3, (geo.size.width - gaps) * CGFloat(part.0) / CGFloat(total)))
                    }
                }
            } else {
                let fraction = min(1, Double(night.asleepMinutes) / Double(max(night.goalMinutes, 1)))
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.line)
                    Capsule()
                        .fill(palette.accent)
                        .frame(width: max(4, geo.size.width * fraction))
                        .widgetAccentable()
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Four rows, top to bottom: awake, REM, core, deep. Neighbouring stages are
/// joined by thin transition lines, like the chart in the app.
struct Hypnogram: View {
    let night: WidgetSnapshot.Night
    let palette: WPalette

    var body: some View {
        let colors: [WidgetSnapshot.Stage: Color] = [
            .awake: WBrand.stageAwake, .rem: WBrand.stageREM, .core: WBrand.stageCore,
            .asleep: WBrand.stageCore.opacity(0.5), .deep: palette.stageDeep,
        ]
        let segments = Self.joined(night)
        let guide = palette.line
        Canvas { context, size in
            Self.draw(in: &context, size: size, segments: segments, colors: colors, guide: guide)
        }
        .accessibilityLabel("Стадии сна за ночь")
    }

    private static func row(_ stage: WidgetSnapshot.Stage) -> Int {
        switch stage {
        case .awake: 0
        case .rem: 1
        case .core, .asleep: 2
        case .deep: 3
        }
    }

    /// Same-stage neighbours merged, gaps up to 10 minutes closed.
    private static func joined(_ night: WidgetSnapshot.Night) -> [WidgetSnapshot.Segment] {
        let total = max(60, night.sleepEnd.timeIntervalSince(night.sleepStart))
        let joinGap = 600 / total
        var result: [WidgetSnapshot.Segment] = []
        for var segment in night.segments.sorted(by: { $0.start < $1.start }) {
            if var last = result.last {
                let gap = segment.start - last.end
                if last.stage == segment.stage && gap <= joinGap {
                    last.end = max(last.end, segment.end)
                    result[result.count - 1] = last
                    continue
                }
                if gap > 0 && gap <= joinGap {
                    last.end = segment.start
                    result[result.count - 1] = last
                } else if gap < 0 {
                    segment.start = last.end
                    guard segment.end > segment.start else { continue }
                }
            }
            result.append(segment)
        }
        return result
    }

    private static func draw(in context: inout GraphicsContext, size: CGSize,
                             segments: [WidgetSnapshot.Segment],
                             colors: [WidgetSnapshot.Stage: Color], guide: Color) {
        let rowHeight = size.height / 4
        let barHeight = rowHeight * 0.66
        func midY(_ stage: WidgetSnapshot.Stage) -> CGFloat { (CGFloat(row(stage)) + 0.5) * rowHeight }
        func color(_ stage: WidgetSnapshot.Stage) -> Color { colors[stage] ?? guide }

        for index in 0..<4 {
            var line = Path()
            let y = (CGFloat(index) + 0.5) * rowHeight
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(line, with: .color(guide), lineWidth: 1)
        }
        func rect(_ segment: WidgetSnapshot.Segment) -> CGRect {
            let left = CGFloat(segment.start) * size.width
            let width = max(3, CGFloat(segment.end - segment.start) * size.width)
            return CGRect(x: min(left, size.width - width), y: midY(segment.stage) - barHeight / 2,
                          width: width, height: barHeight)
        }
        // Soft track like the Health app: halos and ribbons in one translucent layer.
        var soft = context
        soft.opacity = 0.3
        soft.drawLayer { layer in
            for (a, b) in zip(segments, segments.dropFirst()) where row(a.stage) != row(b.stage) {
                guard abs(b.start - a.end) < 0.000_1 else { continue }
                let x = min(max(CGFloat(b.start) * size.width, 1.5), size.width - 1.5)
                let upper = row(a.stage) < row(b.stage) ? a.stage : b.stage
                let lower = upper == a.stage ? b.stage : a.stage
                let band = CGRect(x: x - 1.5, y: midY(upper), width: 3, height: midY(lower) - midY(upper))
                layer.fill(Path(roundedRect: band, cornerRadius: 1.5),
                           with: .linearGradient(Gradient(colors: [color(upper), color(lower)]),
                                                 startPoint: CGPoint(x: x, y: midY(upper)),
                                                 endPoint: CGPoint(x: x, y: midY(lower))))
            }
            for segment in segments {
                let r = rect(segment).insetBy(dx: -1.5, dy: -1.5)
                layer.fill(Path(roundedRect: r, cornerRadius: min(5, r.width / 2)), with: .color(color(segment.stage)))
            }
        }
        for segment in segments {
            let r = rect(segment)
            context.fill(Path(roundedRect: r, cornerRadius: min(4, r.width / 2)), with: .color(color(segment.stage)))
        }
    }
}

struct StepMark: View {
    let status: WidgetSnapshot.StepStatus
    let isCurrent: Bool
    let palette: WPalette

    var body: some View {
        Group {
            switch status {
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .resizable()
                    .foregroundStyle(WBrand.restore)
            case .skipped:
                Image(systemName: "minus.circle")
                    .resizable()
                    .foregroundStyle(palette.fg3)
            case .pending:
                Circle()
                    .strokeBorder(isCurrent ? palette.accent : palette.fg3.opacity(0.6), lineWidth: 1.5)
            }
        }
        .frame(width: 17, height: 17)
        .accessibilityHidden(true)
    }
}

struct StepRow: View {
    let entry: SomnaEntry
    let step: WidgetSnapshot.Step
    var titleSize: CGFloat = 14

    var body: some View {
        let p = entry.palette
        let status = entry.status(of: step)
        let isCurrent = entry.currentStepID == step.id
        HStack(spacing: 10) {
            StepMark(status: status, isCurrent: isCurrent, palette: p)
            Group {
                if let minutes = step.minutes {
                    Text(entry.clock(minutes: minutes))
                        .font(WFont.body(13, .medium))
                        .foregroundStyle(isCurrent ? p.accent : p.fg2)
                } else {
                    Image(systemName: step.systemImage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(p.fg3)
                }
            }
            .frame(width: 40, alignment: .leading)
            Text(step.title)
                .font(WFont.body(titleSize, isCurrent ? .semibold : .regular))
                .foregroundStyle(status == .pending ? p.fg : p.fg3)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Shared texts

extension SomnaEntry {
    var scoreText: String { night?.score.map(String.init) ?? "—" }

    func normText(long: Bool) -> String? {
        guard let n = night, let score = n.score, let norm = n.norm else { return nil }
        let diff = score - norm
        let sign = diff > 0 ? "+\(diff)" : (diff < 0 ? "−\(-diff)" : "±0")
        return long ? "\(sign) к вашей норме (\(norm))" : "\(sign) к норме"
    }

    func normColor(_ p: WPalette) -> Color {
        guard let n = night, let score = n.score, let norm = n.norm, score > norm else { return p.fg2 }
        return WBrand.restore
    }

    var shortfallText: String {
        guard let s = data.shortfall, !s.isPreliminary else { return "—" }
        return s.minutes < 1 ? "0 мин" : "−" + WFormat.duration(s.minutes)
    }

    var recoveryText: String { night?.recovery ?? "—" }

    /// «≈ 7 ч 35 мин сна» or «подъём в 07:25».
    var sleepOutlook: String {
        if let predicted = plan?.predictedSleepMinutes { return "≈ \(WFormat.duration(predicted)) сна" }
        guard let wake else { return "" }
        return "подъём в \(clock(wake))"
    }

    /// «недобор +7 мин» / «по цели» / «запас 20 мин».
    var balanceChange: (text: String, isCaution: Bool)? {
        guard let change = plan?.balanceChangeMinutes else { return nil }
        if change >= 5 { return ("недобор +\(WFormat.duration(change))", true) }
        if change <= -5 { return ("запас \(WFormat.duration(-change))", false) }
        return ("по цели", false)
    }

    var planSentence: String {
        guard let bedtime else { return "Откройте Somna, чтобы собрать план" }
        if let windDown { return "Сегодня: режим в \(clock(windDown)), лечь в \(clock(bedtime))" }
        guard let wake else { return "Сегодня лечь в \(clock(bedtime))" }
        return "Сегодня лечь в \(clock(bedtime)), подъём в \(clock(wake))"
    }

    var alarmText: String {
        guard let plan, let wake else { return "" }
        return plan.alarmEnabled ? "Будильник на \(clock(wake))" : "Будильник выключен"
    }
}

// MARK: - Empty

struct EmptyHomeView: View {
    let entry: SomnaEntry

    var body: some View {
        let p = entry.palette
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(entry: entry, text: "Somna")
            Spacer(minLength: 0)
            Image(systemName: "moon.zzz")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(p.accent)
                .widgetAccentable()
            Text("Откройте Somna")
                .font(WFont.body(15, .semibold))
                .foregroundStyle(p.fg)
            Text("Итог ночи и план на вечер появятся после настройки.")
                .font(WFont.body(12))
                .foregroundStyle(p.fg2)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Small

struct SmallNightView: View {
    let entry: SomnaEntry
    let night: WidgetSnapshot.Night

    var body: some View {
        let p = entry.palette
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(entry: entry, text: "Ночь · \(WFormat.weekdayShort(night.sleepEnd, entry.timeZone))")
            Spacer(minLength: 2)
            Text(night.score.map(String.init) ?? WFormat.hoursMinutes(night.asleepMinutes))
                .font(WFont.display(52))
                .foregroundStyle(p.fg)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .widgetAccentable()
            Text(night.scoreLabel ?? "сна за ночь")
                .font(WFont.body(13))
                .foregroundStyle(p.fg2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 6)
            Text(night.score == nil ? "цель \(WFormat.duration(night.goalMinutes))" : "\(WFormat.duration(night.asleepMinutes)) сна")
                .font(WFont.body(13, .medium))
                .foregroundStyle(p.fg)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            StageBar(night: night, palette: p)
                .frame(height: 5)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct SmallPlanView: View {
    let entry: SomnaEntry

    var body: some View {
        let p = entry.palette
        let past = entry.isPastBedtime
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: past ? "alarm" : "moon")
                    .font(.system(size: 12, weight: .medium))
                Text(entry.isStale ? "Откройте Somna" : (past ? "Пора спать" : "Сегодня лечь"))
                    .font(WFont.body(13, .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(p.fg2)
            Spacer(minLength: 2)
            Text((past ? entry.wake : entry.bedtime).map { entry.clock($0) } ?? "—")
                .font(WFont.display(46))
                .foregroundStyle(p.fg)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .widgetAccentable()
            Text(past ? "подъём" : entry.sleepOutlook)
                .font(WFont.body(13))
                .foregroundStyle(p.fg2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            if past {
                WidgetPill(palette: p, systemImage: "alarm", text: entry.alarmText, size: 11)
            } else if let windDown = entry.windDown {
                WidgetPill(palette: p, systemImage: "iphone.slash", text: "Без экрана с \(entry.clock(windDown))", size: 11)
            } else if let step = entry.steps.first(where: { entry.status(of: $0) == .pending && $0.id != "bedtime" }) {
                WidgetPill(palette: p, systemImage: step.systemImage, text: step.title, size: 11)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Medium

struct MediumNightView: View {
    let entry: SomnaEntry
    let night: WidgetSnapshot.Night

    var body: some View {
        let p = entry.palette
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                WidgetHeader(entry: entry, text: "Ночь · \(WFormat.weekdayShort(night.sleepEnd, entry.timeZone))")
                Spacer(minLength: 2)
                Text(night.score.map(String.init) ?? WFormat.hoursMinutes(night.asleepMinutes))
                    .font(WFont.display(52))
                    .foregroundStyle(p.fg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .widgetAccentable()
                Text(night.scoreLabel ?? "сна за ночь")
                    .font(WFont.body(13))
                    .foregroundStyle(p.fg2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let norm = entry.normText(long: false) {
                    Text(norm)
                        .font(WFont.body(13, .medium))
                        .foregroundStyle(entry.normColor(p))
                        .lineLimit(1)
                }
            }
            .frame(width: 124, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .topLeading)

            Rectangle()
                .fill(p.line)
                .frame(width: 1)
                .padding(.horizontal, 14)

            VStack(alignment: .leading, spacing: 8) {
                MetricLine(palette: p, label: "Сон", value: WFormat.duration(night.asleepMinutes))
                MetricLine(palette: p, label: "Восстановление", value: entry.recoveryText)
                MetricLine(palette: p, label: "Недобор", value: entry.shortfallText)
                Spacer(minLength: 4)
                if let bedtime = entry.bedtime {
                    WidgetPill(palette: p, systemImage: "moon", text: "Сегодня лечь в \(entry.clock(bedtime))")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

struct MediumPlanView: View {
    let entry: SomnaEntry

    var body: some View {
        let p = entry.palette
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.isStale ? "Откройте Somna" : (entry.isPastBedtime ? "Пора спать" : "План на вечер"))
                    .font(WFont.body(15, .semibold))
                    .foregroundStyle(p.fg)
                Spacer()
                if !entry.steps.isEmpty {
                    Text("\(entry.doneCount) из \(entry.steps.count)")
                        .font(WFont.body(13))
                        .foregroundStyle(p.fg2)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(entry.steps.prefix(3)) { step in
                    StepRow(entry: entry, step: step)
                }
            }
            Spacer(minLength: 0)
            PlanFooter(entry: entry)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct PlanFooter: View {
    let entry: SomnaEntry

    var body: some View {
        let p = entry.palette
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(footerText)
                .font(WFont.body(12))
                .foregroundStyle(p.fg2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            if let change = entry.balanceChange {
                Text(change.text)
                    .font(WFont.body(12, .medium))
                    .foregroundStyle(change.isCaution ? WBrand.caution : WBrand.restore)
                    .lineLimit(1)
            }
        }
    }

    private var footerText: String {
        guard let wake = entry.wake else { return "" }
        if let predicted = entry.plan?.predictedSleepMinutes {
            return "≈ \(WFormat.duration(predicted)) сна до \(entry.clock(wake))"
        }
        return entry.plan?.alarmEnabled == true ? "Будильник на \(entry.clock(wake))" : "Подъём в \(entry.clock(wake))"
    }
}

// MARK: - Large

struct LargeNightView: View {
    let entry: SomnaEntry
    let night: WidgetSnapshot.Night

    var body: some View {
        let p = entry.palette
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                WidgetHeader(entry: entry, text: WFormat.longDate(night.sleepEnd, entry.timeZone))
                Spacer(minLength: 6)
                Text(sourceText)
                    .font(WFont.body(12))
                    .foregroundStyle(p.fg3)
                    .lineLimit(1)
            }
            HStack(alignment: .center, spacing: 14) {
                Text(night.score.map(String.init) ?? WFormat.hoursMinutes(night.asleepMinutes))
                    .font(WFont.display(64))
                    .foregroundStyle(p.fg)
                    .lineLimit(1)
                    .widgetAccentable()
                VStack(alignment: .leading, spacing: 3) {
                    Text(night.scoreLabel ?? "сна за ночь")
                        .font(WFont.body(17, .medium))
                        .foregroundStyle(p.fg)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(entry.normText(long: true) ?? "норма появится после 7 ночей")
                        .font(WFont.body(13))
                        .foregroundStyle(p.fg2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            VStack(spacing: 4) {
                if night.segments.isEmpty {
                    StageBar(night: night, palette: p)
                        .frame(height: 8)
                } else {
                    Hypnogram(night: night, palette: p)
                        .frame(height: 64)
                }
                HStack {
                    Text(entry.clock(night.sleepStart))
                    Spacer()
                    Text(entry.clock(night.sleepEnd))
                }
                .font(WFont.body(11))
                .foregroundStyle(p.fg3)
            }
            HStack(alignment: .top, spacing: 10) {
                MetricColumn(palette: p, label: "Сон", value: WFormat.duration(night.asleepMinutes))
                MetricColumn(palette: p, label: "Восстановление", value: entry.recoveryText)
                MetricColumn(palette: p, label: "Недобор", value: entry.shortfallText)
            }
            Spacer(minLength: 0)
            WidgetPill(palette: p, systemImage: "moon", text: entry.planSentence, size: 13)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var sourceText: String {
        let source = night.sourceName ?? "Apple Health"
        guard let synced = night.syncedAt else { return source }
        return "\(source) · \(entry.clock(synced))"
    }
}

struct LargePlanView: View {
    let entry: SomnaEntry

    var body: some View {
        let p = entry.palette
        let past = entry.isPastBedtime
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                WidgetHeader(entry: entry, text: past ? "Пора спать" : "Сегодня вечером")
                Spacer(minLength: 6)
                Text(WFormat.shortDate(entry.eveningStart, entry.timeZone))
                    .font(WFont.body(12))
                    .foregroundStyle(p.fg3)
            }
            HStack(alignment: .center, spacing: 14) {
                Text((past ? entry.wake : entry.bedtime).map { entry.clock($0) } ?? "—")
                    .font(WFont.display(64))
                    .foregroundStyle(p.fg)
                    .lineLimit(1)
                    .widgetAccentable()
                VStack(alignment: .leading, spacing: 3) {
                    Text(past ? "подъём" : "лечь спать")
                        .font(WFont.body(17, .medium))
                        .foregroundStyle(p.fg)
                    Text(past ? entry.alarmText : entry.sleepOutlook)
                        .font(WFont.body(13))
                        .foregroundStyle(p.fg2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            Rectangle()
                .fill(p.line)
                .frame(height: 1)
            HStack(alignment: .firstTextBaseline) {
                Text("План на вечер")
                    .font(WFont.body(15, .semibold))
                    .foregroundStyle(p.fg)
                Spacer()
                if !entry.steps.isEmpty {
                    Text("\(entry.doneCount) из \(entry.steps.count)")
                        .font(WFont.body(13))
                        .foregroundStyle(p.fg2)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                ForEach(entry.steps.prefix(3)) { step in
                    StepRow(entry: entry, step: step, titleSize: 15)
                }
            }
            Spacer(minLength: 0)
            PlanFooter(entry: entry)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
