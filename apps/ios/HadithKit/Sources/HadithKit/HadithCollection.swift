import Foundation

/// Static metadata for the 16 shipped collections.
/// Ported verbatim from `apps/web/src/lib/collections.ts` — the descriptions and
/// grouping are editorial content, not data, so they live in code on both sides.
public struct HadithCollection: Sendable, Identifiable, Hashable {
    public enum Group: String, Sendable, CaseIterable {
        case nineBooks = "nine-books"
        case other = "other"
        case forties = "forties"

        public var title: String {
            switch self {
            case .nineBooks: "The Nine Books"
            case .other: "Other Collections"
            case .forties: "Forties"
            }
        }
    }

    public let name: String
    public let slug: String
    public let group: Group
    public let summary: String

    public var id: String { slug }
}

extension HadithCollection {
    public static let all: [HadithCollection] = [
        .init(name: "Sahih al-Bukhari", slug: "sahih-al-bukhari", group: .nineBooks,
              summary: "The most authentic collection, compiled by Imam al-Bukhari (d. 870 CE)."),
        .init(name: "Sahih Muslim", slug: "sahih-muslim", group: .nineBooks,
              summary: "The second most authentic collection, compiled by Imam Muslim (d. 875 CE)."),
        .init(name: "Sunan al-Nasa'i", slug: "sunan-al-nasai", group: .nineBooks,
              summary: "Known for its strict criteria, compiled by Imam al-Nasa'i (d. 915 CE)."),
        .init(name: "Sunan Abi Dawud", slug: "sunan-abi-dawud", group: .nineBooks,
              summary: "Focused on legal hadith, compiled by Imam Abu Dawud (d. 889 CE)."),
        .init(name: "Sunan Ibn Majah", slug: "sunan-ibn-majah", group: .nineBooks,
              summary: "Part of the six major collections, compiled by Imam Ibn Majah (d. 887 CE)."),
        .init(name: "Jami' al-Tirmidhi", slug: "jami-al-tirmidhi", group: .nineBooks,
              summary: "Known for grading each hadith, compiled by Imam al-Tirmidhi (d. 892 CE)."),
        .init(name: "Muwatta Malik", slug: "muwatta-malik", group: .nineBooks,
              summary: "The earliest compiled collection, by Imam Malik (d. 795 CE)."),
        .init(name: "Musnad Ahmad ibn Hanbal", slug: "musnad-ahmad", group: .nineBooks,
              summary: "One of the largest collections, compiled by Imam Ahmad (d. 855 CE)."),
        .init(name: "Mishkat al-Masabih", slug: "mishkat-al-masabih", group: .other,
              summary: "A comprehensive compilation drawing from the six major books and more."),
        .init(name: "Riyad as-Salihin", slug: "riyad-as-salihin", group: .other,
              summary: "Gardens of the Righteous, compiled by Imam al-Nawawi (d. 1277 CE)."),
        .init(name: "Bulugh al-Maram", slug: "bulugh-al-maram", group: .other,
              summary: "Hadith related to jurisprudence, compiled by Ibn Hajar al-Asqalani (d. 1449 CE)."),
        .init(name: "Al-Adab Al-Mufrad", slug: "al-adab-al-mufrad", group: .other,
              summary: "Hadith on manners and etiquette, compiled by Imam al-Bukhari."),
        .init(name: "Shama'il Muhammadiyah", slug: "shamail-muhammadiyah", group: .other,
              summary: "Description of Prophet Muhammad's appearance and character, by Imam al-Tirmidhi."),
        .init(name: "The Forty Hadith of Imam Nawawi", slug: "nawawi-40", group: .forties,
              summary: "40 foundational hadith selected by Imam al-Nawawi."),
        .init(name: "The Forty Hadith Qudsi", slug: "qudsi-40", group: .forties,
              summary: "40 hadith in which Allah speaks in the first person."),
        .init(name: "The Forty Hadith of Shah Waliullah", slug: "shah-waliullah-40", group: .forties,
              summary: "40 hadith selected by Shah Waliullah al-Dihlawi (d. 1762 CE)."),
    ]

    private static let bySlug = Dictionary(uniqueKeysWithValues: all.map { ($0.slug, $0) })

    public static func named(slug: String) -> HadithCollection? { bySlug[slug] }

    public static func inGroup(_ group: Group) -> [HadithCollection] {
        all.filter { $0.group == group }
    }

    /// A shorter label for chips and dense lists, where the full names run long.
    public var shortName: String {
        switch slug {
        case "sahih-al-bukhari": "Bukhari"
        case "sahih-muslim": "Muslim"
        case "sunan-al-nasai": "Nasa'i"
        case "sunan-abi-dawud": "Abi Dawud"
        case "sunan-ibn-majah": "Ibn Majah"
        case "jami-al-tirmidhi": "Tirmidhi"
        case "muwatta-malik": "Malik"
        case "musnad-ahmad": "Ahmad"
        case "mishkat-al-masabih": "Mishkat"
        case "riyad-as-salihin": "Riyad as-Salihin"
        case "bulugh-al-maram": "Bulugh al-Maram"
        case "al-adab-al-mufrad": "Adab al-Mufrad"
        case "shamail-muhammadiyah": "Shama'il"
        case "nawawi-40": "Nawawi 40"
        case "qudsi-40": "Qudsi 40"
        case "shah-waliullah-40": "Shah Waliullah 40"
        default: name
        }
    }
}
