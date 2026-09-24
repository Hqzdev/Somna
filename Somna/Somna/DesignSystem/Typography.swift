//
//  Typography.swift
//  Somna
//
//  Inter Tight (display, weight 400 only) + Inter (body 400/500/600),
//  bundled as static instances and registered at launch.
//

import SwiftUI
import CoreText
import Foundation

nonisolated enum FontRegistrar {
    static let files = ["InterTight-Regular", "Inter-Regular", "Inter-Medium", "Inter-SemiBold"]

    static func registerAll() {
        for name in files {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

nonisolated enum SomnaFont {
    /// Display face — Inter Tight Regular. Hierarchy comes from size, never from weight.
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom("InterTight-Regular", size: size, relativeTo: style)
    }

    /// Body / UI face — Inter 400, 500 or 600.
    static func body(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        let name: String
        if weight == .medium {
            name = "Inter-Medium"
        } else if weight == .semibold || weight == .bold || weight == .heavy {
            name = "Inter-SemiBold"
        } else {
            name = "Inter-Regular"
        }
        return .custom(name, size: size, relativeTo: style)
    }
}

extension View {
    /// Display text: Inter Tight with tight tracking, as in the Pen type scale.
    func displayStyle(_ size: CGFloat, tracking: CGFloat? = nil) -> some View {
        self
            .font(SomnaFont.display(size))
            .tracking(tracking ?? -size * 0.034)
    }

    func bodyStyle(_ size: CGFloat, _ weight: Font.Weight = .regular) -> some View {
        self.font(SomnaFont.body(size, weight))
    }
}
