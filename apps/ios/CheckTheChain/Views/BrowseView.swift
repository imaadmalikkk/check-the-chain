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
            .navigationTitle("Browse")
            .navigationDestination(for: Route.self) { $0.destination(corpus: corpus) }
        }
        .task {
            counts = (try? await corpus.store.collectionCounts()) ?? [:]
        }
    }

    private func section(_ group: HadithCollection.Group) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(group.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.inkMuted)
                .textCase(.uppercase)
                .tracking(0.6)

            VStack(spacing: 8) {
                ForEach(HadithCollection.inGroup(group)) { collection in
                    NavigationLink(value: Route.collection(collection.slug)) {
                        row(collection)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func row(_ collection: HadithCollection) -> some View {
        // Side by side normally; stacked once the text is large enough that
        // sharing a line squeezes the count until "7,276" wraps to "7,27 / 6".
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                title(collection)
                Spacer(minLength: 8)
                trailing(collection).padding(.top, 2)
            }
            VStack(alignment: .leading, spacing: 10) {
                title(collection)
                trailing(collection)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 16)
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
            LazyVStack(spacing: 8) {
                ForEach(chapters) { chapter in
                    NavigationLink(value: Route.chapter(slug, chapter.chapterID)) {
                        row(chapter)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .readableWidth()
        }
        .background(Palette.ground)
        .navigationTitle(collection?.shortName ?? "Collection")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            chapters = (try? await corpus.store.chapters(slug: slug)) ?? []
        }
    }

    private func row(_ chapter: Chapter) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 14)
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
