import Foundation
import Observation
import HadithKit

/// Owns the corpus and its loading state.
///
/// Opening the database and mapping the embeddings is fast; loading the Core ML
/// model is not (1–2s cold). Those are separated on purpose — the app becomes
/// usable as soon as the database is open, and search upgrades from keyword-only
/// to hybrid in the background when the model finishes. Nothing blocks on the
/// model, and there is no progress bar, which is the main thing this app does
/// differently from the web version.
@Observable
@MainActor
final class AppModel {
    enum State {
        case loading
        case ready(Corpus)
        case failed(String)
    }

    private(set) var state: State = .loading
    private(set) var isSemanticSearchReady = false

    /// The one saved-hadith cache for the whole app. Lives here rather than
    /// on `Corpus` because it is UI-facing main-actor state — `Corpus` and
    /// everything under it stays plain `Sendable` value/actor types so
    /// `HadithKit` stays UI-free.
    let savedState = SavedState()

    /// Nil until the corpus is ready, and on any device without Apple
    /// Intelligence. Lives here rather than on `Corpus` because `AnswerEngine`
    /// requires iOS 26 while `HadithKit` floors at 18 — putting it on `Corpus`
    /// would mean `@available` on a stored property in a package that
    /// deliberately supports the older target.
    private(set) var answerEngine: AnswerEngine?

    /// Whether to offer the Ask affordance at all, and what to say if not.
    /// Read fresh each time: Apple Intelligence can be switched on, and the
    /// model can finish downloading, while the app is running.
    var answerAvailability: AnswerEngine.Availability { AnswerEngine.availability }

    var corpus: Corpus? {
        if case .ready(let corpus) = state { return corpus }
        return nil
    }

    func load() async {
        guard case .loading = state else { return }

        do {
            let corpus = try await Task.detached(priority: .userInitiated) {
                try Corpus()
            }.value
            // Hydrated before `state` flips to `.ready`, so the first frame
            // of UI already has the real saved set — no flash from unstarred
            // to starred once a late hydration lands.
            await savedState.configure(library: corpus.library)
            state = .ready(corpus)

            await corpus.embedder.warmUp()
            isSemanticSearchReady = await corpus.embedder.isReady

            // After the embedder, not before: search must become useful first,
            // and a cold Ask costs the user nothing until they ask.
            if AnswerEngine.availability == .available {
                let engine = AnswerEngine(engine: corpus.engine)
                answerEngine = engine
                await engine.prewarm()
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
