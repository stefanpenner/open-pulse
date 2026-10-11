import Foundation
import Testing
@testable import OpenPulse

@Suite("SessionHistory — streak & week")
struct SessionHistoryStreakTests {
    private func suiteDefaults() -> UserDefaults {
        let name = "test.history.\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    @Test("Append then load newest first")
    func appendLoad() {
        let d = suiteDefaults()
        SessionHistory.append(mode: .calm, durationSeconds: 120, strength: 4, completed: true, defaults: d)
        SessionHistory.append(mode: .focus, durationSeconds: 60, strength: 5, completed: false, defaults: d)
        let items = SessionHistory.load(defaults: d)
        #expect(items.count == 2)
        #expect(items[0].modeRaw == StimulationMode.focus.rawValue)
        #expect(items[1].completed)
    }

    @Test("currentStreak counts consecutive completed days with yesterday grace")
    func streakGrace() {
        let d = suiteDefaults()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_700_000_000) // fixed
        let today = cal.startOfDay(for: now)
        guard let yesterday = cal.date(byAdding: .day, value: -1, to: today),
              let twoAgo = cal.date(byAdding: .day, value: -2, to: today) else {
            Issue.record("date math failed")
            return
        }

        // Completed yesterday + two days ago, nothing today → streak 2
        SessionHistory.append(
            mode: .calm, durationSeconds: 60, strength: 5, completed: true,
            defaults: d, now: yesterday.addingTimeInterval(3600)
        )
        SessionHistory.append(
            mode: .focus, durationSeconds: 60, strength: 5, completed: true,
            defaults: d, now: twoAgo.addingTimeInterval(3600)
        )
        #expect(SessionHistory.currentStreak(defaults: d, now: now, calendar: cal) == 2)
    }

    @Test("Incomplete sessions do not extend streak")
    func incompleteNoStreak() {
        let d = suiteDefaults()
        let cal = Calendar.current
        let now = Date()
        SessionHistory.append(
            mode: .calm, durationSeconds: 30, strength: 5, completed: false,
            defaults: d, now: now
        )
        #expect(SessionHistory.currentStreak(defaults: d, now: now, calendar: cal) == 0)
    }

    @Test("minutesThisWeek sums all sessions")
    func weekMinutes() {
        let d = suiteDefaults()
        let now = Date()
        SessionHistory.append(mode: .calm, durationSeconds: 120, strength: 4, completed: true, defaults: d, now: now)
        SessionHistory.append(mode: .focus, durationSeconds: 60, strength: 5, completed: false, defaults: d, now: now)
        #expect(SessionHistory.minutesThisWeek(defaults: d, now: now) == 3)
    }

    @Test("Clear removes all local history")
    func clearHistory() {
        let d = suiteDefaults()
        SessionHistory.append(mode: .calm, durationSeconds: 60, strength: 5, completed: true, defaults: d)
        #expect(SessionHistory.count(defaults: d) == 1)
        SessionHistory.clear(defaults: d)
        #expect(SessionHistory.load(defaults: d).isEmpty)
        #expect(SessionHistory.count(defaults: d) == 0)
    }

    @Test("History names include Meditate / Burst variants")
    func historyVariantNames() {
        let d = suiteDefaults()
        SessionHistory.append(
            mode: .calm, durationSeconds: 60, strength: 4, completed: true,
            breathePace: .meditate, defaults: d
        )
        SessionHistory.append(
            mode: .painRelief, durationSeconds: 60, strength: 5, completed: true,
            easePattern: .burst, defaults: d
        )
        let items = SessionHistory.load(defaults: d)
        #expect(items[0].modeName.contains("Burst"))
        #expect(items[1].modeName.contains("Meditate"))
    }

    @Test("Legacy headache + burst does not double Burst label")
    func legacyHeadacheNoDoubleBurst() {
        let rec = SessionRecord(
            endedAt: Date(),
            modeRaw: "headache",
            durationSeconds: 60,
            strength: 5,
            completed: true,
            easePatternRaw: "burst"
        )
        #expect(rec.modeName == "Ease burst")
        #expect(!rec.modeName.contains("Burst · Burst"))
        #expect(rec.modeName != "Ease burst · Burst")
    }

    @Test("Old history rows without options still decode")
    func legacyHistoryDecode() throws {
        let d = suiteDefaults()
        let rec = SessionRecord(
            endedAt: Date(),
            modeRaw: "stressRelief",
            durationSeconds: 90,
            strength: 5,
            completed: true
        )
        let data = try JSONEncoder().encode([rec])
        d.set(data, forKey: SessionHistory.storageKey)
        let items = SessionHistory.load(defaults: d)
        #expect(items.count == 1)
        #expect(items[0].modeName == "Stress")
        #expect(items[0].breathePaceRaw == nil)
        #expect(items[0].easePatternRaw == nil)
    }
}
