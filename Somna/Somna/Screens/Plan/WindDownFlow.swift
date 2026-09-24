//
//  WindDownFlow.swift
//  Somna
//
//  08c «Режим сна начался» → 09 Bedtime mode (low-stimulation, full screen)
//  → 10 Alarm sheet. Evening marks go straight into the journal.
//

import SwiftUI
import Foundation

struct WindDownFlow: View {
    @Environment(AppState.self) private var state
    @State private var stage = 0
    @State private var showAlarm = false

    var body: some View {
        Group {
            if stage == 0 {
                WindDownStartedView(
                    onOpenBedtime: { withAnimation(.easeInOut(duration: 0.35)) { stage = 1 } },
                    onBack: { state.cover = nil }
                )
                .transition(.opacity)
            } else {
                BedtimeModeView(
                    onAlarm: { showAlarm = true },
                    onClose: { state.cover = nil }
                )
                .transition(.opacity)
            }
        }
        .environment(\.palette, Palette.night)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showAlarm) {
            SmartAlarmView(closesNight: true)
        }
    }
}

// MARK: - 08c Wind-down started

struct WindDownStartedView: View {
    @Environment(AppState.self) private var state
    @Environment(SomnaStore.self) private var store
    let onOpenBedtime: () -> Void
    let onBack: () -> Void
    private let p = Palette.night

    var body: some View {
        let plan = store.snapshot.plan
        let bed = state.plannedBedtime ?? plan.bedtimeMinutes
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 28) {
                Image(systemName: "moon.fill")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(Brand.restore)
                    .frame(width: 88, height: 88)
                    .background(p.restoreSoft, in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Вечерний режим")
                        .displayStyle(36, tracking: -1.3)
                        .accessibilityAddTraits(.isHeader)
                    Text("Лечь в \(Fmt.clock(bed)) · подъём в \(Fmt.clock(plan.wakeMinutes)). Фокусирование «Сон» на iPhone приглушит уведомления.")
                        .font(SomnaFont.body(16))
                        .foregroundStyle(p.fg2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !plan.actions.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(plan.actions.enumerated()), id: \.element.id) { index, action in
                            let status = store.status(of: action)
                            HStack(spacing: 12) {
                                Image(systemName: icon(for: status))
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundStyle(status == .done ? Brand.restore : p.fg3)
                                Text(action.title)
                                    .font(SomnaFont.body(15, .medium))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(status == .skipped ? "пропущено" : (action.minutes.map { Fmt.clock($0) } ?? ""))
                                    .font(SomnaFont.body(13))
                                    .foregroundStyle(p.fg2)
                            }
                            .padding(.vertical, 13)
                            .overlay(alignment: .bottom) {
                                if index < plan.actions.count - 1 { Divider1() }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 4)
                    .card(padding: 0, radius: Radius.row, fill: p.surface)
                }

                IconLine(systemImage: "alarm",
                         text: store.settings.alarmEnabled
                             ? "Будильник: \(Fmt.clock(store.snapshot.wakeMinutes)) каждый день"
                             : "Будильник Somna не включён — можно включить в режиме сна")
            }
            .padding(.top, 32)

            Spacer(minLength: 24)

            VStack(spacing: 6) {
                PrimaryButton(title: "Открыть режим сна", action: onOpenBedtime)
                TextLink(title: "Вернуться к плану", muted: true, showChevron: false, action: onBack)
                    .frame(maxWidth: .infinity)
            }
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 24)
        .foregroundStyle(p.fg)
        .background { SkyBackground(palette: p) }
    }

    private func icon(for status: PlanStepStatus) -> String {
        switch status {
        case .done: "checkmark.circle.fill"
        case .skipped: "minus.circle"
        case .pending: "circle"
        }
    }
}

// MARK: - 09 Bedtime mode

struct BedtimeModeView: View {
    @Environment(AppState.self) private var state
    @Environment(SomnaStore.self) private var store
    let onAlarm: () -> Void
    let onClose: () -> Void
    @State private var breathing = false
    @State private var now = Date()
    private let p = Palette.night

    init(onAlarm: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.onAlarm = onAlarm
        self.onClose = onClose
    }

    /// Evening factors that go straight into today's journal.
    private let logFactors = [FactorCatalog.lateMeal, FactorCatalog.alcohol, FactorCatalog.screenInBed,
                              FactorCatalog.lateWorkout, FactorCatalog.medication]

    private var bedtime: Int { state.plannedBedtime ?? store.snapshot.plan.bedtimeMinutes }

    private var minutesLeft: Int {
        let bedDate = store.snapshot.today.date(atMinutes: bedtime, in: store.snapshot.timeZone)
        return max(0, Int(bedDate.timeIntervalSince(now) / 60))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                topBar

                VStack(spacing: 6) {
                    Text("до сна")
                        .font(SomnaFont.body(15))
                        .foregroundStyle(p.fg2)
                    Text(Fmt.duration(minutesLeft))
                        .font(SomnaFont.display(minutesLeft >= 60 ? 60 : 80, relativeTo: .largeTitle))
                        .tracking(-3.4)
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text("лечь в \(Fmt.clock(bedtime))")
                        .font(SomnaFont.body(15))
                        .foregroundStyle(p.fg2)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
                .accessibilityElement(children: .combine)

                if let next = store.snapshot.plan.actions.first(where: { store.status(of: $0) == .pending }) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Следующий шаг")
                            .font(SomnaFont.body(12, .semibold))
                            .foregroundStyle(p.fg2)
                        Text(next.title)
                            .font(SomnaFont.body(17, .medium))
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Готово") { store.setStatus(.done, for: next) }
                            .font(SomnaFont.body(14, .semibold))
                            .buttonStyle(.plain)
                            .frame(minHeight: 44)
                    }
                    .card(padding: 20, radius: Radius.row, fill: p.surface)
                }

                breathingRow

                VStack(alignment: .leading, spacing: 12) {
                    Text("Отметить за вечер · попадёт в журнал")
                        .font(SomnaFont.body(13, .semibold))
                        .foregroundStyle(p.fg2)
                    FlowLayout(spacing: 8) {
                        ForEach(store.snapshot.factors.filter { logFactors.contains($0.id) }) { factor in
                            let isOn = (store.journalValue(day: store.today, factorID: factor.id) ?? 0) >= 1
                            ChipToggle(title: factor.title, isOn: isOn, icon: factor.systemImage) {
                                store.setJournal(day: store.today, factorID: factor.id, value: isOn ? 0 : 1)
                            }
                        }
                    }
                }

                Button(action: onAlarm) {
                    HStack(spacing: 12) {
                        Image(systemName: "alarm")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(p.fg2)
                        Text(store.settings.alarmEnabled ? "Будильник \(Fmt.clock(store.snapshot.wakeMinutes))" : "Будильник не включён")
                            .font(SomnaFont.body(15, .medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Изменить")
                            .font(SomnaFont.body(14))
                            .foregroundStyle(p.fg2)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(p.fg3)
                    }
                    .padding(.vertical, 14)
                    .overlay(alignment: .top) { Divider1() }
                    .contentShape(Rectangle())
                }
                .buttonStyle(SoftPressStyle())

                PrimaryButton(title: "Я ложусь — проверить будильник", systemImage: "moon.zzz", action: onAlarm)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .foregroundStyle(p.fg)
        .background { Palette.night.bg.ignoresSafeArea() }
        .task {
            while !Task.isCancelled {
                now = Date()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    private var topBar: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(SoftPressStyle())
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Закрыть режим сна")

                Spacer()

                HStack(spacing: 8) {
                    Image(systemName: "moon.fill")
                        .font(.system(size: 14, weight: .medium))
                    Text("Включите фокус «Сон»")
                        .font(SomnaFont.body(14, .medium))
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .glassEffect(.regular, in: .capsule)
                .accessibilityElement(children: .combine)
            }
            .foregroundStyle(p.fg2)
        }
        .padding(.top, 8)
    }

    private var breathingRow: some View {
        HStack(spacing: 16) {
            BreathingCircle(active: breathing)
            VStack(alignment: .leading, spacing: 2) {
                Text("Дыхание 4–6 · 3 мин")
                    .font(SomnaFont.body(15, .medium))
                Text(breathing ? "Вдох на расширении, выдох на сжатии" : "Без звука, только плавный круг")
                    .font(SomnaFont.body(13))
                    .foregroundStyle(p.fg2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button(breathing ? "Стоп" : "Начать") {
                breathing.toggle()
            }
            .font(SomnaFont.body(14, .semibold))
            .buttonStyle(.plain)
            .frame(minWidth: 44, minHeight: 44)
            .hapticDynamic(trigger: breathing) { _, isOn in isOn ? SensoryFeedback.start : SensoryFeedback.stop }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .overlay {
            RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .strokeBorder(p.line, lineWidth: 1)
        }
    }
}
