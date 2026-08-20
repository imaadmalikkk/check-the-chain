import Foundation

/// BERT-uncased WordPiece tokenizer for `all-MiniLM-L6-v2`.
///
/// A faithful port of HuggingFace's `BertNormalizer` + `BertPreTokenizer` +
/// `WordPiece`, configured exactly as the model's `tokenizer.json` specifies:
/// `clean_text`, `handle_chinese_chars`, `lowercase`, accent stripping, a
/// `##` continuation prefix, and a 100-character cap per word.
///
/// Correctness here is not self-evident, so it is not assumed: the corpus
/// embeddings were produced by Transformers.js with the reference tokenizer,
/// and `TokenizerParityTests` re-embeds the golden queries on-device and
/// requires cosine ≥ 0.999 against those vectors. Any drift in this file shows
/// up there rather than as quietly worse search results.
public struct BertTokenizer: Sendable {
    public struct Encoding: Sendable {
        public let ids: [Int32]
        public let attentionMask: [Int32]
    }

    // Verified against the exported vocabulary by the pipeline's conversion step.
    private static let unknownID: Int32 = 100
    private static let classifierID: Int32 = 101
    private static let separatorID: Int32 = 102
    public static let paddingID: Int32 = 0

    private static let continuationPrefix = "##"
    private static let maxCharactersPerWord = 100

    private let vocab: [String: Int32]

    public init(vocabulary: [String: Int32]) {
        self.vocab = vocabulary
    }

    /// Loads a `vocab.txt` — one token per line, ordered by id.
    public init(vocabularyURL: URL) throws {
        var text = try String(contentsOf: vocabularyURL, encoding: .utf8)
        // A trailing newline would otherwise register an empty token and shift nothing
        // — but it would make the vocabulary count misleading.
        if text.hasSuffix("\n") { text.removeLast() }

        var vocab = [String: Int32](minimumCapacity: 30_600)
        for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            vocab[String(line)] = Int32(index)
        }
        guard vocab["[CLS]"] == Self.classifierID, vocab["[SEP]"] == Self.separatorID else {
            throw HadithKitError.invalidVocabulary
        }
        self.init(vocabulary: vocab)
    }

    /// Tokenizes and pads to `length`, truncating the *content* so `[SEP]`
    /// always terminates the sequence — matching `truncation_side: right`.
    public func encode(_ text: String, paddedTo length: Int) -> Encoding {
        var ids: [Int32] = [Self.classifierID]
        let budget = max(0, length - 2)

        outer: for word in Self.preTokenize(Self.normalize(text)) {
            for piece in wordPieces(word) {
                if ids.count - 1 >= budget { break outer }
                ids.append(piece)
            }
        }
        ids.append(Self.separatorID)

        var mask = [Int32](repeating: 1, count: ids.count)
        if ids.count < length {
            let padding = length - ids.count
            ids.append(contentsOf: [Int32](repeating: Self.paddingID, count: padding))
            mask.append(contentsOf: [Int32](repeating: 0, count: padding))
        }
        return Encoding(ids: ids, attentionMask: mask)
    }

    /// Token count including `[CLS]`/`[SEP]`, used to pick a sequence length.
    public func tokenCount(_ text: String) -> Int {
        var count = 2
        for word in Self.preTokenize(Self.normalize(text)) {
            count += wordPieces(word).count
        }
        return count
    }

    // MARK: - WordPiece

    /// Greedy longest-match-first over the word, `##`-prefixing continuations.
    private func wordPieces(_ word: String) -> [Int32] {
        let characters = Array(word)
        guard !characters.isEmpty else { return [] }
        guard characters.count <= Self.maxCharactersPerWord else { return [Self.unknownID] }

        var pieces: [Int32] = []
        var start = 0
        while start < characters.count {
            var end = characters.count
            var matched: Int32?
            while start < end {
                var candidate = String(characters[start..<end])
                if start > 0 { candidate = Self.continuationPrefix + candidate }
                if let id = vocab[candidate] {
                    matched = id
                    break
                }
                end -= 1
            }
            guard let id = matched else {
                // Reference behaviour: one unmatched piece invalidates the
                // whole word, not just the remainder.
                return [Self.unknownID]
            }
            pieces.append(id)
            start = end
        }
        return pieces
    }

    // MARK: - BertNormalizer

    /// `clean_text` + `handle_chinese_chars` + `lowercase` + accent stripping.
    ///
    /// `strip_accents` is null in the config, which HuggingFace resolves to the
    /// value of `lowercase` — so accents are stripped.
    static func normalize(_ text: String) -> String {
        var cleaned = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if scalar.value == 0 || scalar.value == 0xFFFD { continue }
            if isControl(scalar) { continue }
            if isWhitespace(scalar) {
                cleaned.append(" ")
            } else if isCJK(scalar) {
                cleaned.append(" ")
                cleaned.append(scalar)
                cleaned.append(" ")
            } else {
                cleaned.append(scalar)
            }
        }

        let lowered = String(cleaned).lowercased()
        // NFD, then drop combining marks — the standard accent-stripping recipe.
        var stripped = String.UnicodeScalarView()
        for scalar in lowered.decomposedStringWithCanonicalMapping.unicodeScalars
        where scalar.properties.generalCategory != .nonspacingMark {
            stripped.append(scalar)
        }
        return String(stripped)
    }

    // MARK: - BertPreTokenizer

    /// Splits on whitespace, then peels each punctuation character into its own token.
    static func preTokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = String.UnicodeScalarView()

        func flush() {
            if !current.isEmpty {
                tokens.append(String(current))
                current = String.UnicodeScalarView()
            }
        }

        for scalar in text.unicodeScalars {
            if isWhitespace(scalar) {
                flush()
            } else if isPunctuation(scalar) {
                flush()
                tokens.append(String(scalar))
            } else {
                current.append(scalar)
            }
        }
        flush()
        return tokens
    }

    // MARK: - Character classes

    private static func isWhitespace(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x20, 0x09, 0x0A, 0x0D: return true
        default: return s.properties.generalCategory == .spaceSeparator
        }
    }

    private static func isControl(_ s: Unicode.Scalar) -> Bool {
        // Tab/newline/CR are handled as whitespace above, not as control chars.
        if s.value == 0x09 || s.value == 0x0A || s.value == 0x0D { return false }
        switch s.properties.generalCategory {
        case .control, .format, .lineSeparator, .paragraphSeparator, .privateUse, .surrogate:
            return true
        default:
            return false
        }
    }

    /// BERT's definition: ASCII symbol ranges count as punctuation even when
    /// Unicode classifies them as symbols (`$`, `+`, `^`, `~`, …).
    private static func isPunctuation(_ s: Unicode.Scalar) -> Bool {
        let v = s.value
        if (v >= 33 && v <= 47) || (v >= 58 && v <= 64)
            || (v >= 91 && v <= 96) || (v >= 123 && v <= 126) {
            return true
        }
        switch s.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
             .initialPunctuation, .finalPunctuation, .otherPunctuation:
            return true
        default:
            return false
        }
    }

    private static func isCJK(_ s: Unicode.Scalar) -> Bool {
        let v = s.value
        return (0x4E00...0x9FFF).contains(v)
            || (0x3400...0x4DBF).contains(v)
            || (0x20000...0x2A6DF).contains(v)
            || (0x2A700...0x2B73F).contains(v)
            || (0x2B740...0x2B81F).contains(v)
            || (0x2B820...0x2CEAF).contains(v)
            || (0xF900...0xFAFF).contains(v)
            || (0x2F800...0x2FA1F).contains(v)
    }
}
