import Foundation
import HealthKit

/// Pure HealthKit sample window for Mindful Minutes.
/// End-anchored single sample, or multi-segment so pause gaps are not claimed as practice.
struct MindfulSessionRange: Equatable, Sendable {
    let start: Date
    let end: Date

    /// Active seconds only (pause excluded). Placed just before `end`.
    /// Returns nil when below the 30s meaningful floor.
    static func sample(activeSeconds: Int, end: Date = Date()) -> MindfulSessionRange? {
        guard activeSeconds >= 30 else { return nil }
        let start = end.addingTimeInterval(-TimeInterval(activeSeconds))
        guard end > start else { return nil }
        return MindfulSessionRange(start: start, end: end)
    }

    /// One Health sample per active segment (≥ minSeconds). Pause gaps are omitted.
    static func samples(
        from segments: [(start: Date, end: Date)],
        minSeconds: Int = 30
    ) -> [MindfulSessionRange] {
        segments.compactMap { seg in
            guard seg.end > seg.start else { return nil }
            let secs = Int(seg.end.timeIntervalSince(seg.start))
            guard secs >= minSeconds else { return nil }
            return MindfulSessionRange(start: seg.start, end: seg.end)
        }
    }

    /// Prefer multi-segment samples; if none qualify, end-anchor from activeSeconds.
    static func resolve(
        segments: [(start: Date, end: Date)],
        activeSeconds: Int,
        end: Date = Date(),
        minSeconds: Int = 30
    ) -> [MindfulSessionRange] {
        let fromSegments = samples(from: segments, minSeconds: minSeconds)
        if !fromSegments.isEmpty { return fromSegments }
        if let single = sample(activeSeconds: activeSeconds, end: end) {
            return [single]
        }
        return []
    }
}

// MARK: - Testable seam (VM lifecycle unit tests)

/// Opt-in mindful write surface. Production uses HealthKit; tests inject a recording double.
@MainActor
protocol MindfulMinutesWriting: AnyObject {
    func requestAuthorization() async throws
    func saveSession(start: Date, end: Date) async throws
}

/// Opt-in HealthKit write for mindful minutes after breathing sessions.
/// Privacy-first: never reads health data; only writes when the user enables it.
@MainActor
final class MindfulMinutesStore: MindfulMinutesWriting {
    private let store = HKHealthStore()

    var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    private var mindfulType: HKCategoryType? {
        HKObjectType.categoryType(forIdentifier: .mindfulSession)
    }

    /// Request write-only authorization for mindful sessions.
    func requestAuthorization() async throws {
        guard isHealthDataAvailable, let type = mindfulType else {
            throw MindfulError.unavailable
        }
        try await store.requestAuthorization(toShare: [type], read: [])
    }

    /// Save a completed session window as a mindful sample (duration marker).
    func saveSession(start: Date, end: Date) async throws {
        guard isHealthDataAvailable, let type = mindfulType else {
            throw MindfulError.unavailable
        }
        guard end > start else { throw MindfulError.invalidRange }

        let sample = HKCategorySample(
            type: type,
            value: HKCategoryValue.notApplicable.rawValue,
            start: start,
            end: end
        )
        try await store.save(sample)
    }

    enum MindfulError: Error {
        case unavailable
        case invalidRange
    }
}
