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

    func body(content: Content) -> some View {
        content
            .contextMenu {
                if library != nil {
                    Button {
                        Task { await toggle() }
                    } label: {
                        Label(
                            isSaved ? "Remove from Saved" : "Save",
                            systemImage: isSaved ? "bookmark.slash" : "bookmark"
                        )
                    }
                }
            }
            .task {
                guard let library else { return }
                isSaved = (try? await library.isSaved(ref)) ?? false
            }
    }

    private func toggle() async {
        guard let library else { return }
        isSaved = (try? await library.toggleSaved(ref)) ?? isSaved
    }
}

extension View {
    func savedMenu(ref: HadithRef, library: Library?) -> some View {
        modifier(SavedMenu(ref: ref, library: library))
    }
}
