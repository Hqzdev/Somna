//
//  ExperimentViews.swift
//  Somna
//
//  14 Sleep experiments: A — setup, B — progress, C — results.
//  One habit at a time: 7 nights before the start are the baseline, then
//  14 nights with the habit. A result is interpretable from 5 baseline and
//  7 habit nights; it separates the effect, its uncertainty and what else
//  could have changed. A personal result, not a medical recommendation.
//

import SwiftUI
import Foundation

struct ExperimentTemplate: Identifiable, Hashable {
    let id: String
    let icon: String
    let title: String
    let detail: String
    let metric: OutcomeMetric
    /// Journal factor the habit removes or adds, used to rank templates by the person's data.
    let factorID: String?

    static let all: [ExperimentTemplate] = [
        ExperimentTemplate(id: "caffeine", icon: "cup.and.saucer", title: "Без кофеина после 14:00",
                           detail: "Последняя чашка — до 14:00", metric: .latency, factorID: FactorCatalog.caffeineLate),
        ExperimentTemplate(id: "screen", icon: "iphone", title: "Без телефона в кровати",
                           detail: "Телефон остаётся вне кровати", metric: .latency, factorID: FactorCatalog.screenInBed),
        ExperimentTemplate(id: "dinner", icon: "fork.knife", title: "Ужин за 3 часа до сна",
                           detail: "После ужина — только вода", metric: .score, factorID: FactorCatalog.lateMeal),
        ExperimentTemplate(id: "alcohol", icon: "wineglass", title: "Без алкоголя",
                           detail: "Ни одного напитка вечером", metric: .score, factorID: FactorCatalog.alcohol),
        ExperimentTemplate(id: "light", icon: "sun.max", title: "15 минут дневного света утром",
                           detail: "Выйти на улицу до 10:00", metric: .energy, factorID: FactorCatalog.daylight),
        ExperimentTemplate(id: "wake", icon: "alarm", title: "Подъём в одно время каждый день",
                           detail: "И в выходные тоже, ±15 минут", metric: .energy, factorID: nil)
    ]
}

// MARK: - 14A Setup

struct ExperimentSetupView: View {
    @Environment(AppState.self) private var state
    @Environment(SomnaStore.self) private var store
    @State private var choice: String?
    @State private var customTitle = ""
    @State private var metricIndex = 0

    private let metrics = OutcomeMetric.allCases
    private let customID = "custom"

    var body: some View {
        let mode = state.timeOfDay
        let p = mode.palette
        SomnaScreen(mode: mode) {
            if let active = store.activeExperiment {
                StateBlock(icon: "flask", state: .data, title: "Уже идёт эксперимент",
                           what: "«\(active.title)». Меняйте одну вещь за раз — иначе не понять, что сработало.",
                           actionTitle: "Открыть эксперимент", actionIcon: "arrow.right") {
                    state.push(.experimentProgress)
                }
            } else {
                setup(p)
            }
        }
        .somnaNavTitle("Новый эксперимент", mode: mode)
        .onAppear(perform: preselect)
    }

    @ViewBuilder
    private func setup(_ p: Palette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Какую привычку проверим?")
                .displayStyle(30, tracking: -1)
                .accessibilityAddTraits(.isHeader)
            Text("14 ночей до старта — точка отсчёта, затем 14 ночей с привычкой. Одна вещь за раз.")
                .font(SomnaFont.body(15))
                .foregroundStyle(p.fg2)
                .fixedSize(horizontal: false, vertical: true)
        }

        GroupedList {
            ForEach(Array(templates.enumerated()), id: \.element.id) { index, template in
                optionRow(p, id: template.id, icon: template.icon, title: template.title,
                          detail: hint(for: template) ?? template.detail, highlighted: hint(for: template) != nil,
                          last: false)
            }
            optionRow(p, id: customID, icon: "plus", title: "Свой эксперимент",
                      detail: "Опишите привычку одной фразой", highlighted: false, last: true)
        }
        .haptic(.selection, trigger: choice)

        if choice == customID {
            TextField("Например: прогулка 20 минут вечером", text: $customTitle)
                .font(SomnaFont.body(16))
                .padding(16)
                .background(p.line, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }

        VStack(alignment: .leading, spacing: 10) {
            Text("Что сравниваем")
                .font(SomnaFont.body(15, .semibold))
            SomnaSegmented(options: ["Оценка", "Сон", "Засыпание", "Энергия"], selection: $metricIndex)
            Text(metricHint)
                .font(SomnaFont.body(13))
                .foregroundStyle(p.fg2)
                .fixedSize(horizontal: false, vertical: true)
        }

        VStack(alignment: .leading, spacing: 10) {
            IconLine(systemImage: "calendar", text: dateRange, textColor: p.fg)
            IconLine(systemImage: "checkmark.circle", text: "Каждый вечер одна отметка: получилось или нет", textColor: p.fg)
            IconLine(systemImage: "chart.bar", text: baselineText, textColor: p.fg)
        }
        .card(padding: 18, radius: Radius.row, fill: p.surface2)

        PrimaryButton(title: "Начать с сегодняшнего вечера") {
            start()
        }
        .disabled(!canStart)
        .opacity(canStart ? 1 : 0.4)
    }

    // MARK: Data

    /// Templates linked with worse sleep in this person's data go first.
    private var templates: [ExperimentTemplate] {
        ExperimentTemplate.all.sorted { (hint(for: $0) != nil ? 0 : 1) < (hint(for: $1) != nil ? 0 : 1) }
    }

    private func hint(for template: ExperimentTemplate) -> String? {
        guard let factorID = template.factorID else { return nil }
        var found: FactorInsight?
        for window in FactorInsight.windows.reversed() where found == nil {
            found = store.snapshot.insights(window: window, outcome: .score).first { $0.factorID == factorID && $0.isStable }
        }
        guard let insight = found else { return nil }
        let linkedWithWorse = factorID == FactorCatalog.daylight ? !insight.isUnfavourable : insight.isUnfavourable
        guard linkedWithWorse else { return nil }
        return "В ваших данных: оценка \(insight.outcome.formatDifference(insight.difference ?? 0)) · \(insight.windowDays) дней"
    }

    private var selectedTemplate: ExperimentTemplate? {
        ExperimentTemplate.all.first { $0.id == choice }
    }

    private var canStart: Bool {
        if choice == customID { return !customTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return selectedTemplate != nil
    }

    private var metricHint: String {
        switch metrics[metricIndex] {
        case .score: "Оценка сна учитывает достаточность, непрерывность и ритм; при неполных данных балла нет."
        case .asleep: "Сколько минут вы спали."
        case .latency: "Сколько минут прошло от «в кровати» до сна. Нужны часы или запись времени в кровати."
        case .energy: "Ваша утренняя отметка 1–5. Отмечайте каждое утро, иначе сравнивать будет нечего."
        }
    }

    private var dateRange: String {
        let start = store.today
        return "Точка отсчёта: \(Fmt.dayMonth(start.adding(days: -6)))–\(Fmt.dayMonth(start)) · привычка: \(Fmt.dayMonth(start))–\(Fmt.dayMonth(start.adding(days: Experiment.durationDays - 1)))"
    }

    private var baselineText: String {
        let start = store.today
        let metric = metrics[metricIndex]
        var count = 0
        var day = start.adding(days: -(Experiment.baselineDays - 1))
        while day <= start {
            if store.snapshot.outcomes.value(metric, day) != nil { count += 1 }
            day = day.adding(days: 1)
        }
        if count >= Experiment.minimumBaselineNights {
            return "Точка отсчёта готова: \(count) из \(Experiment.baselineDays) ночей"
        }
        return "До старта есть только \(count) из \(Experiment.baselineDays) ночей — нужно \(Experiment.minimumBaselineNights). Вывод может не получиться."
    }

    private func preselect() {
        guard choice == nil else { return }
        if let factorID = state.experimentFactorID,
           let template = ExperimentTemplate.all.first(where: { $0.factorID == factorID }) {
            choice = template.id
            metricIndex = metrics.firstIndex(of: template.metric) ?? 0
        }
        state.experimentFactorID = nil
    }

    private func start() {
        let metric = metrics[metricIndex]
        if choice == customID {
            let title = String(customTitle.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
            store.startExperiment(title: title, detail: "Свой эксперимент", metric: metric)
        } else if let template = selectedTemplate {
            store.startExperiment(title: template.title, detail: template.detail, metric: metric)
        } else {
            return
        }
        state.setPath([.experimentProgress], for: state.tab)
        state.showToast("Эксперимент начался. Отметьте вечером, получилось ли")
    }

    private func optionRow(_ p: Palette, id: String, icon: String, title: String, detail: String,
                           highlighted: Bool, last: Bool) -> some View {
        let isOn = choice == id
        return Button {
            withAnimation(.snappy) {
                choice = id
                if let template = ExperimentTemplate.all.first(where: { $0.id == id }) {
                    metricIndex = metrics.firstIndex(of: template.metric) ?? metricIndex
                }
            }
        } label: {
            HStack(spacing: 14) {
                IconTile(systemImage: icon, size: 36, circle: false, filled: isOn)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(SomnaFont.body(15, isOn ? .semibold : .medium))
                        .foregroundStyle(p.fg)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(SomnaFont.body(12))
                        .foregroundStyle(highlighted ? p.accent : p.fg2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Circle()
                    .strokeBorder(isOn ? p.fg : p.lineStrong, lineWidth: isOn ? 7 : 1.5)
                    .frame(width: 22, height: 22)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if !last { Divider1() }
        }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - 14B Progress

struct ExperimentProgressView: View {
    @Environment(AppState.self) private var state
    @Environment(SomnaStore.self) private var store
    @State private var confirmStop = false

    var body: some View {
        let mode = state.timeOfDay
        let p = mode.palette
        SomnaScreen(mode: mode) {
            if let experiment = store.activeExperiment,
               let report = store.snapshot.experiments.first(where: { $0.id == experiment.id }) {
                content(p, experiment: experiment, report: report)
            } else {
                StateBlock(icon: "flask", state: .neutral, title: "Эксперимент не идёт",
                           what: "Выберите одну привычку и проверьте её на своих данных: неделя до и две недели с ней.",
                           actionTitle: "Выбрать привычку", actionIcon: "plus") {
                    state.push(.experimentSetup)
                }
            }
            pastExperiments(p)
        }
        .somnaNavTitle("Эксперимент", mode: mode)
        .haptic(.warning, trigger: confirmStop) { _, shown in shown }
        .confirmationDialog("Остановить эксперимент?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Остановить", role: .destructive) {
                if let id = store.activeExperiment?.id {
                    store.stopExperiment(id: id, finished: false)
                    state.showToast("Эксперимент остановлен. Записи журнала сохранятся")
                }
            }
            Button("Продолжить", role: .cancel) {}
        } message: {
            Text("Отметки останутся, но вывода не будет.")
        }
    }

    @ViewBuilder
    private func content(_ p: Palette, experiment: Experiment, report: ExperimentReport) -> some View {
        let evening = experiment.startDay.days(to: store.today) + 1
        let total = Experiment.durationDays
        let done = Set(experiment.doneDays)
        let elapsed = min(max(evening - 1, 0), total)
        let doneCount = (0..<elapsed).filter { done.contains(experiment.startDay.adding(days: $0)) }.count
        let missed = Set((1...max(1, elapsed)).filter { $0 <= elapsed && !done.contains(experiment.startDay.adding(days: $0 - 1)) })

        VStack(alignment: .leading, spacing: 8) {
            Text(experiment.title)
                .displayStyle(30, tracking: -1)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(evening <= total
                 ? "Вечер \(evening) из \(total) · с \(Fmt.dayMonth(experiment.startDay))"
                 : "14 ночей прошли · с \(Fmt.dayMonth(experiment.startDay))")
                .font(SomnaFont.body(15))
                .foregroundStyle(p.fg2)
        }

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Соблюдение")
                        .font(SomnaFont.body(13, .medium))
                        .foregroundStyle(p.fg2)
                    Text(elapsed == 0 ? "Первый вечер" : "\(doneCount) из \(elapsed) вечеров")
                        .displayStyle(28, tracking: -0.8)
                }
                Spacer()
                if elapsed > 0 {
                    StatusTag(text: Fmt.percent(Double(doneCount) / Double(elapsed)),
                              state: doneCount * 4 >= elapsed * 3 ? .restore : .caution)
                }
            }
            ExperimentDays(total: total, today: min(evening, total + 1), missed: missed)
            HStack(spacing: 12) {
                LegendItem(color: Brand.restore, text: "получилось")
                LegendItem(color: p.cautionSoft, text: "нет отметки")
                LegendItem(color: p.accentSoft, text: "сегодня")
            }
        }
        .card()

        if evening <= total {
            let todayDone = done.contains(store.today)
            VStack(alignment: .leading, spacing: 12) {
                Text("Сегодня вечером получилось?")
                    .font(SomnaFont.body(15, .semibold))
                Text(experiment.detail)
                    .font(SomnaFont.body(13))
                    .foregroundStyle(p.fg2)
                HStack(spacing: 8) {
                    SecondaryButton(title: todayDone ? "Получилось ✓" : "Получилось", systemImage: todayDone ? nil : "checkmark") {
                        store.setExperimentDone(id: experiment.id, day: store.today, done: true)
                    }
                    if todayDone {
                        SecondaryButton(title: "Отменить", fullWidth: false) {
                            store.setExperimentDone(id: experiment.id, day: store.today, done: false)
                        }
                    }
                }
            }
            .card(padding: 18, radius: Radius.row)
            .haptic(.success, trigger: todayDone) { _, new in new }
        }

        if experiment.metric == .energy, store.checkIn(for: store.today) == nil {
            MetricRow(state: .caution, label: "Утренняя отметка", sub: "Эксперимент сравнивает энергию — отметьте её сегодня",
                      value: "", showDivider: false) {
                state.sheet = .checkIn
            }
            .padding(.horizontal, 16)
            .card(padding: 0, radius: 22)
        }

        interim(p, report: report)

        VStack(spacing: 6) {
            if report.isComplete {
                PrimaryButton(title: "Завершить и посмотреть итоги", systemImage: "flag.checkered") {
                    store.stopExperiment(id: experiment.id, finished: true)
                    state.push(.experimentResults(experiment.id))
                }
            }
            TextLink(title: "Остановить эксперимент", muted: true, showChevron: false) {
                confirmStop = true
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func interim(_ p: Palette, report: ExperimentReport) -> some View {
        let metric = report.experiment.metric
        return VStack(alignment: .leading, spacing: 8) {
            Text("Промежуточно · \(metric.title.lowercased())")
                .font(SomnaFont.body(12, .semibold))
                .foregroundStyle(p.fg2)
            if let before = report.baselineMedian, let after = report.experimentMedian {
                Text("\(ExperimentFormat.value(before, metric)) до старта → \(ExperimentFormat.value(after, metric)) с привычкой")
                    .font(SomnaFont.body(15, .medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(interimText(report))
                .font(SomnaFont.body(13))
                .foregroundStyle(p.fg2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card(fill: p.surface2)
    }

    private func interimText(_ report: ExperimentReport) -> String {
        var parts: [String] = []
        parts.append("Ночей до старта: \(report.baselineCount) из \(Experiment.baselineDays), с привычкой: \(report.experimentCount).")
        parts.append("Привычка отмечена в \(report.adherenceCount) вечеров.")
        if report.baselineCount < Experiment.minimumBaselineNights {
            parts.append("До старта записано меньше \(Experiment.minimumBaselineNights) ночей — вывод может не получиться.")
        }
        if report.experimentCount < Experiment.minimumExperimentNights {
            parts.append("Выводы делать рано: нужно минимум \(Experiment.minimumExperimentNights) ночей с привычкой.")
        }
        if report.adherenceCount < Experiment.minimumExperimentNights {
            parts.append("Для вывода нужно отметить привычку минимум в \(Experiment.minimumExperimentNights) вечеров.")
        }
        return parts.joined(separator: " ")
    }

    @ViewBuilder
    private func pastExperiments(_ p: Palette) -> some View {
        let past = store.snapshot.experiments.filter { $0.experiment.status != .active }
            .sorted { $0.experiment.startDay > $1.experiment.startDay }
        if !past.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                GroupCaption(text: "Прошлые эксперименты")
                GroupedList {
                    ForEach(Array(past.enumerated()), id: \.element.id) { index, report in
                        MetricRow(state: report.experiment.status == .finished ? .data : .neutral,
                                  label: report.experiment.title,
                                  sub: "\(Fmt.dayMonth(report.experiment.startDay)) · \(report.experiment.status == .finished ? "завершён" : "остановлен")",
                                  value: report.isInterpretable ? report.experiment.metric.formatDifference(report.difference ?? 0) : "",
                                  showDivider: index < past.count - 1) {
                            state.push(.experimentResults(report.id))
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 14C Results

struct ExperimentResultsView: View {
    @Environment(AppState.self) private var state
    @Environment(SomnaStore.self) private var store
    let experimentID: String

    var body: some View {
        let mode = state.timeOfDay
        let p = mode.palette
        SomnaScreen(mode: mode) {
            if let report = store.snapshot.experiments.first(where: { $0.id == experimentID }) {
                content(p, report: report)
            } else {
                StateBlock(icon: "flask", state: .neutral, title: "Эксперимент не найден",
                           what: "Возможно, данные были удалены.")
            }
        }
        .somnaNavTitle("Итоги эксперимента", mode: mode)
    }

    @ViewBuilder
    private func content(_ p: Palette, report: ExperimentReport) -> some View {
        let e = report.experiment
        let metric = e.metric
        let stable = isStable(report)

        VStack(alignment: .leading, spacing: 10) {
            Overline(icon: "flask", text: "\(e.title) · с \(Fmt.dayMonth(e.startDay))")
            Text(headline(report, stable: stable))
                .displayStyle(28, tracking: -0.9)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if report.isInterpretable {
                StatusTag(text: stable ? "Разница устойчивая" : "В пределах обычного разброса",
                          state: stable ? (report.isImprovement ? .restore : .caution) : .neutral)
            }
        }

        if let before = report.baselineMedian, let after = report.experimentMedian {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    LegendItem(color: p.fg3, text: "до · \(report.baselineCount) ночей")
                    LegendItem(color: p.fg, text: "с привычкой · \(report.experimentCount)")
                }
                HStack {
                    Text(metric.title)
                        .font(SomnaFont.body(14, .medium))
                    Spacer()
                    Text("\(ExperimentFormat.value(before, metric)) → \(ExperimentFormat.value(after, metric))")
                        .font(SomnaFont.body(13))
                        .foregroundStyle(p.fg2)
                }
                let top = max(before, after, 1) * 1.15
                ProgressTrack(fraction: before / top, fill: p.fg3)
                ProgressTrack(fraction: after / top, fill: p.fg)
                if let lo = report.intervalLow, let hi = report.intervalHigh {
                    Text("Вероятный диапазон разницы: от \(metric.formatDifference(lo)) до \(metric.formatDifference(hi))")
                        .font(SomnaFont.body(12))
                        .foregroundStyle(p.fg3)
                }
            }
            .card()
            .accessibilityElement(children: .combine)
        }

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(Brand.caution).frame(width: 8, height: 8)
                Text("Что может искажать результат")
                    .font(SomnaFont.body(15, .semibold))
            }
            ForEach(caveats(report), id: \.self) { line in
                IconLine(systemImage: "circle.fill", text: line, size: 14)
            }
        }
        .card()

        VStack(alignment: .leading, spacing: 12) {
            Overline(icon: "arrow.right.circle", text: "Следующий шаг")
            Text(nextStep(report, stable: stable))
                .displayStyle(22, tracking: -0.6)
                .foregroundStyle(Palette.night.fg)
                .fixedSize(horizontal: false, vertical: true)
            if store.activeExperiment == nil {
                PrimaryButton(title: "Новый эксперимент", systemImage: "flask") {
                    state.push(.experimentSetup)
                }
            }
        }
        .environment(\.palette, Palette.night)
        .card(fill: Palette.night.surface)

        Text("Результат относится только к вам и не является медицинской рекомендацией.")
            .font(SomnaFont.body(12))
            .foregroundStyle(p.fg3)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    private func isStable(_ report: ExperimentReport) -> Bool {
        guard report.isInterpretable, let lo = report.intervalLow, let hi = report.intervalHigh else { return false }
        return lo > 0 || hi < 0
    }

    private func headline(_ report: ExperimentReport, stable: Bool) -> String {
        let metric = report.experiment.metric
        guard report.isInterpretable, let d = report.difference else {
            if report.experiment.status == .stopped { return "Эксперимент остановлен — вывода нет." }
            return "Данных не хватило для вывода."
        }
        let name = metric.title.lowercased()
        if !stable { return "Заметной разницы нет: \(name) \(metric.formatDifference(d))." }
        return report.isImprovement
            ? "С привычкой \(name) лучше: \(metric.formatDifference(d))."
            : "С привычкой \(name) хуже: \(metric.formatDifference(d))."
    }

    private func caveats(_ report: ExperimentReport) -> [String] {
        let e = report.experiment
        var lines: [String] = []
        let done = e.doneDays.filter { $0 >= e.startDay && $0 < e.startDay.adding(days: Experiment.durationDays) }.count
        lines.append("Привычка отмечена в \(done) из \(Experiment.durationDays) вечеров\(done < 10 ? " — это мало для уверенного вывода" : "").")
        lines.append("Ночей до старта: \(report.baselineCount) (нужно \(Experiment.minimumBaselineNights)), с привычкой: \(report.experimentCount) (нужно \(Experiment.minimumExperimentNights)).")
        lines.append("Привычка отмечена в \(report.adherenceCount) вечеров; для вывода нужно \(Experiment.minimumExperimentNights). Это сравнение, не доказательство причины.")
        lines.append("В эти недели могло измениться что-то ещё: нагрузка, болезнь, поездки, сезон.")
        lines.append("Две недели — короткий срок: эффект стоит перепроверить позже.")
        return lines
    }

    private func nextStep(_ report: ExperimentReport, stable: Bool) -> String {
        guard report.isInterpretable else {
            return "Повторите эксперимент и отмечайте привычку каждый вечер — без отметок сравнивать нечего."
        }
        if stable && report.isImprovement {
            return "Оставьте привычку. Через месяц сравните ещё раз — эффект мог быть случайным."
        }
        if stable {
            return "Привычка не помогла — верните как было и проверьте следующую."
        }
        return "Разница слишком мала. Проверьте другую привычку — из закономерностей в журнале."
    }
}

// MARK: - Formatting

enum ExperimentFormat {
    static func value(_ v: Double, _ metric: OutcomeMetric) -> String {
        switch metric {
        case .score: "\(Int(v.rounded()))"
        case .asleep, .latency: Fmt.duration(v)
        case .energy: "\(Fmt.number(v, digits: 1)) из 5"
        }
    }
}
