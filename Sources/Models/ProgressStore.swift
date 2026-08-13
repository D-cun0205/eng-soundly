import Combine
import Foundation

/// Persistent per-phoneme accuracy tracking across practice sessions.
/// Every real-model diagnosis feeds it; the dashboard and drills read it.
@MainActor
final class ProgressStore: ObservableObject {

    struct PhonemeStat: Codable, Equatable {
        var attempts: Int = 0
        var errors: Int = 0
        var accuracy: Double { attempts > 0 ? 1 - Double(errors) / Double(attempts) : 1 }
    }

    struct WeakPhoneme: Identifiable {
        var id: String { phoneme }
        let phoneme: String
        let accuracy: Double
        let attempts: Int
    }

    @Published private(set) var stats: [String: PhonemeStat] = [:]

    private let fileURL: URL

    /// Phonemes need this many observations before they count as evidence.
    static let minAttempts = 3

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultURL()
        if let data = try? Data(contentsOf: self.fileURL),
           let decoded = try? JSONDecoder().decode([String: PhonemeStat].self, from: data) {
            stats = decoded
        }
    }

    private static func defaultURL() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("phoneme_progress.json")
    }

    /// Folds one diagnosis into the stats. Demo-mode reports are ignored by
    /// the caller; leniency-skipped mismatches never made it into `issues`,
    /// so only confident errors are counted.
    func record(_ report: DiagnosisReport) {
        // Every target phoneme the user attempted.
        for op in report.ops {
            guard let t = op.target else { continue }
            stats[t, default: PhonemeStat()].attempts += 1
        }
        // Errors: issues anchored to a target phoneme (substitutions/deletions).
        for issue in report.issues {
            guard let t = issue.op.target else { continue }
            stats[t, default: PhonemeStat()].errors += 1
        }
        save()
    }

    /// Weakest phonemes first, requiring a minimum number of attempts.
    var weakestPhonemes: [WeakPhoneme] {
        stats.compactMap { phoneme, stat in
            guard stat.attempts >= Self.minAttempts, stat.errors > 0 else { return nil }
            return WeakPhoneme(phoneme: phoneme, accuracy: stat.accuracy,
                               attempts: stat.attempts)
        }
        .sorted { ($0.accuracy, -$0.attempts) < ($1.accuracy, -$1.attempts) }
    }

    func reset() {
        stats = [:]
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(stats) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
