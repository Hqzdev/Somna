//
//  EveningPlanView.swift
//  Somna
//
//  08 Evening plan: at most three actions, ranked by the person's confirmed
//  patterns, the sleep goal and regularity. Each shows why and where the
//  data came from. Marks are saved for the evening.
//

import SwiftUI
import Foundation

struct EveningPlanView: View {
    @Environment(AppState.self) private var state
    @Environment(SomnaStore.self) private var store

    var body: some View {
        let p = Palette.night
        let snapshot = store.snapshot
        let plan = snapshot.plan
        let actions = plan.actions
        let nextID = actions.first { store.status(of: $0) == .pending }?.id
        SomnaScreen(mode: .night, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("План на вечер")
                    .displayStyle(32, tracking: -1.1)
                    .accessibilityAddTraits(.isHeader)
                Text(summary(snapshot))
                    .font(SomnaFont.body(15))
                    .foregroundStyle(p.fg2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if actions.isEmpty {
                StateBlock(icon: "moon.stars", state: .neutral, title: "Плана пока нет",
                           what: "Задайте время подъёма — и Somna посчитает время отхода ко сну по вашей цели.",
                           actionTitle: "Время подъёма", actionIcon: "alarm") {
                    state.sheet = .alarm
                }
            } else {
                VStack(spacing: 12) {
                    ForEach(actions) { action in
                        PlanStepRow(action: action,
                                    status: store.status(of: action),
                                    isNext: action.id == nextID,
                                    onToggle: {
                                        let current = store.status(of: action)
                                        store.setStatus(current == .done ? .pending : .done, for: action)
                                    },
                                    onSkip: { store.setStatus(.skipped, for: action) })
                    }
                }
            }

            Button {
                state.sheet = .whyPlan
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 18, weight: .medium))
                    Text("Почему этот план?")
                        .font(SomnaFont.body(15, .medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(p.fg3)
                }
                .padding(16)
                .background(p.surface, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(SoftPressStyle())

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "hand.raised")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(p.fg2)
                Text("Любой шаг можно пропустить — без штрафов. Завтра план подстроится под то, что получилось.")
                    .font(SomnaFont.body(13))
                    .foregroundStyle(p.fg2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PrimaryButton(title: "Начать вечерний режим", systemImage: "moon") {
                state.cover = .windDown
            }
        }
        .somnaNavTitle("Сегодня вечером", mode: .night)
    }

    private func summary(_ snapshot: SomnaSnapshot) -> String {
        let plan = snapshot.plan
        let bed = state.plannedBedtime ?? plan.bedtimeMinutes
        var text = "Лечь в \(Fmt.clock(bed)) · подъём в \(Fmt.clock(plan.wakeMinutes))"
        if snapshot.forecast.canPredict {
            let tz = snapshot.timeZone
            let f = snapshot.forecast.forecast(bedtime: snapshot.today.date(atMinutes: bed, in: tz),
                                               wake: snapshot.today.date(atMinutes: plan.wakeMinutes + 1440, in: tz))
            if let predicted = f.predictedMinutes {
                text += " · ≈ \(Fmt.duration(predicted)) сна"
            }
        }
        return text
    }
}

// MARK: - Why this plan

struct WhyPlanSheet: View {
    @Environment(SomnaStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let p = Palette.night
        let plan = store.snapshot.plan
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Как собран план")
                        .displayStyle(26, tracking: -0.8)
                        .accessibilityAddTraits(.isHeader)
                    VStack(alignment: .leading, spacing: 8) {
                        IconLine(systemImage: "1.circle", text: "Сначала — закономерности, устойчиво заметные в ваших данных.")
                        IconLine(systemImage: "2.circle", text: "Затем — время отхода ко сну от подъёма и вашей цели сна.")
                        IconLine(systemImage: "3.circle", text: "Затем — регулярность подъёма и ответы анкеты. Не больше трёх действий.")
                    }
                    ForEach(plan.actions) { action in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 10) {
                                Image(systemName: action.systemImage)
                                    .font(.system(size: 16, weight: .medium))
                                    .frame(width: 36, height: 36)
                                    .background(p.accentSoft, in: Circle())
                                    .accessibilityHidden(true)
                                Text(action.title)
                                    .font(SomnaFont.body(16, .semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Text(action.reason)
                                .font(SomnaFont.body(14))
                                .foregroundStyle(p.fg2)
                                .fixedSize(horizontal: false, vertical: true)
                            SourceLabel(icon: "info.circle", text: action.source)
                        }
                        .card(padding: 18, radius: Radius.row, fill: p.surface)
                    }
                    IconLine(systemImage: "checkmark.shield",
                             text: "Это объяснимые правила на ваших данных (формулы \(SomnaSnapshot.formulaVersion)), а не медицинские рекомендации. Связь в данных — не доказанная причина.")
                }
                .padding(20)
            }
            .background { SkyBackground(palette: p) }
            .foregroundStyle(p.fg)
            .somnaNavTitle("Почему этот план", mode: .night)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .environment(\.palette, p)
        .tint(p.fg)
        .preferredColorScheme(.dark)
        .presentationDragIndicator(.visible)
    }
}
