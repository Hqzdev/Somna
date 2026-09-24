//
//  OnboardingFlow.swift
//  Somna
//
//  01 Welcome → questionnaire (name → goals → difficulties) → 02 Apple
//  Health: what is read and why, then the system permission sheet in
//  context. The answers stay a draft until the last step; then SomnaStore
//  saves them on this iPhone.
//

import SwiftUI
import Foundation

struct OnboardingFlow: View {
    @Environment(SomnaStore.self) private var store
    @State private var path: [OnboardingStep] = []
    @State private var draft = OnboardingProfile.empty
    @State private var didLoadDraft = false

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeView {
                go(to: .name)
            }
            .navigationDestination(for: OnboardingStep.self) { step in
                destination(step)
            }
        }
        .tint(Brand.ink)
        .onAppear {
            guard !didLoadDraft else { return }
            didLoadDraft = true
            draft = store.profile
        }
    }

    @ViewBuilder
    private func destination(_ step: OnboardingStep) -> some View {
        switch step {
        case .name:
            NameStepView(draft: $draft) { go(to: .goals) }
        case .goals:
            GoalsStepView(draft: $draft) { go(to: .difficulties) }
        case .difficulties:
            DifficultiesStepView(draft: $draft) { go(to: .permissions) }
        case .permissions:
            HealthAccessView {
                store.completeOnboarding(with: draft)
            }
        }
    }

    /// A quick double tap (or Return + «Далее») must not push a step twice.
    private func go(to step: OnboardingStep) {
        guard !path.contains(step) else { return }
        path.append(step)
    }
}

// MARK: - 01 Welcome

struct WelcomeView: View {
    let onStart: () -> Void
    private let p = Palette.dawn

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Brand.dawnGradient)
                    .frame(width: 14, height: 14)
                Text("Somna")
                    .displayStyle(22, tracking: -0.6)
            }
            .padding(.top, 8)
            .accessibilityElement(children: .combine)

            SleepCycleCurve()
                .padding(.top, 24)

            Spacer(minLength: 20)

            VStack(alignment: .leading, spacing: 16) {
                Text("Лучший сон начинается с понятной причины")
                    .displayStyle(38, tracking: -1.6)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("Somna объясняет вашу ночь, собирает короткий план на вечер и показывает, сработал ли он.")
                    .font(SomnaFont.body(17))
                    .foregroundStyle(p.fg2)
                    .fixedSize(horizontal: false, vertical: true)
                loop
            }

            Spacer(minLength: 20)

            VStack(spacing: 14) {
                PrimaryButton(title: "Настроить сон", action: onStart)
                HStack(spacing: 6) {
                    Image(systemName: "lock")
                        .font(.system(size: 12, weight: .medium))
                    Text("Данные остаются под вашим контролем")
                        .font(SomnaFont.body(13))
                }
                .foregroundStyle(p.fg2)
                .frame(maxWidth: .infinity)
            }
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 24)
        .foregroundStyle(p.fg)
        .background { SkyBackground(palette: p) }
        .environment(\.palette, p)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var loop: some View {
        HStack(spacing: 6) {
            ForEach(Array(["Ночь", "Причина", "Действие", "Результат"].enumerated()), id: \.offset) { index, word in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(p.fg3)
                }
                Text(word)
                    .font(SomnaFont.body(12, .semibold))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ночь, причина, действие, результат")
    }
}

// MARK: - 02 Apple Health

struct HealthAccessView: View {
    @Environment(SomnaStore.self) private var store
    let onFinish: () -> Void
    @State private var connecting = false
    private let p = Palette.dawn

    private let readItems: [(String, String, String)] = [
        ("bed.double", "Сон и стадии", "Чтобы собрать ночь: засыпание, пробуждения, стадии, время в кровати"),
        ("heart", "Пульс, пульс в покое, ВСР", "Чтобы сравнить восстановление с вашей личной нормой"),
        ("lungs", "Дыхание, температура запястья, кислород", "Долгосрочные изменения — только как наблюдения, не диагнозы"),
        ("figure.walk", "Шаги, тренировки, дневной свет", "Чтобы проверить, как ваш день связан с ночью"),
        ("cup.and.saucer", "Кофеин и алкоголь", "Только если вы записываете их в Здоровье")
    ]

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    var body: some View {
        SomnaScreen(mode: .dawn) {
            VStack(alignment: .leading, spacing: 10) {
                StepProgress(current: OnboardingStep.total)
                    .padding(.bottom, 8)
                Text("Подключите Apple Health")
                    .displayStyle(32, tracking: -1.1)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("Somna только читает данные и ничего не записывает в Здоровье. Все расчёты — на этом iPhone, без аккаунта и сервера.")
                    .font(SomnaFont.body(15))
                    .foregroundStyle(p.fg2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                GroupCaption(text: "Что читаем и зачем")
                GroupedList {
                    ForEach(Array(readItems.enumerated()), id: \.offset) { index, item in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: item.0)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(p.accent)
                                .frame(width: 40, height: 40)
                                .background(p.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.1)
                                    .font(SomnaFont.body(15, .medium))
                                Text(item.2)
                                    .font(SomnaFont.body(13))
                                    .foregroundStyle(p.fg2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 14)
                        .overlay(alignment: .bottom) {
                            if index < readItems.count - 1 { Divider1() }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                Text("В системном окне можно оставить только нужное. Если что-то выключить, Somna просто не покажет этот показатель.")
                    .font(SomnaFont.body(12))
                    .foregroundStyle(p.fg2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }

            status

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 16, weight: .medium))
                    Text("Somna не ставит диагнозы и не заменяет врача")
                        .font(SomnaFont.body(14, .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Оценки — объяснимые правила на ваших данных, а не медицинская модель. Экспорт и удаление — в Профиле.")
                    .font(SomnaFont.body(13))
                    .foregroundStyle(p.fg2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .card(padding: 18, radius: Radius.row, fill: p.surface2)

            #if DEBUG
            VStack(alignment: .leading, spacing: 8) {
                GroupCaption(text: "Отладка")
                Toggle(isOn: Binding(get: { store.usesDemoData }, set: { store.setDemoData($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Демо-данные для симулятора")
                            .font(SomnaFont.body(15, .medium))
                        Text("45 синтетических ночей через тот же расчёт. Только в отладочной сборке.")
                            .font(SomnaFont.body(12))
                            .foregroundStyle(p.fg2)
                    }
                }
                .tint(Brand.restore)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .card(padding: 0)
            }
            #endif

            actions
        }
        .somnaNavTitle("Шаг \(OnboardingStep.total) из \(OnboardingStep.total)", mode: .dawn)
        .haptic(.success, trigger: store.healthRequested) { _, requested in requested }
    }

    /// What is ready right after the Health import. The history of the last
    /// 120 days is already read, so nothing here asks to wait a week.
    private var importSummary: String {
        let snapshot = store.snapshot
        var parts: [String] = []
        if let score = snapshot.lastRecorded?.score {
            parts.append("Последняя ночь — \(score.value) из 100.")
        }
        if snapshot.regularity != nil {
            parts.append("Норма, режим и недобор уже посчитаны по вашей истории.")
        } else if snapshot.regularityNightsMissing > 0 {
            parts.append("Оценка работает с первой ночи, личная норма и режим — через \(Fmt.nights(snapshot.regularityNightsMissing)).")
        }
        parts.append("План на сегодня готов: лечь в \(Fmt.clock(snapshot.plan.bedtimeMinutes)).")
        return parts.joined(separator: " ")
    }

    @ViewBuilder
    private var status: some View {
        if !store.healthAvailable {
            StateBlock(icon: "heart.slash", state: .caution, title: "Здоровье недоступно на этом устройстве",
                       what: "Somna сможет работать с журналом и утренними отметками, но без данных о сне расчётов не будет.")
        } else if store.healthRequested || store.usesDemoData {
            let nights = store.snapshot.reports.count
            if store.sync == .syncing {
                StateBlock(icon: "arrow.triangle.2.circlepath", state: .data, title: "Читаем данные из Здоровья",
                           what: "Собираем ночи за последние 120 дней.", actionTitle: "Это займёт несколько секунд", isLoading: true)
            } else if nights > 0 {
                StateBlock(icon: "checkmark", state: .restore, title: "Найдено \(Fmt.nights(nights))",
                           what: importSummary)
            } else {
                StateBlock(icon: "moon.zzz", state: .neutral, title: "Данных о сне пока нет",
                           what: "Если вы только что разрешили доступ, ночь появится после сна с Apple Watch или с режимом «Сон» на iPhone. Если доступ к сну выключен, его можно включить в Настройках → Здоровье → Доступ к данным.",
                           available: "План на сегодня уже готов: лечь в \(Fmt.clock(store.snapshot.plan.bedtimeMinutes)). Журнал и утренние отметки работают и без данных")
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 4) {
            if store.healthAvailable && !store.healthRequested && !store.usesDemoData {
                PrimaryButton(title: connecting ? "Открываем запрос…" : "Подключить Apple Health", systemImage: "heart.text.square") {
                    connecting = true
                    Task {
                        await store.connectHealth()
                        connecting = false
                    }
                }
                .disabled(connecting)
                TextLink(title: "Позже", muted: true, showChevron: false, action: onFinish)
                    .frame(maxWidth: .infinity)
            } else {
                PrimaryButton(title: "Готово", action: onFinish)
            }
        }
    }
}
