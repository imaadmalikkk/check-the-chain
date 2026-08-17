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
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
