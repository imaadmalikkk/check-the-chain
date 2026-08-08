import Foundation
import Testing
@testable import HadithKit

/// The English chain is inferred, not looked up, so these tests are the only
/// thing standing between a reader and a confidently-wrong name.
@Suite("Narrator names")
struct NarratorNameTests {
    @Test("Compound names built from the article")
    func compounds() {
        // One name, not "servant of" + "Allah".
        #expect(NarratorName.english("عبد الله") == "Abdullah")
        #expect(NarratorName.english("عبد الرحمن") == "Abd al-Rahman")
        #expect(NarratorName.english("عبد الرزاق") == "Abd al-Razzaq")
        #expect(NarratorName.english("عبد الله بن عمر") == "Abdullah ibn Umar")
    }

    @Test("The kunya takes the genitive after ibn")
    func kunya() {
        #expect(NarratorName.english("أبو هريرة") == "Abu Hurayra")
        #expect(NarratorName.english("أبي هريرة") == "Abu Hurayra")
        // "Abu Bakr ibn Abi Shayba" is how the literature spells it; "ibn Abu"
        // would be wrong Arabic.
        #expect(NarratorName.english("أبو بكر بن أبي شيبة") == "Abu Bakr ibn Abi Shayba")
    }

    @Test("Chains from Bukhari 1, end to end")
    func bukhariOne() {
        let chain = [
            "الحميدي عبد الله بن الزبير",
            "سفيان",
            "يحيى بن سعيد الأنصاري",
            "محمد بن إبراهيم التيمي",
            "علقمة بن وقاص الليثي",
            "عمر بن الخطاب",
            "رسول الله",
        ]
        let english = chain.map(NarratorName.english)

        #expect(english[1] == "Sufyan")
        #expect(english[2] == "Yahya ibn Sa'id al-Ansari")
        #expect(english[3] == "Muhammad ibn Ibrahim al-Taymi")
        #expect(english[5] == "Umar ibn al-Khattab")
        #expect(english[6] == "the Messenger of Allah \u{FDFA}")
        // al-Humaydi is outside the lexicon, so this is the rule path end to
        // end: split the article, vowel the stem, keep the compound intact.
        #expect(english[0] == "al-Hamidi Abdullah ibn al-Zubayr")
        #expect(english[4] == "Alqama ibn Waqas al-Lithi")
    }

    @Test("The definite article is split off, not fused onto the name")
    func definiteArticle() {
        // Fused, these read "Alhamidi" and "Allithi" — which look like names
        // and are not.
        #expect(NarratorName.english("الحميدي") == "al-Hamidi")
        #expect(NarratorName.english("الليثي") == "al-Lithi")
        // Already in the lexicon, so the article never gets split twice.
        #expect(NarratorName.english("الزهري") == "al-Zuhri")
        #expect(NarratorName.english("الله") == "Allah")
    }

    @Test("Sentence fragments read as sentences, not as people")
    func fragments() {
        // The upstream parse splits on transmission verbs and keeps whatever is
        // left, so these genuinely appear as chain links. Transliterating them
        // would invent narrators named "Qal" and "Wahadathana".
        #expect(NarratorName.english("قال") == "said")
        #expect(NarratorName.english("وحدثنا") == "and narrated to us")
        #expect(NarratorName.english("أبيه") == "his father")
        #expect(NarratorName.english("النبي") == "the Prophet \u{FDFA}")
        #expect(NarratorName.english("أبي هريرة قال قال رسول الله")
                == "Abu Hurayra said said the Messenger of Allah \u{FDFA}")
    }

    @Test("Unknown names get vowels rather than a consonant run")
    func fallbackVowels() {
        // Arabic writes no short vowels, so the rule has to supply them. These
        // are the patterns it is expected to get right.
        #expect(NarratorName.english("قتادة") == "Qatada")
        #expect(NarratorName.english("منصور") == "Mansur")
        #expect(NarratorName.english("كثير") == "Kathir")
    }

    @Test("Never empty, never crashes, always Latin")
    func robustness() async throws {
        let store = try TestFixtures.corpus().store

        // A broad sweep of real chains rather than a handful of samples: the
        // rule path takes whatever the sanad parser produced, and the only way
        // to know it has no input it chokes on is to feed it a lot of them.
        var seen = Set<String>()
        for slug in HadithCollection.all.map(\.slug) {
            let page = try await store.page(slug: slug, page: 0, pageSize: 400)
            for hadith in page.items {
                for narrator in hadith.isnadNarrators { seen.insert(narrator) }
            }
        }
        #expect(seen.count > 1_000)

        for narrator in seen {
            let english = NarratorName.english(narrator)
            #expect(!english.isEmpty, "empty rendering for \(narrator)")
            #expect(
                english.unicodeScalars.allSatisfy { !Self.isUnreadable($0) },
                "Arabic left untransliterated in “\(english)” (from “\(narrator)”)"
            )
        }
    }

    /// Every Arabic block, plus the private-use area the corpus has one stray
    /// codepoint in. `ﷺ` is the one exception: it is placed deliberately, and
    /// iOS renders it in any font the app uses.
    private static func isUnreadable(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0xFDFA: false
        case 0x0600...0x06FF, 0x0750...0x077F, 0x0870...0x08FF,
             0xFB50...0xFDFF, 0xFE70...0xFEFF: true
        case 0xE000...0xF8FF: true
        default: false
        }
    }
}
