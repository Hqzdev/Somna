//
//  SleepDebtView.swift
//  Somna
//
//  11 Sleep balance: observed shortfall over 14 calendar days. Extra sleep
//  is separate; missing nights are skipped (never counted as zero).
//  The goal is editable; a personal suggestion never changes it silently.
//

import SwiftUI
import Foundation

struct SleepDebtView: View {
    @Environment(AppState.self) private var state
    @Environment(SomnaStore.self) private var store

    var body: some View {
        let mode = state.timeOfDay
        let p = mode.palette
        let snapshot = store.snapshot
        SomnaScreen(mode: mode, spacing: 24) {
            if let balance = snapshot.balance {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Недобор относительно цели")
                            .font(SomnaFont.body(13, .medium))
                            .foregroundStyle(p.fg2)
                        Text(balance.hasCoverage ? Fmt.duration(balance.shortfallMinutes) : "—")
                            .font(SomnaFont.display(52, relativeTo: .largeTitle))
                            .tracking(-2)
                        Text(balance.isPreliminary
                             ? "Нужно 10 из 14 календарных дней; сейчас \(Fmt.nights(balance.nights))."
                             : "За 14 календарных дней · дополнительно сверх цели: \(Fmt.duration(balance.extraMinutes))")
                            .font(SomnaFont.body(13))
                            .foregroundStyle(p.fg2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    BalanceChart(entries: balance.entries)
                    HStack(spacing: 14) {
                        LegendItem(color: Brand.restore, text: "Больше цели")
                        LegendItem(color: Brand.caution, text: "Меньше цели")
                    }
                }
                .card(padding: 22, radius: Radius.hero)
            } else {
                StateBlock(icon: "hourglass", state: .neutral, title: "Недобор появится после 10 дней с данными",
                           what: "Считаем по ночам, которые записаны в Здоровье. Пропущенные ночи не считаются нулём.")
            }

            VStack(alignment: .leading, spacing: 8) {
                GroupCaption(text: "Цель сна")
                GroupedList {
                    MetricRow(state: nil, label: "Цель на ночь", sub: "Меняется в любой момент — всё пересчитается",
                              value: Fmt.duration(snapshot.settings.goalMinutes), showDivider: false) {
                        state.sheet = .sleepGoal
                    }
                }
            }

            if let suggestion = snapshot.needSuggestion {
                VStack(alignment: .leading, spacing: 12) {
                    Overline(icon: "sparkles", iconColor: p.accent, text: "Личная оценка")
                    Text("Возможно, вам комфортно спать около \(Fmt.duration(suggestion.suggestedMinutes))")
                        .font(SomnaFont.body(16, .medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("По \(Fmt.nights(suggestion.basedOnNights)) с оценками сна и энергии 4–5. Это подсказка, не измеренная биологическая потребность.")
                        .font(SomnaFont.body(13))
                        .foregroundStyle(p.fg2)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        PrimaryButton(title: "Сделать целью", systemImage: nil, compact: true) {
                            store.setGoal(minutes: suggestion.suggestedMinutes)
                            state.showToast("Цель — \(Fmt.duration(suggestion.suggestedMinutes))")
                        }
                    }
                }
                .card(padding: 20, radius: Radius.row)
            }

            VStack(alignment: .leading, spacing: 8) {
                GroupCaption(text: "Как считаем")
                VStack(alignment: .leading, spacing: 8) {
                    IconLine(systemImage: "sum", text: "Складываем недостающие минуты за 14 календарных дней; нужно 10 дней с данными.")
                    IconLine(systemImage: "plus.forwardslash.minus", text: "Сон сверх цели показываем отдельно — он не погашает недобор автоматически.")
                    IconLine(systemImage: "moon.zzz", text: "Ночи без записи не считаются нулём. Цель для каждой ночи берётся из истории изменений.")
                }
                .card(padding: 18, radius: Radius.row)
            }
        }
        .somnaNavTitle("Недобор сна", mode: mode)
    }
}

// MARK: - Sleep goal editor

struct SleepGoalSheet: View {
    @Environment(AppState.self) private var state
    @Environment(SomnaStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var minutes = SleepSettings.defaultGoalMinutes

    var body: some View {
        let p = state.timeOfDay.palette
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Какую цель сна поставить?")
                    .displayStyle(24, tracking: -0.7)
                    .accessibilityAddTraits(.isHeader)
                Text("Стартовая цель — 7 ч 30 мин. Для взрослых ориентир — 7 часов и больше; ваша потребность может отличаться.")
                    .font(SomnaFont.body(14))
                    .foregroundStyle(p.fg2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button {
                        minutes = max(5 * 60, minutes - 15)
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 52, height: 52)
                            .background(p.line, in: Circle())
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityLabel("Меньше на 15 минут")
                    Spacer()
                    Text(Fmt.duration(minutes))
                        .displayStyle(34, tracking: -1)
                        .contentTransition(.numericText())
                    Spacer()
                    Button {
                        minutes = min(11 * 60, minutes + 15)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 52, height: 52)
                            .background(p.line, in: Circle())
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityLabel("Больше на 15 минут")
                }
                .hapticDynamic(trigger: minutes) { old, new in
                    new > old ? SensoryFeedback.increase : (new < old ? SensoryFeedback.decrease : nil)
                }
                if let s = store.snapshot.needSuggestion {
                    IconLine(systemImage: "sparkles", iconColor: p.accent,
                             text: "По вашим утренним отметкам: \(Fmt.duration(s.suggestedMinutes)) (\(Fmt.nights(s.basedOnNights))).")
                }
                Spacer()
                PrimaryButton(title: "Сохранить", systemImage: nil) {
                    store.setGoal(minutes: minutes)
                    dismiss()
                    state.showToast("Цель — \(Fmt.duration(minutes)). Показатели пересчитываются.")
                }
            }
            .padding(20)
            .foregroundStyle(p.fg)
            .environment(\.palette, p)
            .somnaNavTitle("Цель сна", mode: state.timeOfDay)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
        .tint(p.fg)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { minutes = store.settings.goalMinutes }
    }
}
