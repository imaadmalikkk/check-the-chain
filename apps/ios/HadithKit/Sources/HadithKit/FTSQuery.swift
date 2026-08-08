import Foundation

/// Translates a user's typed query into an FTS5 MATCH expression.
///
/// Two problems to solve. First, FTS5's query syntax is not a safe place to
/// interpolate arbitrary text — an apostrophe in "Prophet's" or a bare `*` is
/// a syntax error, and the query comes straight from a text field.
///
/// Second, and less obviously: FTS5 joins bare terms with AND, while Convex's
/// search index — which produced the results this engine has to match — uses OR
/// with relevance ranking and prefix-matches the final term. Bare AND would
/// return nothing for most natural-language queries ("what did the prophet say
/// about seeking knowledge" requires all eight words in one hadith). So terms
/// are quoted, OR-joined, and the last one gets a prefix wildcard.
enum FTSQuery {
    /// Matches `apps/web/src/app/api/search/route.ts`, which returns no results
    /// below three characters rather than scanning the corpus on every keystroke.
    static let minimumQueryLength = 3

    static func match(for query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minimumQueryLength else { return nil }

        let terms = trimmed
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map { $0.lowercased() }
            .filter { !$0.isEmpty }

        guard !terms.isEmpty else { return nil }

        // Quoting makes each term a literal string token, which is what
        // neutralizes the syntax characters. A prefix `*` is legal immediately
        // after a closing quote.
        var clauses = terms.map { "\"\($0)\"" }
        if let last = terms.last, last.count >= 2 {
            clauses[clauses.count - 1] = "\"\(last)\"*"
        }
        return clauses.joined(separator: " OR ")
    }
}
