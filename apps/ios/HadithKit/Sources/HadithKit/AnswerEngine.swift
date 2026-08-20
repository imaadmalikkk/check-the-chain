import Foundation
import FoundationModels

/// Answers a question from hadith the app has already retrieved.
///
/// The model never sees the corpus and never produces a narration. It is given
/// a question and a numbered list of candidates, and returns *which numbers*
/// answer it plus a short summary. The app renders the narrations themselves
/// from its own database. A model with no channel to emit scripture cannot
/// fabricate scripture — that is the point, and everything else here is in
/// service of it.
///
/// Nothing in this type reports failure to the user. Every path that cannot
/// produce a trustworthy answer returns nil, and the caller shows plain ranked
/// results — the app exactly as it behaved before this existed.
@available(iOS 26.0, macOS 26.0, *)
public actor AnswerEngine {
    /// Why the feature can or cannot run. The three unavailable reasons are
    /// not interchangeable: one is permanent and two are things the person
    /// holding the phone can fix, which is a UI decision, so they stay
    /// distinct rather than collapsing to a bool.
    public enum Availability: Sendable, Equatable {
        case available
        /// No Apple Intelligence on this hardware. Hide the affordance.
        case ineligibleDevice
        /// Switched off. Offer the explanation; it is actionable.
        case appleIntelligenceOff
        /// Still downloading. Transient — say so.
        case modelDownloading
    }

    /// Read at the point of use, never cached: Apple Intelligence can be
    /// switched on, and the model can finish downloading, while the app runs.
    public static var availability: Availability {
        switch SystemLanguageModel.default.availability {
        case .available: .available
        case .unavailable(.deviceNotEligible): .ineligibleDevice
        case .unavailable(.appleIntelligenceNotEnabled): .appleIntelligenceOff
        case .unavailable(.modelNotReady): .modelDownloading
        @unknown default: .ineligibleDevice
        }
    }

    /// How many retrieved narrations the model is shown.
    ///
    /// Eight, with each narration's English truncated below, is the context
    /// budget. `exceededContextWindowSize` is a real error case, and designing
    /// under the limit is better than catching a failure at it — the reader
    /// loses nothing, since the full text is rendered from the database
    /// whatever the model was shown.
    private static let candidateCount = 8
    private static let candidateCharacterLimit = 400

    private let engine: SearchEngine
    private var session: LanguageModelSession?

    public init(engine: SearchEngine) {
        self.engine = engine
    }

    /// Loads the model before the first question, so the first Ask is not also
    /// the one that pays for a cold start.
    public func prewarm() {
        guard Self.availability == .available else { return }
        makeSession().prewarm()
    }

    public func answer(_ question: String) async -> Answer? {
        guard Self.availability == .available else { return nil }

        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return nil }

        guard let candidates = try? await engine.search(query: trimmed, limit: Self.candidateCount),
              !candidates.isEmpty
        else { return nil }

        let session = makeSession()
        do {
            let response = try await session.respond(
                to: Self.prompt(question: trimmed, candidates: candidates),
                generating: DraftAnswer.self
            )
            let draft = response.content
            return AnswerValidator.validate(
                answered: draft.answered,
                summary: draft.summary,
                supporting: draft.supporting,
                against: candidates
            )
        } catch {
            // Guardrail violations, context overflow, refusals and rate limits
            // all land here and all mean the same thing to the reader: no
            // summary, results as normal. Surfacing a dialog about a token
            // budget would help nobody.
            Log.ask.error("Answer generation failed: \(error, privacy: .public)")
            return nil
        }
    }

    /// One session per request rather than one for the actor's lifetime.
    ///
    /// A session accumulates a transcript, and this feature has no follow-up
    /// questions — carrying the previous question's narrations into the next
    /// one would spend context on irrelevant text and let an earlier answer
    /// colour a later one.
    private func makeSession() -> LanguageModelSession {
        LanguageModelSession(instructions: Self.instructions)
    }

    private static let instructions = """
        You help someone understand hadith they have searched for.

        You are given a question and a numbered list of narrations retrieved \
        from a hadith collection. Answer only from those narrations. Do not use \
        anything you know about Islam from any other source — if the narrations \
        do not answer the question, set answered to false. Declining is a \
        correct and expected outcome, not a failure, and is far better than an \
        answer the narrations do not support.

        Never quote the narrations. The app displays their full text beside \
        your summary, so quoting wastes the reader's attention and risks \
        misquoting. Refer to them by what they say, not by reproducing them.

        The numbers are for your reply only — the reader never sees them. Never \
        write "the second one" or "narration 6". Write about the subject \
        itself, as one paragraph a person could read aloud without having the \
        list in front of them.

        Only describe narrations that bear on the question. Ignore the rest \
        rather than mentioning them, and do not summarise the list as a list.

        Never state a ruling, obligation or prohibition that the narrations do \
        not themselves state. You are describing what these narrations say, not \
        issuing a judgement.
        """

    private static func prompt(question: String, candidates: [SearchResult]) -> String {
        let numbered = candidates.enumerated().map { index, result in
            let english = result.hadith.english.prefix(candidateCharacterLimit)
            let ellipsis = result.hadith.english.count > candidateCharacterLimit ? "…" : ""
            return "\(index + 1). [\(result.hadith.reference)] \(english)\(ellipsis)"
        }.joined(separator: "\n\n")

        return """
            Question: \(question)

            Narrations:
            \(numbered)
            """
    }
}

/// What the model returns. Indices and prose — never a narration.
@available(iOS 26.0, macOS 26.0, *)
@Generable
struct DraftAnswer {
    @Guide(description: "true only if the numbered narrations actually answer the question")
    var answered: Bool

    @Guide(description: "Two or three sentences describing only what the numbered narrations say. Never quote them. Never state a ruling they do not state.")
    var summary: String

    @Guide(description: "Numbers of the narrations that support the summary, most relevant first")
    var supporting: [Int]
}
