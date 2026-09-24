//
//  CheckInSheet.swift
//  Somna
//
//  04 Morning check-in: energy, optional independent sleep-quality rating,
//  tags and note.
//  Saved on this iPhone for the night that just ended; used by the sleep-need
//  suggestion and experiments on «утренняя энергия».
//

import SwiftUI
import Foundation

struct CheckInSheet: View {
    @Environment(AppState.self) private var state
    @Environment(SomnaStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var energy: Int?
    @State private var quality: Int?
    @State private var tags: Set<String> = []
    @State private var note = ""
    @FocusState private var noteFocused: Bool

    static let labels = ["Разбит", "Вяло", "Нормально", "Бодро", "Отлично"]
    private let tagOptions = ["Разбитость", "Сонливость", "Ясная голова", "Боль в голове", "Хорошее настроение"]

    var body: some View {
        let p = state.timeOfDay.palette
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Как вы себя чувствуете после пробуждения?")
                            .displayStyle(25, tracking: -0.8)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Text(subtitle)
                            .font(SomnaFont.body(13))
                            .foregroundStyle(p.fg2)
                    }
                    Spacer(minLength: 0)
                    GlassIconButton(systemImage: "xmark", label: "Закрыть") { dismiss() }
                }

                HStack(spacing: 6) {
                    ForEach(1...5, id: \.self) { value in
                        ScaleOption(number: value, label: CheckInSheet.labels[value - 1], selected: energy == value) {
                            withAnimation(.snappy(duration: 0.2)) { energy = value }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Как вы спали? · по желанию")
                        .font(SomnaFont.body(13, .semibold))
                        .foregroundStyle(p.fg2)
                    HStack(spacing: 6) {
                        ForEach(1...5, id: \.self) { value in
                            ScaleOption(number: value, label: ["Плохо", "Неважно", "Обычно", "Хорошо", "Отлично"][value - 1], selected: quality == value) {
                                withAnimation(.snappy(duration: 0.2)) { quality = quality == value ? nil : value }
                            }
                        }
                    }
                    Text("Эта оценка проверяет расчёт Somna и не меняет балл сегодняшней ночи.")
                        .font(SomnaFont.body(12))
                        .foregroundStyle(p.fg2)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Что ещё заметили? · по желанию")
                        .font(SomnaFont.body(13, .semibold))
                        .foregroundStyle(p.fg2)
                    FlowLayout(spacing: 8) {
                        ForEach(tagOptions, id: \.self) { tag in
                            ChipToggle(title: tag, isOn: tags.contains(tag)) {
                                if tags.contains(tag) { tags.remove(tag) } else { tags.insert(tag) }
                            }
                        }
                    }
                }

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "pencil.line")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(p.fg3)
                        .padding(.top, 2)
                    TextField("Заметка: например, «разбудил шум за окном»", text: $note, axis: .vertical)
                        .font(SomnaFont.body(15))
                        .lineLimit(1...4)
                        .focused($noteFocused)
                }
                .padding(16)
                .background(p.line, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                IconLine(systemImage: "sparkles", iconColor: p.accent,
                         text: "Отметки помогают проверять оценку сна и рекомендации. Их видите только вы.")

                PrimaryButton(title: "Сохранить", systemImage: nil) {
                    guard let energy else { return }
                    store.saveCheckIn(day: day, energy: energy, quality: quality, tags: tagOptions.filter(tags.contains), note: note)
                    dismiss()
                    state.showToast("Сохранено — это уточнит рекомендации")
                }
                .disabled(energy == nil)
                .opacity(energy == nil ? 0.4 : 1)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .foregroundStyle(p.fg)
        .tint(p.fg)
        .environment(\.palette, p)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            guard let saved = store.checkIn(for: day) else { return }
            energy = saved.energy
            quality = saved.quality
            tags = Set(saved.tags)
            note = saved.note
        }
    }

    /// The night being rated: the latest one, or today when none is recorded.
    private var day: DayKey {
        store.snapshot.latest?.dayKey ?? store.snapshot.today
    }

    private var subtitle: String {
        guard let night = store.snapshot.latest?.night else { return "Ночь ещё не записана — отметка сохранится на сегодня" }
        return "Проснулись в \(Fmt.time(night.sleepEnd, night.timeZone)) · \(Fmt.duration(night.asleepMinutes)) сна"
    }
}
