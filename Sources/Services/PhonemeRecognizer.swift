import CoreML
import Foundation

/// Turns 16 kHz audio samples into a canonical-IPA phoneme sequence.
protocol PhonemeRecognizer {
    /// True when backed by the real acoustic model (vs. demo mock).
    var isRealModel: Bool { get }
    /// `targetHint` lets the mock produce meaningful demo output; the real
    /// recognizer ignores it entirely — no target leakage into recognition.
    func recognize(samples: [Float], targetHint: [String]) async throws -> [String]
}

// MARK: - Core ML (wav2vec2 phoneme CTC)

final class CoreMLPhonemeRecognizer: PhonemeRecognizer {
    let isRealModel = true

    private let model: MLModel
    private let idToToken: [Int: String]
    private let padID: Int
    private let fixedInputLength: Int?   // nil → flexible shape

    /// Returns nil when the model or vocab is not bundled (demo mode).
    init?() {
        guard let modelURL = Bundle.main.url(forResource: "PhonemeCTC", withExtension: "mlmodelc")
                ?? Bundle.main.url(forResource: "PhonemeCTC", withExtension: "mlpackage"),
              let vocabURL = Bundle.main.url(forResource: "phoneme_vocab", withExtension: "json"),
              let vocabData = try? Data(contentsOf: vocabURL),
              let vocab = try? JSONDecoder().decode([String: Int].self, from: vocabData)
        else { return nil }

        do {
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndNeuralEngine
            if modelURL.pathExtension == "mlpackage" {
                let compiled = try MLModel.compileModel(at: modelURL)
                model = try MLModel(contentsOf: compiled, configuration: config)
            } else {
                model = try MLModel(contentsOf: modelURL, configuration: config)
            }
        } catch {
            print("CoreMLPhonemeRecognizer: model load failed — \(error)")
            return nil
        }

        idToToken = Dictionary(uniqueKeysWithValues: vocab.map { ($0.value, $0.key) })
        padID = vocab["<pad>"] ?? 0

        // Read input mode written by the conversion script, if present.
        if let infoURL = Bundle.main.url(forResource: "phoneme_model_info", withExtension: "json"),
           let data = try? Data(contentsOf: infoURL),
           let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let mode = info["input_mode"] as? String, mode.hasPrefix("fixed:"),
           let len = Int(mode.dropFirst("fixed:".count)) {
            fixedInputLength = len
        } else {
            fixedInputLength = nil
        }
    }

    func recognize(samples: [Float], targetHint: [String]) async throws -> [String] {
        guard !samples.isEmpty else { return [] }

        // wav2vec2 expects zero-mean / unit-variance input.
        var x = samples
        let mean = x.reduce(0, +) / Float(x.count)
        let variance = x.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(x.count)
        let std = max(sqrt(variance), 1e-7)
        for i in x.indices { x[i] = (x[i] - mean) / std }

        if let fixed = fixedInputLength {
            if x.count < fixed { x.append(contentsOf: [Float](repeating: 0, count: fixed - x.count)) }
            if x.count > fixed { x = Array(x.prefix(fixed)) }
        }

        let array = try MLMultiArray(shape: [1, NSNumber(value: x.count)], dataType: .float32)
        x.withUnsafeBufferPointer { src in
            array.dataPointer.bindMemory(to: Float.self, capacity: x.count)
                .update(from: src.baseAddress!, count: x.count)
        }

        let input = try MLDictionaryFeatureProvider(dictionary: ["audio": MLFeatureValue(multiArray: array)])
        let output = try await model.prediction(from: input)
        guard let logits = output.featureValue(for: "logits")?.multiArrayValue else {
            throw NSError(domain: "PhonemeRecognizer", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "모델 출력 없음"])
        }

        return decodeCTC(logits: logits)
    }

    /// Greedy CTC decode: argmax per frame → collapse repeats → drop blanks.
    private func decodeCTC(logits: MLMultiArray) -> [String] {
        let shape = logits.shape.map(\.intValue)   // [1, T, V]
        guard shape.count == 3 else { return [] }
        let t = shape[1], v = shape[2]
        let ptr = logits.dataPointer.bindMemory(to: Float.self, capacity: t * v)

        var ids: [Int] = []
        var prev = -1
        for frame in 0..<t {
            var best = 0
            var bestVal = -Float.infinity
            let base = frame * v
            for c in 0..<v where ptr[base + c] > bestVal {
                bestVal = ptr[base + c]
                best = c
            }
            if best != prev && best != padID { ids.append(best) }
            prev = best
        }

        return ids.compactMap { idToToken[$0] }
            .compactMap { PhonemeMapping.normalizeRecognized($0) }
    }
}

// MARK: - Mock (demo mode, until the Core ML model is bundled)

/// Deterministic demo recognizer: echoes the target with one plausible
/// Korean-L1 error injected, so the diagnosis UI can be exercised end-to-end.
final class MockPhonemeRecognizer: PhonemeRecognizer {
    let isRealModel = false

    private static let typicalErrors: [String: String] = [
        "ɹ": "l", "f": "p", "v": "b", "θ": "s", "ð": "d",
        "z": "dʒ", "æ": "ɛ", "ɪ": "i", "ʊ": "u", "ɚ": "ə",
    ]

    func recognize(samples: [Float], targetHint: [String]) async throws -> [String] {
        try await Task.sleep(for: .milliseconds(400))  // simulate inference latency
        var result = targetHint
        // Inject the first applicable typical error (deterministic, not random).
        if let idx = result.firstIndex(where: { Self.typicalErrors[$0] != nil }) {
            result[idx] = Self.typicalErrors[result[idx]]!
        }
        // Word-final stop → simulate Korean release vowel (cake → 케이크).
        if let last = result.last, ["k", "t", "p", "b", "d", "ɡ"].contains(last) {
            result.append("ə")
        }
        return result
    }
}
