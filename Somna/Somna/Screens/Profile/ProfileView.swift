//
//  ProfileView.swift
//  Somna
//
//  18 Profile and settings: questionnaire, sleep goal, wake-up and alarm,
//  data sources, export and deletion. Everything is stored on this iPhone
//  only; deleting never touches Apple Health. Debug builds add demo controls.
//

import SwiftUI
import Foundation

struct ProfileView: View {
    @Environment(AppState.self) private var state
    @Environment(SomnaStore.self) private var store
    @State private var confirmDelete = false
    @State private var exportURLs: [URL] = []
    @State private var exportError: String?
    @State private var isDeleting = false

    var body: some View {
        let mode = state.timeOfDay
        let p = mode.palette
        let snapshot = store.snapshot
        let profile = store.profile
        SomnaScreen(mode: mode) {
            HStack(spacing: 14) {
                avatar(p)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.displayName ?? "Ваш профиль")
                        .displayStyle(26, tracking: -0.8)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(historyLine(snapshot))
                        .font(SomnaFont.body(13))
                        .foregroundStyle(p.fg2)
                }
            }

            group("Анкета") {
                MetricRow(state: nil, label: "Имя", value: profile.displayName ?? "Не указано",
                          valueColor: profile.displayName == nil ? p.fg2 : nil) { editAnswers() }
                MetricRow(state: nil, label: "Цели сна", sub: profile.goalsSummary, value: "") { editAnswers() }
                MetricRow(state: nil, label: "Что мешает спать", sub: profile.difficultiesSummary, value: "", showDivider: false) { editAnswers() }
            }

            group("Цель и режим") {
                MetricRow(state: snapshot.needSuggestion == nil ? nil : .data, label: "Цель сна",
                          sub: snapshot.needSuggestion.map { "Можно \(Fmt.duration($0.suggestedMinutes)) — по \($0.basedOnNights) бодрым утрам" }
                              ?? "Сколько сна нужно вам. Время засыпания не входит",
                          value: Fmt.duration(store.settings.goalMinutes)) {
                    state.sheet = .sleepGoal
                }
                MetricRow(state: nil, label: "Подъём",
                          sub: store.settings.alarmEnabled ? "Будильник Somna включён" : "Будильник Somna выключен",
                          value: store.settings.wakeMinutes == nil ? "авто · \(Fmt.clock(snapshot.wakeMinutes))" : Fmt.clock(snapshot.wakeMinutes)) {
                    state.sheet = .alarm
                }
                MetricRow(state: nil, label: "Лечь по плану", sub: "Подъём минус цель сна",
                          value: Fmt.clock(snapshot.plan.bedtimeMinutes), showChevron: false, showDivider: false)
            }

            group("Данные") {
                MetricRow(state: healthState, label: "Apple Health", sub: healthLine, value: "") {
                    state.push(.dataSources)
                }
                MetricRow(state: nil, label: "Источники сна",
                          sub: snapshot.sources.isEmpty ? "Пока не найдены" : snapshot.sources.map(\.name).joined(separator: ", "),
                          value: snapshot.sources.isEmpty ? "" : "\(snapshot.sources.count)", showDivider: false) {
                    state.push(.dataSources)
                }
            }

            group("Отклик") {
                toggleRow(p, icon: "iphone.radiowaves.left.and.right", title: "Тактильный отклик",
                          sub: "Лёгкая вибрация на нажатия, выбор и завершение шагов",
                          isOn: Binding(get: { store.settings.hapticsEnabled }, set: { store.setHaptics($0) }),
                          last: true)
            }

            group("Приватность") {
                exportRow(p)
                MetricRow(state: nil, label: "Удалить все данные Somna",
                          sub: "Анкета, журнал, эксперименты, настройки и кэш. Apple Health не трогаем",
                          value: isDeleting ? "…" : "", valueColor: Brand.attention, showDivider: false) {
                    confirmDelete = true
                }
            }

            IconLine(systemImage: "lock",
                     text: "Somna работает без аккаунта и сервера: данные читаются из Здоровья и считаются на этом iPhone. Ничего не отправляется.")

            #if DEBUG
            debugControls(p)
            #endif

            Text("Somna · формулы \(SomnaSnapshot.formulaVersion) · не является медицинским изделием")
                .font(SomnaFont.body(12))
                .foregroundStyle(p.fg3)
                .frame(maxWidth: .infinity)
        }
        .toolbar(.hidden, for: .navigationBar)
        .haptic(Haptic.primary, trigger: store.settings.hapticsEnabled) { _, isOn in isOn }
        .haptic(.warning, trigger: confirmDelete) { _, shown in shown }
        .confirmationDialog("Удалить все данные Somna?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                Task { await deleteAll() }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Анкета, журнал, отметки, эксперименты, настройки и будильник будут удалены с этого iPhone. Данные в Apple Health останутся.")
        }
    }

    // MARK: Pieces

    private func historyLine(_ snapshot: SomnaSnapshot) -> String {
        guard let first = snapshot.reports.first?.dayKey else { return "Ночей пока нет" }
        return "Ночи с \(Fmt.dayMonth(first)) · \(Fmt.nights(snapshot.dataState.nights))"
    }

    private var healthState: SignalState? {
        if store.usesDemoData { return .caution }
        if !store.healthRequested { return .neutral }
        if case .failed = store.sync { return .attention }
        return .restore
    }

    private var healthLine: String {
        if store.usesDemoData { return "Демо-данные вместо Здоровья" }
        if !store.healthAvailable { return "Недоступно на этом устройстве" }
        if !store.healthRequested { return "Не подключено" }
        switch store.sync {
        case .syncing: return "Обновляем…"
        case .failed(let message): return message
        case .idle: return store.lastSync.map { "Обновлено \(Fmt.relative($0))" } ?? "Подключено"
        }
    }

    private func editAnswers() {
        state.sheet = .profileAnswers
    }

    @ViewBuilder
    private func exportRow(_ p: Palette) -> some View {
        if exportURLs.isEmpty {
            MetricRow(state: nil, label: "Экспорт данных",
                      sub: exportError ?? "CSV: ночи, журнал, отметки, эксперименты + анкета",
                      value: "") {
                do {
                    exportURLs = try store.exportFiles()
                    exportError = nil
                } catch {
                    exportError = "Не удалось подготовить файлы"
                }
            }
        } else {
            ShareLink(items: exportURLs) {
                HStack(spacing: 12) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Поделиться файлами")
                            .font(SomnaFont.body(15, .medium))
                        Text("\(exportURLs.count) файлов готово")
                            .font(SomnaFont.body(12))
                            .foregroundStyle(p.fg2)
                    }
                    Spacer()
                }
                .padding(.vertical, 12)
                .frame(minHeight: 56)
                .overlay(alignment: .bottom) { Divider1() }
                .contentShape(Rectangle())
            }
            .buttonStyle(SoftPressStyle())
        }
    }

    private func deleteAll() async {
        isDeleting = true
        await store.deleteAllData()
        isDeleting = false
        exportURLs = []
        state.resetNavigation()
        state.showToast("Данные Somna удалены")
    }

    /// First letter of the name, or a moon when the name was skipped.
    private func avatar(_ p: Palette) -> some View {
        Group {
            if let initial = store.profile.displayName?.first {
                Text(String(initial).uppercased())
                    .displayStyle(24, tracking: -0.5)
            } else {
                Image(systemName: "moon.stars")
                    .font(.system(size: 20, weight: .medium))
            }
        }
        .foregroundStyle(p.fgInverse)
        .frame(width: 56, height: 56)
        .background(p.surfaceInverse, in: Circle())
        .accessibilityHidden(true)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            GroupCaption(text: title)
            GroupedList {
                content()
            }
        }
    }

    private func toggleRow(_ p: Palette, icon: String, title: String, sub: String, isOn: Binding<Bool>, last: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(SomnaFont.body(15, .medium))
                Text(sub)
                    .font(SomnaFont.body(12))
                    .foregroundStyle(p.fg2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .tint(Brand.restore)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            if !last { Divider1() }
        }
    }

    // MARK: Debug

    #if DEBUG
    private func debugControls(_ p: Palette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            GroupCaption(text: "Отладка · только в Debug-сборке")
            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: Binding(get: { store.usesDemoData }, set: { store.setDemoData($0) })) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Демо-данные")
                            .font(SomnaFont.body(15, .medium))
                        Text("90 синтетических ночей вместо Здоровья — для Simulator")
                            .font(SomnaFont.body(12))
                            .foregroundStyle(p.fg2)
                    }
                }
                .tint(Brand.restore)
                Divider1()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Время суток интерфейса")
                        .font(SomnaFont.body(15, .medium))
                    SomnaSegmented(options: ["Авто", "Рассвет", "Закат", "Сумерки", "Ночь"], selection: timeBinding)
                }
            }
            .card(padding: 18)
        }
    }

    private var timeBinding: Binding<Int> {
        Binding(
            get: {
                guard let t = state.timeOverride else { return 0 }
                return (TimeOfDay.allCases.firstIndex(of: t) ?? 0) + 1
            },
            set: { index in
                state.timeOverride = index == 0 ? nil : TimeOfDay.allCases[index - 1]
            }
        )
    }
    #endif
}

// MARK: - Data sources

struct DataSourcesView: View {
    @Environment(AppState.self) private var state
    @Environment(SomnaStore.self) private var store

    private let readTypes = [
        ("bed.double", "Сон и время в кровати"),
        ("heart", "Пульс и пульс в покое"),
        ("waveform.path.ecg", "Вариабельность пульса (ВСР)"),
        ("lungs", "Частота дыхания"),
        ("thermometer.medium", "Температура запястья"),
        ("drop", "Кислород в крови"),
        ("figure.walk", "Шаги, тренировки, дневной свет"),
        ("cup.and.saucer", "Кофеин и алкоголь, если вы их записываете")
    ]

    var body: some View {
        let mode = state.timeOfDay
        let p = mode.palette
        let sources = store.snapshot.sources
        SomnaScreen(mode: mode) {
            healthCard(p)

            VStack(alignment: .leading, spacing: 8) {
                GroupCaption(text: "Источники сна · по приоритету")
                if sources.isEmpty {
                    StateBlock(icon: "bed.double", state: .neutral, title: "Источники пока не найдены",
                               what: "Как только в Здоровье появятся записи сна, здесь будет видно, откуда они — часы, iPhone или другое приложение.")
                } else {
                    GroupedList {
                        ForEach(Array(sources.enumerated()), id: \.element.id) { index, source in
                            SourceOrderRow(source: source, index: index, count: sources.count) { from, to in
                                var ordered = sources
                                ordered.swapAt(from, to)
                                store.setSourceOrder(ordered)
                            }
                        }
                    }
                    Text("Если два источника записали одну ночь, Somna берёт ночь того, кто выше. Время в кровати никогда не считается сном.")
                        .font(SomnaFont.body(12))
                        .foregroundStyle(p.fg2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                GroupCaption(text: "Что Somna читает")
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(readTypes.indices, id: \.self) { i in
                        IconLine(systemImage: readTypes[i].0, text: readTypes[i].1, textColor: p.fg)
                    }
                    Divider1()
                    Text("Только чтение: Somna ничего не записывает в Здоровье. Датчики спальни (HomeKit) пока не подключаются — отмечайте жару, шум и свет в журнале.")
                        .font(SomnaFont.body(12))
                        .foregroundStyle(p.fg2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .card(padding: 18)
            }
        }
        .somnaNavTitle("Данные и доступы", mode: mode)
        .refreshable { await store.refreshHealth() }
    }

    @ViewBuilder
    private func healthCard(_ p: Palette) -> some View {
        if store.usesDemoData {
            StateBlock(icon: "testtube.2", state: .caution, title: "Включены демо-данные",
                       what: "Расчёты идут на синтетических ночах. Выключите демо в профиле, чтобы читать Здоровье.")
        } else if !store.healthAvailable {
            StateBlock(icon: "heart.slash", state: .neutral, title: "Здоровье недоступно",
                       what: "На этом устройстве нет Apple Health. Журнал и отметки работают и без него.")
        } else if !store.healthRequested {
            StateBlock(icon: "heart.text.square", state: .data, title: "Здоровье не подключено",
                       what: "Somna попросит доступ только на чтение. Каждый тип можно разрешить или запретить отдельно.",
                       actionTitle: "Подключить Здоровье", actionIcon: "heart",
                       isLoading: store.sync == .syncing) {
                Task { await store.connectHealth() }
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    IconTile(systemImage: "heart.fill", state: .restore, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apple Health")
                            .font(SomnaFont.body(15, .semibold))
                        Text(syncLine)
                            .font(SomnaFont.body(12))
                            .foregroundStyle(p.fg2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button {
                        Task { await store.refreshHealth() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(SoftPressStyle())
                    .disabled(store.sync == .syncing)
                    .accessibilityLabel("Обновить из Здоровья")
                }
                Text("iOS не сообщает приложению, какие типы вы запретили. Если каких-то данных нет — проверьте Настройки → Здоровье → Доступ к данным → Somna.")
                    .font(SomnaFont.body(12))
                    .foregroundStyle(p.fg2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .card(padding: 18)
        }
    }

    private var syncLine: String {
        switch store.sync {
        case .syncing: "Обновляем…"
        case .failed(let message): message
        case .idle: store.lastSync.map { "Обновлено \(Fmt.relative($0)) · только чтение" } ?? "Подключено · только чтение"
        }
    }
}

private struct SourceOrderRow: View {
    @Environment(\.palette) private var p
    let source: DetectedSource
    let index: Int
    let count: Int
    let move: (Int, Int) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(SomnaFont.body(13, .semibold))
                .foregroundStyle(p.fg2)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(source.name)
                    .font(SomnaFont.body(15, .medium))
                Text("\(source.sampleCount) записей\(source.hasStages ? " · со стадиями" : "")")
                    .font(SomnaFont.body(12))
                    .foregroundStyle(p.fg2)
            }
            Spacer(minLength: 8)
            arrow("chevron.up", label: "Выше", enabled: index > 0) { move(index, index - 1) }
            arrow("chevron.down", label: "Ниже", enabled: index < count - 1) { move(index, index + 1) }
        }
        .padding(.vertical, 8)
        .frame(minHeight: 56)
        .overlay(alignment: .bottom) {
            if index < count - 1 { Divider1() }
        }
    }

    private func arrow(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .frame(width: 32, height: 32)
                .background(p.line, in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .accessibilityLabel("\(source.name): \(label)")
    }
}
