/**
 * Parses the chain of transmission out of a hadith's Arabic text.
 *
 * A sanad is a strict alternation: a transmission verb, a narrator, a verb, a
 * narrator, and so on until the matn — the hadith itself — begins. So the parse
 * is a split on the verbs, and everything between two of them is a name.
 *
 * That only works if the verb list is complete. The first version of this
 * recognised seven verbs and none of the forms Arabic writes with the
 * conjunction attached, so `وحدثنا` ("and narrated to us") was never a
 * boundary and the whole clause after it survived as a single "narrator".
 * Measured across the corpus, roughly one chain link in twenty was a fragment
 * of a sentence rather than a person: `قال` ("said") was the fifth most common
 * token in the entire chain corpus.
 *
 * Two things keep that from coming back:
 *
 * - `BOUNDARY` is built from stems with the `و`/`ف` prefixes generated, rather
 *   than a hand-listed set of surface forms.
 * - Anything that survives the split is still checked against `FUNCTION_WORDS`,
 *   because no split will ever catch every construction in 47,000 hadith. A
 *   name runs until the first function word and no further.
 */

function escapeRegex(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

export function stripDiacritics(text: string): string {
  return text.replace(
    /[ؐ-ًؚ-ٰٟۖ-ۜ۟-ۤۧ-۪ۨ-ۭ]/g,
    ""
  );
}

/**
 * Transmission verbs, as stems. Every one of these also occurs with `و` ("and")
 * or `ف` ("then") written joined to the front, which is how a sanad introduces
 * each parallel narrator — `وحدثنا`, `وأخبرني`, `فقال`.
 */
const TRANSMISSION_VERBS = [
  "حدثناه", "حدثنيه", "حدثتني", "حدثتنا", "حدثنا", "حدثني", "حدثهم", "حدثه",
  "أخبرناه", "أخبرتني", "أخبرنا", "أخبرني", "أخبرهم", "أخبره",
  "أنبأنا", "أنبأني", "أنبأه", "نبأنا",
  "سمعته", "سمعت", "سمعنا", "سمع",
  "يحدث", "يحدثه", "يخبر",
  "قالوا", "قالت", "قالا", "قال", "يقول",
  "عن",
  // The taḥwīl mark: a single letter standing for "the chain switches here".
  // It is not a name and never was, but at one character it also can't be
  // filtered by length without taking real material with it.
  "ح",
];

/**
 * Clause openers. These are not transmission verbs, but they end a name just as
 * definitively: `عن أبي هريرة أن رسول الله قال` has to break before `أن`, or
 * "Abu Hurayra that the Messenger of Allah" becomes one narrator. That exact
 * string appeared 624 times.
 */
const CLAUSE_OPENERS = ["أنهما", "أنهم", "أنها", "أنه", "أن"];

const BOUNDARY = new RegExp(
  "(?<=^|\\s)(?:[وف]?(?:" +
    [...TRANSMISSION_VERBS, ...CLAUSE_OPENERS].map(escapeRegex).join("|") +
    "))(?=\\s|$)",
  "g"
);

/**
 * Words that are never part of a name.
 *
 * A segment is truncated at the first of these rather than rejected outright:
 * in a sanad the name comes first and any trailing clause after it, so
 * `أبي هريرة أن رسول الله` still yields "أبي هريرة".
 */
const FUNCTION_WORDS = new Set([
  // Particles and pronouns
  "في", "على", "من", "إلى", "عند", "مع", "ثم", "إن", "إلا", "حتى", "أو",
  "لا", "ما", "هو", "هي", "هم", "هذا", "هذه", "ذلك", "تلك", "الذي", "التي",
  "به", "بهذا", "بمثل", "بنحو", "له", "لها", "لهم", "لي", "لك", "قد", "لقد",
  "كل", "بعض", "غير", "نفسه", "كنت", "كنا", "كان", "كانت", "أنا", "نحن",
  "يا", "إذا", "إذ", "لما", "فلما", "بينا", "بينما", "وهو", "وهي",
  // Verbs that open the matn
  "سألت", "سأل", "سئل", "قلت", "قرأت", "رأيت", "نهى", "أمر", "دخلت",
  "خرج", "جاء", "أتى", "كتب", "صلى", "توفي", "مات",
  // Editorial vocabulary — a scribe's note about the chain, not a link in it
  "نحوه", "مثله", "فيه", "يعني", "جميعا", "كلاهما", "كلهم", "كليهما",
  "واللفظ", "اللفظ", "المعنى", "الإسناد", "الحديث", "حديث", "بإسناده",
  "مرة", "يوم", "رجل", "رجلا", "امرأة", "المنبر", "زاد", "نحو",
]);

const HONORIFICS = [
  /رضي الله عنه(ا|م|ما)?/g,
  /رضى الله عنه(ا|م|ما)?/g,
  /صلى الله عليه وسلم/g,
  /صلى الله عليه و سلم/g,
  /عليه السلام/g,
  /عليها السلام/g,
  /عليهم السلام/g,
  /أم المؤمنين/g,
];

const MATN_MARKERS = /[""«»“”‏]/;

/**
 * Everything before the hadith text itself.
 *
 * A quotation mark is the reliable signal; failing that, the first mention of
 * the Prophet usually ends the chain, since what follows is what he said.
 */
function extractIsnadPortion(arabic: string): string {
  const quote = arabic.search(MATN_MARKERS);
  if (quote !== -1) return arabic.substring(0, quote);

  const plain = stripDiacritics(arabic);
  const prophetRef = plain.search(/رسول الله|النبي/);
  if (prophetRef !== -1) {
    const comma = plain.indexOf("،", prophetRef);
    if (comma !== -1) return arabic.substring(0, comma);
    return arabic.substring(0, Math.min(prophetRef + 80, arabic.length));
  }
  return arabic.substring(0, Math.floor(arabic.length * 0.6));
}

/**
 * A conjunction written joined to the front of a word is still a conjunction:
 * `وأنا` is "and I", not a name. Real names beginning with `و` — Wahb, Waki',
 * Wa'il — leave a stem that is not a function word, so this can't eat them.
 */
function isFunctionWord(token: string): boolean {
  if (FUNCTION_WORDS.has(token)) return true;
  if (token.length > 2 && (token.startsWith("و") || token.startsWith("ف"))) {
    return FUNCTION_WORDS.has(token.slice(1));
  }
  return false;
}

/**
 * Punctuation, honorifics and diacritics out; single spaces in.
 *
 * This has to happen **before** the split, not after. The corpus writes the
 * comma tight against the preceding word — `قَالَ،` — so a word boundary
 * expressed as `(?=\s|$)` never fires there, and the verb sails through as part
 * of a name. That is one of the two bugs this parser was rewritten for, and it
 * is invisible in any test whose input is already tidy.
 */
function normalize(text: string): string {
  let out = stripDiacritics(text);
  for (const pattern of HONORIFICS) out = out.replace(pattern, " ");
  return out
    .replace(/ـ/g, "")
    .replace(/[،,:;.!?(){}\[\]"'“”«»\-–—/]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

/**
 * Reduces one segment to the name at the front of it, or "" if there isn't one.
 */
function cleanName(segment: string): string {
  const tokens = segment.split(" ").filter(Boolean);

  let start = 0;
  while (start < tokens.length && (tokens[start] === "و" || tokens[start] === "ف")) {
    start += 1;
  }

  const name: string[] = [];
  for (let i = start; i < tokens.length; i++) {
    if (isFunctionWord(tokens[i])) break;
    name.push(tokens[i]);
  }

  return name.join(" ").trim();
}

/**
 * Verbs that introduce a *person*. `حدثنا فلان` is "so-and-so narrated to us";
 * whatever follows is a narrator.
 */
const NARRATOR_VERBS = /^(?:حدث|أخبر|أنبأ|نبأ|سمع|يحدث|يخبر|عن)/;

/**
 * The source of the matn, which is not a transmitter but is what the chain
 * terminates in, and what the app labels "Source".
 */
const SOURCE_REFERENCES = new Set(["رسول الله", "النبي", "رسول الله ", "نبي الله"]);

/**
 * Splits on the boundary while keeping the verb that introduced each piece.
 *
 * `String.split` throws that away, and it is the one signal that separates a
 * narrator from the hadith itself: both sit directly after a boundary word, but
 * only one of them sits after a verb of transmission. `قال` introduces speech —
 * so what follows it is the matn, not a person.
 */
function pieces(text: string): { verb: string; text: string }[] {
  const out: { verb: string; text: string }[] = [];
  let cursor = 0;
  let verb = "";
  for (const match of text.matchAll(BOUNDARY)) {
    out.push({ verb, text: text.slice(cursor, match.index) });
    verb = match[0].replace(/^[وف]/, "");
    cursor = match.index + match[0].length;
  }
  out.push({ verb, text: text.slice(cursor) });
  return out;
}

export function parseIsnad(arabic: string): string[] | null {
  if (!arabic || arabic.length < 20) return null;

  const isnadPortion = extractIsnadPortion(arabic);
  if (isnadPortion.length < 10) return null;

  const narrators: string[] = [];

  for (const piece of pieces(normalize(isnadPortion))) {
    const name = cleanName(piece.text);
    if (name.length < 3 || name.length > 60) continue;

    // The leading piece has no verb before it — the chain simply opens with the
    // collector's teacher. Everything after that has to be verb-introduced.
    const introduced =
      piece.verb === "" ||
      NARRATOR_VERBS.test(piece.verb) ||
      SOURCE_REFERENCES.has(name);
    if (!introduced) continue;

    // A repeated name means the split fired twice inside one attribution, not
    // that two people of the same name narrated in sequence.
    if (narrators[narrators.length - 1] === name) continue;
    narrators.push(name);
  }

  return narrators.length >= 2 ? narrators : null;
}
