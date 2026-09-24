//
//  Rows.swift
//  Somna
//
//  Reusable rows from the Pen component library: Metric Row, Insight,
//  Plan Item, Timeline Row, Scale Option, Permission Row, State Block, Chart Header.
//

import SwiftUI
import Foundation

// MARK: - Metric Row

struct MetricRow: View {
    @Environment(\.palette) private var p
    var state: SignalState? = .neutral
    let label: String
    var sub: String?
    let value: String
    var valueColor: Color?
    var showChevron = true
    var showDivider = true
    var action: (() -> Void)?

    var body: some View {
        Group {
            if let action {
                Button(action: action) { content }
                    .buttonStyle(SoftPressStyle())
            } else {
                content
            }
        }
        .overlay(alignment: .bottom) {
            if showDivider { Divider1() }
        }
    }

    private var content: some View {
        HStack(spacing: 12) {
            if let state {
                Circle()
                    .fill(state.dot(p))
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(SomnaFont.body(15, .medium))
                    .foregroundStyle(p.fg)
                if let sub {
                    Text(sub)
                        .font(SomnaFont.body(13))
                        .foregroundStyle(p.fg2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Text(value)
                .font(SomnaFont.body(15, .semibold))
                .foregroundStyle(valueColor ?? p.fg)
                .multilineTextAlignment(.trailing)
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(p.fg3)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 14)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Insight

struct InsightRow: View {
    @Environment(\.palette) private var p
    var state: SignalState = .restore
    let icon: String
    let title: String
    let detail: String
    var metaIcon = "applewatch"
    let meta: String
    var showDivider = true

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            IconTile(systemImage: icon, state: state, size: 36)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(SomnaFont.body(16, .medium))
                    .foregroundStyle(p.fg)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(SomnaFont.body(14))
                    .foregroundStyle(p.fg2)
                    .fixedSize(horizontal: false, vertical: true)
                SourceLabel(icon: metaIcon, text: meta)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) {
            if showDivider { Divider1() }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Plan Item

struct PlanStepRow: View {
    @Environment(\.palette) private var p
    let action: PlanAction
    let status: PlanStepStatus
    let isNext: Bool
    let onToggle: () -> Void
    var onSkip: (() -> Void)?

    private var timeLabel: String {
        let time = action.minutes.map { Fmt.clock($0) }
        switch status {
        case .done: return [time, "ГОТОВО"].compactMap { $0 }.joined(separator: " · ")
        case .skipped: return [time, "ПРОПУЩЕНО"].compactMap { $0 }.joined(separator: " · ")
        case .pending:
            if isNext { return [time, "СЛЕДУЮЩИЙ"].compactMap { $0 }.joined(separator: " · ") }
            return time ?? "СЕГОДНЯ"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                checkButton
                VStack(alignment: .leading, spacing: 4) {
                    Text(timeLabel)
                        .font(SomnaFont.body(13, .semibold))
                        .foregroundStyle(isNext && status == .pending ? p.fg : p.fg2)
                    Text(action.title)
                        .font(SomnaFont.body(16, .medium))
                        .foregroundStyle(status == .pending ? p.fg : p.fg2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(status == .skipped ? "Ничего страшного — завтра план подстроится." : action.reason)
                        .font(SomnaFont.body(14))
                        .foregroundStyle(p.fg2)
                        .fixedSize(horizontal: false, vertical: true)
                    if status != .skipped {
                        SourceLabel(icon: "info.circle", text: action.source)
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
            }
            if isNext && status == .pending, let onSkip {
                Button("Пропустить сегодня", action: onSkip)
                    .font(SomnaFont.body(14, .semibold))
                    .foregroundStyle(p.fg2)
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)
                    .padding(.leading, 42)
            }
        }
        .padding(16)
        .background(p.surface, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
        .overlay {
            if isNext && status == .pending {
                RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                    .strokeBorder(p.fg2, lineWidth: 1.5)
            }
        }
        .opacity(status == .skipped ? 0.6 : 1)
        .hapticDynamic(trigger: status) { _, newStatus in
            if newStatus == .done { return .success }
            if newStatus == .skipped { return Haptic.soft }
            return Haptic.tap
        }
    }

    private var checkButton: some View {
        Button(action: onToggle) {
            ZStack {
                Circle()
                    .strokeBorder(status == .done ? Color.clear : p.lineStrong, lineWidth: 1.5)
                    .background(Circle().fill(status == .done ? Brand.restore : Color.clear))
                if status == .done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                } else if status == .skipped {
                    Image(systemName: "minus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(p.fg2)
                }
            }
            .frame(width: 28, height: 28)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(-8)
        .accessibilityLabel(status == .done ? "Отмечено: \(action.title)" : "Отметить: \(action.title)")
    }
}

// MARK: - Timeline Row

struct TimelineRow: View {
    @Environment(\.palette) private var p
    let time: String
    let icon: String
    let title: String
    let detail: String
    let relation: String
    var state: SignalState = .neutral
    var isLast = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(time)
                .font(SomnaFont.body(13, .semibold))
                .foregroundStyle(p.fg2)
                .frame(width: 44, alignment: .leading)
                .padding(.top, 5)
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(p.fg)
                    .frame(width: 28, height: 28)
                    .background(state.soft(p), in: Circle())
                if !isLast {
                    Rectangle()
                        .fill(p.lineStrong)
                        .frame(width: 1.5)
                        .frame(maxHeight: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(SomnaFont.body(15, .medium))
                    .foregroundStyle(p.fg)
                Text(detail)
                    .font(SomnaFont.body(13))
                    .foregroundStyle(p.fg2)
                    .fixedSize(horizontal: false, vertical: true)
                StatusTag(text: relation, state: state)
                    .padding(.top, 2)
            }
            .padding(.top, 4)
            .padding(.bottom, isLast ? 4 : 20)
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Scale Option

struct ScaleOption: View {
    @Environment(\.palette) private var p
    let number: Int
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text("\(number)")
                    .displayStyle(22, tracking: -0.5)
                    .foregroundStyle(selected ? p.fgInverse : p.fg)
                    .frame(width: 56, height: 56)
                    .background(selected ? p.surfaceInverse : p.bg, in: Circle())
                Text(label)
                    .font(SomnaFont.body(11, selected ? .semibold : .medium))
                    .foregroundStyle(selected ? p.fg : p.fg2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(feedback: nil))
        .haptic(.selection, trigger: selected) { _, isSelected in isSelected }
        .accessibilityLabel("\(number) — \(label)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Selectable Row

/// Multi-choice row: icon tile, title, optional subtitle and a check circle.
struct SelectableRow: View {
    @Environment(\.palette) private var p
    let icon: String
    let title: String
    var subtitle: String?
    let isSelected: Bool
    var showDivider = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(p.accent)
                    .frame(width: 40, height: 40)
                    .background(p.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(SomnaFont.body(15, .medium))
                        .foregroundStyle(p.fg)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle {
                        Text(subtitle)
                            .font(SomnaFont.body(13))
                            .foregroundStyle(p.fg2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(isSelected ? p.fg : p.lineStrong)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 12)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(feedback: nil))
        .haptic(.selection, trigger: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .overlay(alignment: .bottom) {
            if showDivider { Divider1() }
        }
    }
}

// MARK: - Permission Row

struct PermissionRow: View {
    @Environment(\.palette) private var p
    let icon: String
    let title: String
    let why: String
    @Binding var isOn: Bool
    var disabled = false
    var showDivider = true

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(p.accent)
                .frame(width: 40, height: 40)
                .background(p.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SomnaFont.body(15, .medium))
                    .foregroundStyle(p.fg)
                Text(why)
                    .font(SomnaFont.body(13))
                    .foregroundStyle(p.fg2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .tint(Brand.restore)
                .disabled(disabled)
        }
        .padding(.vertical, 14)
        .opacity(disabled ? 0.45 : 1)
        .overlay(alignment: .bottom) {
            if showDivider { Divider1() }
        }
    }
}

// MARK: - State Block

/// «What happened · what is still available · the next step».
struct StateBlock: View {
    @Environment(\.palette) private var p
    let icon: String
    var state: SignalState = .neutral
    let title: String
    let what: String
    var available: String?
    var actionTitle: String?
    var actionIcon: String?
    var isLoading = false
    var action: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                IconTile(systemImage: icon, state: state, size: 40, circle: false)
                Text(title)
                    .font(SomnaFont.body(16, .semibold))
                    .foregroundStyle(p.fg)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(what)
                .font(SomnaFont.body(14))
                .foregroundStyle(p.fg2)
                .fixedSize(horizontal: false, vertical: true)
            if let available {
                IconLine(systemImage: "checkmark.circle", iconColor: Brand.restore, text: available, textColor: p.fg)
            }
            if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(actionTitle ?? "Загрузка…")
                        .font(SomnaFont.body(12))
                        .foregroundStyle(p.fg2)
                }
            } else if let actionTitle {
                SecondaryButton(title: actionTitle, systemImage: actionIcon, fullWidth: false, action: action)
            }
        }
        .card()
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Chart Header

struct ChartHeader<Trailing: View>: View {
    @Environment(\.palette) private var p
    let title: String
    let range: String
    let trailing: Trailing

    init(title: String, range: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.range = range
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SomnaFont.body(15, .semibold))
                    .foregroundStyle(p.fg)
                    .accessibilityAddTraits(.isHeader)
                Text(range)
                    .font(SomnaFont.body(12))
                    .foregroundStyle(p.fg2)
            }
            Spacer(minLength: 8)
            trailing
        }
    }
}

extension ChartHeader where Trailing == EmptyView {
    init(title: String, range: String) {
        self.init(title: title, range: range) { EmptyView() }
    }
}
