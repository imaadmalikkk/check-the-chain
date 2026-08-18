import SwiftUI
import HadithKit

/// Search state, kept out of the view so debouncing and cancellation are
/// explicit rather than tangled in body evaluation.
@Observable
@MainActor
final class SearchModel {
    private static let debounce = Duration.milliseconds(300)

    /// Only reschedule when the text actually changed.
    ///
    /// `.searchable` writes through a custom `Binding`, and SwiftUI writes the
    /// same string back more than once — on focus changes and keyboard
    /// updates. A bare `didSet` treated each of those as a new query and
    /// cancelled the in-flight task, which search never noticed because it
    /// finishes in milliseconds, and answering never survived because it takes
    /// seconds. The summary would simply never appear.
    var query = "" { didSet { if query != oldValue { scheduleSearch() } } }
    var collectionFilter: Set<String> = []
    var gradingFilter: Set<Grading> = []

    /// Off by default. Ask costs several seconds of model time, so it is
    /// something the reader opts into rather than something that happens to
    /// every query they type.
    var isAskMode = false { didSet { if isAskMode != oldValue { scheduleSearch() } } }

    private(set) var results: [SearchResult] = []
    private(set) var isSearching = false
    private(set) var hasSearched = false
    private(set) var answer: Answer?
    private(set) var isAnswering = false

    private let engine: SearchEngine
    /// Read live rather than captured.
    ///
    /// `AppModel` builds the answer engine *after* the embedder finishes
    /// warming, which is well after the corpus goes `.ready` and this model is
    /// constructed in `onAppear`. Capturing the value here caught nil every
    /// time and kept it for the life of the screen, so Ask silently did
    /// nothing — search ran, results appeared, and no summary ever came.
    private let answerEngine: @MainActor () -> AnswerEngine?
    private var task: Task<Void, Never>?

    init(engine: SearchEngine, answerEngine: @escaping @MainActor () -> AnswerEngine?) {
        self.engine = engine
        self.answerEngine = answerEngine
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

    /// The narrations the summary was drawn from, in the model's order.
    ///
    /// Taken straight from the answer rather than looked up in `results`. The
    /// answer engine retrieves its own candidates with a smaller limit, and RRF
    /// fuses differently at different fetch depths — so the cited hadith are
    /// not guaranteed to appear in this screen's 60, and a lookup would
    /// silently drop the evidence for a summary that stayed on screen.
    ///
    /// Also deliberately not filtered by the collection and grading chips: the
    /// summary is visible, so what it rests on has to be visible too. Hiding a
    /// cited narration would ask the reader to trust a paragraph whose sources
    /// the app is concealing, which is the opposite of this app's purpose.
    var citations: [Hadith] { answer?.citations ?? [] }

    /// Everything else the search turned up, filters applied as normal.
    var uncitedResults: [SearchResult] {
        guard let answer else { return visibleResults }
        let cited = Set(answer.citations.map(\.id))
        return visibleResults.filter { !cited.contains($0.id) }
    }

    private func scheduleSearch() {
        task?.cancel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard text.count >= 3 else {
            results = []
            hasSearched = false
            isSearching = false
            answer = nil
            return
        }

        task = Task { [engine] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }

            isSearching = true
            // A limit of 60 rather than the web's 20: filtering happens after
            // the search, so a narrow collection filter needs enough results to
            // have something left to show.
            let found = (try? await engine.search(query: text, limit: 60)) ?? []
            isSearching = false
            guard !Task.isCancelled else { return }
            results = found
            hasSearched = true
            answer = nil

            // Answering runs after results are on screen, not instead of them.
            // It takes seconds where search takes milliseconds, and a reader
            // who finds what they wanted in the list should never be waiting
            // on a paragraph they did not ask for.
            guard isAskMode, let answerEngine = answerEngine(), !found.isEmpty else { return }
            isAnswering = true
            let produced = await answerEngine.answer(text)
            isAnswering = false
            guard !Task.isCancelled else { return }
            answer = produced
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
            .libraryToolbar(corpus: corpus)
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
            if model == nil {
                model = SearchModel(engine: corpus.engine) { app.answerEngine }
            }
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

                if model.isAnswering {
                    answeringIndicator
                } else if let answer = model.answer {
                    AnswerCard(answer: answer)
                }

                ForEach(model.visibleResults) { result in
                    NavigationLink(value: Route.hadith(result.hadith.collectionSlug, result.hadith.number)) {
                        HadithCard(hadith: result.hadith, query: model.query, score: result.score)
                    }
                    .buttonStyle(.plain)
                    .savedMenu(
                        ref: HadithRef(
                            collectionSlug: result.hadith.collectionSlug,
                            number: result.hadith.number
                        )
                    )
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

    /// Cited narrations carry no score: the model chose them, so a relevance
    /// percentage from the search that fetched them is answering a question
    /// nobody asked.
    private func resultCard(_ hadith: Hadith, query: String, score: Int? = nil) -> some View {
        NavigationLink(value: Route.hadith(hadith.collectionSlug, hadith.number)) {
            HadithCard(hadith: hadith, query: query, score: score)
        }
        .buttonStyle(.plain)
        .savedMenu(ref: HadithRef(collectionSlug: hadith.collectionSlug, number: hadith.number))
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

    /// Deliberately a card in the results flow rather than an overlay: the
    /// results underneath are already usable, and dimming them to wait for a
    /// summary would take away the thing that already works.
    private var answeringIndicator: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Reading the narrations…")
                .font(.footnote)
                .foregroundStyle(Palette.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
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

    /// The Ask control, and the explanation when it is visible but idle.
    ///
    /// Drawn only when the device could ever run the model. On hardware
    /// without Apple Intelligence there is no control and no note — the reader
    /// is never shown a feature they cannot have.
    @ViewBuilder
    private func askToggle(_ model: SearchModel) -> some View {
        @Bindable var model = model
        let availability = app.answerAvailability

        if availability != .ineligibleDevice {
            VStack(spacing: 8) {
                Button {
                    model.isAskMode.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                        Text("Ask")
                    }
                    .font(.subheadline.weight(model.isAskMode ? .semibold : .regular))
                    .foregroundStyle(model.isAskMode ? Palette.ground : Palette.inkBody)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background {
                        Capsule().fill(model.isAskMode ? Palette.ink : Palette.chip)
                    }
                }
                .buttonStyle(.plain)
                .disabled(availability != .available)
                .opacity(availability == .available ? 1 : 0.5)
                .accessibilityIdentifier("askToggle")
                // The resolved availability, published for the same reason
                // `RootView` publishes the resolved colour scheme: a test
                // cannot otherwise tell "the model declined" from "the model
                // was never reachable", and those need different fixes.
                .accessibilityValue(String(describing: availability))

                AnswerUnavailableNote(availability: availability)
                    .padding(.horizontal, 32)
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .padding(.bottom, 12)
        }
    }

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

            askToggle(model)

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
