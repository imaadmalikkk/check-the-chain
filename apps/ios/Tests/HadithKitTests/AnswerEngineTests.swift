import Foundation
import FoundationModels
import Testing
@testable import HadithKit

/// The live half of the answering feature.
///
/// Every test that needs the model is gated on it actually being available, so
/// this suite passes on a machine or simulator without Apple Intelligence
/// rather than failing for a reason that has nothing to do with the code. The
/// rules themselves are covered unconditionally in `AnswerValidatorTests` —
/// that split is deliberate, and it is why the safety logic is a pure function.
@Suite("Answering")
struct AnswerEngineTests {
    private static var modelIsAvailable: Bool {
        AnswerEngine.availability == .available
    }

    private func engine() throws -> AnswerEngine {
        AnswerEngine(engine: try TestFixtures.corpus().engine)
    }

    /// Not tautological despite mirroring the switch it tests: the three
    /// unavailable reasons drive three different pieces of UI, so mapping two
    /// of them to the same case would be invisible until someone with Apple
    /// Intelligence switched off saw the wrong explanation.
    @Test("Each unavailable reason maps to its own case")
    func availabilityMapping() {
        let expected: AnswerEngine.Availability = switch SystemLanguageModel.default.availability {
        case .available: .available
        case .unavailable(.deviceNotEligible): .ineligibleDevice
        case .unavailable(.appleIntelligenceNotEnabled): .appleIntelligenceOff
        case .unavailable(.modelNotReady): .modelDownloading
        @unknown default: .ineligibleDevice
        }
        #expect(AnswerEngine.availability == expected)
    }

    @Test("A question too short to search returns nothing")
    func rejectsShortQuestions() async throws {
        let engine = try engine()
        #expect(await engine.answer("  ") == nil)
        #expect(await engine.answer("ab") == nil)
    }

    @Test("Unavailable means nil, never a crash", .enabled(if: !modelIsAvailable))
    func unavailableReturnsNil() async throws {
        let engine = try engine()
        #expect(await engine.answer("what did the prophet say about intentions") == nil)
    }

    /// The corpus certainly covers this — Bukhari 1 is the hadith of intentions
    /// — so a decline here would mean the model is refusing work it can do.
    @Test("A covered question cites real hadith", .enabled(if: modelIsAvailable))
    func answersCoveredQuestion() async throws {
        let answer = try #require(
            try await engine().answer("what did the prophet say about intentions"),
            "The model declined a question the corpus definitely answers"
        )

        #expect(!answer.summary.isEmpty)
        #expect(!answer.citations.isEmpty)

        // Every citation must be a real row, not something the model composed.
        let store = try TestFixtures.corpus().store
        for hadith in answer.citations {
            let real = try await store.hadith(slug: hadith.collectionSlug, number: hadith.number)
            #expect(real?.english == hadith.english)
        }
    }

    /// The test that matters most in this suite.
    ///
    /// The model has read Islamic texts, and plenty else besides. Asked
    /// something the corpus cannot answer, its instinct is to answer anyway.
    /// This is the direct probe for that: nothing in 47,442 hadith addresses
    /// French geography, so the only correct behaviour is to decline.
    @Test("A question the corpus cannot answer is declined", .enabled(if: modelIsAvailable))
    func declinesUncoveredQuestion() async throws {
        let answer = try await engine().answer("what is the capital of France")
        #expect(answer == nil, "The model answered from its own knowledge instead of declining")
    }
}
