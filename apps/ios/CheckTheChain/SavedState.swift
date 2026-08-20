import Foundation
import Observation
import HadithKit

/// The one place every screen reads and writes "is this hadith saved."
///
/// `Library` is a SwiftData actor, so `isSaved`/`save`/`removeSaved` are all
/// `async` — correct for the source of truth, but a context-menu label, a
/// toolbar icon, and a list row all need an answer synchronously, during
/// `body`. Before this type existed, each of the three screens that needed
/// one kept its own private snapshot of the answer and refreshed it on its
/// own schedule; the gaps between those schedules are what let a button
/// reading "Save" delete a favourite. This hydrates the saved set once at
/// launch, holds it in memory from then on, and is the only writer of it —
/// every mutation, wherever it happens, updates this set immediately, so
/// every reader sees the same answer regardless of where the change came
/// from.
@MainActor
@Observable
final class SavedState {
    private(set) var savedRefs: Set<HadithRef> = []

    /// Surfaced by a single `.saveErrorAlert` mounted once near the root of
    /// the view tree (see `RootView`'s `MainTabs`), per `SaveErrorPolicy` —
    /// the one place a `toggleSaved`-adjacent failure needs handling now,
    /// instead of three.
    var errorMessage: String?

    private var library: Library?

    /// False once `Corpus.library` is nil — the store could not open. Every
    /// method below already no-ops in that case; this just lets a caller
    /// decide whether to offer the affordance at all (see `SavedMenu`, which
    /// must produce no context menu rather than one full of no-ops).
    var isAvailable: Bool { library != nil }

    /// Call once, when the corpus becomes ready. Harmless to call with a nil
    /// `library`: the saved set just stays empty and every read/write below
    /// becomes a no-op, which is exactly how the app behaved before this
    /// feature existed.
    func configure(library: Library?) async {
        self.library = library
        guard let library else { return }
        savedRefs = Set((try? await library.saved()) ?? [])
    }

    /// Synchronous by design — the whole point of this cache. Safe to read
    /// from `body`.
    func contains(_ ref: HadithRef) -> Bool {
        savedRefs.contains(ref)
    }

    /// Idempotent, matching `Library.save`: safe to call on an already-saved
    /// ref (see its doc comment — it only bumps `savedAt`).
    func save(_ ref: HadithRef) async {
        guard let library else { return }
        do {
            try await library.save(ref)
            savedRefs.insert(ref)
            errorMessage = nil
        } catch {
            errorMessage = SaveErrorPolicy.updateFailedMessage
        }
    }

    /// A no-op, not an error, if `ref` isn't saved — matches
    /// `Library.removeSaved`.
    func removeSaved(_ ref: HadithRef) async {
        guard let library else { return }
        do {
            try await library.removeSaved(ref)
            savedRefs.remove(ref)
            errorMessage = nil
        } catch {
            errorMessage = SaveErrorPolicy.updateFailedMessage
        }
    }

    /// Callers read the new state back via `contains`, which this has already
    /// updated by the time the call returns.
    func toggleSaved(_ ref: HadithRef) async {
        guard let library else { return }
        do {
            let isSaved = try await library.toggleSaved(ref)
            apply(isSaved, to: ref)
            errorMessage = nil
        } catch {
            // A throw here is not proof the write didn't happen, so this
            // re-reads real truth instead of guessing — the same
            // self-correction the detail page's star used to do locally.
            if let isSaved = try? await library.isSaved(ref) {
                apply(isSaved, to: ref)
            }
            errorMessage = SaveErrorPolicy.updateFailedMessage
        }
    }

    private func apply(_ isSaved: Bool, to ref: HadithRef) {
        if isSaved {
            savedRefs.insert(ref)
        } else {
            savedRefs.remove(ref)
        }
    }
}
