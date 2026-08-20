import Foundation
import Testing
@testable import HadithKit

/// The safety rules, tested without the model.
///
/// `AnswerValidator` takes plain values rather than the `@Generable` draft on
/// purpose: Apple Intelligence is unavailable on some machines and in some
/// simulators, and the rules that stop a religious answer going wrong must not
/// be the part of the system that goes untested when it is.
@Suite("Answer validator")
struct AnswerValidatorTests {
    private func candidate(_ number: String, english: String = "Some narration text.") -> SearchResult {
        SearchResult(
            hadith: Hadith(
                id: Int64(number) ?? 1,
                collection: "Sahih al-Bukhari",
                collectionSlug: "sahih-al-bukhari",
                number: number,
                order: 0,
                narrator: "",
                english: english,
                arabic: "",
                gradingRaw: "Sahih",
                gradedBy: "",
                isnadNarrators: [],
                chapterID: nil,
                chapterEnglish: nil,
                hadithInChapter: nil
            ),
            score: 100
        )
    }

    private var three: [SearchResult] { [candidate("1"), candidate("2"), candidate("3")] }

    private let goodSummary = "These narrations describe restraining anger rather than acting on it."

    @Test("Indices map to the right hadith, in the model's order")
    func mapsInModelOrder() {
        let answer = AnswerValidator.validate(
            answered: true, summary: goodSummary, supporting: [3, 1], against: three
        )

        let result = try? #require(answer)
        #expect(result?.summary == goodSummary)
        #expect(result?.citations.map(\.number) == ["3", "1"])
    }

    @Test("Declining is honoured")
    func declines() {
        #expect(AnswerValidator.validate(
            answered: false, summary: goodSummary, supporting: [1], against: three
        ) == nil)
    }

    /// An answer with nothing behind it is the shape "answered from
    /// pretraining" takes — the model had no narration to point at and wrote
    /// something anyway.
    @Test("An answer with no citations is treated as a decline")
    func answeredWithNoSupport() {
        #expect(AnswerValidator.validate(
            answered: true, summary: goodSummary, supporting: [], against: three
        ) == nil)
    }

    @Test("Out-of-range indices are dropped")
    func dropsOutOfRange() {
        let answer = AnswerValidator.validate(
            answered: true, summary: goodSummary, supporting: [0, 2, 4, -1, 99], against: three
        )
        #expect(answer?.citations.map(\.number) == ["2"])
    }

    @Test("Dropping every index declines rather than answering unsupported")
    func allIndicesInvalid() {
        #expect(AnswerValidator.validate(
            answered: true, summary: goodSummary, supporting: [0, 7], against: three
        ) == nil)
    }

    @Test("Duplicates collapse, order preserved")
    func deduplicates() {
        let answer = AnswerValidator.validate(
            answered: true, summary: goodSummary, supporting: [2, 1, 2, 2], against: three
        )
        #expect(answer?.citations.map(\.number) == ["2", "1"])
    }

    /// The model was told not to quote. A long quoted span means it ignored an
    /// instruction, so the rest of that response has not earned trust either.
    @Test("A long quoted span declines the whole response")
    func longQuoteDeclines() {
        let quoting = "The Prophet said \"the strong is not the one who overcomes people by his strength, but the one who controls himself in anger\" here."
        #expect(AnswerValidator.validate(
            answered: true, summary: quoting, supporting: [1], against: three
        ) == nil)
    }

    @Test("A short quoted phrase is allowed")
    func shortQuoteAllowed() {
        let brief = "These narrations concern what the Prophet called \"true strength\" when angry."
        #expect(AnswerValidator.validate(
            answered: true, summary: brief, supporting: [1], against: three
        ) != nil)
    }

    /// A single quote character leaves the tail unbalanced. Treating that as a
    /// quote is the conservative direction: better a lost summary than a
    /// rendered one that smuggled a narration out of the model.
    @Test("An unbalanced quote is treated as quoting")
    func unbalancedQuoteDeclines() {
        let unbalanced = "These narrations say \"the strong is not the one who overcomes people by his strength, but the one who controls himself"
        #expect(AnswerValidator.validate(
            answered: true, summary: unbalanced, supporting: [1], against: three
        ) == nil)
    }

    @Test("An empty or near-empty summary declines")
    func emptySummary() {
        #expect(AnswerValidator.validate(
            answered: true, summary: "   ", supporting: [1], against: three
        ) == nil)
        #expect(AnswerValidator.validate(
            answered: true, summary: "Yes.", supporting: [1], against: three
        ) == nil)
    }

    @Test("No candidates means nothing to cite")
    func noCandidates() {
        #expect(AnswerValidator.validate(
            answered: true, summary: goodSummary, supporting: [1], against: []
        ) == nil)
    }

    @Test("The summary is trimmed")
    func trimsSummary() {
        let answer = AnswerValidator.validate(
            answered: true, summary: "  \(goodSummary)\n", supporting: [1], against: three
        )
        #expect(answer?.summary == goodSummary)
    }
}
