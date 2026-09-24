//
//  Components.swift
//  Somna
//
//  Screen scaffold, buttons, cards, tags and small building blocks.
//  Color is read from the time-of-day palette in the environment.
//

import SwiftUI
import Foundation

// MARK: - Screen scaffold

/// Scrollable screen with the time-of-day sky, gutters and palette.
struct SomnaScreen<Content: View>: View {
    let mode: TimeOfDay
    let spacing: CGFloat
    let content: Content

    init(mode: TimeOfDay, spacing: CGFloat = Space.section, @ViewBuilder content: () -> Content) {
        self.mode = mode
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        let p = mode.palette
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) {
                content
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, 8)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background { SkyBackground(palette: p) }
        .foregroundStyle(p.fg)
        .tint(p.fg)
        .environment(\.palette, p)
    }
}

/// Background: palette sky fading into the page color over the top ~440 pt.
struct SkyBackground: View {
    let palette: Palette
    var depth: CGFloat = 440

    var body: some View {
        palette.bg
            .overlay(alignment: .top) {
                LinearGradient(colors: [palette.sky, palette.bg], startPoint: .top, endPoint: .bottom)
                    .frame(height: depth)
            }
            .ignoresSafeArea()
    }
}

extension View {
    /// Inline navigation title in the Somna type style.
    func somnaNavTitle(_ title: String, subtitle: String? = nil, mode: TimeOfDay) -> some View {
        modifier(NavTitleModifier(title: title, subtitle: subtitle, palette: mode.palette))
    }

    /// Tonal card: white-on-porcelain by day, lighter indigo by night. No borders.
    func card(padding: CGFloat = 20, radius: CGFloat = Radius.card, fill: Color? = nil) -> some View {
        modifier(CardModifier(padding: padding, radius: radius, fill: fill))
    }
}

struct NavTitleModifier: ViewModifier {
    let title: String
    let subtitle: String?
    let palette: Palette

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text(title)
                            .font(SomnaFont.body(17, .semibold))
                            .foregroundStyle(palette.fg)
                        if let subtitle {
                            Text(subtitle)
                                .font(SomnaFont.body(12))
                                .foregroundStyle(palette.fg2)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
    }
}

struct CardModifier: ViewModifier {
    @Environment(\.palette) private var p
    let padding: CGFloat
    let radius: CGFloat
    let fill: Color?

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill ?? p.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

// MARK: - Buttons

/// The only filled action in the system: Indigo Ink by day, porcelain by night.
struct PrimaryButton: View {
    @Environment(\.palette) private var p
    let title: String
    var systemImage: String? = "arrow.right"
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(SomnaFont.body(compact ? 15 : 16, .semibold))
                    .tracking(-0.3)
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .foregroundStyle(p.fgInverse)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: compact ? 44 : 52)
            .background(p.surfaceInverse, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle(feedback: Haptic.primary))
    }
}

/// Neutral pill for secondary actions.
struct SecondaryButton: View {
    @Environment(\.palette) private var p
    let title: String
    var systemImage: String?
    var fullWidth = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(title)
                    .font(SomnaFont.body(15, .semibold))
                    .tracking(-0.2)
            }
            .foregroundStyle(p.fg)
            .padding(.horizontal, 18)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 44)
            .background(p.line, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
    }
}

/// Text link with a chevron.
struct TextLink: View {
    @Environment(\.palette) private var p
    let title: String
    var muted = false
    var showChevron = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(SomnaFont.body(15, .semibold))
                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .foregroundStyle(muted ? p.fg2 : p.fg)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(SoftPressStyle())
    }
}

/// Circular Liquid Glass button for floating / navigation controls.
struct GlassIconButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void
    @State private var taps = 0

    init(systemImage: String, label: String, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.label = label
        self.action = action
    }

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .haptic(Haptic.tap, trigger: taps)
        .accessibilityLabel(label)
    }
}

// MARK: - Labels

struct StatusTag: View {
    @Environment(\.palette) private var p
    let text: String
    var state: SignalState = .restore

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(state.dot(p))
                .frame(width: 7, height: 7)
            Text(text)
                .font(SomnaFont.body(12, .semibold))
                .foregroundStyle(p.fg)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(state.soft(p), in: RoundedRectangle(cornerRadius: Radius.tag, style: .continuous))
    }
}

struct SourceLabel: View {
    @Environment(\.palette) private var p
    var icon = "applewatch"
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
            Text(text)
                .font(SomnaFont.body(12, .medium))
        }
        .foregroundStyle(p.fg2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Источник: \(text)")
    }
}

/// Three-bar confidence indicator: 1 — низкая, 2 — средняя, 3 — высокая.
struct ConfidenceView: View {
    @Environment(\.palette) private var p
    var level = 2
    var text = "Уверенность: средняя"
    var emphasized = false

    var body: some View {
        HStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<3, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(i < level ? p.fg : p.lineStrong)
                        .frame(width: 3, height: CGFloat(5 + i * 3))
                }
            }
            Text(text)
                .font(SomnaFont.body(emphasized ? 13 : 12, .medium))
                .foregroundStyle(emphasized ? p.fg : p.fg2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

struct Overline: View {
    @Environment(\.palette) private var p
    var icon: String?
    var iconColor: Color?
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(iconColor ?? p.fg2)
            }
            Text(text)
                .font(SomnaFont.body(13, .medium))
                .foregroundStyle(p.fg2)
        }
    }
}

struct SectionHeader: View {
    @Environment(\.palette) private var p
    let title: String
    var action: String?
    var onAction: (() -> Void)?

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            Text(title)
                .displayStyle(22, tracking: -0.6)
                .foregroundStyle(p.fg)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let action {
                if let onAction {
                    Button(action: onAction) {
                        Text(action)
                            .font(SomnaFont.body(14, .medium))
                            .foregroundStyle(p.fg2)
                            .frame(minHeight: 32)
                    }
                    .buttonStyle(SoftPressStyle())
                } else {
                    Text(action)
                        .font(SomnaFont.body(14, .medium))
                        .foregroundStyle(p.fg2)
                }
            }
        }
    }
}

struct GroupCaption: View {
    @Environment(\.palette) private var p
    let text: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(text.uppercased())
                .font(SomnaFont.body(12, .semibold))
                .tracking(0.4)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(SomnaFont.body(12))
                    .foregroundStyle(p.fg3)
            }
        }
        .foregroundStyle(p.fg2)
        .padding(.horizontal, 4)
    }
}

struct LegendItem: View {
    @Environment(\.palette) private var p
    let color: Color
    let text: String
    var width: CGFloat = 10
    var height: CGFloat = 10

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: min(width, height) / 3)
                .fill(color)
                .frame(width: width, height: height)
            Text(text)
                .font(SomnaFont.body(12, .medium))
                .foregroundStyle(p.fg2)
        }
    }
}

struct Divider1: View {
    @Environment(\.palette) private var p

    var body: some View {
        Rectangle()
            .fill(p.line)
            .frame(height: 1)
    }
}

/// Icon inside a soft circular or rounded tile.
struct IconTile: View {
    @Environment(\.palette) private var p
    let systemImage: String
    var state: SignalState = .neutral
    var size: CGFloat = 36
    var circle = true
    var filled = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: circle ? size / 2 : 12, style: .continuous)
        Image(systemName: systemImage)
            .font(.system(size: size * 0.45, weight: .medium))
            .foregroundStyle(filled ? p.fgInverse : (state == .neutral ? p.fg : state.dot(p)))
            .frame(width: size, height: size)
            .background(filled ? p.surfaceInverse : state.soft(p), in: shape)
            .accessibilityHidden(true)
    }
}

// MARK: - Controls

/// Tag-like selectable chip (12 pt corners, not a pill).
struct ChipToggle: View {
    @Environment(\.palette) private var p
    let title: String
    let isOn: Bool
    var icon: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .medium))
                }
                Text(title)
                    .font(SomnaFont.body(14, .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .foregroundStyle(isOn ? p.fgInverse : p.fg)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(isOn ? p.surfaceInverse : p.surface, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                    .strokeBorder(isOn ? Color.clear : p.lineStrong, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: Radius.chip))
        }
        .buttonStyle(PressScaleStyle(feedback: nil))
        .haptic(.selection, trigger: isOn)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Simple wrapping layout for chips. A chip wider than the row is narrowed
/// to the row width (long Russian labels, large Dynamic Type).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    private func itemSize(_ view: LayoutSubview, maxWidth: CGFloat) -> CGSize {
        let ideal = view.sizeThatFits(.unspecified)
        guard maxWidth.isFinite, ideal.width > maxWidth else { return ideal }
        return view.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for view in subviews {
            let size = itemSize(view, maxWidth: maxWidth)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, maxWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = itemSize(view, maxWidth: bounds.width)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Segmented control in the Somna style (white thumb on a tinted track).
struct SomnaSegmented: View {
    @Environment(\.palette) private var p
    let options: [String]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                let isOn = index == selection
                Button {
                    withAnimation(.snappy(duration: 0.25)) { selection = index }
                } label: {
                    Text(options[index])
                        .font(SomnaFont.body(13, isOn ? .semibold : .medium))
                        .foregroundStyle(isOn ? p.fg : p.fg2)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background {
                            if isOn {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(p.isDark ? p.surface2 : p.surface)
                                    .shadow(color: .black.opacity(p.isDark ? 0 : 0.07), radius: 8, y: 3)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(3)
        .background(p.line, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .haptic(.selection, trigger: selection)
    }
}

/// Thin progress track.
struct ProgressTrack: View {
    @Environment(\.palette) private var p
    let fraction: Double
    var fill: Color?
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(p.line)
                Capsule()
                    .fill(fill ?? p.fg)
                    .frame(width: max(height, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Rows grouped in one tonal container with hairline separators.
struct GroupedList<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 4)
        .card(padding: 0)
    }
}

/// Bullet line with an icon.
struct IconLine: View {
    @Environment(\.palette) private var p
    let systemImage: String
    var iconColor: Color?
    let text: String
    var size: CGFloat = 13
    var textColor: Color?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(iconColor ?? p.fg2)
                .frame(width: 18)
            Text(text)
                .font(SomnaFont.body(size))
                .foregroundStyle(textColor ?? p.fg2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
