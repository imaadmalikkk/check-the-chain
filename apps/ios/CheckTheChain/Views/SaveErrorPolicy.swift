import SwiftUI

/// The one message every `toggleSaved`-adjacent failure surfaces: the detail
/// page's star, the context menu, and the dangling row's Remove.
///
/// The design doc requires `toggleSaved` failures to be surfaced rather than
/// swallowed — it is the one persistence operation in this feature the user
/// explicitly asked for, so it must not appear to succeed silently. Before
/// this, the three call sites each did something different (a silent
/// self-correcting re-read with no message, `try?` that kept the stale value,
/// a silent `try?` followed by a reload); this is the one message they now
/// share, so "surfaced" means the same thing everywhere instead of three
/// different answers to the same requirement.
enum SaveErrorPolicy {
    static let updateFailedMessage = "Couldn't update your saved list. Try again."
}

extension View {
    /// A brief, unobtrusive alert for a `SaveErrorPolicy` failure.
    ///
    /// `.alert` rather than an inline banner: two of the three call sites — a
    /// context menu row inside a `LazyVStack`, and a toolbar star button —
    /// have no dedicated space for a persistent line without disturbing
    /// layout that isn't otherwise about errors, and an alert needs no new
    /// visual language on top of the app's flat monochrome design system (no
    /// borders, no shadows, colour only on the grading badge) — it's a system
    /// surface, not a custom one.
    func saveErrorAlert(_ message: Binding<String?>) -> some View {
        alert(
            "Couldn't Update",
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { isPresented in
                    if !isPresented { message.wrappedValue = nil }
                }
            ),
            presenting: message.wrappedValue
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { text in
            Text(text)
        }
    }
}
