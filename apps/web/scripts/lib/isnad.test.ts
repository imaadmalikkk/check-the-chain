import { test } from "node:test";
import assert from "node:assert/strict";
import { parseIsnad } from "./isnad.ts";

/**
 * Run with `npm run test:isnad -w apps/web`.
 *
 * Every case here is a real hadith that the previous parser got wrong, quoted
 * with the diacritics and the tight punctuation the corpus actually uses —
 * tidied-up input is exactly what hid the punctuation bug.
 */

const BUKHARI_1 =
  "حَدَّثَنَا الْحُمَيْدِيُّ عَبْدُ اللَّهِ بْنُ الزُّبَيْرِ، قَالَ حَدَّثَنَا سُفْيَانُ، قَالَ حَدَّثَنَا " +
  "يَحْيَى بْنُ سَعِيدٍ الأَنْصَارِيُّ، قَالَ أَخْبَرَنِي مُحَمَّدُ بْنُ إِبْرَاهِيمَ التَّيْمِيُّ، أَنَّهُ " +
  "سَمِعَ عَلْقَمَةَ بْنَ وَقَّاصٍ اللَّيْثِيَّ، يَقُولُ سَمِعْتُ عُمَرَ بْنَ الْخَطَّابِ رضى الله عنه عَلَى " +
  "الْمِنْبَرِ قَالَ سَمِعْتُ رَسُولَ اللَّهِ صلى الله عليه وسلم يَقُولُ ‏\"‏ إِنَّمَا الأَعْمَالُ بِالنِّيَّاتِ";

test("a clean chain is unchanged", () => {
  assert.deepEqual(parseIsnad(BUKHARI_1), [
    "الحميدي عبد الله بن الزبير",
    "سفيان",
    "يحيى بن سعيد الأنصاري",
    "محمد بن إبراهيم التيمي",
    "علقمة بن وقاص الليثي",
    "عمر بن الخطاب",
    "رسول الله",
  ]);
});

test("a verb written tight against a comma is still a boundary", () => {
  // `قَالَ،` — no space before the comma. A boundary expressed as `(?=\s|$)`
  // never fires here, which is how "أبي قال" became a narrator.
  const arabic =
    "حَدَّثَنَا مُحَمَّدُ بْنُ بَشَّارٍ، حَدَّثَنَا وَهْبُ بْنُ جَرِيرٍ، حَدَّثَنَا أَبِي قَالَ، " +
    "سَمِعْتُ مُحَمَّدَ بْنَ إِسْحَاقَ، يُحَدِّثُ عَنْ أَبَانَ بْنِ صَالِحٍ، عَنْ مُجَاهِدٍ، " +
    "عَنْ جَابِرِ بْنِ عَبْدِ اللَّهِ، قَالَ \"‏ كذا";
  const chain = parseIsnad(arabic);
  assert.ok(chain);
  assert.ok(!chain.some((n) => n.includes("قال")), `“قال” survived: ${chain.join(" | ")}`);
  assert.ok(chain.includes("أبي"));
  assert.ok(chain.includes("مجاهد"));
});

test("the conjunction form of a transmission verb is a boundary", () => {
  // `وحدثنا` was never in the old verb list, so everything after it survived as
  // a single "narrator".
  const arabic =
    "حَدَّثَنَا يَحْيَى بْنُ يَحْيَى، ح وَحَدَّثَنَا عَمْرٌو النَّاقِدُ، وَزُهَيْرُ بْنُ حَرْبٍ، " +
    "قَالُوا حَدَّثَنَا سُفْيَانُ، عَنِ الزُّهْرِيِّ، عَنْ سَالِمٍ، عَنْ أَبِيهِ، عَنِ النَّبِيِّ";
  const chain = parseIsnad(arabic);
  assert.ok(chain);
  for (const link of chain) {
    assert.ok(!link.includes("حدثنا"), `transmission verb kept as a name: ${link}`);
    assert.ok(!link.startsWith("ح "), `taḥwīl mark kept as a name: ${link}`);
  }
  assert.ok(chain.includes("الزهري"));
  assert.ok(chain.includes("أبيه"));
});

test("a clause opener ends the name", () => {
  // "عن أبي هريرة أن رسول الله" produced one narrator called
  // "Abu Hurayra that the Messenger of Allah" — 624 times.
  const chain = parseIsnad(
    "حَدَّثَنَا مَالِكٌ، عَنْ أَبِي الزِّنَادِ، عَنِ الأَعْرَجِ، عَنْ أَبِي هُرَيْرَةَ، " +
      "أَنَّ رَسُولَ اللَّهِ صلى الله عليه وسلم قَالَ \"‏ كذا"
  );
  assert.ok(chain);
  assert.ok(chain.includes("أبي هريرة"));
  assert.ok(!chain.some((n) => n.includes("أن")), chain.join(" | "));
});

test("speech introduces the hadith, not a narrator", () => {
  // Both a narrator and the matn sit directly after a boundary word. Only the
  // narrator sits after a verb of *transmission*; `قال` introduces speech.
  const chain = parseIsnad(
    "حَدَّثَنَا مُسَدَّدٌ، حَدَّثَنَا يَحْيَى، عَنْ مُحَمَّدِ بْنِ عَجْلاَنَ، قَالَ سَمِعْتُ أَبِي " +
      "يُحَدِّثُ، عَنْ أَبِي هُرَيْرَةَ، قَالَ قَالَ رَسُولُ اللَّهِ صلى الله عليه وسلم ‏\"‏ لاَ يَبُولَنَّ"
  );
  assert.deepEqual(chain, ["مسدد", "يحيى", "محمد بن عجلان", "أبي", "أبي هريرة", "رسول الله"]);
});

test("editorial asides are not narrators", () => {
  // "- يعني ابن محمد -" is a scribe identifying the previous name, set off by
  // dashes. It is not another link.
  const chain = parseIsnad(
    "حَدَّثَنَا عَبْدُ الْعَزِيزِ، - يَعْنِي ابْنَ مُحَمَّدٍ - عَنْ مُحَمَّدٍ، عَنْ أَبِيهِ، " +
      "عَنْ أَبِي هُرَيْرَةَ، قَالَ \"‏ كذا"
  );
  assert.ok(chain);
  assert.ok(!chain.some((n) => n.includes("يعني")), chain.join(" | "));
  assert.deepEqual(chain[0], "عبد العزيز");
});

test("a name beginning with waw is not mistaken for a conjunction", () => {
  // Wahb, Waki' and Wa'il all start with the letter the parser strips as "and".
  const chain = parseIsnad(
    "حَدَّثَنَا وَكِيعٌ، عَنْ وُهَيْبٍ، عَنْ وَائِلٍ، عَنْ أَبِيهِ، قَالَ \"‏ كذا"
  );
  assert.deepEqual(chain, ["وكيع", "وهيب", "وائل", "أبيه"]);
});

test("no chain rather than a bad one", () => {
  assert.equal(parseIsnad(""), null);
  assert.equal(parseIsnad("قصير"), null);
});
