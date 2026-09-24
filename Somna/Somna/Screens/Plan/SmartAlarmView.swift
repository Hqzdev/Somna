//
//  SmartAlarmView.swift
//  Somna
//
//  10 Wake-up time and alarm. On iPhone this is a plain alarm at a fixed time
//  through AlarmKit. Waking in a light sleep phase is not promised here: it
//  needs a future Apple Watch app that reuses SomnaCore.
//

import SwiftUI
import Foundation

struct SmartAlarmView: View {
    @Environment(AppState.self) private var state
    @Environment(SomnaStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// true when opened from bedtime mode: saving also closes the night screens.
    let closesNight: Bool

    @State private var automatic = true
    @State private var wake = 7 * 60 + 30
    @State private var alarmOn = false
    @State private var isSaving = false
    @State private var loaded = false

    private let p = Palette.night
    private let wakeOptions: [Int] = Array(stride(from: 4 * 60, through: 11 * 60 + 30, by: 5))

    init(closesNight: Bool = false) {
        self.closesNight = closesNight
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    wakeCard
                    bedtimeHint
                    alarmCard

                    IconLine(systemImage: "info.circle",
                             text: "Будильник звонит ровно в заданное время. Будить в лёгкой фазе сна iPhone не умеет — для этого нужны часы, это появится с приложением для Apple Watch.")

                    PrimaryButton(title: closesNight ? "Сохранить и лечь спать" : "Сохранить",
                                  systemImage: closesNight ? "moon" : "checkmark") {
                        Task { await saveAndClose() }
                    }
                    .disabled(isSaving)
                    .opacity(isSaving ? 0.6 : 1)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .background { SkyBackground(palette: p) }
            .foregroundStyle(p.fg)
            .somnaNavTitle("Подъём и будильник", mode: .night)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Закрыть без сохранения")
                }
            }
        }
        .environment(\.palette, p)
        .tint(p.fg)
        .preferredColorScheme(.dark)
        .presentationDragIndicator(.visible)
        .onAppear(perform: load)
    }

    // MARK: Sections

    private var wakeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Подъём")
                .font(SomnaFont.body(13, .medium))
                .foregroundStyle(p.fg2)
            Picker("Подъём", selection: $wake) {
                ForEach(wakeOptions, id: \.self) { m in
                    Text(Fmt.clock(m))
                        .font(SomnaFont.display(28))
                        .tag(m)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 150)
            .onChange(of: wake) { _, new in
                if loaded && new != usualWake { automatic = false }
            }

            if automatic {
                Text(store.snapshot.dataState.isEmpty
                     ? "Данных о сне пока нет, взято 07:30. Прокрутите, чтобы задать своё время."
                     : "Сейчас — ваш обычный подъём по данным Здоровья. Прокрутите, чтобы задать своё время.")
                    .font(SomnaFont.body(12))
                    .foregroundStyle(p.fg2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                TextLink(title: "Считать по обычному подъёму", muted: true, showChevron: false) {
                    automatic = true
                    wake = usualWake
                }
            }
        }
        .card(padding: 20, radius: Radius.hero, fill: p.surface)
    }

    private var bedtimeHint: some View {
        let goal = store.settings.goalMinutes
        let bed = wake + 1440 - goal
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bed.double")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(p.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text("Лечь в \(Fmt.clock(bed))")
                    .font(SomnaFont.body(15, .semibold))
                Text("Чтобы проспать цель \(Fmt.duration(goal)). Время засыпания сюда не входит — ложитесь чуть раньше, если долго засыпаете.")
                    .font(SomnaFont.body(13))
                    .foregroundStyle(p.fg2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .card(padding: 18, radius: Radius.row, fill: p.surface2)
    }

    private var alarmCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            PermissionRow(icon: "alarm", title: "Будильник Somna",
                          why: "Каждый день в \(Fmt.clock(wake)). При первом включении iOS спросит разрешение.",
                          isOn: $alarmOn, showDivider: false)
            if let message = store.alarmMessage {
                Text(message)
                    .font(SomnaFont.body(13))
                    .foregroundStyle(Brand.caution)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 12)
            }
        }
        .padding(.horizontal, 18)
        .card(padding: 0, fill: p.surface)
    }

    // MARK: Actions

    private func load() {
        guard !loaded else { return }
        automatic = store.settings.wakeMinutes == nil
        wake = clamp(store.settings.wakeMinutes ?? store.snapshot.wakeMinutes)
        alarmOn = store.settings.alarmEnabled
        DispatchQueue.main.async { loaded = true }
    }

    private func saveAndClose() async {
        isSaving = true
        await store.saveWake(minutes: automatic ? nil : wake, alarm: alarmOn)
        isSaving = false
        if alarmOn && !store.settings.alarmEnabled {
            // Permission denied or scheduling failed: keep the sheet open with the message.
            alarmOn = false
            return
        }
        dismiss()
        if closesNight {
            state.cover = nil
            state.showToast(alarmOn ? "Будильник на \(Fmt.clock(wake)). Спокойной ночи" : "Спокойной ночи")
        }
    }

    /// Usual wake-up from the last 14 nights, or the default without data.
    private var usualWake: Int {
        let median = store.snapshot.regularity.map { PlanBuilder.roundTo5(Int($0.medianWake.rounded())) }
        return clamp(median ?? SomnaEngine.defaultWakeMinutes)
    }

    private func clamp(_ minutes: Int) -> Int {
        let rounded = (minutes % 1440 + 2) / 5 * 5
        return min(wakeOptions.last ?? rounded, max(wakeOptions.first ?? rounded, rounded))
    }
}
