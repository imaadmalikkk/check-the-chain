import SwiftUI
import HadithKit

struct BrowseView: View {
    let corpus: Corpus

    @State private var counts: [String: Int] = [:]
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    ForEach(HadithCollection.Group.allCases, id: \.self) { group in
                        section(group)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
                .readableWidth()
            }
            .background(Palette.ground)
            .scrollEdgeEffectStyle(.soft, for: .top)
            // Inline, not a large title. A large title is a heading the size of
            // a headline for a screen whose content is already labelled by
            // section — and it is the loudest thing on an otherwise quiet page.
            .navigationTitle("Browse")
            .navigationBarTitleDisplayMode(.inline)
            .libraryToolbar(corpus: corpus)
            .navigationDestination(for: Route.self) { $0.destination(corpus: corpus) }
        }
        .task {
            counts = (try? await corpus.store.collectionCounts()) ?? [:]
        }
    }

    /// One surface per group, rows divided by hairlines.
    ///
    /// These collections are peers, and a stack of individually shadowed cards
    /// turned a list of sixteen into sixteen separate objects to look at. One
    /// block per group says "these belong together" and gives the eye a single
    /// edge to follow down.
    private func section(_ group: HadithCollection.Group) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(group.title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Palette.inkMuted)
                .padding(.leading, 6)

            let collections = HadithCollection.inGroup(group)
            VStack(spacing: 0) {
                ForEach(Array(collections.enumerated()), id: \.element.id) { index, collection in
                    NavigationLink(value: Route.collection(collection.slug)) {
                        row(collection)
                    }
                    .buttonStyle(.plain)
                    if index < collections.count - 1 {
                        RowDivider()
                    }
                }
            }
            .groupedSurface()
        }
    }

    private func row(_ collection: HadithCollection) -> some View {
        // A plain row, not `ViewThatFits`. That measured the summary's *ideal*
        // width — the width it would take unwrapped — which for a sentence is
        // always wider than the screen, so the fallback stacked layout won won
        // every time and the count landed on its own line under the summary.
        // Keeping the count unwrappable is what the stacking was for, and
        // `lineLimit(1).fixedSize` does that on its own.
        HStack(alignment: .center, spacing: 12) {
            title(collection)
            Spacer(minLength: 8)
            trailing(collection)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }

    private func title(_ collection: HadithCollection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(collection.name)
                .font(.body.weight(.medium))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.leading)
            Text(collection.summary)
                .font(.caption)
                .foregroundStyle(Palette.inkMuted)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
        }
    }

    private func trailing(_ collection: HadithCollection) -> some View {
        HStack(spacing: 6) {
            if let count = counts[collection.slug] {
                Text(count.formatted())
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Palette.inkBody)
                    // A wrapped number is unreadable at any size.
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Palette.inkFaint)
        }
    }
}

/// A collection's chapters. Chapters, not a flat 7,000-item list — Bukhari alone
/// is unreadable without them.
struct CollectionView: View {
    let corpus: Corpus
    let slug: String

    @State private var chapters: [Chapter] = []

    private var collection: HadithCollection? { HadithCollection.named(slug: slug) }

    var body: some View {
        ScrollView {
            // One surface for the whole chapter list, same as Browse. Bukhari
            // has 97 chapters; as separate cards that is 97 shadows.
            LazyVStack(spacing: 0) {
                ForEach(Array(chapters.enumerated()), id: \.element.id) { index, chapter in
                    NavigationLink(value: Route.chapter(slug, chapter.chapterID)) {
                        row(chapter)
                    }
                    .buttonStyle(.plain)
                    if index < chapters.count - 1 {
                        RowDivider()
                    }
                }
            }
            .groupedSurface()
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .readableWidth()
        }
        .background(Palette.ground)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle(collection?.shortName ?? "Collection")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            chapters = (try? await corpus.store.chapters(slug: slug)) ?? []
        }
    }

    private func row(_ chapter: Chapter) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(chapter.nameEnglish)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.leading)
                if !chapter.nameArabic.isEmpty {
                    Text(chapter.nameArabic)
                        .font(.custom(ArabicFont.regular, size: 15))
                        .foregroundStyle(Palette.inkMuted)
                        .environment(\.layoutDirection, .rightToLeft)
                }
            }
            Spacer(minLength: 8)
            Text("\(chapter.hadithCount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Palette.inkFaint)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Palette.inkFaint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }
}

/// A chapter's hadith, paged. 50 at a time, matching the web app's page size.
struct ChapterView: View {
    let corpus: Corpus
    let slug: String
    let chapterID: Int

    @State private var hadith: [Hadith] = []
    @State private var chapter: Chapter?
    @State private var total = 0
    @State private var page = 0
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(hadith) { item in
                    NavigationLink(value: Route.hadith(item.collectionSlug, item.number)) {
                        HadithCard(hadith: item)
                    }
                    .buttonStyle(.plain)
                    .savedMenu(
                        ref: HadithRef(collectionSlug: item.collectionSlug, number: item.number),
                        library: corpus.library
                    )
                }

                if hadith.count < total {
                    Button {
                        Task { await loadNextPage() }
                    } label: {
                        if isLoading {
                            ProgressView()
                        } else {
                            Text("Load more (\(hadith.count) of \(total))")
                                .font(.footnote.weight(.medium))
                        }
                    }
                    .buttonStyle(.glass)
                    .padding(.vertical, 12)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .readableWidth()
        }
        .background(Palette.ground)
        // The chapter's name, not "Book 7" — someone reading "The Book of
        // Prayer" should see that at the top, not an index number.
        .navigationTitle(chapter?.nameEnglish ?? "Book \(chapterID)")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard hadith.isEmpty else { return }
            chapter = try? await corpus.store.chapters(slug: slug).first { $0.chapterID == chapterID }
            await loadNextPage()
        }
    }

    private func loadNextPage() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        guard let result = try? await corpus.store.page(slug: slug, chapterID: chapterID, page: page)
        else { return }
        hadith.append(contentsOf: result.items)
        total = result.total
        page += 1
    }
}
