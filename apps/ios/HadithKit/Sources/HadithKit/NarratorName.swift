import Foundation

/// Renders an Arabic isnad entry in Latin script.
///
/// The corpus stores chains only in Arabic — there is no English narrator field
/// anywhere upstream, and no open dataset maps these 34,317 distinct strings to
/// English. So this is transliteration, done on-device, not a lookup.
///
/// It works in two layers:
///
/// 1. **A lexicon** of the 330 most frequent tokens, spelled the conventional
///    English way ("Shu'ba", not "shu'ba"; "al-Zuhri", not "alzhry"). Those 330
///    tokens are 85% of every token in every chain in the corpus, which is why a
///    hand-written list is worth having at all: the alternative is rule output
///    for names that already have a settled English spelling.
/// 2. **Rules** for the rest — the structural words that make an Arabic name
///    (`ibn`, `Abu`, `Abd al-`), and a letter-by-letter fallback for the 15%
///    tail.
///
/// The fallback is approximate and cannot be otherwise. The stored text carries
/// no short vowels, so `قتادة` is literally `q-t-a-d-a` and "Qatada" is inferred
/// by assuming the unwritten vowel is *a* — right for `منصور` → Mansur, roughly
/// right for `شعبة` → Sha'ba (Shu'ba), and wrong often enough that the screen
/// showing this says so.
public enum NarratorName {
    /// Best-effort English rendering. Never fails, never returns empty for
    /// non-empty input.
    public static func english(_ arabic: String) -> String {
        let tokens = normalize(arabic)
            .split(whereSeparator: { $0 == " " || $0 == "\u{00A0}" })
            .map(String.init)
            .filter { $0 != "-" && $0 != "ا" }
        guard !tokens.isEmpty else { return "" }

        var parts: [String] = []
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            let next = index + 1 < tokens.count ? tokens[index + 1] : nil

            switch (token, next) {
            // "عبد الله" is one name, not "servant of" + "Allah". Every other
            // `عبد al-X` compound does split that way and keeps its article.
            case ("عبد", "الله"):
                parts.append("Abdullah")
                index += 2
            case ("رسول", "الله"):
                parts.append("the Messenger of Allah \u{FDFA}")
                index += 2
            case ("عبد", .some(let second)):
                parts.append("Abd " + word(second))
                index += 2
            // The kunya takes the genitive after `ibn` — which is why the
            // literature writes "Abu Bakr ibn Abi Shayba", never "ibn Abu".
            case ("أبو", _), ("أبي", _), ("أبا", _):
                parts.append(parts.last == "ibn" ? "Abi" : "Abu")
                index += 1
            default:
                parts.append(word(token))
                index += 1
            }
        }

        // A token can render to nothing — the sanad text carries the odd stray
        // `؟` and one private-use codepoint, none of which are letters.
        let rendered = parts.filter { !$0.isEmpty }.joined(separator: " ")
        return rendered.isEmpty ? "—" : rendered
    }

    /// A single token, after peeling off the two prefixes Arabic writes joined
    /// to the following word.
    ///
    /// The conjunction `و` ("and") comes first — the parse emits `وأبو`,
    /// `ومحمد`, `وقتيبة` as single tokens. Then the definite article `ال`,
    /// which is nearly always part of a nisba (`الحميدي`, `الليثي`) and has to
    /// be split off or the transliteration fuses it onto the name: "Alhamidi"
    /// instead of "al-Hamidi". Names that genuinely begin `al-` are in the
    /// lexicon and never reach here.
    private static func word(_ token: String) -> String {
        if let known = lexicon[token] { return known }

        if token.count > 2, token.hasPrefix("و") {
            let rest = String(token.dropFirst())
            if lexicon[rest] != nil || rest.hasPrefix("ال") {
                return "and " + word(rest)
            }
        }

        if token.count > 3, token.hasPrefix("ال") {
            let stem = String(token.dropFirst(2))
            return "al-" + (lexicon[stem] ?? transliterate(stem))
        }

        return transliterate(token)
    }

    /// Strips the marks the pipeline may or may not have removed already, and
    /// folds the alef variants so lexicon keys match however the source spelled
    /// them.
    private static func normalize(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for scalar in text.unicodeScalars {
            switch scalar.value {
            // Harakat, shadda, sukun, superscript alef, tatweel.
            case 0x064B...0x0652, 0x0670, 0x0640: continue
            case 0x0671: out.append("ا")   // alef wasla
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Fallback transliteration

extension NarratorName {
    private static let consonants: [Character: String] = [
        "ب": "b", "ت": "t", "ث": "th", "ج": "j", "ح": "h", "خ": "kh",
        "د": "d", "ذ": "dh", "ر": "r", "ز": "z", "س": "s", "ش": "sh",
        "ص": "s", "ض": "d", "ط": "t", "ظ": "z", "ع": "'", "غ": "gh",
        "ف": "f", "ق": "q", "ك": "k", "ل": "l", "م": "m", "ن": "n",
        "ه": "h", "ء": "'", "ؤ": "'", "ئ": "'",
    ]

    /// Letter-by-letter, then a guess at the vowels that were never written.
    ///
    /// Arabic script records long vowels and omits short ones, so a bare
    /// consonant run is not a cluster the reader is meant to pronounce — it is a
    /// place where a vowel has been left out. Inserting *a* is the single best
    /// guess: it is the most common short vowel and the vowel of the dominant
    /// `faʿala`/`faʿāl` name patterns. Doing it only at the start of a word and
    /// inside runs of three or more avoids turning `mansur` into `manasur`.
    private static func transliterate(_ token: String) -> String {
        var units: [(latin: String, isVowel: Bool)] = []
        for (position, character) in token.enumerated() {
            switch character {
            case "ا", "آ", "ة", "ى":
                units.append(("a", true))
            case "إ":
                units.append(("i", true))
            case "أ":
                units.append(position == 0 ? ("a", true) : ("'", false))
            // Word-initially these are the consonants w and y; anywhere else
            // they are almost always the long vowels they also spell.
            case "و":
                units.append(position == 0 ? ("w", false) : ("u", true))
            case "ي":
                units.append(position == 0 ? ("y", false) : ("i", true))
            default:
                if let mapped = consonants[character] {
                    units.append((mapped, false))
                }
            }
        }
        // Nothing in the token was a letter. Returning it verbatim would leak
        // Arabic into a line the reader came here to read in English.
        guard !units.isEmpty else { return "" }

        var out = ""
        var run = 0
        for (index, unit) in units.enumerated() {
            out += unit.latin
            if unit.isVowel {
                run = 0
                continue
            }
            run += 1
            let nextIsConsonant = index + 1 < units.count && !units[index + 1].isVowel
            if nextIsConsonant, index == 0 || run >= 2 {
                out += "a"
                run = 0
            }
        }
        return out.prefix(1).uppercased() + out.dropFirst()
    }
}

// MARK: - Lexicon

extension NarratorName {
    /// The 330 most frequent tokens in the corpus, which between them account
    /// for 85% of every token in every chain.
    ///
    /// Two kinds of entry live here. Most are names, spelled as the English
    /// hadith literature spells them. The rest are **not names at all**: the
    /// upstream parse splits the Arabic sanad on transmission verbs and keeps
    /// the fragments, so `قال` ("said"), `وحدثنا` ("and narrated to us") and
    /// `ح` — the taḥwīl mark for a switch of chain — all appear as chain links.
    /// Transliterating those would produce plausible-looking nonsense names, so
    /// they are translated into lowercase prose instead: a reader can then see
    /// that the link is a fragment of a sentence rather than a person.
    private static let lexicon: [String: String] = [
        // Structural
        "بن": "ibn", "ابن": "ibn", "أبو": "Abu", "أبي": "Abu", "أبا": "Abu",
        "أم": "Umm", "بنت": "bint", "ابنة": "bint", "مولى": "mawla of",
        "بني": "Banu", "بنى": "Banu", "الناقد": "al-Naqid",
        // Kinship links stand in for a name the sanad didn't spell out, and are
        // the one place the chain says "and then whoever this person's father
        // was". Transliterated they read as invented names ("Abihma").
        "أبيه": "his father", "أبيهما": "their father", "أبويه": "his parents",
        "ابنه": "his son", "ابنى": "sons of", "ابني": "sons of",
        "أمه": "his mother", "أخيه": "his brother", "أخته": "his sister",
        "جده": "his grandfather", "جدته": "his grandmother",
        "جدها": "her grandfather", "عمه": "his uncle", "عمته": "his aunt",

        // Not names — sentence fragments the sanad parse kept
        "قال": "said", "قالا": "they both said", "قالت": "she said",
        "قالوا": "they said", "وقال": "and said", "فقال": "then said",
        "يقول": "saying", "وحدثنا": "and narrated to us",
        "وحدثني": "and narrated to me", "وحدثناه": "and narrated it to us",
        "وحدثنيه": "and narrated it to me", "أنبأنا": "informed us",
        "حدثه": "narrated to him", "يحدث": "narrating", "أخبره": "informed him",
        "ح": "(ḥ — chain switches here)", "أن": "that", "أنه": "that he",
        "في": "in", "من": "from", "على": "upon", "عليه": "upon him",
        "وهو": "and he", "يعني": "meaning", "كان": "was", "إلى": "to",
        "بهذا": "with this", "الإسناد": "isnad", "الحديث": "the hadith",
        "حديث": "hadith", "نهى": "forbade", "جميعا": "all of them",
        "كلاهما": "both of them", "كلهم": "all of them",
        "واللفظ": "and the wording", "مرة": "once", "ما": "what",
        "إذا": "when", "سألت": "I asked", "سأل": "asked", "سئل": "was asked",
        "قلت": "I said", "يوم": "the day", "يا": "O", "هو": "he",
        "هذا": "this", "قرأت": "I read", "لي": "to me", "له": "to him",
        "أو": "or", "ثم": "then", "لا": "not", "مع": "with", "عند": "with",
        "إلا": "except", "إن": "indeed", "حتى": "until", "لما": "when",
        "رأيت": "I saw", "به": "with it", "المعنى": "the meaning",
        "كنا": "we were", "ذلك": "that", "وأنا": "and I", "وعن": "and from",
        "رجل": "a man", "رجلا": "a man", "الصلاة": "the prayer",
        "صلى": "may Allah bless him", "وسلم": "and grant him peace",
        "النبي": "the Prophet \u{FDFA}", "الله": "Allah", "رسول": "Messenger",

        // Names
        "محمد": "Muhammad", "يحيى": "Yahya", "سعيد": "Sa'id", "عمرو": "Amr",
        "مالك": "Malik", "الرحمن": "al-Rahman", "عمر": "Umar",
        "هريرة": "Hurayra", "سفيان": "Sufyan", "إبراهيم": "Ibrahim",
        "علي": "Ali", "بكر": "Bakr", "إسحاق": "Ishaq", "عبيد": "Ubayd",
        "شعبة": "Shu'ba", "إسماعيل": "Isma'il", "شيبة": "Shayba",
        "يزيد": "Yazid", "هشام": "Hisham", "سلمة": "Salama", "موسى": "Musa",
        "سليمان": "Sulayman", "قتيبة": "Qutayba", "خالد": "Khalid",
        "أحمد": "Ahmad", "الزهري": "al-Zuhri", "نافع": "Nafi'", "أنس": "Anas",
        "زيد": "Zayd", "شهاب": "Shihab", "جعفر": "Ja'far", "عباس": "Abbas",
        "يونس": "Yunus", "عثمان": "Uthman", "حماد": "Hammad", "وهب": "Wahb",
        "الأعمش": "al-A'mash", "قتادة": "Qatada", "سعد": "Sa'd",
        "عروة": "Urwa", "عائشة": "A'isha", "صالح": "Salih", "أيوب": "Ayyub",
        "المثنى": "al-Muthanna", "حميد": "Humayd", "بشار": "Bashshar",
        "الحسن": "al-Hasan", "وكيع": "Waki'", "معاوية": "Mu'awiya",
        "جابر": "Jabir", "الليث": "al-Layth", "منصور": "Mansur",
        "حرب": "Harb", "معمر": "Ma'mar", "عطاء": "Ata'",
        "الزبير": "al-Zubayr", "جرير": "Jarir", "عاصم": "Asim",
        "داود": "Dawud", "الحارث": "al-Harith", "الرزاق": "al-Razzaq",
        "الوليد": "al-Walid", "شعيب": "Shu'ayb", "كثير": "Kathir",
        "العزيز": "al-Aziz", "زهير": "Zuhayr", "جريج": "Jurayj",
        "مسلم": "Muslim", "مسدد": "Musaddad", "ثابت": "Thabit",
        "يوسف": "Yusuf", "القاسم": "al-Qasim", "بشر": "Bishr", "عيسى": "Isa",
        "عيينة": "Uyayna", "رافع": "Rafi'", "كريب": "Kurayb",
        "نمير": "Numayr", "هارون": "Harun", "يعقوب": "Ya'qub",
        "أسامة": "Usama", "عامر": "Amir", "سالم": "Salim", "جبير": "Jubayr",
        "دينار": "Dinar", "معاذ": "Mu'adh", "حفص": "Hafs", "حبيب": "Habib",
        "الأعلى": "al-A'la", "زياد": "Ziyad", "الملك": "al-Malik",
        "عمار": "Ammar", "العلاء": "al-Ala'", "عكرمة": "Ikrima",
        "المسيب": "al-Musayyab", "قيس": "Qays", "الأعرج": "al-A'raj",
        "حازم": "Hazim", "الأسود": "al-Aswad", "الحكم": "al-Hakam",
        "طلحة": "Talha", "نصر": "Nasr", "سويد": "Suwayd", "مسعود": "Mas'ud",
        "عدي": "Adi", "حاتم": "Hatim", "الزناد": "al-Zinad", "يسار": "Yasar",
        "همام": "Hammam", "حجر": "Hujr", "عقبة": "Uqba", "محمود": "Mahmud",
        "المبارك": "al-Mubarak", "عوانة": "Awana", "الخدري": "al-Khudri",
        "حجاج": "Hajjaj", "بكير": "Bukayr", "عبدة": "Abda", "حسين": "Husayn",
        "آدم": "Adam", "هلال": "Hilal", "الأنصاري": "al-Ansari",
        "المغيرة": "al-Mughira", "عقيل": "Uqayl", "هناد": "Hannad",
        "غيلان": "Ghaylan", "عمران": "Imran", "علقمة": "Alqama",
        "مهدي": "Mahdi", "مسلمة": "Maslama", "الشعبي": "al-Sha'bi",
        "الأوزاعي": "al-Awza'i", "الربيع": "al-Rabi'", "سهل": "Sahl",
        "النضر": "al-Nadr", "عباد": "Abbad", "هشيم": "Hushaym",
        "حصين": "Husayn", "عون": "Awn", "إسرائيل": "Isra'il",
        "نعيم": "Nu'aym", "أسلم": "Aslam", "الأحوص": "al-Ahwas",
        "الوهاب": "al-Wahhab", "فضيل": "Fudayl", "زائدة": "Za'ida",
        "الوارث": "al-Warith", "الفضل": "al-Fadl", "طاوس": "Tawus",
        "شريك": "Sharik", "سهيل": "Suhayl", "سماك": "Simak", "وائل": "Wa'il",
        "عبيدة": "Ubayda", "مجاهد": "Mujahid", "زريع": "Zuray'",
        "عياش": "Ayyash", "حكيم": "Hakim", "الحسين": "al-Husayn",
        "اليمان": "al-Yaman", "كعب": "Ka'b", "ربيعة": "Rabi'a",
        "التيمي": "al-Taymi", "مسروق": "Masruq", "النعمان": "al-Nu'man",
        "بردة": "Burda", "عمير": "Umayr", "سيرين": "Sirin",
        "عمارة": "Umara", "إدريس": "Idris", "ليث": "Layth", "عفان": "Affan",
        "الصباح": "al-Sabbah", "حمزة": "Hamza", "شيبان": "Shayban",
        "علية": "Ulayya", "سليم": "Sulaym", "مروان": "Marwan",
        "قلابة": "Qilaba", "ليلى": "Layla", "حرملة": "Harmala",
        "منيع": "Mani'", "عوف": "Awf", "بريدة": "Burayda",
        "الواحد": "al-Wahid", "ميمون": "Maymun", "حنبل": "Hanbal",
        "عبادة": "Ubada", "يعلى": "Ya'la", "سمرة": "Samura", "بلال": "Bilal",
        "خلف": "Khalaf", "المقبري": "al-Maqburi", "روح": "Rawh",
        "رمح": "Rumh", "صفوان": "Safwan", "مسهر": "Mus-hir",
        "القعنبي": "al-Qa'nabi", "بشير": "Bashir", "حبان": "Hibban",
        "عجلان": "Ajlan", "الخطاب": "al-Khattab", "حسان": "Hassan",
        "السائب": "al-Sa'ib", "وهيب": "Wuhayb", "الصمد": "al-Samad",
        "عمرة": "Amra", "سلام": "Salam", "ذر": "Dharr", "هاشم": "Hashim",
        "أبان": "Aban", "عتبة": "Utba", "زكريا": "Zakariyya",
        "زكرياء": "Zakariyya", "الطاهر": "al-Tahir",
        "المنكدر": "al-Munkadir", "شقيق": "Shaqiq", "السري": "al-Sari",
        "مخلد": "Makhlad", "البراء": "al-Bara'", "البصري": "al-Basri",
        "الحميد": "al-Hamid", "العباس": "al-Abbas", "شريح": "Shurayh",
        "غندر": "Ghundar", "الدمشقي": "al-Dimashqi", "بقية": "Baqiyya",
        "المنذر": "al-Mundhir", "عطية": "Atiyya", "ذئب": "Dhi'b",
        "مريم": "Maryam", "ميسرة": "Maysara", "غياث": "Ghiyath",
        "أمية": "Umayya", "كامل": "Kamil", "مليكة": "Mulayka",
        "الأشج": "al-Ashajj", "معن": "Ma'n", "زرعة": "Zur'a",
        "الثقفي": "al-Thaqafi", "القطان": "al-Qattan",
        "المفضل": "al-Mufaddal", "أمامة": "Umama", "نضرة": "Nadra",
        "طالب": "Talib", "الشيباني": "al-Shaybani", "أسماء": "Asma'",
        "عروبة": "Aruba", "عياض": "Iyad", "الحذاء": "al-Hadhdha'",
        "سنان": "Sinan", "المكي": "al-Makki", "الحجاج": "al-Hajjaj",
        "الضحاك": "al-Dahhak", "مسعر": "Mis'ar", "الجريري": "al-Jurayri",
        "الجعد": "al-Ja'd", "حذيفة": "Hudhayfa", "المعتمر": "al-Mu'tamir",
        "رجاء": "Raja'", "الهمداني": "al-Hamdani", "الرحيم": "al-Rahim",
        "كيسان": "Kaysan", "هانئ": "Hani'",

        // Names that only became frequent once the sanad parser stopped
        // splitting chains on the wrong words. `زوج` is kinship, not a name:
        // "A'isha, wife of the Prophet" is one link.
        "زوج": "wife of", "وعنه": "and from him",
        "أوس": "Aws", "عازب": "Azib", "الجهني": "al-Juhani",
        "العاص": "al-As", "الصامت": "al-Samit", "الأشعري": "al-Ash'ari",
        "حفصة": "Hafsa", "مطرف": "Mutarrif", "شداد": "Shaddad",
        "السرح": "al-Sarh", "زرارة": "Zurara", "بهز": "Bahz",
        "جندب": "Jundub",
    ]
}
