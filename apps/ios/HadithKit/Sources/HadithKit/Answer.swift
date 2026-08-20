import Foundation

/// An answer the app is willing to show: a short summary, and the narrations
/// it was drawn from.
///
/// The narrations are `Hadith` values read from the app's own database, never
/// text produced by a model. That is the whole design: a model that cannot
/// emit scripture cannot fabricate it.
public struct Answer: Sendable, Equatable {
    /// Never empty, never a quote — see `AnswerValidator`.
    public let summary: String
    /// In the order the model judged most relevant.
    public let citations: [Hadith]
}

/// The safety rules, as a pure function.
///
/// This deliberately takes plain values rather than the `@Generable` draft the
/// model returns. `FoundationModels` needs iOS 26 and Apple Intelligence, which
/// some machines and simulators do not have — and the part of the system that
/// stops a religious answer going wrong must not be the part that goes
/// untested when they don't. `AnswerEngine` owns the model; this owns the
/// rules, and the rules are testable anywhere.
///
/// Every rule below resolves to the same outcome: return nil. The caller then
/// shows plain ranked results, which is the app exactly as it behaved before
/// this feature existed. There is no failure mode here that degrades to
/// *showing something worse* — only to showing less.
enum AnswerValidator {
    /// Above this, a quoted span is the model reproducing a narration rather
    /// than referring to one.
    static let maximumQuotedSpan = 40

    /// Below this, a "summary" is an assent ("Yes.", "It is permitted.") with
    /// no substance to check against the citations.
    static let minimumSummaryLength = 20

    static func validate(
        answered: Bool,
        summary: String,
        supporting: [Int],
        against candidates: [SearchResult]
    ) -> Answer? {
        guard answered, !candidates.isEmpty else { return nil }

        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minimumSummaryLength else { return nil }
        guard !containsLongQuotedSpan(trimmed) else { return nil }

        // `supporting` is 1-based: the prompt numbers the narrations from 1,
        // because a model asked to count from zero gets it wrong often enough
        // to matter.
        var seen = Set<Int>()
        let citations = supporting
            .filter { (1...candidates.count).contains($0) && seen.insert($0).inserted }
            .map { candidates[$0 - 1].hadith }

        // An answer with nothing behind it is the shape "answered from
        // pretraining" takes — the model had no narration to point at and
        // wrote something anyway. That is the failure this whole design is
        // aimed at, so it is a decline rather than a summary shown bare.
        guard !citations.isEmpty else { return nil }

        return Answer(summary: trimmed, citations: citations)
    }

    /// Whether the text contains a quoted run long enough to be a narration.
    ///
    /// Catches quoting, not verbatim copying without quote marks — a model
    /// determined to reproduce text unquoted would get past this. It is a
    /// guard against the instruction being ignored in the obvious way, and the
    /// citations beside it are the real defence.
    ///
    /// An unbalanced quote leaves the tail counted as quoted. That is the
    /// conservative direction on purpose: losing a summary costs the reader a
    /// paragraph, rendering a smuggled narration costs them the thing this app
    /// exists to protect.
    private static func containsLongQuotedSpan(_ text: String) -> Bool {
        let curly: Set<Character> = ["\u{201C}", "\u{201D}", "\u{201E}", "\u{00AB}", "\u{00BB}"]
        let normalised = String(text.map { curly.contains($0) ? "\"" : $0 })

        return normalised
            .split(separator: "\"", omittingEmptySubsequences: false)
            .enumerated()
            // Alternating: even indices sit outside the quotes, odd inside.
            .contains { $0.offset.isMultiple(of: 2) == false && $0.element.count > maximumQuotedSpan }
    }
}
