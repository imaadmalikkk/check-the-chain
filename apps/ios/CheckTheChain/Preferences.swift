import Foundation

/// Shared `@AppStorage` keys.
///
/// A bare string literal duplicated at every call site has no compiler help:
/// a typo in one silently decouples a toggle from what it's supposed to
/// control. One constant, used everywhere the key is needed.
enum PreferenceKey {
    /// Whether `HadithDetailView` calls `Library.recordView`. Owned by the
    /// app target, not HadithKit — `Library` knows nothing about this switch,
    /// it just isn't called when this is off.
    static let recordsHistory = "recordsHistory"
}
