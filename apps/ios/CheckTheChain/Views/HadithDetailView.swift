import SwiftUI
import HadithKit

/// A single hadith, read in full.
///
/// The page is three labelled blocks — what this hadith is, the narration in
/// Arabic, the translation — rather than one undifferentiated column of text.
/// Without the labels the reader has to work out from the script alone which
/// block is the narration and which is a translation of it, and the Arabic and
/// the English run into each other with only a rule between them.
///
/// Arabic stays first and largest: it is the narration, and the English is a
/// translation of it. The web app sets them in the same order, and inverting the
/// hierarchy on mobile because the screen is narrower would be the wrong trade.
struct HadithDetailView: View {
    let corpus: Corpus
    let slug: String
    let number: String

    /// Above this, an attribution stops reading as a label. Chosen from the
    /// data: 28,829 narrators are under 60 characters, the standard "X reported
    /// that the Prophet ﷺ said:" forms reach ~180, and the 522 outliers past
    /// 250 are full paragraphs.
    private static let attributionLengthLimit = 200

    /// Chains of one exist (a companion narrating directly), so this is not a
    /// theoretical case.
    static func narratorCount(_ n: Int) -> String {
        "\(n) narrator" + (n == 1 ? "" : "s")
    }

    @State private var hadith: Hadith?
    /// Default on. Someone who wants no reading history can turn it off in the
    /// library sheet; see Task 7.
    @AppStorage(PreferenceKey.recordsHistory) private var recordsHistory = true

    @Environment(AppModel.self) private var app

    private var ref: HadithRef { HadithRef(collectionSlug: slug, number: number) }

    var body: some View {
        ScrollView {
            if let hadith {
                VStack(alignment: .leading, spacing: 26) {
                    heading(hadith)

                    if !hadith.arabic.isEmpty {
                        block("Arabic") {
                            // Carded rather than set loose on the page. The
                            // Arabic runs to nine lines on a phone for a hadith
                            // as short as Bukhari 1, and without a boundary
                            // there is nothing to tell the eye where the
                            // narration ends and the translation begins.
                            Text(hadith.arabic)
                                .foregroundStyle(Palette.ink)
                                .arabicText(size: 21)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .cardSurface()
                        }
                    }

                    block("Translation") {
                        VStack(alignment: .leading, spacing: 12) {
                            if !hadith.narrator.isEmpty {
                                // Nothing is truncated here — the narrator field
                                // carries real narration text, and `english`
                                // picks up mid-sentence after it. But italic grey
                                // is a label treatment: it works for "Narrated
                                // Abu Hurayra:" and becomes unreadable across the
                                // 522 attributions that run past 250 characters,
                                // so those are set as body prose instead.
                                Text(hadith.narrator)
                                    .font(hadith.narrator.count > Self.attributionLengthLimit
                                          ? .body : .callout.italic())
                                    .foregroundStyle(hadith.narrator.count > Self.attributionLengthLimit
                                                     ? Palette.inkBody : Palette.inkMuted)
                                    .lineSpacing(hadith.narrator.count > Self.attributionLengthLimit ? 7 : 0)
                                    .textSelection(.enabled)
                            }
                            Text(hadith.english)
                                .font(.body)
                                .foregroundStyle(Palette.inkBody)
                                .lineSpacing(7)
                                .textSelection(.enabled)
                        }
                    }

                    if !hadith.isnadNarrators.isEmpty {
                        chainLink(hadith)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 48)
                .readableWidth()
            } else {
                ProgressView().padding(.top, 80)
            }
        }
        .background(Palette.ground)
        // Without this the last lines of a translation sit hard behind the
        // floating tab bar instead of dissolving under it.
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .navigationTitle(HadithCollection.named(slug: slug)?.shortName ?? "Hadith")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let hadith {
                if app.savedState.isAvailable {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task { await app.savedState.toggleSaved(ref) }
                        } label: {
                            Image(systemName: app.savedState.contains(ref) ? "bookmark.fill" : "bookmark")
                        }
                        .accessibilityLabel(app.savedState.contains(ref) ? "Remove from saved" : "Save")
                        .accessibilityIdentifier("saveToggle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: shareText(hadith)) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .task {
            hadith = try? await corpus.store.hadith(slug: slug, number: number)
            guard let library = corpus.library else { return }
            if recordsHistory {
                await library.recordView(ref)
            }
        }
    }

    /// A labelled block of content.
    private func block<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label).sectionLabel()
            content()
        }
    }

    private func heading(_ hadith: Hadith) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(hadith.reference)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Palette.ink)

            if let chapterID = hadith.chapterID, let chapter = hadith.chapterEnglish {
                Text(HadithCard.chapterLine(
                    chapterID: chapterID,
                    inChapter: hadith.hadithInChapter,
                    chapter: chapter
                ))
                .font(.footnote)
                .foregroundStyle(Palette.inkMuted)
            }

            // The grading and who issued it belong together — at the foot of the
            // page, as this used to be, "Graded by Darussalam" reads as an
            // orphaned footnote rather than a qualifier on the badge above it.
            if hadith.grading != .unknown {
                VStack(alignment: .leading, spacing: 5) {
                    GradingBadge(grading: hadith.grading)
                    attribution(hadith)
                }
                .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private func attribution(_ hadith: Hadith) -> some View {
        if !hadith.gradedBy.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text("Graded by \(hadith.gradedBy)")
                if hadith.gradedByIsPublisher {
                    // The web app discloses this and so must the app: a reader
                    // deciding whether to forward a hadith should know the
                    // grading came from a publisher, not a hadith scholar.
                    Text("Darussalam is a publisher, not a hadith scholar.")
                        .foregroundStyle(Palette.inkFaint)
                }
            }
            .font(.caption)
            .foregroundStyle(Palette.inkMuted)
        }
    }

    private func chainLink(_ hadith: Hadith) -> some View {
        NavigationLink(value: Route.isnad(hadith.collectionSlug, hadith.number)) {
            HStack(spacing: 12) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkMuted)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Chain of narrators")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.ink)
                    Text(Self.narratorCount(hadith.isnadNarrators.count) + " in this isnad")
                        .font(.caption)
                        .foregroundStyle(Palette.inkMuted)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.inkFaint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(padding: 16, radius: Radius.row)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("isnadLink")
    }

    private func shareText(_ hadith: Hadith) -> String {
        var parts = [hadith.english, "\n— \(hadith.reference)"]
        if hadith.grading != .unknown {
            parts.append("(\(hadith.grading.rawValue) — \(hadith.grading.meaning))")
        }
        return parts.joined(separator: " ")
    }
}

/// The isnad — the chain of transmission a hadith's authenticity rests on.
///
/// The names are parsed out of the Arabic sanad and are stored in the order
/// they appear there: the collector's own teacher first, working back through
/// the transmitters to the original source nearest the Prophet ﷺ. The roles are
/// labelled the same way the web app labels them, because getting the direction
/// backwards would misrepresent the chain entirely.
struct IsnadView: View {
    let corpus: Corpus
    let slug: String
    let number: String

    @State private var hadith: Hadith?

    private enum Role {
        case collector, transmitter, source

        init(index: Int, count: Int) {
            self = index == 0 ? .collector : (index == count - 1 ? .source : .transmitter)
        }

        var label: String? {
            switch self {
            case .collector: "Collector"
            case .source: "Source"
            case .transmitter: nil
            }
        }

        /// The amber is the web app's `bg-amber-500`; it marks the end of the
        /// chain, which is the one link a reader is actually looking for.
        var fill: Color {
            switch self {
            case .collector: Palette.ink
            case .source: Palette.adaptive(light: 0xF59E0B, dark: 0xFBBF24)
            case .transmitter: Palette.surfaceRaised
            }
        }

        var numeral: Color {
            switch self {
            case .collector: Palette.ground
            // Both ambers are light, in either appearance, so the numeral is
            // dark in both — inverting it with the scheme would put white on
            // amber at about 2.9:1.
            case .source: Color(white: 0.1)
            case .transmitter: Palette.inkMuted
            }
        }

        var ring: Color {
            self == .transmitter ? Palette.hairline : .clear
        }
    }

    var body: some View {
        ScrollView {
            if let hadith {
                VStack(alignment: .leading, spacing: 18) {
                    header(hadith)
                    chain(hadith.isnadNarrators)

                    // The chain is machine-parsed from Arabic text, not curated.
                    // Saying so is the difference between a useful aid and a
                    // false claim of scholarly authority.
                    Text("""
                        Parsed automatically from the Arabic sanad, and not \
                        matched against a biographical dictionary. The English \
                        is transliterated on-device: Arabic writes no short \
                        vowels, so spellings of less common names are an \
                        approximation.
                        """)
                        .font(.caption)
                        .foregroundStyle(Palette.inkFaint)
                        .lineSpacing(3)
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 48)
                .frame(maxWidth: .infinity, alignment: .leading)
                .readableWidth()
            } else {
                ProgressView().padding(.top, 80)
            }
        }
        .background(Palette.ground)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .navigationTitle("Chain of Narrators")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            hadith = try? await corpus.store.hadith(slug: slug, number: number)
        }
    }

    private func header(_ hadith: Hadith) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(hadith.reference)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Palette.ink)
            // Which end is which is the one thing a reader has to know before
            // the list means anything, so it is stated rather than left to the
            // two role labels buried at the top and bottom of the chain.
            Text(HadithDetailView.narratorCount(hadith.isnadNarrators.count)
                 + ", from the collector down to the original source")
                .font(.footnote)
                .foregroundStyle(Palette.inkMuted)
        }
    }

    /// The chain, on one carded surface.
    ///
    /// Loose on the page background the links had nothing holding them together,
    /// which for a screen whose entire subject is a *chain* was the wrong
    /// impression to give. The rail is numbered rather than dotted: the number
    /// replaces the "Narrator #n" caption that used to repeat under every single
    /// name and dominate a screen that is otherwise mostly names.
    private func chain(_ narrators: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(narrators.enumerated()), id: \.offset) { index, narrator in
                link(
                    narrator: narrator,
                    position: index + 1,
                    role: Role(index: index, count: narrators.count),
                    isLast: index == narrators.count - 1
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 16)
    }

    private func link(narrator: String, position: Int, role: Role, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            // The connector is drawn rather than implied by spacing: a chain
            // that visibly connects is the entire point of this screen.
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(role.fill)
                    Circle().strokeBorder(role.ring, lineWidth: 1)
                    Text("\(position)")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(role.numeral)
                }
                .frame(width: 24, height: 24)
                .accessibilityLabel("Narrator \(position)")

                if !isLast {
                    Rectangle()
                        .fill(Palette.hairline)
                        .frame(width: 1.5)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 24)
            // A rail of numbered discs stops being a rail once the discs scale
            // past a couple of lines tall; the names beside it still scale.
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)

            VStack(alignment: .leading, spacing: 3) {
                if let label = role.label {
                    Text(label).sectionLabel()
                }
                // English first, because a reader who can't read the Arabic
                // couldn't use this screen at all before it was here. The Arabic
                // stays directly underneath rather than being replaced: it is
                // what the corpus actually holds, and the English above it is
                // inferred.
                Text(NarratorName.english(narrator))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.ink)
                    .textSelection(.enabled)
                Text(narrator)
                    .foregroundStyle(Palette.inkMuted)
                    .arabicName(size: 17)
                    .textSelection(.enabled)
            }
            .padding(.top, 1)
            .padding(.bottom, isLast ? 0 : 20)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
