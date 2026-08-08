import SwiftUI
import HadithKit

/// The opening screen: one hadith, given room to breathe.
///
/// Deliberately not a dashboard. A reference app's home screen earns nothing by
/// listing statistics — the useful thing it can do is put a single narration in
/// front of someone and let them read it.
struct TodayView: View {
    let corpus: Corpus

    @State private var hadith: Hadith?
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    if let hadith {
                        NavigationLink(value: Route.hadith(hadith.collectionSlug, hadith.number)) {
                            dailyCard(hadith)
                        }
                        .buttonStyle(.plain)
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 60)
                    }

                    disclaimer
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
                .readableWidth()
            }
            .background(Palette.ground)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .navigationTitle("Today")
            .navigationDestination(for: Route.self) { $0.destination(corpus: corpus) }
        }
        .task {
            hadith = try? await corpus.store.hadithOfTheDay()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Hadith of the Day")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Palette.ink)
            Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.subheadline)
                .foregroundStyle(Palette.inkMuted)
        }
        .padding(.top, 8)
    }

    private func dailyCard(_ hadith: Hadith) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                if hadith.grading != .unknown {
                    GradingBadge(grading: hadith.grading)
                }
                Spacer(minLength: 0)
                Text(hadith.reference)
                    .font(.caption)
                    .foregroundStyle(Palette.inkFaint)
            }

            if !hadith.arabic.isEmpty {
                Text(hadith.arabic)
                    .foregroundStyle(Palette.ink)
                    .arabicText(size: 21)
                    .lineLimit(6)
            }

            if !hadith.narrator.isEmpty {
                Text(hadith.narrator)
                    .font(.subheadline.italic())
                    .foregroundStyle(Palette.inkMuted)
            }

            Text(hadith.english)
                .font(.body)
                .foregroundStyle(Palette.inkBody)
                .lineSpacing(5)
                .lineLimit(8)

            Text("Read in full")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Palette.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 22)
    }

    private var disclaimer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(corpus.hadithCount.formatted()) hadith across \(HadithCollection.all.count) collections, searchable offline.")
            Text("This tool searches major hadith collections. It is not a substitute for scholarly verification.")
        }
        .font(.caption)
        .foregroundStyle(Palette.inkFaint)
        .padding(.top, 8)
    }
}
