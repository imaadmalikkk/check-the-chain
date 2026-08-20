import Foundation

/// Brute-force nearest-neighbour search over the whole corpus.
///
/// Replaces Convex's vector index. At 47k × 384 there is no reason for an ANN
/// structure: a full scan is ~18M multiply-accumulates, which the CPU does in a
/// few milliseconds, and it returns exact results rather than approximate ones.
///
/// Both the stored vectors and the query are L2-normalized, so ranking by the
/// raw integer dot product is monotonic in cosine similarity — the quantization
/// scale is a positive constant shared by every row and cancels out of the
/// comparison. That is why `scale` is recorded in the sidecar but never applied
/// to a score.
public final class VectorIndex: Sendable {
    public struct Metadata: Decodable, Sendable {
        public let revision: String
        public let count: Int
        public let dim: Int
        public let dtype: String
        public let scale: Double
    }

    public let metadata: Metadata

    /// Memory-mapped, so the 18MB matrix is paged in on demand and counts as
    /// clean file-backed memory the system can evict under pressure.
    private let storage: Data

    public init(binaryURL: URL, metadataURL: URL) throws {
        guard FileManager.default.fileExists(atPath: binaryURL.path) else {
            throw HadithKitError.missingResource(binaryURL.lastPathComponent)
        }
        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            throw HadithKitError.missingResource(metadataURL.lastPathComponent)
        }

        metadata = try JSONDecoder().decode(Metadata.self, from: Data(contentsOf: metadataURL))
        guard metadata.dtype == "int8" else {
            throw HadithKitError.corruptEmbeddings("unsupported dtype \(metadata.dtype)")
        }

        storage = try Data(contentsOf: binaryURL, options: .mappedIfSafe)
        let expected = metadata.count * metadata.dim
        guard storage.count == expected else {
            throw HadithKitError.corruptEmbeddings(
                "expected \(expected) bytes for \(metadata.count)×\(metadata.dim), found \(storage.count)"
            )
        }
    }

    /// Quantizes the query and returns the `limit` best-matching row ids,
    /// highest similarity first.
    public func search(embedding: [Float], limit: Int) -> [Int64] {
        guard embedding.count == metadata.dim else { return [] }

        let scale = Float(metadata.scale)
        var query = [Int8](repeating: 0, count: metadata.dim)
        for i in 0..<metadata.dim {
            let q = (embedding[i] * scale).rounded()
            query[i] = Int8(max(-127, min(127, q)))
        }

        let dim = metadata.dim
        let rows = metadata.count
        var top = TopK(capacity: limit)

        storage.withUnsafeBytes { raw in
            let corpus = raw.bindMemory(to: Int8.self)
            query.withUnsafeBufferPointer { q in
                for row in 0..<rows {
                    let score = Self.dot(q.baseAddress!, corpus.baseAddress! + row * dim, dim)
                    top.offer(id: Int64(row), score: score)
                }
            }
        }

        return top.sortedIDs()
    }

    /// Widening int8 dot product, 16 lanes at a time.
    ///
    /// The widening matters: element products reach 127×127 and 384 of them are
    /// summed, which overflows Int16 well before the end of a row. Accumulating
    /// in Int32 lanes keeps it exact.
    @inline(__always)
    private static func dot(
        _ a: UnsafePointer<Int8>,
        _ b: UnsafePointer<Int8>,
        _ count: Int
    ) -> Int32 {
        var accumulator = SIMD16<Int32>()
        var i = 0
        while i + 16 <= count {
            // `truncatingIfNeeded` sign-extends when widening, which is what we want.
            let lhs = SIMD16<Int32>(truncatingIfNeeded: UnsafeRawPointer(a + i).loadUnaligned(as: SIMD16<Int8>.self))
            let rhs = SIMD16<Int32>(truncatingIfNeeded: UnsafeRawPointer(b + i).loadUnaligned(as: SIMD16<Int8>.self))
            accumulator &+= lhs &* rhs
            i += 16
        }
        var total = accumulator.wrappedSum()
        while i < count {
            total &+= Int32(a[i]) * Int32(b[i])
            i += 1
        }
        return total
    }
}

/// Bounded top-k selector.
///
/// A full sort of 47k candidates per keystroke would dominate the scan it
/// follows. This keeps only `capacity` entries and rejects the overwhelming
/// majority with a single comparison against the current worst score.
private struct TopK {
    private var ids: [Int64]
    private var scores: [Int32]
    private let capacity: Int
    private var count = 0
    private var worstIndex = 0

    init(capacity: Int) {
        self.capacity = max(1, capacity)
        ids = [Int64](repeating: 0, count: self.capacity)
        scores = [Int32](repeating: .min, count: self.capacity)
    }

    mutating func offer(id: Int64, score: Int32) {
        if count < capacity {
            ids[count] = id
            scores[count] = score
            count += 1
            if count == capacity { recomputeWorst() }
            return
        }
        guard score > scores[worstIndex] else { return }
        ids[worstIndex] = id
        scores[worstIndex] = score
        recomputeWorst()
    }

    private mutating func recomputeWorst() {
        var index = 0
        var worst = scores[0]
        for i in 1..<count where scores[i] < worst {
            worst = scores[i]
            index = i
        }
        worstIndex = index
    }

    func sortedIDs() -> [Int64] {
        (0..<count)
            .sorted { scores[$0] > scores[$1] }
            .map { ids[$0] }
    }
}
