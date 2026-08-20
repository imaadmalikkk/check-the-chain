# Ask — on-device answering over retrieved hadith

**Status:** approved, not yet implemented
**Scope:** `apps/ios` only. No pipeline change, no web change, no new dependency.

## Why

The app can already find the right hadith. It cannot yet answer a question *about* them, and that is the one thing a person holding a phone actually wants: "what did the prophet say about being angry" should produce an answer, not a ranked list they must read in full to evaluate.

This is also the feature that makes the product distinct. Everything else here is a better hadith search; on-device answering is something no free app does, and it is only possible because the corpus, the embeddings and now the model all live on the device.

## The safety problem, stated first

This is a religious domain and people act on what they read. A small on-device model generating text about Islamic rulings can fail in three ways, in increasing order of how hard they are to notice:

1. **Fabricating a narration.** Inventing text and attributing it to the Prophet ﷺ.
2. **Answering from pretraining.** The model has read Islamic texts. Asked about something the corpus does not cover, its instinct is to answer anyway — producing something plausible, unsourced, and untraceable to any narration in the app.
3. **Subtly misstating a ruling** while every individual citation remains correct. The citations check out; the sentence above them does not follow from them.

The architecture below is aimed at these three, in that order. **(1) is made structurally impossible. (2) is given an explicit escape hatch and defaults to declining. (3) is mitigated but not eliminated** — it is the residual risk of choosing synthesis, and the disclaimer exists for it.

## Decisions

| Decision | Choice | Why |
|---|---|---|
| Model output | **Selection + 2–3 sentence synthesis** | Chosen over selection-only. More useful, and closer to what people expect from an assistant. The cost is failure mode (3), accepted knowingly. |
| Scripture | **Never model output** | The model returns indices; the app renders narration text from its own SQLite. Failure mode (1) cannot occur — the model has no channel to emit a narration. |
| Placement | An **Ask toggle** on the search canvas | Explicit, so the user knows which mode they are in, and it can hide itself rather than fail at query time. |
| Unavailable devices | **Hide when ineligible; explain when fixable** | A permanently dead control is worse than none. But "Apple Intelligence is off" and "the model is still downloading" are both things the user can act on, so those show. |
| Where the code lives | **HadithKit**, behind `@available(iOS 26, *)` | Engine logic, and the project's rule is logic in the package, pixels in the app. Keeps it unit-testable. |

## Non-goals

Multi-turn conversation or follow-up questions. Chat history. Streaming token-by-token display. Tool calling. Any Arabic-language answering — the corpus's English is what gets summarised. Any claim of scholarly authority.

## Architecture

```
question
  → SearchEngine.search(query:limit:)        (unchanged, already shipped)
  → top 8 candidates, English truncated       (context window is finite)
  → LanguageModelSession.respond(generating: DraftAnswer.self)
  → AnswerValidator.validate(draft, against: candidates)   ← pure function
  → Answer { summary?, citations[Hadith], declined }
  → UI renders summary + real hadith cards
```

### What the model returns

```swift
@Generable
struct DraftAnswer {
    @Guide(description: "true only if the numbered narrations below actually answer the question")
    var answered: Bool

    @Guide(description: "Two or three sentences describing only what the numbered narrations say. \
Never quote them — the app displays their text. Never state a ruling they do not state.")
    var summary: String

    @Guide(description: "Numbers of the narrations that support the summary, most relevant first")
    var supporting: [Int]
}
```

`answered` is the single most important field in this design. Without it the model has no way to decline, and a model that cannot decline will answer from pretraining — failure mode (2). The instructions must state plainly that declining is a correct outcome.

### The validator

A **pure function**, deliberately: `(DraftAnswer, [SearchResult]) -> Answer`. It is where the safety rules live, and being pure is what makes them testable without the model — which matters because Foundation Models may not be available in the simulator that runs CI.

Rules, each rejecting a specific observed failure:

- `answered == false` → declined, no summary shown.
- `supporting` empty but `answered == true` → **treat as declined.** An answer with nothing behind it is the shape failure mode (2) takes.
- Indices outside `1...candidates.count` → dropped. If that empties the list, declined.
- Duplicate indices → de-duplicated, order preserved.
- A quoted span in `summary` longer than 40 characters → **the whole response is declined**, not stripped. The model was told not to quote; a long quote means it ignored an instruction, and the rest of that response has not earned trust.
- `summary` empty or shorter than 20 characters after trimming → declined.

Declining is always safe: the UI falls back to plain ranked results, which is exactly the app as it shipped yesterday.

### Public surface

```swift
@available(iOS 26.0, macOS 26.0, *)
public struct Answer: Sendable {
    public let summary: String        // non-empty when present
    public let citations: [Hadith]    // in the model's relevance order
}

@available(iOS 26.0, macOS 26.0, *)
public actor AnswerEngine {
    public enum Availability: Sendable, Equatable {
        case available
        case ineligibleDevice          // hide the affordance
        case appleIntelligenceOff      // show, explain, actionable
        case modelDownloading          // show, explain, transient
    }
    public static var availability: Availability { get }

    public init(engine: SearchEngine)
    public func prewarm()
    /// Returns nil when the model declined or could not run — the caller shows
    /// plain results, which is the app's behaviour without this feature.
    public func answer(_ question: String) async -> Answer?
}
```

`answer` returns an optional rather than throwing. Every failure — guardrail violation, context overflow, rate limiting, a declined draft — collapses to the same outcome for the user: no summary, results as normal. A thrown error would force every call site to re-derive that.

## Availability

`SystemLanguageModel.availability` gives three unavailable reasons, and they are not the same thing:

| Reason | Treatment |
|---|---|
| `deviceNotEligible` | Hide the Ask affordance entirely. Nothing the user can do. |
| `appleIntelligenceNotEnabled` | Show it; tapping explains it can be switched on in Settings. |
| `modelNotReady` | Show it; explain the model is still downloading. Transient. |

Availability is read at the point of use, not cached at launch — Apple Intelligence can be enabled, and the model can finish downloading, while the app is running.

## Error handling

- **Any `GenerationError`** — `guardrailViolation`, `exceededContextWindowSize`, `refusal`, `rateLimited`, `assetsUnavailable` — returns nil. Logged via the existing `Log` subsystem, never surfaced as an alert. The user asked a question and gets results; a dialog explaining a token budget helps nobody.
- **Context overflow is designed against, not just caught.** Eight candidates with English truncated to 400 characters each is the budget. The full text is rendered from the database regardless, so truncation costs nothing visible.
- **The model is never on the main actor.** `AnswerEngine` is an actor; the UI awaits it.

## Testing

The validator carries the weight, because it can be tested exhaustively and deterministically:

- declines on `answered: false`
- declines on `answered: true` with empty `supporting`
- drops out-of-range indices; declines when that empties the list
- de-duplicates while preserving order
- declines on a quoted span over 40 characters
- declines on an empty or near-empty summary
- maps indices to the correct hadith, in the model's order

Plus, gated on real availability so the suite still passes on a machine without Apple Intelligence:

- `availability` returns a value that matches `SystemLanguageModel.default.availability`
- a live end-to-end answer for a question the corpus certainly covers ("what did the prophet say about intentions") produces citations that are all real hadith
- **a question the corpus cannot answer** ("what is the capital of France") declines rather than answering

That last one is the test that matters most. It is the direct probe for failure mode (2), and it is the one a reviewer should look for.

## Consequences for the docs

`apps/ios/README.md` lists "AI chat over retrieved hadith via the Foundation Models framework" under "Not built (deliberately)". That line goes, replaced by a section covering the three failure modes and what the architecture does about each. `CLAUDE.md` gains an `AnswerEngine` bullet beside `Library`.
