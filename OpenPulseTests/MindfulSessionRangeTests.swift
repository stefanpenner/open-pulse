import Foundation
import Testing
@testable import OpenPulse

@Suite("MindfulSessionRange")
struct MindfulSessionRangeTests {
    @Test("End-anchored window uses active duration only")
    func endAnchoredActiveDuration() {
        let end = Date(timeIntervalSince1970: 1_700_000_600)
        let range = MindfulSessionRange.sample(activeSeconds: 300, end: end)
        #expect(range != nil)
        #expect(range!.end == end)
        #expect(range!.start == end.addingTimeInterval(-300))
        #expect(Int(range!.end.timeIntervalSince(range!.start)) == 300)
    }

    @Test("After long pause, sample does not start at original wall start")
    func pauseDoesNotClaimPauseWallTime() {
        // Session wall start at t0; pause 600s; active 300s; stop at t0+900
        let wallStart = Date(timeIntervalSince1970: 1_700_000_000)
        let stop = wallStart.addingTimeInterval(900)
        let range = MindfulSessionRange.sample(activeSeconds: 300, end: stop)!
        #expect(range.start > wallStart)
        #expect(range.start == stop.addingTimeInterval(-300))
        // Pause block [wallStart+0 … wallStart+600] is outside the sample when pause was early
        #expect(range.start >= wallStart.addingTimeInterval(600))
    }

    @Test("Rejects short or invalid active windows")
    func rejectsShort() {
        let end = Date()
        #expect(MindfulSessionRange.sample(activeSeconds: 29, end: end) == nil)
        #expect(MindfulSessionRange.sample(activeSeconds: 0, end: end) == nil)
        #expect(MindfulSessionRange.sample(activeSeconds: -5, end: end) == nil)
    }

    @Test("Accepts 30s minimum")
    func acceptsMinimum() {
        let end = Date(timeIntervalSince1970: 1000)
        let range = MindfulSessionRange.sample(activeSeconds: 30, end: end)
        #expect(range != nil)
        #expect(Int(range!.end.timeIntervalSince(range!.start)) == 30)
    }

    @Test("Multi-segment samples skip pause gaps")
    func multiSegmentSkipsPause() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        // practice 300s, pause 600s, practice 300s
        let segments: [(Date, Date)] = [
            (t0, t0.addingTimeInterval(300)),
            (t0.addingTimeInterval(900), t0.addingTimeInterval(1200)),
        ]
        let ranges = MindfulSessionRange.samples(from: segments)
        #expect(ranges.count == 2)
        #expect(ranges[0].start == t0)
        #expect(ranges[0].end == t0.addingTimeInterval(300))
        #expect(ranges[1].start == t0.addingTimeInterval(900))
        #expect(ranges[1].end == t0.addingTimeInterval(1200))
        // Pause gap [300, 900] is not covered
        #expect(ranges[0].end <= t0.addingTimeInterval(300))
        #expect(ranges[1].start >= t0.addingTimeInterval(900))
    }

    @Test("Multi-segment drops sub-30s fragments")
    func multiSegmentDropsShort() {
        let t0 = Date(timeIntervalSince1970: 2_000)
        let segments: [(Date, Date)] = [
            (t0, t0.addingTimeInterval(20)),
            (t0.addingTimeInterval(100), t0.addingTimeInterval(400)),
        ]
        let ranges = MindfulSessionRange.samples(from: segments)
        #expect(ranges.count == 1)
        #expect(Int(ranges[0].end.timeIntervalSince(ranges[0].start)) == 300)
    }

    @Test("Multi-segment empty input yields empty")
    func multiSegmentEmpty() {
        #expect(MindfulSessionRange.samples(from: []).isEmpty)
    }

    @Test("Resolve prefers valid multi-segment samples")
    func resolvePrefersSegments() {
        let t0 = Date(timeIntervalSince1970: 3_000)
        let segs: [(Date, Date)] = [
            (t0, t0.addingTimeInterval(120)),
            (t0.addingTimeInterval(200), t0.addingTimeInterval(500)),
        ]
        let ranges = MindfulSessionRange.resolve(
            segments: segs,
            activeSeconds: 999,
            end: t0.addingTimeInterval(600)
        )
        #expect(ranges.count == 2)
        #expect(ranges[0].end.timeIntervalSince(ranges[0].start) == 120)
    }

    @Test("Resolve falls back when all segments too short")
    func resolveFallbackShortSegments() {
        let end = Date(timeIntervalSince1970: 10_000)
        let segs: [(Date, Date)] = [
            (end.addingTimeInterval(-20), end.addingTimeInterval(-10)),
        ]
        let ranges = MindfulSessionRange.resolve(
            segments: segs,
            activeSeconds: 300,
            end: end
        )
        #expect(ranges.count == 1)
        #expect(Int(ranges[0].end.timeIntervalSince(ranges[0].start)) == 300)
        #expect(ranges[0].end == end)
    }

    @Test("Resolve falls back when segments empty")
    func resolveFallbackEmpty() {
        let end = Date(timeIntervalSince1970: 20_000)
        let ranges = MindfulSessionRange.resolve(
            segments: [],
            activeSeconds: 90,
            end: end
        )
        #expect(ranges.count == 1)
        #expect(Int(ranges[0].end.timeIntervalSince(ranges[0].start)) == 90)
    }

    @Test("Resolve empty when no segments and short active")
    func resolveEmptyWhenShort() {
        let ranges = MindfulSessionRange.resolve(
            segments: [],
            activeSeconds: 20,
            end: Date()
        )
        #expect(ranges.isEmpty)
    }
}
