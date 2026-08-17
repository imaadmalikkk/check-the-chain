import SwiftUI
import HadithKit

/// Design tokens.
///
/// The palette is monochrome apart from grading, which is the one place colour
/// carries meaning rather than decoration.
///
/// The ground is a real grey, not the near-white `#FAFAFA` this used to be.
/// That single value is most of what separates a clean layout from a flat one:
/// against `#FAFAFA` a white card is invisible and needs a border drawn round it
/// to exist at all, and once every card has a border the screen is a grid of
/// boxes. Against `#F2F2F3` the card simply *is* lighter than the page, so the
/// borders come off and nothing is lost.
enum Palette {
    static let ground = adaptive(light: 0xF2F2F3, dark: 0x0A0A0A)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x1A1A1C)
    static let surfaceRaised = adaptive(light: 0xFFFFFF, dark: 0x242426)
    /// Filled controls that sit on the ground — suggestion chips, quiet buttons.
    static let chip = adaptive(light: 0xE7E7EA, dark: 0x1F1F21)
    /// Dividers *inside* a surface. There are no borders around one.
    static let hairline = adaptive(light: 0xECECEE, dark: 0x2C2C2E)

    static let ink = adaptive(light: 0x1C1C1E, dark: 0xF2F2F3)
    static let inkBody = adaptive(light: 0x2C2C2E, dark: 0xE4E4E6)
    static let inkMuted = adaptive(light: 0x8A8A8E, dark: 0x98989D)
    static let inkFaint = adaptive(light: 0xB4B4B9, dark: 0x6C6C70)

    static let highlight = adaptive(light: 0xFDF0C8, dark: 0x4A3A0E)

    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

/// Corner radii. Large and consistent — the reference designs round everything
/// generously and never mix radii within a screen.
enum Radius {
    static let card: CGFloat = 22
    static let row: CGFloat = 18
}

/// The visual language for authenticity grading.
///
/// This is the most information-dense element in the app: it is the answer to
/// "is this hadith real". Colour alone can't carry that — the term and its
/// plain-English gloss are always shown together, and the palette is only a
/// reinforcement. The fills are lighter than they were and the outlines are
/// gone; a badge does not need a border to read as a badge.
extension Grading {
    var tint: Color {
        switch self {
        case .sahih: Palette.adaptive(light: 0x057857, dark: 0x6EE7B7)
        case .hasan: Palette.adaptive(light: 0xA85B08, dark: 0xFCD34D)
        case .daif: Palette.adaptive(light: 0xB4231C, dark: 0xFCA5A5)
        case .mawdu: Palette.adaptive(light: 0x8A1D1D, dark: 0xFCA5A5)
        case .unknown: Palette.adaptive(light: 0x8A8A8E, dark: 0x98989D)
        }
    }

    var fill: Color {
        switch self {
        case .sahih: Palette.adaptive(light: 0xE8F7F0, dark: 0x0A2A20)
        case .hasan: Palette.adaptive(light: 0xFBF2E0, dark: 0x33240A)
        case .daif: Palette.adaptive(light: 0xFBEBEA, dark: 0x361212)
        case .mawdu: Palette.adaptive(light: 0xF8DFDE, dark: 0x451212)
        case .unknown: Palette.adaptive(light: 0xEDEDEF, dark: 0x1F1F21)
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

    /// A content surface: a fill and a radius. Nothing else.
    ///
    /// No border and **no shadow**. A card does not need to pretend to float; it
    /// reads as a card because it is lighter than the ground it sits on, which
    /// is the whole reason `Palette.ground` is a real grey. A soft drop shadow
    /// under every card is the tell of a design that doesn't trust its own
    /// contrast, and it looks cheap next to flat fills.
    func cardSurface(padding: CGFloat = 20, radius: CGFloat = Radius.card) -> some View {
        self
            .padding(padding)
            .background(Palette.surface, in: .rect(cornerRadius: radius))
    }

    /// A grouped block of rows, iOS Settings style: one surface, rows divided by
    /// hairlines that inset past the leading content rather than running edge to
    /// edge. Used wherever the content is a list of peers — collections,
    /// chapters — which a stack of separate cards turns into visual gravel.
    func groupedSurface() -> some View {
        self.background(Palette.surface, in: .rect(cornerRadius: Radius.card))
    }

    /// A quiet filled capsule that sits directly on the ground.
    func chipSurface() -> some View {
        self
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Palette.chip, in: .capsule)
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

/// A hairline that starts where the row's text starts.
///
/// A divider that runs the full width of a card cuts it in half; one that inset
/// to the text column reads as a separator between peers.
struct RowDivider: View {
    var inset: CGFloat = 16

    var body: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(height: 0.5)
            .padding(.leading, inset)
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
