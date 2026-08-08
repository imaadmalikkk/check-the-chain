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
            .navigationTitle("Search")
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
            if model.query.isEmpty { prompt }
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

    private var prompt: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Palette.inkFaint)
            Text("Search by meaning or wording")
                .font(.callout)
                .foregroundStyle(Palette.inkMuted)
            Text(app.isSemanticSearchReady
                 ? "Paste a hadith you've been sent, or describe one."
                 : "Preparing semantic search…")
                .font(.footnote)
                .foregroundStyle(Palette.inkFaint)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 80)
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
