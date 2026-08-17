import SwiftUI
import HadithKit

/// The authenticity grading, shown as term + plain-English gloss.
///
/// The gloss is not optional. "Da'if" means nothing to most people opening this
/// app, and the whole purpose of the product is telling someone whether a hadith
/// they were sent is sound.
struct GradingBadge: View {
    let grading: Grading
    var compact = false

    var body: some View {
        HStack(spacing: 5) {
            Text(grading.rawValue)
                .font(.caption.weight(.semibold))
            if !compact {
                Text(grading.meaning)
                    .font(.caption2)
                    .opacity(0.7)
            }
        }
        .foregroundStyle(grading.tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(grading.fill, in: .capsule)
        // Grading is important enough to scale, but it's a badge — past
        // accessibility1 it stops being a badge and starts being a paragraph.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}

/// English hadith text with the query's terms marked.
///
/// Mirrors `highlightMatch` in `apps/web/src/components/result-card.tsx`,
/// including its stop-word filter and its two-character minimum — without those
/// a query like "what did the prophet say about anger" lights up half the
/// paragraph and the highlight stops meaning anything.
struct HighlightedText: View {
    let text: String
    let query: String

    var body: some View {
        Text(attributed)
    }

    private var attributed: AttributedString {
        var result = AttributedString(text)
        let terms = Self.significantTerms(in: query)
        guard !terms.isEmpty else { return result }

        for term in terms {
            var searchRange = result.startIndex..<result.endIndex
            while let found = result[searchRange].range(of: term, options: .caseInsensitive) {
                result[found].backgroundColor = Palette.highlight
                guard found.upperBound < result.endIndex else { break }
                searchRange = found.upperBound..<result.endIndex
            }
        }
        return result
    }

    static func significantTerms(in query: String) -> [String] {
        query
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count > 2 && !StopWords.all.contains($0.lowercased()) }
    }
}

/// Ported verbatim from `apps/web/src/lib/stop-words.ts`.
enum StopWords {
    static let all: Set<String> = [
        "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for", "of",
        "with", "by", "is", "was", "are", "were", "be", "been", "has", "have", "had",
        "do", "does", "did", "will", "would", "could", "should", "may", "might",
        "shall", "it", "its", "he", "she", "his", "her", "they", "them", "their",
        "we", "us", "our", "you", "your", "i", "me", "my", "that", "this", "these",
        "those", "which", "who", "whom", "what", "when", "where", "how", "not", "no",
        "nor", "if", "then", "than", "so", "as", "from", "into", "about", "said",
    ]
}

/// A hadith as it appears in a list — search results and browse alike.
struct HadithCard: View {
    let hadith: Hadith
    var query: String = ""
    var score: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Reference and grading share the top line. The badge used to sit
            // alone on the first row, spending the most prominent line in the
            // card on a coloured pill; putting it last instead would bury the
            // one thing the app exists to tell you. Beside the reference it is
            // both the first thing read and only half a row.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(hadith.reference)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 4)
                if hadith.grading != .unknown {
                    GradingBadge(grading: hadith.grading, compact: true)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let chapterID = hadith.chapterID, let chapter = hadith.chapterEnglish {
                    Text(Self.chapterLine(chapterID: chapterID, inChapter: hadith.hadithInChapter, chapter: chapter))
                        .font(.caption)
                        .foregroundStyle(Palette.inkMuted)
                }
                Spacer(minLength: 4)
                if let score {
                    Text("\(score)%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Palette.inkFaint)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                }
            }
            .padding(.top, 3)

            if !hadith.narrator.isEmpty {
                // Capped at two lines. The narrator field holds everything up to
                // the colon introducing the quote, and 522 hadith have one over
                // 250 characters — Muwatta 1467's runs to 5,323. Uncapped, a
                // single attribution would fill the card and push the hadith
                // itself out of view. The full text is on the detail page.
                Text(hadith.narrator)
                    .font(.subheadline.italic())
                    .foregroundStyle(Palette.inkMuted)
                    .lineLimit(2)
                    .padding(.top, 10)
            }

            HighlightedText(text: hadith.english, query: query)
                .font(.body)
                .foregroundStyle(Palette.inkBody)
                .lineSpacing(5)
                .lineLimit(6)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    /// e.g. "Book 1, Hadith 1 · Revelation".
    ///
    /// Collections that aren't divided into numbered books (Riyad as-Salihin,
    /// the forties) carry `chapter_id = 0`, and "Book 0" reads like a bug. The
    /// web app shows it; here the number is simply dropped when there isn't one.
    static func chapterLine(chapterID: Int, inChapter: Int?, chapter: String) -> String {
        var parts: [String] = []
        if chapterID > 0 { parts.append("Book \(chapterID)") }
        if let inChapter { parts.append("Hadith \(inChapter)") }

        let reference = parts.joined(separator: ", ")
        return reference.isEmpty ? chapter : "\(reference) · \(chapter)"
    }
}

/// Horizontally scrolling filter pills.
///
/// One `GlassEffectContainer` around the whole row rather than glass per pill:
/// that way adjacent pills blend into a single piece of glass and morph as a
/// unit when selections change, instead of animating as a dozen separate blobs.
struct FilterChips<Value: Hashable & Sendable>: View {
    struct Option: Identifiable {
        let value: Value
        let label: String
        var id: Value { value }
    }

    let options: [Option]
    @Binding var selection: Set<Value>
    @Namespace private var namespace

    var body: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(options) { option in
                        let isOn = selection.contains(option.value)
                        Button {
                            withAnimation(.snappy(duration: 0.25)) {
                                if isOn { selection.remove(option.value) } else { selection.insert(option.value) }
                            }
                        } label: {
                            Text(option.label)
                                .font(.footnote.weight(isOn ? .semibold : .regular))
                                .foregroundStyle(isOn ? Palette.ground : Palette.inkBody)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        .background {
                            if isOn { Capsule().fill(Palette.ink) }
                        }
                        .glassSurface(in: .capsule, interactive: true)
                        .glassEffectID(option.value, in: namespace)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
        .scrollIndicators(.hidden)
        // Chips are a control, not content. Allowed to scale into the
        // accessibility range they grow to ~350pt of stacked pills and push the
        // results they're filtering off the screen entirely.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}
