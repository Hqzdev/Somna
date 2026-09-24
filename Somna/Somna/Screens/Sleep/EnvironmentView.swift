//
//  EnvironmentView.swift
//  Somna
//
//  15 Bedroom: manual marks for tonight (heat, noise, light) saved in the
//  journal and compared with sleep like any other factor. HomeKit sensors
//  are an optional future source; until then the marks are the data.
//

import SwiftUI
import Foundation

struct EnvironmentView: View {
    @Environment(AppState.self) private var state
    @Environment(SomnaStore.self) private var store

    private let roomFactors = [FactorCatalog.roomHot, FactorCatalog.roomNoise, FactorCatalog.roomLight]

    var body: some View {
        let mode = state.timeOfDay
        let p = mode.palette
        let today = store.today
        let factors = store.snapshot.factors.filter { roomFactors.contains($0.id) }
        SomnaScreen(mode: mode, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                GroupCaption(text: "Спальня сегодня", trailing: Fmt.dayMonth(today))
                GroupedList {
                    ForEach(Array(factors.enumerated()), id: \.element.id) { index, factor in
                        let value = store.journalValue(day: today, factorID: factor.id)
                        HStack(spacing: 12) {
                            Image(systemName: factor.systemImage)
                                .font(.system(size: 17, weight: .medium))
                                .frame(width: 24)
                                .accessibilityHidden(true)
                            Text(factor.title)
                                .font(SomnaFont.body(15, .medium))
                            Spacer(minLength: 8)
                            YesNoControl(value: value) { newValue in
                                store.setJournal(day: today, factorID: factor.id, value: newValue)
                            }
                        }
                        .padding(.vertical, 12)
                        .overlay(alignment: .bottom) {
                            if index < factors.count - 1 { Divider1() }
                        }
                    }
                }
                Text("Отметка «нет» тоже важна: без неё ночь не попадёт в сравнение.")
                    .font(SomnaFont.body(12))
                    .foregroundStyle(p.fg2)
                    .padding(.horizontal, 4)
            }

            let insights = store.snapshot.factorInsights
                .filter { roomFactors.contains($0.factorID) && $0.windowDays == 90 && $0.outcome == .score && $0.hasEnoughData }
            if insights.isEmpty {
                StateBlock(icon: "thermometer.medium", state: .neutral, title: "Связей со сном пока нет",
                           what: "Нужно минимум по \(FactorInsight.minimumPerGroup) ночей с отметкой «да» и «нет» за 90 дней.")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    GroupCaption(text: "Что видно за 90 дней")
                    VStack(spacing: 12) {
                        ForEach(insights) { insight in
                            FactorInsightCard(insight: insight, factor: factors.first { $0.id == insight.factorID })
                        }
                    }
                }
            }

            StateBlock(icon: "house", state: .neutral, title: "Датчики HomeKit",
                       what: "Подключение датчиков температуры и шума будет необязательным источником в следующей версии. Сейчас Somna опирается на ваши отметки и ничего не додумывает.")
        }
        .somnaNavTitle("Спальня", mode: mode)
    }
}

/// «Да / Нет» with a third state «не отмечено».
struct YesNoControl: View {
    @Environment(\.palette) private var p
    let value: Double?
    let onChange: (Double?) -> Void

    var body: some View {
        HStack(spacing: 6) {
            option("Нет", selected: value == 0) { onChange(value == 0 ? nil : 0) }
            option("Да", selected: value.map { $0 >= 1 } ?? false) { onChange((value ?? 0) >= 1 ? nil : 1) }
        }
        .haptic(.selection, trigger: value)
    }

    private func option(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(SomnaFont.body(14, selected ? .semibold : .medium))
                .foregroundStyle(selected ? p.fgInverse : p.fg)
                .frame(minWidth: 52, minHeight: 44)
                .background(selected ? p.surfaceInverse : p.line, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(feedback: nil))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
