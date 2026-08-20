import SwiftUI
import HadithKit

/// Navigation destinations, addressed by the same identifiers the web app uses
/// in its URLs (`/hadith/{slug}/{number}`, `/browse/{slug}`). Keeping the shapes
/// aligned means universal links can be added later by mapping a path to a case,
/// with no rework of the navigation itself.
enum Route: Hashable {
    case collection(String)
    case chapter(String, Int)
    case hadith(String, String)
    case isnad(String, String)

    @ViewBuilder
    func destination(corpus: Corpus) -> some View {
        switch self {
        case .collection(let slug):
            CollectionView(corpus: corpus, slug: slug)
        case .chapter(let slug, let chapterID):
            ChapterView(corpus: corpus, slug: slug, chapterID: chapterID)
        case .hadith(let slug, let number):
            HadithDetailView(corpus: corpus, slug: slug, number: number)
        case .isnad(let slug, let number):
            IsnadView(corpus: corpus, slug: slug, number: number)
        }
    }
}
