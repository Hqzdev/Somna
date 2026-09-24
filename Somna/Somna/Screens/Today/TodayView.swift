//
//  TodayView.swift
//  Somna
//
//  03 «Сегодня»: the morning answer in under 10 seconds — outcome, likely
//  reason, one best action — from the computed snapshot. Honest states when
//  Health is not connected or there are no nights yet.
//

import SwiftUI
import Foundation

struct TodayView: View {
    @Environment(AppState.self) private var state
    @Environment(SomnaStore.self) private var store

    var body: some View {
        let mode = state.timeOfDay
        let snapshot = store.snapshot
        SomnaScreen(mode: mode, spacing: 20) {
            header(mode: mode, snapshot: snapshot)
            banners
            if let latest = snapshot.latest {
                OutcomeCard(report: latest, snapshot: snapshot, lastSync: store.lastSync) {
                    state.selectedNight = latest.dayKey
                    state.go(to: .sleep)
                }
            } else {
                noNightCard(snapshot)
            }
            TodayActionCard(mode: mode, plan: snapshot.plan)
            summary(snapshot)
        }
        .refreshable { await store.refreshHealth() }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func header(mode: TimeOfDay, snapshot: SomnaSnapshot) -> some View {
        let p = mode.palette
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: sunSymbol(mode))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Brand.sunrise)
                Text(mode == .dawn ? Fmt.dayTitle(snapshot.today) : "\(Fmt.dayTitle(snapshot.today)) · вечер впереди")
                    .font(SomnaFont.body(13, .medium))
                    .foregroundStyle(p.fg2)
            }
            Text(greeting(mode))
                .displayStyle(30, tracking: -1)
                .foregroundStyle(p.fg)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private func sunSymbol(_ mode: TimeOfDay) -> String {
        switch mode {
        case .dawn: "sunrise"
        case .sunset: "sunset"
        case .dusk, .night: "moon.stars"
        }
    }

    /// Greeting with the name from the questionnaire; without it if skipped.
    private func greeting(_ mode: TimeOfDay) -> String {
        let base: String = switch mode {
        case .dawn: "Доброе утро"
        case .sunset: "Добрый день"
        case .dusk, .night: "Добрый вечер"
        }
        guard let name = store.profile.displayName else { return base }
        return "\(base), \(name)"
    }

    @ViewBuilder
    private var banners: some View {
        if case .failed(let message) = store.sync {
            NoticeBanner(icon: "exclamationmark.arrow.triangle.2.circlepath", title: "Данные не обновились",
                         text: message, action: "Повторить") {
                Task { await store.refreshHealth() }
            }
        } else if store.healthAvailable && !store.healthRequested && !store.usesDemoData {
            NoticeBanner(icon: "heart.text.square", title: "Apple Health не подключено",
                         text: "Без него Somna не видит ночи. Доступ только на чтение.", action: "Подключить") {
                Task { await store.connectHealth() }
            }
        } else if store.sync == .syncing && store.snapshot.reports.isEmpty {
            NoticeBanner(icon: "arrow.triangle.2.circlepath", title: "Читаем данные из Здоровья",
                         text: "Собираем ночи за последние 120 дней.", action: nil) {}
        }
    }

    @ViewBuilder
    private func noNightCard(_ snapshot: SomnaSnapshot) -> some View {
        if let last = snapshot.lastRecorded {
            StateBlock(icon: "moon.zzz", state: .neutral,
                       title: "Прошлой ночи нет в Здоровье",
                       what: "Последняя записанная ночь — \(Fmt.dayMonth(last.dayKey)). Возможно, часы были сняты или разрядились.",
                       available: "Баланс сна и план на вечер считаются по записанным ночам",
                       actionTitle: "Открыть последнюю ночь", actionIcon: "chevron.right") {
                state.selectedNight = last.dayKey
                state.go(to: .sleep)
            }
        } else if store.healthRequested || store.usesDemoData {
            StateBlock(icon: "moon.zzz", state: .neutral,
                       title: "Ночей пока нет",
                       what: "Первая ночь появится утром после сна с Apple Watch или с режимом «Сон» на iPhone. Если доступ к сну выключен, его можно включить в Настройках → Здоровье → Доступ к данным.",
                       available: "Журнал, утренние отметки и план на вечер работают уже сейчас")
        }
    }

    private func summary(_ snapshot: SomnaSnapshot) -> some View {
        GroupedList {
            recoveryRow(snapshot)
            if let balance = snapshot.balance {
                MetricRow(state: balance.hasCoverage ? (balance.deficitMinutes > 30 ? .caution : .restore) : .neutral, label: "Недобор к цели",
                          sub: balance.isPreliminary
                              ? "Нужно 10 из 14 дней · сейчас \(Fmt.nights(balance.nights))"
                              : "14 календарных дней · без вычета длинных ночей",
                          value: balance.text) {
                    state.push(.sleepDebt)
                }
            } else {
                MetricRow(state: .neutral, label: "Недобор к цели", sub: "Появится после 10 дней с данными", value: "—") {
                    state.push(.sleepDebt)
                }
            }
            if let r = snapshot.regularity {
                MetricRow(state: Signal.regularity(r.score), label: "Регулярность",
                          sub: "Время сна плавает \(r.spreadText)", value: r.scoreText) {
                    state.push(.circadian)
                }
            } else {
                MetricRow(state: .neutral, label: "Регулярность",
                          sub: snapshot.regularityNightsMissing > 0
                              ? "Посчитается через \(Fmt.nights(snapshot.regularityNightsMissing))"
                              : "Не считается при сменном графике",
                          value: "—") {
                    state.push(.circadian)
                }
            }
            checkInRow(snapshot)
        }
    }

    @ViewBuilder
    private func recoveryRow(_ snapshot: SomnaSnapshot) -> some View {
        if let recovery = snapshot.latest?.recovery {
            MetricRow(state: recovery.status == .lowerThanUsual ? .caution : .neutral, label: "Восстановление",
                      sub: recoverySub(recovery), value: recovery.status == .insufficient ? "—" : "Открыть") {
                state.push(.healthSignals)
            }
        } else {
            MetricRow(state: .neutral, label: "Восстановление",
                      sub: "Сон и измерения сравниваются с вашей нормой", value: "—") {
                state.push(.healthSignals)
            }
        }
    }

    private func recoverySub(_ r: RecoveryReport) -> String {
        var parts: [String] = ["сон"]
        if r.hrvDeviation != nil { parts.append("ВСР") }
        if r.rhrDeviation != nil { parts.append("пульс в покое") }
        return r.status.title + " · " + parts.joined(separator: ", ")
    }

    @ViewBuilder
    private func checkInRow(_ snapshot: SomnaSnapshot) -> some View {
        let day = snapshot.latest?.dayKey ?? snapshot.today
        if let checkIn = store.checkIn(for: day) {
            MetricRow(state: .restore, label: "Утреннее самочувствие", sub: "Отмечено · можно изменить",
                      value: "\(CheckInSheet.labels[checkIn.energy - 1]) · \(checkIn.energy)", showDivider: false) {
                state.sheet = .checkIn
            }
        } else {
            MetricRow(state: .data, label: "Утреннее самочувствие", sub: "Займёт 10 секунд",
                      value: "Отметить", valueColor: state.timeOfDay.palette.accent, showDivider: false) {
                state.sheet = .checkIn
            }
        }
    }
}

// MARK: - Outcome

private struct OutcomeCard: View {
    @Environment(\.palette) private var p
    let report: NightReport
    let snapshot: SomnaSnapshot
    let lastSync: Date?
    let onReview: () -> Void

    var body: some View {
        let goal = snapshot.settings.goalMinutes
        let asleep = report.night.asleepMinutes
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Оценка сна")
                        .font(SomnaFont.body(13, .medium))
                        .foregroundStyle(p.fg2)
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(report.score.map { "\($0.value)" } ?? "—")
                            .font(SomnaFont.display(76, relativeTo: .largeTitle))
                            .tracking(-3.4)
                        Text("/100")
                            .displayStyle(20, tracking: -0.5)
                            .foregroundStyle(p.fg3)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 8) {
                    if let score = report.score {
                        StatusTag(text: score.label, state: score.signal)
                    }
                    if let note = baselineNote {
                        Text(note)
                            .font(SomnaFont.body(12, .medium))
                            .foregroundStyle(p.fg2)
                            .multilineTextAlignment(.trailing)
                    }
                }
                .padding(.bottom, 8)
            }
            .accessibilityElement(children: .combine)

            Text(report.explanation ?? "Оценка появится при надёжных данных о длительности, непрерывности и режиме.")
                .displayStyle(21, tracking: -0.5)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .lastTextBaseline) {
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text(Fmt.duration(asleep))
                            .font(SomnaFont.body(17, .semibold))
                        Text("сна")
                            .font(SomnaFont.body(14))
                            .foregroundStyle(p.fg2)
                    }
                    Spacer()
                    Text("цель \(Fmt.duration(goal))")
                        .font(SomnaFont.body(13, .medium))
                        .foregroundStyle(p.fg2)
                }
                ProgressTrack(fraction: asleep / Double(max(goal, 1)))
                Text(gapNote(asleep: asleep, goal: goal))
                    .font(SomnaFont.body(12))
                    .foregroundStyle(p.fg2)
            }
            .accessibilityElement(children: .combine)

            HStack {
                SourceLabel(icon: report.night.stages.hasDetailedStages ? "applewatch" : "iphone", text: sourceText)
                Spacer()
                TextLink(title: "Разбор ночи", action: onReview)
            }
            .padding(.top, 2)
            .overlay(alignment: .top) {
                Divider1().offset(y: -10)
            }
        }
        .card(padding: 24, radius: Radius.hero)
    }

    /// Compared with the median score of the previous 30 nights.
    private var baselineNote: String? {
        guard let value = report.score?.value else { return nil }
        let previous = snapshot.reports.filter { $0.dayKey < report.dayKey }.suffix(30).compactMap { $0.score?.value }
        guard previous.count >= 7, let median = Stats.median(previous.map(Double.init)) else {
            return "личная норма — через \(Fmt.nights(7 - previous.count))"
        }
        let diff = value - Int(median.rounded())
        let sign = diff > 0 ? "+\(diff)" : (diff < 0 ? "−\(-diff)" : "±0")
        return "\(sign) к вашей медиане (\(Int(median.rounded())))"
    }

    private func gapNote(asleep: Double, goal: Int) -> String {
        let gap = Double(goal) - asleep
        if gap >= 5 { return "Не хватило \(Fmt.duration(gap)) — это учтено в плане на вечер" }
        if gap <= -5 { return "На \(Fmt.duration(-gap)) больше цели" }
        return "Почти ровно ваша цель"
    }

    private var sourceText: String {
        let names = report.night.sourceIDs.compactMap { id in snapshot.sources.first { $0.id == id }?.name }
        let source = names.isEmpty ? "Apple Health" : names.joined(separator: " + ")
        guard let lastSync else { return source }
        return "\(source) · \(Fmt.relative(lastSync))"
    }
}

// MARK: - The one action (rendered in the night palette — it belongs to the evening)

private struct TodayActionCard: View {
    @Environment(AppState.self) private var state
    let mode: TimeOfDay
    let plan: RecoveryPlan
    private let night = Palette.night

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Overline(icon: overlineIcon, text: overline)
            Text(action?.title ?? "Лечь в кровать в \(Fmt.clock(plan.bedtimeMinutes))")
                .displayStyle(27, tracking: -0.9)
                .foregroundStyle(night.fg)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(action?.reason ?? "Чтобы выспаться к \(Fmt.clock(plan.wakeMinutes)).")
                .font(SomnaFont.body(14))
                .foregroundStyle(night.fg2)
                .fixedSize(horizontal: false, vertical: true)
            if let source = action?.source {
                SourceLabel(icon: "info.circle", text: source)
            }
            PrimaryButton(title: mode == .night ? "Открыть план на вечер" : "План на вечер", systemImage: "arrow.right") {
                state.go(to: .plan)
                if mode == .night {
                    state.planPath = [.eveningPlan]
                }
            }
        }
        .environment(\.palette, night)
        .card(padding: 24, radius: Radius.hero, fill: night.surface)
    }

    /// Morning: the top-ranked action; later in the day, the next timed one.
    private var action: PlanAction? {
        switch mode {
        case .dawn: plan.actions.first
        default: plan.actions.first { $0.minutes != nil } ?? plan.actions.first
        }
    }

    private var overline: String {
        switch mode {
        case .dawn: "Главное действие"
        case .sunset, .dusk: "На вечер"
        case .night: "Вечер"
        }
    }

    private var overlineIcon: String {
        mode == .dawn ? "moon.stars" : "moon"
    }
}

// MARK: - Banner

struct NoticeBanner: View {
    @Environment(\.palette) private var p
    let icon: String
    let title: String
    let text: String
    let action: String?
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(SomnaFont.body(14, .semibold))
                Text(text)
                    .font(SomnaFont.body(12))
                    .foregroundStyle(p.fg2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let action {
                Button(action, action: onAction)
                    .font(SomnaFont.body(13, .semibold))
                    .buttonStyle(SoftPressStyle())
                    .frame(minHeight: 44)
            }
        }
        .card(padding: 14, radius: 16, fill: p.surface2)
        .accessibilityElement(children: .combine)
    }
}
