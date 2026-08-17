import SwiftUI
import HadithKit

/// Search state, kept out of the view so debouncing and cancellation are
/// explicit rather than tangled in body evaluation.
@Observable
@MainActor
final class SearchModel {
    private static let debounce = Duration.milliseconds(300)

    var query = "" { didSet { scheduleSearch() } }
    var collectionFilter: Set<String> = []
    var gradingFilter: Set<Grading> = []

    private(set) var results: [SearchResult] = []
    private(set) var isSearching = false
    private(set) var hasSearched = false

    private let engine: SearchEngine
    private var task: Task<Void, Never>?

    init(engine: SearchEngine) {
        self.engine = engine
    }

    /// Filters are applied to the returned results rather than pushed into the
    /// query, exactly as the web app does. Narrowing the search itself would
    /// change the ranking, and a filter should reveal what's already there — not
    /// promote different hadith into the top ten.
    var visibleResults: [SearchResult] {
        results.filter { result in
            (collectionFilter.isEmpty || collectionFilter.contains(result.hadith.collectionSlug))
                && (gradingFilter.isEmpty || gradingFilter.contains(result.hadith.grading))
        }
    }

    var hasActiveFilters: Bool { !collectionFilter.isEmpty || !gradingFilter.isEmpty }

    private func scheduleSearch() {
        task?.cancel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard text.count >= 3 else {
            results = []
            hasSearched = false
            isSearching = false
            return
        }

        task = Task { [engine] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }

            isSearching = true
            defer { isSearching = false }

            // A limit of 60 rather than the web's 20: filtering happens after
            // the search, so a narrow collection filter needs enough results to
            // have something left to show.
            let found = (try? await engine.search(query: text, limit: 60)) ?? []
            guard !Task.isCancelled else { return }
            results = found
            hasSearched = true
        }
    }
}

struct SearchView: View {
    let corpus: Corpus
    /// Switches to the Browse tab.
    ///
    /// The canvas needs its own way there. While the search tab is active iOS 26
    /// collapses the entire tab group behind a single button, so on a cold
    /// launch — which lands here — "Browse" does not exist on screen at all and
    /// getting to it means tapping a collapsed control that gives no hint of
    /// what it holds.
    let showBrowse: () -> Void

    @Environment(AppModel.self) private var app
    @State private var model: SearchModel?
    @State private var path = NavigationPath()
    @State private var showFilters = false

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let model {
                    content(model)
                } else {
                    Color.clear
                }
            }
            .background(Palette.ground)
            // No title. The screen is a search field and a wordmark; a large
            // "Search" heading above them would be labelling the obvious, and
            // the reference designs put nothing in the top bar at all.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Route.self) { $0.destination(corpus: corpus) }
        }
        .searchable(
            text: Binding(
                get: { model?.query ?? "" },
                set: { model?.query = $0 }
            ),
            prompt: "Search 47,000 hadith"
        )
        .onAppear {
            if model == nil { model = SearchModel(engine: corpus.engine) }
        }
    }

    @ViewBuilder
    private func content(_ model: SearchModel) -> some View {
        @Bindable var model = model

        ScrollView {
            LazyVStack(spacing: 10) {
                if !model.results.isEmpty {
                    filters(model)
                }

                ForEach(model.visibleResults) { result in
                    NavigationLink(value: Route.hadith(result.hadith.collectionSlug, result.hadith.number)) {
                        HadithCard(hadith: result.hadith, query: model.query, score: result.score)
                    }
                    .buttonStyle(.plain)
                }

                if model.hasSearched && model.visibleResults.isEmpty {
                    emptyState(model)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 40)
            .readableWidth()
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .overlay(alignment: .top) {
            if model.isSearching { searchingIndicator }
        }
        .overlay {
            if model.query.isEmpty { prompt(model) }
        }
    }

    private func filters(_ model: SearchModel) -> some View {
        @Bindable var model = model

        return VStack(spacing: 8) {
            FilterChips(
                options: Grading.allCases
                    .filter { $0 != .unknown }
                    .map { .init(value: $0, label: $0.rawValue) },
                selection: $model.gradingFilter
            )
            FilterChips(
                options: Self.collectionsPresent(in: model.results)
                    .map { .init(value: $0.slug, label: $0.shortName) },
                selection: $model.collectionFilter
            )
        }
        .padding(.horizontal, -16)
        .padding(.bottom, 4)
    }

    /// Only offer collections that actually appear in the results. A chip that
    /// filters to zero is noise.
    private static func collectionsPresent(in results: [SearchResult]) -> [HadithCollection] {
        let slugs = Set(results.map(\.hadith.collectionSlug))
        return HadithCollection.all.filter { slugs.contains($0.slug) }
    }

    private var searchingIndicator: some View {
        ProgressView()
            .controlSize(.small)
            .padding(10)
            .glassSurface(in: .circle)
            .padding(.top, 8)
    }

    /// Example queries, tapped to fill the field.
    ///
    /// One of each kind the two search legs are for: a verbatim fragment that
    /// keyword search nails, and two paraphrases that only the vector leg finds.
    /// They are examples, not features — the point is to show in three words
    /// that you can type what you remember rather than what was written.
    private static let suggestions: [(icon: String, text: String)] = [
        ("quote.opening", "reward of deeds"),
        ("house", "good neighbours"),
        ("hand.raised", "forgiving others"),
    ]

    /// The opening screen: mostly empty, with the search field the only thing
    /// asking to be used.
    private func prompt(_ model: SearchModel) -> some View {
        VStack(spacing: 0) {
            Spacer()

            Text("check the chain")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Palette.inkMuted)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Button(action: showBrowse) {
                HStack(spacing: 4) {
                    Text("Browse \(HadithCollection.all.count) collections")
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                }
                .font(.footnote)
                .foregroundStyle(Palette.inkMuted)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("browseFromCanvas")
            .padding(.top, 14)

            Spacer()

            if !app.isSemanticSearchReady {
                // Search still works while the model loads — it degrades to
                // keyword-only — so this is a status line, not a blocker.
                Text("Preparing semantic search…")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkFaint)
                    .padding(.bottom, 14)
            }

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Self.suggestions, id: \.text) { suggestion in
                        Button {
                            model.query = suggestion.text
                        } label: {
                            Label(suggestion.text, systemImage: suggestion.icon)
                                .font(.subheadline)
                                .foregroundStyle(Palette.inkBody)
                                .lineLimit(1)
                                .chipSurface()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .padding(.bottom, 12)
        }
    }

    private func emptyState(_ model: SearchModel) -> some View {
        ContentUnavailableView {
            Label("No matches", systemImage: "magnifyingglass")
        } description: {
            Text(model.hasActiveFilters
                 ? "No results match the selected filters."
                 : "Try describing the hadith in different words.")
        }
        .padding(.top, 40)
    }
}
