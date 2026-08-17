import SwiftUI
import HadithKit

/// Long-press a result to star it.
///
/// A modifier applied where cards are used, rather than a parameter on
/// `HadithCard`. The card stays a pure function of a hadith and knows nothing
/// about persistence, and the call sites that need this opt in.
///
/// No star is drawn *on* the card. That would put a glyph on every row for a
/// state that is false almost always.
private struct SavedMenu: ViewModifier {
    let ref: HadithRef
    let library: Library?
    /// Fires after a successful save or remove. `LibraryView` uses this to
    /// reload its Saved list immediately — nothing else about *this*
    /// screen's identity changes when the ref goes in or out of the store,
    /// so nothing else would tell the row's owner to refresh.
    var onChange: (() -> Void)?

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
                    // Two fixed items, not one label picked from cached
                    // state. The previous version read `isSaved` — refreshed
                    // by a `.task` attached right here — to choose between
                    // "Save" and "Remove from Saved". That closed most of the
                    // gap but not all of it: the `.task` is an async actor
                    // read racing a ~0.5s context-menu lift animation, and
                    // `.contextMenu`'s content closure is evaluated (and, per
                    // reports, can be snapshotted for the lift) before an
                    // async read that hasn't landed yet has any chance to
                    // update it. A stale label here isn't cosmetic: this
                    // toggles a real save, so a button that still reads
                    // "Save" because the refresh hasn't landed yet *deletes*
                    // the favourite it claims to create.
                    //
                    // There is no version of "pick the one correct label"
                    // that isn't subject to that same race — the content has
                    // to be known before presentation, and truth is only
                    // knowable by an async read. So this stops trying to show
                    // one correct label and shows both fixed outcomes
                    // instead. Each one's label is a description of exactly
                    // what tapping it does, unconditionally, so neither can
                    // ever disagree with its own action. Whichever one
                    // doesn't apply to the current state is a no-op rather
                    // than a wrong answer: `save` on an already-saved ref is
                    // an upsert that only bumps `savedAt` (see its doc
                    // comment), and `removeSaved` on a ref that isn't saved
                    // is a no-op by construction. Nothing here depends on
                    // `isSaved` being fresh, so there is no gap left to race.
                    Button {
                        Task { await save(library: library) }
                    } label: {
                        Label("Save", systemImage: "bookmark")
                    }
                    Button(role: .destructive) {
                        Task { await remove(library: library) }
                    } label: {
                        Label("Remove from Saved", systemImage: "bookmark.slash")
                    }
                }
                .saveErrorAlert($errorMessage)
        } else {
            content
        }
    }

    private func save(library: Library) async {
        do {
            try await library.save(ref)
            errorMessage = nil
            onChange?()
        } catch {
            errorMessage = SaveErrorPolicy.updateFailedMessage
        }
    }

    private func remove(library: Library) async {
        do {
            try await library.removeSaved(ref)
            errorMessage = nil
            onChange?()
        } catch {
            errorMessage = SaveErrorPolicy.updateFailedMessage
        }
    }
}

extension View {
    func savedMenu(ref: HadithRef, library: Library?, onChange: (() -> Void)? = nil) -> some View {
        modifier(SavedMenu(ref: ref, library: library, onChange: onChange))
    }
}
