import SwiftUI
import HadithKit

/// Long-press a result to star it.
///
/// A modifier applied where cards are used, rather than a parameter on
/// `HadithCard`. The card stays a pure function of a hadith and knows nothing
/// about persistence, and the two call sites that need this opt in.
///
/// No star is drawn *on* the card. That would put a glyph on every row for a
/// state that is false almost always.
private struct SavedMenu: ViewModifier {
    let ref: HadithRef
    let library: Library?

    @State private var isSaved = false
    @State private var errorMessage: String?

    func body(content: Content) -> some View {
        // Guards the modifier itself, not just the button inside it. With
        // only the button guarded, a long-press with no library still lifted
        // the row into a context menu with nothing in it — a visible "this
        // control exists" cue for a feature that, per the README, is
        // supposed to be as if it were never there.
        if let library {
            content
                .contextMenu {
                    Button {
                        Task { await toggle(library: library) }
                    } label: {
                        Label(
                            isSaved ? "Remove from Saved" : "Save",
                            systemImage: isSaved ? "bookmark.slash" : "bookmark"
                        )
                    }
                    // The row this modifier is attached to lives in a
                    // `LazyVStack` that does not recreate on `Back` — a
                    // detail-page star, then Back, then a long-press on the
                    // very same row, and the outer `.task` below never
                    // reruns, so `isSaved` can be stale by the time this menu
                    // is shown. `.contextMenu` has no "will present" hook,
                    // but SwiftUI rebuilds a context menu's content fresh on
                    // every presentation, so a `.task` *inside* the menu
                    // content — attached here, to the button itself — fires
                    // again each time the menu is about to appear and
                    // refreshes the cache before the label is read. That is
                    // what actually closes the gap; the `else` branch in
                    // `toggle(library:)` below is the second half, for
                    // correctness of the write itself rather than the label.
                    .task { await refresh(library: library) }
                }
                .task { await refresh(library: library) }
                .saveErrorAlert($errorMessage)
        } else {
            content
        }
    }

    private func refresh(library: Library) async {
        isSaved = (try? await library.isSaved(ref)) ?? isSaved
    }

    /// Re-reads truth immediately before deciding what to do, and branches
    /// explicitly on that fresh read rather than on the cached `isSaved` —
    /// the value that can go stale. A blind `toggleSaved` would still write
    /// the store correctly (it makes the same fresh check internally, and
    /// nothing here changes what ends up on disk), but writing the read out
    /// here means the button's behaviour is never described in terms of, or
    /// coupled to, the same cache whose staleness is what caused the bug in
    /// the first place — and it lets this branch use `save`/`removeSaved`
    /// directly, so "what truth said" and "what happened" are the same
    /// statement rather than two implementations that have to agree.
    private func toggle(library: Library) async {
        do {
            let current = try await library.isSaved(ref)
            if current {
                try await library.removeSaved(ref)
            } else {
                try await library.save(ref)
            }
            isSaved = !current
            errorMessage = nil
        } catch {
            // Self-correcting: a throw here is not proof the write didn't
            // happen, so re-read rather than assume it failed cleanly.
            isSaved = (try? await library.isSaved(ref)) ?? isSaved
            errorMessage = SaveErrorPolicy.updateFailedMessage
        }
    }
}

extension View {
    func savedMenu(ref: HadithRef, library: Library?) -> some View {
        modifier(SavedMenu(ref: ref, library: library))
    }
}
