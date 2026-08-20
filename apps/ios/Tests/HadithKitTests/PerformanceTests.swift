import Foundation
import Testing
@testable import HadithKit

/// Measures the parts of search that could plausibly get slow, and asserts
/// budgets rather than just printing numbers.
///
/// Note these run on the simulator, where Core ML has no Neural Engine and
/// falls back to CPU ("Espresso compiled without MPSGraph engine" in the log).
/// Embedding is therefore *slower* here than on device; the budgets are set for
/// the simulator, so device performance can only beat them.
@Suite("Performance", .serialized)
struct PerformanceTests {
    /// The full-corpus scan is the one thing that runs on every keystroke and
    /// grows with the corpus. 47k × 384 int8 dot products should be a few
    /// milliseconds — it measures at 0.5ms here. The budget is set an order of
    /// magnitude above that because the failure mode isn't gradual: if the SIMD
    /// path stops vectorizing, this jumps straight to ~335ms.
    @Test("Vector scan over the full corpus stays under 5ms")
    func vectorScan() throws {
        let index = try TestFixtures.vectorIndex()
        let golden = try TestFixtures.golden()
        let query = golden.cases[0].embedding

        // Warm the page cache — the first scan pays for faulting in 18MB.
        _ = index.search(embedding: query, limit: 40)

        var timings: [Double] = []
        for testCase in golden.cases.prefix(10) {
            let start = ContinuousClock.now
            _ = index.search(embedding: testCase.embedding, limit: 40)
            timings.append(Double((ContinuousClock.now - start).components.attoseconds) / 1e15)
        }

        let median = timings.sorted()[timings.count / 2]
        print("Vector scan median: \(String(format: "%.2f", median)) ms over \(index.metadata.count) rows")
        #expect(median < 5, "Vector scan slowed to \(median) ms")
    }

    @Test("Keyword search stays under 50ms")
    func keywordSearch() async throws {
        let store = try TestFixtures.corpus().store
        _ = try await store.fullTextSearch(query: "prayer at night", limit: 40)

        var timings: [Double] = []
        for query in ["prayer at night", "kindness to neighbours", "fasting ramadan", "zakat charity"] {
            let start = ContinuousClock.now
            _ = try await store.fullTextSearch(query: query, limit: 40)
            timings.append(Double((ContinuousClock.now - start).components.attoseconds) / 1e15)
        }

        let median = timings.sorted()[timings.count / 2]
        print("FTS median: \(String(format: "%.2f", median)) ms")
        #expect(median < 50, "Keyword search slowed to \(median) ms")
    }

    /// End-to-end with the model already loaded — what a user feels after the
    /// first search of a session.
    @Test("Warm hybrid search stays under 150ms on the simulator")
    func warmSearch() async throws {
        let corpus = try TestFixtures.corpus()
        await corpus.embedder.warmUp()
        _ = try await corpus.engine.search(query: "warm up", limit: 20)

        var timings: [Double] = []
        for query in ["the virtue of praying at night", "kindness to neighbours",
                      "backbiting and gossip", "honesty in trade"] {
            let start = ContinuousClock.now
            _ = try await corpus.engine.search(query: query, limit: 20)
            timings.append(Double((ContinuousClock.now - start).components.attoseconds) / 1e15)
        }

        let median = timings.sorted()[timings.count / 2]
        print("Warm hybrid search median: \(String(format: "%.0f", median)) ms (CPU-only on simulator)")
        #expect(median < 150, "Warm search slowed to \(median) ms")
    }

    /// The reason the app is offline in the first place is that the web version
    /// leaks WASM tensors until Safari runs out of memory. The native path has
    /// no equivalent, and this asserts it: 50 consecutive searches must not grow
    /// the process footprint.
    @Test("Repeated searches do not grow memory")
    func memoryStaysFlat() async throws {
        let corpus = try TestFixtures.corpus()
        await corpus.embedder.warmUp()

        for _ in 0..<10 {
            _ = try await corpus.engine.search(query: "settling into a steady state", limit: 20)
        }
        let baseline = residentBytes()

        for i in 0..<50 {
            _ = try await corpus.engine.search(query: "search number \(i) about prayer", limit: 20)
        }
        let after = residentBytes()

        let growthMB = Double(after &- baseline) / 1_048_576
        print("Memory after 50 searches: \(String(format: "%+.1f", growthMB)) MB (baseline \(baseline / 1_048_576) MB)")
        #expect(growthMB < 10, "Footprint grew \(growthMB) MB over 50 searches")
    }

    private func residentBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }
}
