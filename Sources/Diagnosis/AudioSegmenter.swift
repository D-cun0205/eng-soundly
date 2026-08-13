import Foundation

/// Splits long recordings into model-window-sized chunks for recognition,
/// cutting at the quietest moment so phonemes aren't sliced mid-sound.
enum AudioSegmenter {

    /// Splits `samples` into segments of at most `window` samples. Each cut
    /// lands on the quietest 20 ms found in the last 40% of the window.
    static func segment(_ samples: [Float], window: Int) -> [[Float]] {
        guard window > 0 else { return [samples] }
        var segments: [[Float]] = []
        var start = 0
        while samples.count - start > window {
            let searchFrom = start + Int(Double(window) * 0.6)
            let searchTo = start + window
            let frame = 320   // 20 ms at 16 kHz
            var quietest = searchTo - frame
            var quietestEnergy = Float.infinity
            var i = searchFrom
            while i + frame <= searchTo {
                var e: Float = 0
                for s in samples[i..<(i + frame)] { e += s * s }
                if e < quietestEnergy { quietestEnergy = e; quietest = i }
                i += frame
            }
            let cut = quietest + frame / 2
            segments.append(Array(samples[start..<cut]))
            start = cut
        }
        segments.append(Array(samples[start...]))
        return segments
    }
}
