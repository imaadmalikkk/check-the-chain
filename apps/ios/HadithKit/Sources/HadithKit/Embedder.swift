import CoreML
import Foundation

/// Turns a query string into the 384-dim vector `VectorIndex` searches with.
///
/// Mean pooling and L2 normalization live inside the Core ML graph (see
/// `packages/pipeline/coreml/convert_minilm.py`), so this type does no tensor
/// arithmetic — it tokenizes, predicts, and hands back the result. Pooling is
/// the easiest place to silently diverge from the corpus embeddings, and there
/// is exactly one implementation of it.
public actor Embedder {
    /// Must match `SEQ_LENGTHS` in the conversion script. Core ML compiles a
    /// variant per shape; asking for anything else fails at prediction time.
    private static let sequenceLengths = [32, 64, 128, 256]

    private let modelURL: URL
    private let tokenizer: BertTokenizer
    private var model: MLModel?

    public init(compiledModelURL: URL, vocabularyURL: URL) throws {
        guard FileManager.default.fileExists(atPath: compiledModelURL.path) else {
            throw HadithKitError.missingResource(compiledModelURL.lastPathComponent)
        }
        modelURL = compiledModelURL
        tokenizer = try BertTokenizer(vocabularyURL: vocabularyURL)
    }

    public var isReady: Bool { model != nil }

    /// Loads the model ahead of the first query.
    ///
    /// A cold load costs 1–2 seconds. Calling this at launch means the search
    /// field is hybrid by the time anyone has finished typing, instead of
    /// stalling on the first keystroke.
    public func warmUp() async {
        _ = try? loadModel()
    }

    public func embed(_ text: String) throws -> [Float] {
        let model = try loadModel()
        let length = Self.sequenceLength(for: tokenizer.tokenCount(text))
        let encoding = tokenizer.encode(text, paddedTo: length)

        let input = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: try Self.multiArray(encoding.ids)),
            "attention_mask": MLFeatureValue(multiArray: try Self.multiArray(encoding.attentionMask)),
        ])

        let output = try model.prediction(from: input)
        guard let array = output.featureValue(for: "embedding")?.multiArrayValue else {
            throw HadithKitError.missingResource("embedding output")
        }

        return array.withUnsafeBufferPointer(ofType: Float.self) { Array($0) }
    }

    private func loadModel() throws -> MLModel {
        if let model { return model }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        let loaded = try MLModel(contentsOf: modelURL, configuration: configuration)
        model = loaded
        return loaded
    }

    private static func sequenceLength(for tokenCount: Int) -> Int {
        sequenceLengths.first { tokenCount <= $0 } ?? sequenceLengths[sequenceLengths.count - 1]
    }

    private static func multiArray(_ values: [Int32]) throws -> MLMultiArray {
        let array = try MLMultiArray(shape: [1, NSNumber(value: values.count)], dataType: .int32)
        let pointer = array.dataPointer.bindMemory(to: Int32.self, capacity: values.count)
        for (index, value) in values.enumerated() { pointer[index] = value }
        return array
    }
}
