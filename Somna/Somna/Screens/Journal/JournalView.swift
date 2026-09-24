//
//  JournalView.swift
//  Somna
//
//  12 Journal: fast logging of sleep-relevant behavior for one day. Values
//  from Apple Health are filled in automatically and can be corrected; an
//  empty row means «unknown», never «no». A factor logged on day D is compared
//  with the night that ends on D + 1. Root of the «Журнал» tab.
//

import SwiftUI
import Foundation

struct JournalView: View {
    @Environment(AppState.self) private var state
    @Environment(SomnaStore.self) private var store
    @State private var selected: DayKey?

    var body: some View {
        let mode = state.timeOfDay
        let p = mode.palette
        let snapshot = store.snapshot
        let day = selected ?? snapshot.today
        SomnaScreen(mode: mode, spacing: 22) {
            header(p, day: day)
            weekStrip(p, snapshot: snapshot, selected: day)
            discoveries(snapshot)

            section(title: "Утро", trailing: Fmt.dayMonth(day)) {
                wellbeingRow(p, day: day)
            }

            ForEach(JournalSection.allCases, id: \.self) { group in
                let factors = snapshot.factors.filter { $0.section == group }
                if !factors.isEmpty {
                    section(title: group.title, trailing: trailing(for: group, day: day)) {
                        ForEach(Array(factors.enumerated()), id: \.element.id) { index, factor in
                            FactorLogRow(factor: factor, day: day, last: index == factors.count - 1)
                        }
                    }
                }
            }

            Button {
                state.sheet = .customFactor
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Добавить свой фактор")
                        .font(SomnaFont.body(15, .semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                        .strokeBorder(p.lineStrong, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(SoftPressStyle())

            IconLine(systemImage: "lock",
                     text: "Записи хранятся только на этом iPhone. Пустая строка значит «не знаю» — такие дни не попадают в сравнения.")
        }
        .toolbar(.hidden, for: .navigationBar)
        .haptic(.success, trigger: store.customFactors.count) { old, new in new > old }
    }

    // MARK: Header

    private func header(_ p: Palette, day: DayKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(day == store.today ? "Сегодня · \(Fmt.dayMonth(day))" : Fmt.dayTitle(day))
                .font(SomnaFont.body(13, .medium))
                .foregroundStyle(p.fg2)
            Text("Журнал")
                .displayStyle(30, tracking: -1)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private func weekStrip(_ p: Palette, snapshot: SomnaSnapshot, selected: DayKey) -> some View {
        let days = (0..<7).map { snapshot.today.adding(days: $0 - 6) }
        return HStack(spacing: 6) {
            ForEach(days, id: \.self) { day in
                let isOn = day == selected
                let hasEntries = hasEntries(day)
                Button {
                    withAnimation(.snappy) { self.selected = day }
                } label: {
                    VStack(spacing: 4) {
                        Text(Fmt.weekdayShort(day))
                            .font(SomnaFont.body(11))
                            .foregroundStyle(isOn ? p.fgInverse : p.fg2)
                        Text(Fmt.dayNumber(day))
                            .font(SomnaFont.body(15, .semibold))
                            .foregroundStyle(isOn ? p.fgInverse : p.fg)
                        Circle()
                            .fill(hasEntries ? Brand.restore : Color.clear)
                            .frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(isOn ? p.surfaceInverse : p.surface,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(Fmt.dayTitle(day))\(hasEntries ? ", есть записи" : "")")
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .haptic(.selection, trigger: selected)
    }

    private func hasEntries(_ day: DayKey) -> Bool {
        if store.checkIn(for: day) != nil { return true }
        let prefix = "\(day.description)|"
        return store.journal.keys.contains { $0.hasPrefix(prefix) }
    }

    private func discoveries(_ snapshot: SomnaSnapshot) -> some View {
        let stable = snapshot.insights(window: 30, outcome: .score).filter(\.isStable)
        let top = stable.max { abs($0.difference ?? 0) < abs($1.difference ?? 0) }
        let experiment = store.activeExperiment.flatMap { active in snapshot.experiments.first { $0.id == active.id } }
        return GroupedList {
            MetricRow(state: stable.isEmpty ? .neutral : .data, label: "Закономерности",
                      sub: top.map { "\($0.title): \($0.outcome.formatDifference($0.difference ?? 0)) к оценке" }
                          ?? "Появятся от \(FactorInsight.minimumPerGroup) ночей с фактором и без",
                      value: stable.isEmpty ? "" : "\(stable.count)") {
                state.push(.insights)
            }
            if let experiment {
                MetricRow(state: .restore, label: "Эксперимент: \(experiment.experiment.title)",
                          sub: "День \(max(0, min(experiment.dayNumber, Experiment.durationDays))) из \(Experiment.durationDays)",
                          value: "идёт", showDivider: false) {
                    state.push(.experimentProgress)
                }
            } else {
                MetricRow(state: .neutral, label: "Эксперимент",
                          sub: "Проверить одну привычку: неделя до и две недели с ней",
                          value: "", showDivider: false) {
                    state.push(.experimentSetup)
                }
            }
        }
    }

    // MARK: Sections

    private func trailing(for group: JournalSection, day: DayKey) -> String {
        switch group {
        case .evening, .night: "влияет на ночь на \(Fmt.dayMonth(day.adding(days: 1)))"
        case .day: Fmt.dayMonth(day)
        }
    }

    private func section<Rows: View>(title: String, trailing: String, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            GroupCaption(text: title, trailing: trailing)
            VStack(spacing: 0) {
                rows()
            }
            .padding(.horizontal, 16)
            .card(padding: 0, radius: 22)
        }
    }

    private func wellbeingRow(_ p: Palette, day: DayKey) -> some View {
        let checkIn = store.checkIn(for: day)
        let canLog = day == (store.snapshot.latest?.dayKey ?? store.today)
        return JournalRowShell(icon: "face.smiling", title: "Самочувствие",
                               sub: checkIn == nil ? "утренняя отметка" : "из утренней отметки", last: true) {
            if let checkIn {
                Text("\(CheckInSheet.labels[checkIn.energy - 1]) · \(checkIn.energy)")
                    .font(SomnaFont.body(15, .semibold))
            } else if canLog {
                Button("Отметить") { state.sheet = .checkIn }
                    .font(SomnaFont.body(14, .semibold))
                    .foregroundStyle(p.accent)
                    .buttonStyle(SoftPressStyle())
                    .frame(minHeight: 44)
            } else {
                Text("—")
                    .font(SomnaFont.body(15, .semibold))
                    .foregroundStyle(p.fg3)
            }
        }
    }
}

// MARK: - Rows

private struct JournalRowShell<Trailing: View>: View {
    @Environment(\.palette) private var p
    let icon: String
    let title: String
    let sub: String
    let last: Bool
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(p.fg2)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(SomnaFont.body(15, .medium))
                    .fixedSize(horizontal: false, vertical: true)
                if !sub.isEmpty {
                    Text(sub)
                        .font(SomnaFont.body(12))
                        .foregroundStyle(p.fg2)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.vertical, 12)
        .frame(minHeight: 56)
        .overlay(alignment: .bottom) {
            if !last { Divider1() }
        }
    }
}

/// One factor for one day: the person's entry wins, then Apple Health.
private struct FactorLogRow: View {
    @Environment(\.palette) private var p
    @Environment(SomnaStore.self) private var store
    let factor: JournalFactor
    let day: DayKey
    let last: Bool

    var body: some View {
        let manual = store.journalValue(day: day, factorID: factor.id)
        let auto = store.snapshot.factorValues[factor.id]?[day]
        let value = manual ?? auto
        JournalRowShell(icon: factor.systemImage, title: factor.title,
                        sub: subtitle(manual: manual, auto: auto), last: last) {
            control(value: value, manual: manual)
        }
        .contextMenu {
            if manual != nil {
                Button("Очистить запись", systemImage: "arrow.uturn.backward") {
                    store.setJournal(day: day, factorID: factor.id, value: nil)
                }
            }
            if factor.isCustom {
                Button("Удалить фактор", systemImage: "trash", role: .destructive) {
                    store.removeCustomFactor(id: factor.id)
                }
            }
        }
    }

    private func subtitle(manual: Double?, auto: Double?) -> String {
        if manual != nil { return factor.isCustom ? "свой фактор · ваша отметка" : "ваша отметка" }
        if auto != nil { return "авто из Здоровья" }
        if factor.healthDerived { return "нет данных в Здоровье" }
        return factor.isCustom ? "свой фактор" : "не отмечено"
    }

    @ViewBuilder
    private func control(value: Double?, manual: Double?) -> some View {
        switch factor.kind {
        case .yesNo:
            YesNoPicker(title: factor.title, value: value.map { $0 >= 1 }) { newValue in
                store.setJournal(day: day, factorID: factor.id, value: newValue.map { $0 ? 1 : 0 })
            }
        case .scale:
            ScalePicker(title: factor.title, value: value.map { Int($0.rounded()) }) { newValue in
                store.setJournal(day: day, factorID: factor.id, value: newValue.map(Double.init))
            }
        case .count:
            CountStepper(value: Int((value ?? 0).rounded()), isKnown: value != nil) { newValue in
                store.setJournal(day: day, factorID: factor.id, value: Double(newValue))
            }
        case .minutes:
            AutoValue(text: value.map { Fmt.duration($0) } ?? "—", isAuto: manual == nil && value != nil)
        case .steps:
            AutoValue(text: value.map { Fmt.number($0) } ?? "—", isAuto: manual == nil && value != nil)
        }
    }
}

private struct YesNoPicker: View {
    @Environment(\.palette) private var p
    let title: String
    let value: Bool?
    let onChange: (Bool?) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach([true, false], id: \.self) { option in
                let isOn = value == option
                Button {
                    onChange(isOn ? nil : option)
                } label: {
                    Text(option ? "Да" : "Нет")
                        .font(SomnaFont.body(13, isOn ? .semibold : .medium))
                        .foregroundStyle(isOn ? p.fg : p.fg2)
                        .frame(minWidth: 44, minHeight: 32)
                        .background(isOn ? (p.isDark ? p.surface2 : Color.white) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title): \(option ? "да" : "нет")")
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(2)
        .background(p.line, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .haptic(.selection, trigger: value)
    }
}

private struct ScalePicker: View {
    @Environment(\.palette) private var p
    let title: String
    let value: Int?
    let onChange: (Int?) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { option in
                let isOn = value == option
                Button {
                    onChange(isOn ? nil : option)
                } label: {
                    Text("\(option)")
                        .font(SomnaFont.body(12, .semibold))
                        .foregroundStyle(isOn ? p.fgInverse : p.fg2)
                        .frame(width: 26, height: 26)
                        .background(isOn ? p.surfaceInverse : p.line, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .frame(width: 30, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title): \(option) из 5")
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .haptic(.selection, trigger: value)
    }
}

private struct CountStepper: View {
    @Environment(\.palette) private var p
    let value: Int
    let isKnown: Bool
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 10) {
            step("minus", label: "Меньше") { onChange(max(0, value - 1)) }
                .disabled(!isKnown || value == 0)
                .opacity(!isKnown || value == 0 ? 0.4 : 1)
            Text(isKnown ? "\(value)" : "—")
                .font(SomnaFont.body(15, .semibold))
                .frame(minWidth: 16)
                .contentTransition(.numericText())
            step("plus", label: "Больше") { onChange(isKnown ? value + 1 : 1) }
        }
        .hapticDynamic(trigger: value) { old, new in
            if new > old { return .increase }
            if new < old { return .decrease }
            return nil
        }
    }

    private func step(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .frame(width: 32, height: 32)
                .background(p.line, in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(-6)
        .accessibilityLabel(label)
    }
}

private struct AutoValue: View {
    @Environment(\.palette) private var p
    let text: String
    let isAuto: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(text)
                .font(SomnaFont.body(15, .semibold))
            if isAuto {
                Text("авто")
                    .font(SomnaFont.body(11, .medium))
                    .foregroundStyle(p.accent)
            }
        }
    }
}

// MARK: - Custom factor sheet

struct CustomFactorSheet: View {
    @Environment(AppState.self) private var state
    @Environment(SomnaStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind = 0

    private let kinds: [FactorKind] = [.yesNo, .scale, .count]

    var body: some View {
        let p = state.timeOfDay.palette
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Что вы хотите отслеживать?")
                    .displayStyle(24, tracking: -0.7)
                TextField("Например: вечерняя прогулка", text: $name)
                    .font(SomnaFont.body(16))
                    .padding(16)
                    .background(p.line, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .onChange(of: name) { _, new in
                        if new.count > 40 { name = String(new.prefix(40)) }
                    }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Как отмечать")
                        .font(SomnaFont.body(13, .semibold))
                        .foregroundStyle(p.fg2)
                    SomnaSegmented(options: ["Да / нет", "Шкала 1–5", "Число"], selection: $kind)
                    Text(kindHint)
                        .font(SomnaFont.body(12))
                        .foregroundStyle(p.fg2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                IconLine(systemImage: "sparkles", iconColor: p.accent,
                         text: "Когда наберётся по \(FactorInsight.minimumPerGroup) ночей с фактором и без него, Somna сравнит их.")
                Spacer()
                PrimaryButton(title: "Добавить фактор", systemImage: "plus") {
                    guard !trimmed.isEmpty else { return }
                    store.addCustomFactor(title: trimmed, kind: kinds[kind])
                    dismiss()
                }
                .disabled(trimmed.isEmpty)
                .opacity(trimmed.isEmpty ? 0.4 : 1)
            }
            .padding(20)
            .foregroundStyle(p.fg)
            .environment(\.palette, p)
            .somnaNavTitle("Свой фактор", mode: state.timeOfDay)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
        .tint(p.fg)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var kindHint: String {
        switch kinds[kind] {
        case .scale: "«С фактором» — дни с оценкой 4 или 5."
        case .count: "«С фактором» — дни, когда было хотя бы 1."
        default: "«С фактором» — дни с ответом «Да»."
        }
    }
}
