//
//  HealthSignalsView.swift
//  Somna
//
//  17 Health signals: recovery against the personal baseline and long-term
//  changes — the median of the last 7 nights against the previous 28.
//  A sustained change is shown as an observation, never as a diagnosis.
//  Consumer measurements are not a clinical assessment.
//

import SwiftUI
import Foundation

struct HealthSignalsView: View {
    @Environment(AppState.self) private var state
    @Environment(SomnaStore.self) private var store

    var body: some View {
        let mode = state.timeOfDay
        let p = mode.palette
        let snapshot = store.snapshot
        SomnaScreen(mode: mode, spacing: 24) {
            recoveryCard(snapshot, p: p)

            VStack(alignment: .leading, spacing: 8) {
                GroupCaption(text: "7 ночей против 28 предыдущих")
                if snapshot.trends.isEmpty {
                    StateBlock(icon: "waveform.path.ecg", state: .neutral, title: "Трендов пока нет",
                               what: "Нужно минимум 5 из последних 7 ночей и 14 из 28 предыдущих для каждого показателя.")
                } else {
                    GroupedList {
                        ForEach(Array(snapshot.trends.enumerated()), id: \.element.id) { index, t in
                            TrendRow(trend: t, values: series(t.metric, snapshot),
                                     showDivider: index < snapshot.trends.count - 1)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 16, weight: .medium))
                    Text("Наблюдения, не диагнозы")
                        .font(SomnaFont.body(14, .semibold))
                }
                Text("Часы и телефон измеряют приблизительно. Устойчивое изменение — повод обратить внимание на самочувствие, режим и нагрузку. Если что-то беспокоит, обсудите это с врачом.")
                    .font(SomnaFont.body(13))
                    .foregroundStyle(p.fg2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .card(padding: 18, radius: Radius.row, fill: p.surface2)
        }
        .somnaNavTitle("Сигналы здоровья", mode: mode)
    }

    @ViewBuilder
    private func recoveryCard(_ snapshot: SomnaSnapshot, p: Palette) -> some View {
        if let report = snapshot.latest, let recovery = report.recovery {
            VStack(alignment: .leading, spacing: 14) {
                Text("Восстановление")
                    .font(SomnaFont.body(15, .semibold))
                Text(recovery.status.title)
                    .displayStyle(25, tracking: -0.7)
                Text("\(recovery.signalCount) доступных сигнала · \(recovery.adverseCount) с отклонением от цели или личной базы. Это наблюдение, не медицинская оценка.")
                    .font(SomnaFont.body(12))
                    .foregroundStyle(p.fg2)
                VStack(spacing: 10) {
                    IconLine(systemImage: "moon.zzz", text: "Сон \(Fmt.duration(recovery.asleepMinutes)) при цели \(Fmt.duration(recovery.goalMinutes))")
                    if let v = report.vitals.hrv, let b = recovery.hrvBaseline {
                        IconLine(systemImage: "waveform.path.ecg", text: "ВСР \(Int(v.rounded())) мс · обычно около \(Int(b.median.rounded())) мс")
                    }
                    if let v = report.vitals.restingHeartRate, let b = recovery.rhrBaseline {
                        IconLine(systemImage: "heart", text: "Пульс в покое \(Int(v.rounded())) · обычно около \(Int(b.median.rounded()))")
                    }
                    if let energy = report.checkIn?.energy {
                        IconLine(systemImage: "sun.max", text: "Утренняя энергия: \(energy) из 5")
                    }
                }
                if !recovery.hasPhysiology {
                    Text("Личная база физиологических измерений появится после 14 сопоставимых ночей одного источника.")
                        .font(SomnaFont.body(12))
                        .foregroundStyle(p.fg2)
                }
            }
            .card(padding: 22, radius: Radius.hero)
        } else {
            StateBlock(icon: "heart.text.square", state: .neutral, title: "Восстановление пока недоступно",
                       what: "Нужна прошлая ночь и личная база из 14 измерений ВСР или пульса в покое.")
        }
    }

    private func series(_ metric: TrendMetric, _ snapshot: SomnaSnapshot) -> [Double] {
        snapshot.reports.suffix(35).filter(\.night.isValid).compactMap { r -> Double? in
            switch metric {
            case .asleep: return r.night.asleepMinutes
            case .bedtime: return r.night.bedtimeScale
            case .hrv: return r.vitals.hrv
            case .restingHeartRate: return r.vitals.restingHeartRate
            case .respiratoryRate: return r.vitals.respiratoryRate
            case .wristTemperature: return r.vitals.wristTemperature
            case .oxygenSaturation: return r.vitals.oxygenSaturation
            }
        }
    }
}

private struct TrendRow: View {
    @Environment(\.palette) private var p
    let trend: TrendObservation
    let values: [Double]
    let showDivider: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(trend.metric.title)
                    .font(SomnaFont.body(15, .medium))
                Text("\(format(trend.recentMedian)) против \(format(trend.priorMedian))")
                    .font(SomnaFont.body(13))
                    .foregroundStyle(p.fg2)
                if trend.isSustained {
                    StatusTag(text: trend.isUp ? "Устойчиво выше" : "Устойчиво ниже", state: .caution)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 8)
            if values.count >= 5 {
                Sparkline(values: values,
                          normLow: trend.priorMedian - abs(trend.difference) * 0.25,
                          normHigh: trend.priorMedian + abs(trend.difference) * 0.25,
                          color: trend.isSustained ? Brand.caution : nil)
            }
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            if showDivider { Divider1() }
        }
        .accessibilityElement(children: .combine)
    }

    private func format(_ v: Double) -> String {
        switch trend.metric {
        case .asleep: Fmt.duration(v)
        case .bedtime: Fmt.clock(ClockTime.minutesOfDay(fromBedtimeScale: v))
        case .wristTemperature: "\(Fmt.number(v, digits: 2))°"
        case .respiratoryRate: "\(Fmt.number(v, digits: 1)) \(trend.metric.unit)"
        default: "\(Int(v.rounded())) \(trend.metric.unit)"
        }
    }
}
