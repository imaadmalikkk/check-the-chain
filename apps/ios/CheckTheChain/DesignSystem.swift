import SwiftUI
import HadithKit

/// Design tokens, carried over from the web app so the two products read as one.
///
/// The light values are the web app's literally — `#FAFAFA` ground, `#171717`
/// ink, hairline neutral borders, and the emerald/amber/red grading palette from
/// `apps/web/src/components/grading-badge.tsx`. The dark values are new: the web
/// app has no dark mode, and iOS needs one.
enum Palette {
    // Tailwind neutrals, the same ramp the web app uses.
    static let ground = adaptive(light: 0xFAFAFA, dark: 0x0A0A0A)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x161616)
    static let surfaceRaised = adaptive(light: 0xFFFFFF, dark: 0x1F1F1F)
    static let hairline = adaptive(light: 0xE5E5E5, dark: 0x2A2A2A)

    static let ink = adaptive(light: 0x171717, dark: 0xF5F5F5)
    static let inkBody = adaptive(light: 0x262626, dark: 0xE5E5E5)
    static let inkMuted = adaptive(light: 0x737373, dark: 0x9A9A9A)
    static let inkFaint = adaptive(light: 0xA3A3A3, dark: 0x6E6E6E)

    static let highlight = adaptive(light: 0xFEF3C7, dark: 0x4A3A0E)

    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

/// The visual language for authenticity grading.
///
/// This is the most information-dense element in the app: it is the answer to
/// "is this hadith real". Colour alone can't carry that — the term and its
/// plain-English gloss are always shown together, and the palette is only a
/// reinforcement.
extension Grading {
    var tint: Color {
        switch self {
        case .sahih: Palette.adaptive(light: 0x047857, dark: 0x6EE7B7)
        case .hasan: Palette.adaptive(light: 0xB45309, dark: 0xFCD34D)
        case .daif: Palette.adaptive(light: 0xB91C1C, dark: 0xFCA5A5)
        case .mawdu: Palette.adaptive(light: 0x7F1D1D, dark: 0xFCA5A5)
        case .unknown: Palette.adaptive(light: 0x737373, dark: 0x9A9A9A)
        }
    }

    var fill: Color {
        switch self {
        case .sahih: Palette.adaptive(light: 0xECFDF5, dark: 0x052E22)
        case .hasan: Palette.adaptive(light: 0xFFFBEB, dark: 0x36260A)
        case .daif: Palette.adaptive(light: 0xFEF2F2, dark: 0x3B1212)
        case .mawdu: Palette.adaptive(light: 0xFEE2E2, dark: 0x4A1212)
        case .unknown: Palette.adaptive(light: 0xFAFAFA, dark: 0x1F1F1F)
        }
    }

    var stroke: Color {
        switch self {
        case .sahih: Palette.adaptive(light: 0xA7F3D0, dark: 0x0B5741)
        case .hasan: Palette.adaptive(light: 0xFDE68A, dark: 0x6B4A0C)
        case .daif: Palette.adaptive(light: 0xFECACA, dark: 0x6B1F1F)
        case .mawdu: Palette.adaptive(light: 0xFCA5A5, dark: 0x7A2020)
        case .unknown: Palette.adaptive(light: 0xE5E5E5, dark: 0x2A2A2A)
        }
    }
}

/// Arabic typography.
///
/// Noto Naskh Arabic is the same face the web app loads, bundled here rather
/// than substituted with SF Arabic so the two products set the same text the
/// same way. It is deliberately set larger than the surrounding English with
/// generous leading: naskh needs the vertical room for its ascenders and
/// descenders, and the Arabic is the primary text on a hadith page, not a
/// decorative accompaniment to the translation.
enum ArabicFont {
    static let regular = "NotoNaskhArabic-Regular"
    static let bold = "NotoNaskhArabic-Bold"

    static func body(_ size: CGFloat = 22) -> Font {
        .custom(regular, size: size, relativeTo: .body)
    }

    static func title(_ size: CGFloat = 20) -> Font {
        .custom(bold, size: size, relativeTo: .headline)
    }
}

extension View {
    /// Caps content at a readable line length and centres it.
    ///
    /// Without this, a hadith on a 13" iPad sets at roughly 150 characters per
    /// line — more than twice the measure at which prose stays readable, and
    /// the eye loses its place returning to the start of each line. The web app
    /// solves the same problem with `max-w-2xl mx-auto`; this is that number in
    /// points. It also improves landscape iPhone for free.
    func readableWidth(_ maxWidth: CGFloat = 700) -> some View {
        self
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }

    /// Renders an Arabic paragraph with the right face, direction, and leading.
    ///
    /// `leading` and `trailing` resolve *against the layout direction*, so inside
    /// the right-to-left environment below, `.leading` is the right edge — which
    /// is where an Arabic paragraph starts and where every line must be flush.
    /// This previously said `.trailing`, which pinned the text to the left and
    /// left the ragged edge on the right: the exact inverse of how Arabic sets,
    /// and the reason short closing lines appeared to float away from the margin.
    ///
    /// The extra leading is 0.3em, not the 0.55em it was. Noto Naskh already
    /// carries tall intrinsic line metrics for its ascenders and descenders;
    /// adding another half an em on top pulled the lines so far apart they read
    /// as unrelated fragments rather than one continuous narration.
    func arabicText(size: CGFloat = 22) -> some View {
        self
            .font(ArabicFont.body(size))
            .lineSpacing(size * 0.3)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.layoutDirection, .rightToLeft)
    }

    /// Renders a short Arabic name inside an otherwise left-aligned column.
    ///
    /// Unlike a paragraph, a name sits in a list beside English labels, so its
    /// block stays flush with them. The base direction is still right-to-left so
    /// the glyphs, and any punctuation around them, order correctly; only the
    /// block alignment differs. 95% of narrator names fit on one line, where the
    /// distinction is invisible anyway.
    func arabicName(size: CGFloat = 20) -> some View {
        self
            .font(.custom(ArabicFont.regular, size: size, relativeTo: .body))
            .lineSpacing(size * 0.3)
            .multilineTextAlignment(.trailing)
            .environment(\.layoutDirection, .rightToLeft)
    }

    /// The small caps label that introduces a block of content.
    ///
    /// The detail page stacks three different kinds of text — a narration in
    /// Arabic, an attribution, and a translation — and without a label the
    /// reader has to infer which is which from the script and the styling.
    func sectionLabel() -> some View {
        self
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Palette.inkFaint)
            .textCase(.uppercase)
            .tracking(0.6)
    }

    /// A plain content surface: hairline border, subtle rounding, no glass.
    ///
    /// Apple's rule, and the one most apps break: glass belongs on controls
    /// floating *above* content. Blurring what's behind a paragraph of a hadith
    /// to make it look modern would make it harder to read, which is the only
    /// thing that actually matters here.
    func cardSurface(padding: CGFloat = 18) -> some View {
        self
            .padding(padding)
            .background(Palette.surface, in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Palette.hairline, lineWidth: 0.5)
            }
    }

    /// The single point where Liquid Glass enters the app.
    ///
    /// Every floating control routes through here. That's deliberate: an iOS 18
    /// backport needs `.ultraThinMaterial` fallbacks for all of them, and
    /// funnelling them into one modifier means that change touches one file
    /// instead of every view.
    func glassSurface<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        self.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
    }
}

extension UIColor {
    fileprivate convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
