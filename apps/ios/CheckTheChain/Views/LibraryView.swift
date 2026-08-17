import SwiftUI
import HadithKit

/// What the app remembers: what you starred, and what you opened.
///
/// A sheet behind a toolbar icon rather than a fourth tab. With
/// `Tab(role: .search)` active, iOS 26 folds the whole tab group behind one
/// collapsed button, so a fourth item would make an existing problem worse.
struct LibraryView: View {
    let corpus: Corpus

    private enum Segment: String, CaseIterable, Identifiable {
        case saved = "Saved"
        case recent = "Recent"
        var id: Self { self }
    }

    @Environment(\.dismiss) private var dismiss
    @AppStorage(PreferenceKey.recordsHistory) private var recordsHistory = true

    @State private var segment: Segment = .saved
    @State private var refs: [HadithRef] = []
    @State private var resolved: [HadithRef: Hadith] = [:]
    @State private var isLoading = true
    @State private var path = NavigationPath()
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack(path: $path) {
            content
                .background(Palette.ground)
                .navigationTitle(segment.rawValue)
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: Route.self) { $0.destination(corpus: corpus) }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) { overflow }
                }
                .safeAreaInset(edge: .top) { picker }
        }
        .task(id: segment) { await reload() }
        // `.task(id: segment)` is on the stack, not the pushed detail view —
        // pushing a hadith *inside* this sheet doesn't change `segment` and
        // doesn't dismiss the stack, so it never reruns on its own. Unstar
        // from the pushed detail page, come back with the system back
        // button, and without this the row would still be sitting here.
        // `path` is already `@State` right here, so returning to root is
        // exactly the moment this can catch.
        .onChange(of: path) { _, newPath in
            guard newPath.isEmpty else { return }
            Task { await reload() }
        }
        .saveErrorAlert($errorMessage)
    }

    private var picker: some View {
        Picker("View", selection: $segment) {
            ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    /// The history controls live here rather than in a settings screen, because
    /// there is no settings screen and this is where the thing they control is.
    private var overflow: some View {
        Menu {
            Toggle("Record history", isOn: $recordsHistory)
            Button("Clear history", systemImage: "trash", role: .destructive) {
                Task {
                    do {
                        try await corpus.library?.clearRecent()
                        errorMessage = nil
                    } catch {
                        errorMessage = SaveErrorPolicy.updateFailedMessage
                    }
                    await reload()
                }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityIdentifier("libraryOverflow")
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
        } else if refs.isEmpty {
            empty
        } else {
            // `ScrollView`/`LazyVStack`, same as every other list in the app,
            // rather than `List`. A `List` was tried so Saved rows could carry
            // a real `.swipeActions`, but a `NavigationLink` inside a `List`
            // draws a system disclosure chevron that `.buttonStyle(.plain)`
            // does not suppress — it sat outside the card, on the ground
            // colour, and it also ate ~30pt from the row so Saved cards were
            // narrower than the identical cards everywhere else. Suppressing
            // it means fighting `List` (there is no public modifier for it);
            // getting `readableWidth()`, the vertical rhythm, and every
            // stripped List surface back to matching every other screen is
            // more code, permanently, to buy one gesture this screen is the
            // only place in the app to use.
            //
            // `.savedMenu` — the long-press affordance already on every
            // result card — covers removal instead: for a Saved row it always
            // reads "Remove from Saved" and removes it (see `SavedMenu`'s doc
            // comment for why the label is no longer state-dependent). That
            // makes this screen's rows behave exactly like the identical card
            // everywhere else, rather than inventing a second, sheet-only way
            // to do the same thing.
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(refs, id: \.self) { ref in
                        row(ref)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 40)
                .readableWidth()
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
        }
    }

    @ViewBuilder
    private func row(_ ref: HadithRef) -> some View {
        if let hadith = resolved[ref] {
            NavigationLink(value: Route.hadith(ref.collectionSlug, ref.number)) {
                HadithCard(hadith: hadith)
            }
            .buttonStyle(.plain)
            .savedMenu(ref: ref, library: corpus.library) {
                Task { await reload() }
            }
        } else {
            dangling(ref)
        }
    }

    /// A saved hadith the corpus no longer has — renumbered or dropped by a
    /// later pipeline run. Shown rather than skipped: silently dropping refs is
    /// how someone loses saved items without ever learning they had them.
    private func dangling(_ ref: HadithRef) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(HadithCollection.named(slug: ref.collectionSlug)?.name ?? ref.collectionSlug) \(ref.number)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink)
            Text("No longer in this corpus.")
                .font(.caption)
                .foregroundStyle(Palette.inkMuted)
            Button("Remove") {
                Task {
                    guard let library = corpus.library else { return }
                    do {
                        // Segment-specific: under Recent the ref lives in
                        // `ViewedHadith`, not `SavedHadith`. Each segment's
                        // row must clear the store it actually came from.
                        switch segment {
                        case .saved: try await library.removeSaved(ref)
                        case .recent: try await library.removeRecent(ref)
                        }
                        errorMessage = nil
                    } catch {
                        errorMessage = SaveErrorPolicy.updateFailedMessage
                    }
                    await reload()
                }
            }
            .font(.caption.weight(.medium))
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var empty: some View {
        ContentUnavailableView {
            Label(
                segment == .saved ? "Nothing saved yet" : "Nothing read yet",
                systemImage: segment == .saved ? "bookmark" : "clock"
            )
        } description: {
            Text(segment == .saved
                 ? "Tap the bookmark on any hadith to keep it here."
                 : "Hadith you open will appear here.")
        }
        .padding(.top, 40)
    }

    private func reload() async {
        // Captured up front rather than read again after the awaits below:
        // `.task(id: segment)` cancels the in-flight task when the segment
        // changes, but none of `library.saved()`, `library.recent()`, or
        // `store.hadith(refs:)` check `Task.isCancelled` — they are plain
        // actor calls that run to completion regardless. Without this guard a
        // slow call for the *previous* segment can finish after a fast call
        // for the new one and overwrite `refs`/`resolved` with stale data,
        // leaving the picker reading one segment while the list shows
        // another's rows. Comparing against `self.segment` at write time is
        // what makes a late, stale completion a no-op instead of a visible
        // regression.
        let requested = segment

        // No `await` yet, so `segment` cannot have moved since `requested` was
        // captured — nothing stale to guard against on this branch.
        guard let library = corpus.library else {
            refs = []
            isLoading = false
            return
        }
        isLoading = true
        let next = switch requested {
        case .saved: (try? await library.saved()) ?? []
        case .recent: (try? await library.recent()) ?? []
        }
        let nextResolved = (try? await corpus.store.hadith(refs: next)) ?? [:]

        guard segment == requested else { return }
        resolved = nextResolved
        refs = next
        isLoading = false
    }
}

extension View {
    /// Puts the bookmark icon on a tab root, so the list is reachable from
    /// wherever you are rather than only from the launch screen.
    func libraryToolbar(corpus: Corpus) -> some View {
        modifier(LibraryToolbar(corpus: corpus))
    }
}

private struct LibraryToolbar: ViewModifier {
    let corpus: Corpus
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                if corpus.library != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { isPresented = true } label: {
                            Image(systemName: "bookmark")
                        }
                        .accessibilityLabel("Saved and recent")
                        .accessibilityIdentifier("libraryButton")
                    }
                }
            }
            .sheet(isPresented: $isPresented) {
                LibraryView(corpus: corpus)
            }
    }
}
