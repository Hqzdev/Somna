//
//  QuestionnaireViews.swift
//  Somna
//
//  Start questionnaire: 1 name → 2 sleep goals → 3 what gets in the way,
//  then 4 data & permissions (OnboardingFlow.swift). Answers stay a draft
//  until the flow is finished. The same pickers are reused in Profile to
//  edit the saved answers.
//

import SwiftUI
import UIKit
import Foundation

nonisolated enum OnboardingStep: Hashable {
    case name, goals, difficulties, permissions

    static let total = 4
}

// MARK: - Step scaffold

/// Progress bar in four segments.
struct StepProgress: View {
    @Environment(\.palette) private var p
    let current: Int
    var total: Int = OnboardingStep.total

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index < current ? p.fg : p.line)
                    .frame(height: 4)
            }
        }
        .animation(.easeOut(duration: 0.25), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Шаг \(current) из \(total)")
    }
}

/// One questionnaire screen: progress, title, content and a bottom action bar
/// that stays above the keyboard.
struct QuestionnaireStep<Content: View>: View {
    private let p = Palette.dawn
    let step: Int
    let title: String
    let subtitle: String
    let canContinue: Bool
    let hint: String?
    let skipTitle: String?
    let onSkip: (() -> Void)?
    let onContinue: () -> Void
    let content: Content

    init(step: Int, title: String, subtitle: String,
         canContinue: Bool = true, hint: String? = nil,
         skipTitle: String? = nil, onSkip: (() -> Void)? = nil,
         onContinue: @escaping () -> Void,
         @ViewBuilder content: () -> Content) {
        self.step = step
        self.title = title
        self.subtitle = subtitle
        self.canContinue = canContinue
        self.hint = hint
        self.skipTitle = skipTitle
        self.onSkip = onSkip
        self.onContinue = onContinue
        self.content = content()
    }

    var body: some View {
        SomnaScreen(mode: .dawn, spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                StepProgress(current: step)
                    .padding(.bottom, 4)
                Text(title)
                    .displayStyle(32, tracking: -1.1)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(SomnaFont.body(15))
                    .foregroundStyle(p.fg2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
        .somnaNavTitle("Шаг \(step) из \(OnboardingStep.total)", mode: .dawn)
    }

    private var actionBar: some View {
        VStack(spacing: 4) {
            if let hint, !canContinue {
                Text(hint)
                    .font(SomnaFont.body(13))
                    .foregroundStyle(p.fg2)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 6)
            }
            PrimaryButton(title: "Далее", action: onContinue)
                .disabled(!canContinue)
                .opacity(canContinue ? 1 : 0.4)
            if let skipTitle, let onSkip {
                TextLink(title: skipTitle, muted: true, showChevron: false, action: onSkip)
            }
        }
        .padding(.horizontal, Space.gutter)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(stops: [.init(color: p.bg.opacity(0), location: 0),
                                   .init(color: p.bg, location: 0.3)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
        .foregroundStyle(p.fg)
        .environment(\.palette, p)
    }
}

// MARK: - 1 · Name

struct NameStepView: View {
    @Binding var draft: OnboardingProfile
    let onNext: () -> Void

    var body: some View {
        QuestionnaireStep(step: 1,
                          title: "Как к вам обращаться?",
                          subtitle: "Имя нужно только для приветствия и хранится на этом iPhone.",
                          skipTitle: "Пропустить",
                          onSkip: {
                              draft.name = ""
                              onNext()
                          },
                          onContinue: onNext) {
            NameField(name: $draft.name, autofocus: true, onSubmit: onNext)
        }
    }
}

// MARK: - 2 · Goals

struct GoalsStepView: View {
    @Binding var draft: OnboardingProfile
    let onNext: () -> Void

    var body: some View {
        QuestionnaireStep(step: 2,
                          title: "Чего вы хотите от сна?",
                          subtitle: "Можно выбрать несколько целей — от них будет зависеть план на вечер.",
                          canContinue: draft.hasGoals,
                          hint: "Выберите хотя бы одну цель",
                          onContinue: onNext) {
            VStack(alignment: .leading, spacing: 8) {
                GroupCaption(text: "Цели", trailing: draft.goals.isEmpty ? "не выбрано" : "выбрано: \(draft.goals.count)")
                GoalsPicker(goals: $draft.goals)
            }
        }
    }
}

// MARK: - 3 · Difficulties

struct DifficultiesStepView: View {
    @Binding var draft: OnboardingProfile
    let onNext: () -> Void

    var body: some View {
        QuestionnaireStep(step: 3,
                          title: "Что мешает спать?",
                          subtitle: "Отметьте то, что бывает хотя бы раз в неделю. Если ничего не подходит — просто нажмите «Далее».",
                          onContinue: onNext) {
            DifficultiesPicker(difficulties: $draft.difficulties, note: $draft.note)
        }
    }
}

// MARK: - Reusable inputs

struct NameField: View {
    @Environment(\.palette) private var p
    @Binding var name: String
    let autofocus: Bool
    let onSubmit: () -> Void
    @FocusState private var focused: Bool

    init(name: Binding<String>, autofocus: Bool = false, onSubmit: @escaping () -> Void = {}) {
        self._name = name
        self.autofocus = autofocus
        self.onSubmit = onSubmit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Имя", text: $name, prompt: Text("Ваше имя").foregroundStyle(p.fg3))
                .font(SomnaFont.body(17))
                .textContentType(.givenName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .focused($focused)
                .onSubmit(onSubmit)
                .padding(.horizontal, 18)
                .frame(minHeight: 56)
                .background(p.surface, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                        .strokeBorder(focused ? p.fg : p.lineStrong, lineWidth: focused ? 1.5 : 1)
                }
                .onChange(of: name) { _, newValue in
                    if newValue.count > OnboardingProfile.nameLimit {
                        name = String(newValue.prefix(OnboardingProfile.nameLimit))
                    }
                }
                .accessibilityLabel("Имя")
                .accessibilityHint("Необязательно")
            Text("Необязательно. Без имени приветствие будет просто «Доброе утро».")
                .font(SomnaFont.body(13))
                .foregroundStyle(p.fg2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task {
            guard autofocus else { return }
            try? await Task.sleep(for: .milliseconds(450))
            focused = true
        }
    }
}

struct GoalsPicker: View {
    @Binding var goals: Set<SleepGoal>

    var body: some View {
        GroupedList {
            ForEach(SleepGoal.allCases) { goal in
                SelectableRow(icon: goal.systemImage, title: goal.title, subtitle: goal.subtitle,
                              isSelected: goals.contains(goal),
                              showDivider: goal != SleepGoal.allCases.last) {
                    if goals.contains(goal) {
                        goals.remove(goal)
                    } else {
                        goals.insert(goal)
                    }
                }
            }
        }
    }
}

struct DifficultiesPicker: View {
    @Environment(\.palette) private var p
    @Binding var difficulties: Set<SleepDifficulty>
    @Binding var note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            FlowLayout(spacing: 8) {
                ForEach(SleepDifficulty.allCases) { item in
                    ChipToggle(title: item.title, isOn: difficulties.contains(item)) {
                        if difficulties.contains(item) {
                            difficulties.remove(item)
                        } else {
                            difficulties.insert(item)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                GroupCaption(text: "Другое", trailing: "\(note.count) / \(OnboardingProfile.noteLimit)")
                TextField("Другое", text: $note, prompt: Text("Коротко, своими словами").foregroundStyle(p.fg3), axis: .vertical)
                    .font(SomnaFont.body(16))
                    .lineLimit(1...3)
                    .submitLabel(.done)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .frame(minHeight: 56)
                    .background(p.surface, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                            .strokeBorder(p.lineStrong, lineWidth: 1)
                    }
                    .onChange(of: note) { _, newValue in
                        // Return must not add line breaks; keep it one short line.
                        let cleaned = String(newValue.replacingOccurrences(of: "\n", with: " ")
                            .prefix(OnboardingProfile.noteLimit))
                        if cleaned != newValue { note = cleaned }
                    }
                    .accessibilityLabel("Другое")
                    .accessibilityHint("Необязательно, до \(OnboardingProfile.noteLimit) символов")
            }

            IconLine(systemImage: "info.circle",
                     text: "Это ваше описание, а не медицинская оценка. Somna не ставит диагнозы.")
        }
    }
}

// MARK: - Edit saved answers (from Profile)

struct ProfileAnswersSheet: View {
    @Environment(AppState.self) private var state
    @Environment(SomnaStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft = OnboardingProfile.empty
    @State private var loaded = false

    var body: some View {
        let mode = state.timeOfDay
        let p = mode.palette
        NavigationStack {
            SomnaScreen(mode: mode, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    GroupCaption(text: "Имя")
                    NameField(name: $draft.name)
                }
                VStack(alignment: .leading, spacing: 8) {
                    GroupCaption(text: "Цели сна", trailing: draft.goals.isEmpty ? "не выбрано" : "выбрано: \(draft.goals.count)")
                    GoalsPicker(goals: $draft.goals)
                    if !draft.hasGoals {
                        Text("Выберите хотя бы одну цель, чтобы сохранить")
                            .font(SomnaFont.body(13))
                            .foregroundStyle(p.fg2)
                            .padding(.horizontal, 4)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    GroupCaption(text: "Что мешает спать")
                    DifficultiesPicker(difficulties: $draft.difficulties, note: $draft.note)
                }
                Text("Ответы хранятся только на этом iPhone.")
                    .font(SomnaFont.body(12))
                    .foregroundStyle(p.fg3)
                    .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .somnaNavTitle("Ваши ответы", mode: mode)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        store.updateProfile(draft)
                        state.showToast("Ответы сохранены на этом iPhone")
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!draft.hasGoals)
                }
            }
        }
        .tint(p.fg)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(loaded && draft.normalized(completed: true) != store.profile)
        .onAppear {
            guard !loaded else { return }
            draft = store.profile
            loaded = true
        }
    }
}
