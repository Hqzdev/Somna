//
//  Theme.swift
//  Somna
//
//  Visual tokens mirrored from design.pen: four time-of-day palettes
//  (dawn → sunset → dusk → night), brand colors, spacing and radii.
//

import SwiftUI
import Foundation

// MARK: - Hex colors

nonisolated extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

// MARK: - Brand colors (theme-independent)

nonisolated enum Brand {
    static let ink = Color(hex: 0x151581)
    static let porcelain = Color(hex: 0xF6F6FA)
    static let lavenderMist = Color(hex: 0xA1A1CD)
    static let lilac = Color(hex: 0x9F73E6)
    static let info = Color(hex: 0x20A2E3)
    static let electricViolet = Color(hex: 0x5465FF)

    /// Semantic states — color is used only when it carries meaning.
    static let restore = Color(hex: 0x00BB76)
    static let caution = Color(hex: 0xFF85B1)
    static let attention = Color(hex: 0xF25C75)

    /// Dawn accents, decorative only (sky, sunrise icon, wake window).
    static let sunrise = Color(hex: 0xFF8F66)
    static let sun = Color(hex: 0xFFC27A)

    /// Sleep stages.
    static let stageAwake = Color(hex: 0xFF85B1)
    static let stageREM = Color(hex: 0x20A2E3)
    static let stageCore = Color(hex: 0x5465FF)

    static let dawnGradient = LinearGradient(
        colors: [Color(hex: 0x8A96FF), sunrise, sun],
        startPoint: .leading,
        endPoint: .trailing
    )
}

// MARK: - Time of day

nonisolated enum TimeOfDay: String, CaseIterable, Identifiable, Sendable {
    case dawn, sunset, dusk, night

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dawn: "Рассвет"
        case .sunset: "Закат"
        case .dusk: "Сумерки"
        case .night: "Ночь"
        }
    }

    var hours: String {
        switch self {
        case .dawn: "05:00–15:00"
        case .sunset: "15:00–18:00"
        case .dusk: "18:00–21:00"
        case .night: "21:00–05:00"
        }
    }

    static func at(hour: Int) -> TimeOfDay {
        switch hour {
        case 5..<15: .dawn
        case 15..<18: .sunset
        case 18..<21: .dusk
        default: .night
        }
    }

    var palette: Palette {
        switch self {
        case .dawn: .dawn
        case .sunset: .sunset
        case .dusk: .dusk
        case .night: .night
        }
    }
}

// MARK: - Palette

nonisolated struct Palette: Equatable, Sendable {
    var bg: Color
    var sky: Color
    var surface: Color
    var surface2: Color
    var surfaceInverse: Color
    var fg: Color
    var fg2: Color
    var fg3: Color
    var fgInverse: Color
    var line: Color
    var lineStrong: Color
    var tabSelected: Color
    var overlay: Color
    var accent: Color
    var accentSoft: Color
    var restoreSoft: Color
    var cautionSoft: Color
    var attentionSoft: Color
    var stageDeep: Color
    var isDark: Bool

    static let dawn = Palette(
        bg: Color(hex: 0xFBF6F1),
        sky: Color(hex: 0xFFE1CC),
        surface: Color(hex: 0xFFFFFF),
        surface2: Color(hex: 0xF8EEE6),
        surfaceInverse: Color(hex: 0x151581),
        fg: Color(hex: 0x151581),
        fg2: Color(hex: 0x151581, alpha: 0.66),
        fg3: Color(hex: 0x6868AA),
        fgInverse: Color(hex: 0xFFFFFF),
        line: Color(hex: 0x151581, alpha: 0.10),
        lineStrong: Color(hex: 0x151581, alpha: 0.20),
        tabSelected: Color(hex: 0xFF8F66, alpha: 0.15),
        overlay: Color(hex: 0x0B0B3B, alpha: 0.40),
        accent: Color(hex: 0x5465FF),
        accentSoft: Color(hex: 0x5465FF, alpha: 0.10),
        restoreSoft: Color(hex: 0x00BB76, alpha: 0.12),
        cautionSoft: Color(hex: 0xFF85B1, alpha: 0.16),
        attentionSoft: Color(hex: 0xF25C75, alpha: 0.12),
        stageDeep: Color(hex: 0x151581),
        isDark: false
    )

    static let sunset = Palette(
        bg: Color(hex: 0xEEEBF3),
        sky: Color(hex: 0xF3D0C4),
        surface: Color(hex: 0xFBFAFD),
        surface2: Color(hex: 0xE5E1EE),
        surfaceInverse: Color(hex: 0x151581),
        fg: Color(hex: 0x151581),
        fg2: Color(hex: 0x151581, alpha: 0.68),
        fg3: Color(hex: 0x6464A8),
        fgInverse: Color(hex: 0xFFFFFF),
        line: Color(hex: 0x151581, alpha: 0.12),
        lineStrong: Color(hex: 0x151581, alpha: 0.22),
        tabSelected: Color(hex: 0xE88C7A, alpha: 0.17),
        overlay: Color(hex: 0x0B0B3B, alpha: 0.45),
        accent: Color(hex: 0x5465FF),
        accentSoft: Color(hex: 0x5465FF, alpha: 0.12),
        restoreSoft: Color(hex: 0x00BB76, alpha: 0.14),
        cautionSoft: Color(hex: 0xFF85B1, alpha: 0.18),
        attentionSoft: Color(hex: 0xF25C75, alpha: 0.14),
        stageDeep: Color(hex: 0x151581),
        isDark: false
    )

    static let dusk = Palette(
        bg: Color(hex: 0x232266),
        sky: Color(hex: 0x5E4786),
        surface: Color(hex: 0x2E2D78),
        surface2: Color(hex: 0x38378A),
        surfaceInverse: Color(hex: 0xF6F6FA),
        fg: Color(hex: 0xF6F6FA),
        fg2: Color(hex: 0xC5C5E6),
        fg3: Color(hex: 0x9C9CCB),
        fgInverse: Color(hex: 0x151581),
        line: Color(hex: 0xFFFFFF, alpha: 0.12),
        lineStrong: Color(hex: 0xFFFFFF, alpha: 0.22),
        tabSelected: Color(hex: 0xFFFFFF, alpha: 0.12),
        overlay: Color(hex: 0x000000, alpha: 0.63),
        accent: Color(hex: 0x9AA4FF),
        accentSoft: Color(hex: 0x9AA4FF, alpha: 0.16),
        restoreSoft: Color(hex: 0x00BB76, alpha: 0.22),
        cautionSoft: Color(hex: 0xFF85B1, alpha: 0.22),
        attentionSoft: Color(hex: 0xF25C75, alpha: 0.22),
        stageDeep: Color(hex: 0xC9CCFF),
        isDark: true
    )

    static let night = Palette(
        bg: Color(hex: 0x0B0B3B),
        sky: Color(hex: 0x12124A),
        surface: Color(hex: 0x14145A),
        surface2: Color(hex: 0x1C1C6B),
        surfaceInverse: Color(hex: 0xF6F6FA),
        fg: Color(hex: 0xF6F6FA),
        fg2: Color(hex: 0xA1A1CD),
        fg3: Color(hex: 0x8080BA),
        fgInverse: Color(hex: 0x151581),
        line: Color(hex: 0xFFFFFF, alpha: 0.12),
        lineStrong: Color(hex: 0xFFFFFF, alpha: 0.20),
        tabSelected: Color(hex: 0xFFFFFF, alpha: 0.10),
        overlay: Color(hex: 0x000000, alpha: 0.63),
        accent: Color(hex: 0x8A96FF),
        accentSoft: Color(hex: 0x8A96FF, alpha: 0.15),
        restoreSoft: Color(hex: 0x00BB76, alpha: 0.20),
        cautionSoft: Color(hex: 0xFF85B1, alpha: 0.20),
        attentionSoft: Color(hex: 0xF25C75, alpha: 0.20),
        stageDeep: Color(hex: 0xC9CCFF),
        isDark: true
    )
}

// MARK: - Environment

nonisolated struct PaletteKey: EnvironmentKey {
    static let defaultValue: Palette = .dawn
}

nonisolated extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

// MARK: - Spacing & shape tokens

nonisolated enum Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let gutter: CGFloat = 20
    static let section: CGFloat = 24
    static let xl: CGFloat = 32
}

nonisolated enum Radius {
    static let tag: CGFloat = 8
    static let chip: CGFloat = 12
    static let row: CGFloat = 20
    static let card: CGFloat = 24
    static let hero: CGFloat = 28
}

// MARK: - Semantic state

nonisolated enum SignalState: Sendable {
    case restore, caution, attention, neutral, data

    func dot(_ p: Palette) -> Color {
        switch self {
        case .restore: Brand.restore
        case .caution: Brand.caution
        case .attention: Brand.attention
        case .neutral: p.fg3
        case .data: p.accent
        }
    }

    func soft(_ p: Palette) -> Color {
        switch self {
        case .restore: p.restoreSoft
        case .caution: p.cautionSoft
        case .attention: p.attentionSoft
        case .neutral: p.line
        case .data: p.accentSoft
        }
    }
}

// MARK: - Haptics
//
// Tactile tokens live here with the visual ones so the whole design system
// compiles as one unit. Built on SwiftUI's declarative `sensoryFeedback`:
// haptics fire from state changes. Switch: Профиль → Тактильный отклик.
//
// Vocabulary (keep it small so the app stays calm):
// • tap        — light impact on press of buttons, chips, rows
// • primary    — a slightly firmer impact for the one main action
// • selection  — changing a value: segments, scales, slider steps, yes/no
// • increase / decrease — counters and steppers
// • success    — something completed: plan step, check-in, saved alarm
// • warning    — only before a destructive or irreversible choice
// • breath     — very soft pulse at each inhale / exhale in bedtime mode

nonisolated struct HapticsEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

nonisolated extension EnvironmentValues {
    var hapticsEnabled: Bool {
        get { self[HapticsEnabledKey.self] }
        set { self[HapticsEnabledKey.self] = newValue }
    }
}

enum Haptic {
    static let tap = SensoryFeedback.impact(weight: .light, intensity: 0.55)
    static let primary = SensoryFeedback.impact(weight: .medium, intensity: 0.7)
    static let soft = SensoryFeedback.impact(flexibility: .soft, intensity: 0.6)
    static let breath = SensoryFeedback.impact(flexibility: .soft, intensity: 0.4)
}

// MARK: - Modifiers

private struct HapticModifier<Trigger: Equatable>: ViewModifier {
    @Environment(\.hapticsEnabled) private var enabled
    let feedback: SensoryFeedback
    let trigger: Trigger
    let condition: ((Trigger, Trigger) -> Bool)?

    func body(content: Content) -> some View {
        content.sensoryFeedback(feedback, trigger: trigger) { oldValue, newValue in
            guard enabled else { return false }
            return condition?(oldValue, newValue) ?? true
        }
    }
}

private struct DynamicHapticModifier<Trigger: Equatable>: ViewModifier {
    @Environment(\.hapticsEnabled) private var enabled
    let trigger: Trigger
    let feedback: (Trigger, Trigger) -> SensoryFeedback?

    func body(content: Content) -> some View {
        content.sensoryFeedback(trigger: trigger) { oldValue, newValue in
            guard enabled else { return nil }
            return feedback(oldValue, newValue)
        }
    }
}

extension View {
    /// Plays `feedback` when `trigger` changes (and `condition`, if given, returns true).
    func haptic<Trigger: Equatable>(_ feedback: SensoryFeedback, trigger: Trigger,
                                    condition: ((Trigger, Trigger) -> Bool)? = nil) -> some View {
        modifier(HapticModifier(feedback: feedback, trigger: trigger, condition: condition))
    }

    /// Chooses the feedback from the old and new value; return nil for silence.
    func hapticDynamic<Trigger: Equatable>(trigger: Trigger,
                                           _ feedback: @escaping (Trigger, Trigger) -> SensoryFeedback?) -> some View {
        modifier(DynamicHapticModifier(trigger: trigger, feedback: feedback))
    }
}

// MARK: - Button styles with feedback on touch-down

/// Scales slightly and taps on press. Used by pills, chips and tiles.
struct PressScaleStyle: ButtonStyle {
    var feedback: SensoryFeedback? = Haptic.tap

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .haptic(feedback ?? Haptic.tap, trigger: configuration.isPressed) { _, isPressed in
                isPressed && feedback != nil
            }
    }
}

/// No scale, just a gentle dim and a light tap. Used by list rows and text links.
struct SoftPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .haptic(Haptic.tap, trigger: configuration.isPressed) { _, isPressed in
                isPressed
            }
    }
}
