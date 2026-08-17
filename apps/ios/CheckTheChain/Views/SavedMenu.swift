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

    @Environment(AppModel.self) private var app

    func body(content: Content) -> some View {
        // Guards the modifier itself, not just the button inside it. With
        // only the button guarded, a long-press with no library still lifted
        // the row into a context menu with nothing in it — a visible "this
        // control exists" cue for a feature that, per the README, is
        // supposed to be as if it were never there.
        if app.savedState.isAvailable {
            content.contextMenu {
                // One item, picked from `SavedState.contains`, not two fixed
                // outcomes. The previous version showed both "Save" and
                // "Remove from Saved" unconditionally, because the label used
                // to be read from a private per-view cache refreshed by a
                // `.task` racing the ~0.5s context-menu lift animation — a
                // button could read "Save" from stale state and *delete* the
                // favourite it claimed to create. `SavedState.contains` is a
                // synchronous read of the one shared in-memory set, current
                // as of the moment this menu is built, so there is no async
                // gap left for the label to race.
                if app.savedState.contains(ref) {
                    Button(role: .destructive) {
                        Task { await app.savedState.removeSaved(ref) }
                    } label: {
                        Label("Remove from Saved", systemImage: "bookmark.slash")
                    }
                } else {
                    Button {
                        Task { await app.savedState.save(ref) }
                    } label: {
                        Label("Save", systemImage: "bookmark")
                    }
                }
            }
        } else {
            content
        }
    }
}

extension View {
    func savedMenu(ref: HadithRef) -> some View {
        modifier(SavedMenu(ref: ref))
    }
}
