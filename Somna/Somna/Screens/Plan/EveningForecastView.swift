//
//  EveningForecastView.swift
//  Somna
//
//  07 «Какой сон вероятен сегодня». Root of the «План» tab.
//  Duration is shown only with enough comparable nights and back-tested range.
//

import SwiftUI
import Foundation

struct EveningForecastView: View {
    @Environment(AppState.self) private var state
    @Environment(SomnaStore.self) private var store

    private var snapshot: SomnaSnapshot { store.snapshot }
    private var plan: RecoveryPlan { snapshot.plan }

    /// Bedtime tonight, minutes after today's midnight (may exceed 1440).
    private var bed: Int { state.plannedBedtime ?? plan.bedtimeMinutes }

    private var bedBinding: Binding<Int> {
        Binding(get: { bed }, set: { state.plannedBedtime = $0 })
    }

    var body: some View {
        let mode = state.forecastMode
        let p = mode.palette
        let forecast = forecastFor(bed)
        SomnaScreen(mode: mode) {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(Fmt.dayTitle(snapshot.today)) · \(Fmt.time(Date()))")
                    .font(SomnaFont.body(13, .medium))
                    .foregroundStyle(p.fg2)
                Text("Какой сон вероятен сегодня")
                    .displayStyle(32, tracking: -1.1)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }

            forecastCard(p, forecast: forecast)

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .lastTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Лечь в кровать")
                            .font(SomnaFont.body(13, .medium))
                            .foregroundStyle(p.fg2)
                        Text(Fmt.clock(bed))
                            .font(SomnaFont.display(48, relativeTo: .largeTitle))
                            .tracking(-2)
                            .contentTransition(.numericText())
                    }
                    Spacer()
                    Button {
                        state.sheet = .alarm
                    } label: {
                        Text("подъём в \(Fmt.clock(snapshot.wakeMinutes))")
                            .font(SomnaFont.body(13, .medium))
                            .foregroundStyle(p.fg2)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(SoftPressStyle())
                    .accessibilityHint("Открывает время подъёма и будильник")
                }
                BedtimeSlider(minutes: bedBinding, lower: sliderRange.lower, upper: sliderRange.upper,
                              goodLow: plan.bedtimeMinutes - 45, goodHigh: plan.bedtimeMinutes,
                              lastNight: lastNightBedtime)
                HStack(spacing: 16) {
                    LegendItem(color: p.restoreSoft, text: "хватит сна до цели", width: 14)
                    if lastNightBedtime != nil {
                        LegendItem(color: Brand.caution, text: "прошлая ночь", width: 2, height: 12)
                    }
                }
                Text(outcomeSentence(forecast))
                    .font(SomnaFont.body(16, .medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .animation(.default, value: bed)
                VStack(spacing: 0) {
                    optionRow(p, minutes: plan.bedtimeMinutes, title: "\(Fmt.clock(plan.bedtimeMinutes)) · по цели")
                    optionRow(p, minutes: plan.bedtimeMinutes - 30, title: "\(Fmt.clock(plan.bedtimeMinutes - 30)) · на 30 мин раньше")
                    if let last = lastNightBedtime, abs(last - plan.bedtimeMinutes) >= 10 {
                        optionRow(p, minutes: last, title: "\(Fmt.clock(last)) · как вчера")
                    }
                }
            }
            .card()

            considered(p)

            PrimaryButton(title: "Собрать план на вечер") {
                state.push(.eveningPlan)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Forecast

    private func forecastFor(_ bedtime: Int) -> SleepForecast {
        let tz = snapshot.timeZone
        let bedDate = snapshot.today.date(atMinutes: bedtime, in: tz)
        let wakeDate = snapshot.today.date(atMinutes: snapshot.wakeMinutes + 1440, in: tz)
        return snapshot.forecast.forecast(bedtime: bedDate, wake: wakeDate)
    }

    private func forecastCard(_ p: Palette, forecast: SleepForecast) -> some View {
        let model = snapshot.forecast
        let goal = Double(snapshot.settings.goalMinutes)
        var rangeText = "прогноз по вашим \(Fmt.nights(min(model.nights, ForecastModel.window)))"
        if let lo = forecast.lowMinutes, let hi = forecast.highMinutes {
            rangeText = "обычно от \(Fmt.duration(lo)) до \(Fmt.duration(hi))"
        }
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                if let predicted = forecast.predictedMinutes {
                    forecastValue(p, label: "Сон, вероятно", value: "≈ \(Fmt.duration(predicted))", range: rangeText,
                                  low: forecast.lowMinutes, high: forecast.highMinutes, point: predicted,
                                  minV: goal - 180, maxV: goal + 60)
                } else {
                    forecastValue(p, label: "Окно сна", value: Fmt.duration(forecast.windowMinutes),
                                  range: "от отбоя до подъёма", low: nil, high: nil, point: nil)
                }
            }
            IconLine(systemImage: "info.circle", text: footnote(model, forecast), size: 12)
                .padding(.top, 14)
                .overlay(alignment: .top) { Divider1() }
        }
        .card(padding: 22, radius: Radius.hero)
    }

    private func footnote(_ model: ForecastModel, _ forecast: SleepForecast) -> String {
        if !model.canPredict {
            return "Прогноз длительности появится после \(Fmt.nights(ForecastModel.minimumNights)) с временем в кровати и проверкой ошибок (сейчас \(model.nights)). Пока — только окно сна."
        }
        var text = "Это вероятность, а не обещание."
        if !forecast.latencyKnown {
            text += " Время засыпания неизвестно: источник не записывает «в кровати»."
        }
        text += " Балл ночи не прогнозируем: пробуждения заранее неизвестны."
        return text
    }

    private func forecastValue(_ p: Palette, label: String, value: String, range: String,
                               low: Double?, high: Double?, point: Double?,
                               minV: Double = 0, maxV: Double = 100) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(SomnaFont.body(13, .medium))
                .foregroundStyle(p.fg2)
            Text(value)
                .font(SomnaFont.display(34, relativeTo: .largeTitle))
                .tracking(-1.4)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            if let low, let high, let point, maxV > minV {
                LikelyRange(low: low, high: high, point: point, minV: minV, maxV: maxV)
            }
            Text(range)
                .font(SomnaFont.body(12))
                .foregroundStyle(p.fg2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Slider

    private var sliderRange: (lower: Int, upper: Int) {
        let anchor = plan.bedtimeMinutes
        let lower = (anchor - 90) / 30 * 30
        return (lower, lower + 180)
    }

    /// Last night's time in bed on tonight's scale (23:40 → 1420, 00:30 → 1470).
    private var lastNightBedtime: Int? {
        guard let night = snapshot.latest?.night else { return nil }
        let start = night.inBedStart ?? night.sleepStart
        return Int(ClockTime.bedtimeScale(start, in: night.timeZone).rounded()) + 720
    }

    // MARK: Outcome

    private func outcomeSentence(_ f: SleepForecast) -> String {
        guard let predicted = f.predictedMinutes, let change = f.balanceChangeMinutes else {
            return "Если лечь в \(Fmt.clock(bed)) и встать в \(Fmt.clock(snapshot.wakeMinutes)), на сон останется \(Fmt.duration(f.windowMinutes))."
        }
        var text = "Если лечь в \(Fmt.clock(bed)), вы получите примерно \(Fmt.duration(predicted)) сна"
        if change <= -5 {
            text += " — это на \(Fmt.duration(-change)) больше цели. Избыток не вычитает прошлый недобор автоматически."
        } else if change < 5 {
            text += " — ровно по цели."
        } else {
            text += " — на \(Fmt.duration(change)) меньше цели."
        }
        return text
    }

    private func optionRow(_ p: Palette, minutes: Int, title: String) -> some View {
        let isOn = bed == minutes
        let f = forecastFor(minutes)
        let change = f.balanceChangeMinutes
        let dot: Color = (change ?? 0) <= 0 ? Brand.restore : ((change ?? 0) <= 15 ? p.fg3 : Brand.caution)
        return Button {
            withAnimation(.snappy) { state.plannedBedtime = minutes }
        } label: {
            HStack(spacing: 10) {
                Text(title)
                    .font(SomnaFont.body(14, isOn ? .semibold : .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(f.predictedMinutes == nil ? "окно " : "≈ ")\(Fmt.duration(f.predictedMinutes ?? f.windowMinutes))")
                    .font(SomnaFont.body(13))
                    .foregroundStyle(p.fg2)
                if let change {
                    HStack(spacing: 6) {
                        Circle().fill(dot).frame(width: 6, height: 6)
                        Text(change <= 0 ? "по цели" : "−\(Fmt.duration(change))")
                            .font(SomnaFont.body(13, .semibold))
                    }
                    .frame(minWidth: 90, alignment: .trailing)
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(isOn ? p.tabSelected : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: What is taken into account

    private func considered(_ p: Palette) -> some View {
        let model = snapshot.forecast
        let today = snapshot.today
        let caffeine = snapshot.factorValues[FactorCatalog.caffeineLate]?[today]
        let workout = snapshot.factorValues[FactorCatalog.lateWorkout]?[today]
        return VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Что учтено")
            GroupedList {
                MetricRow(state: .neutral, label: "Подъём",
                          sub: snapshot.settings.wakeMinutes == nil ? "Ваше обычное время за 14 ночей" : "Выбрано вами",
                          value: Fmt.clock(snapshot.wakeMinutes), showChevron: false)
                MetricRow(state: .neutral, label: "Цель сна", sub: "Можно изменить в Профиле",
                          value: Fmt.duration(snapshot.settings.goalMinutes), showChevron: false)
                MetricRow(state: .neutral, label: "Засыпание",
                          sub: model.medianLatency == nil ? "Нет данных «в кровати»" : "Медиана до 28 ночей",
                          value: model.medianLatency.map { Fmt.duration($0) } ?? "—", showChevron: false)
                MetricRow(state: .neutral, label: "Бодрствование ночью", sub: "Медиана до 28 ночей",
                          value: model.medianAwake.map { Fmt.duration($0) } ?? "—", showChevron: false)
                if let caffeine {
                    MetricRow(state: caffeine >= 1 ? .caution : .restore, label: "Кофеин после 14:00",
                              sub: "Журнал или Apple Health", value: caffeine >= 1 ? "Да" : "Нет", showChevron: false)
                }
                if let workout {
                    MetricRow(state: workout >= 1 ? .caution : .neutral, label: "Тренировка после 19:00",
                              sub: "Apple Health", value: workout >= 1 ? "Да" : "Нет", showChevron: false)
                }
                MetricRow(state: (snapshot.balance?.deficitMinutes ?? 0) > 30 ? .caution : .neutral, label: "Баланс сна",
                          sub: "14 ночей", value: snapshot.balance?.text ?? "—", showChevron: false, showDivider: false)
            }
        }
    }
}
