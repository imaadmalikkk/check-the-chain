import os

/// Shared logging for the package's internal use.
///
/// Kept internal: nothing outside HadithKit needs to see it, and the point of
/// on-device logging here is Console/sysdiagnose visibility for a subsystem
/// that can otherwise fail with no crash and no message — a SwiftData
/// migration failure would make every favourite vanish silently without this.
enum Log {
    static let library = Logger(subsystem: "com.checkthechain.app", category: "Library")
}
