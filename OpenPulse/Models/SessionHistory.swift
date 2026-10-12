import Foundation

/// One completed or stopped session — local only, no cloud.
struct SessionRecord: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let endedAt: Date
    let modeRaw: String
    let durationSeconds: Int
    let strength: Int
    /// True when the timer ran to zero; false if the user stopped early.
    let completed: Bool
    /// Nil on rows saved before pace and pattern existed.
    let breathePaceRaw: String?
    let easePatternRaw: String?

    init(
        id: UUID = UUID(),
        endedAt: Date,
        modeRaw: String,
        durationSeconds: Int,
        strength: Int,
        completed: Bool,
        breathePaceRaw: String? = nil,
        easePatternRaw: String? = nil
    ) {
        self.id = id
        self.endedAt = endedAt
        self.modeRaw = modeRaw
        self.durationSeconds = durationSeconds
        self.strength = strength
        self.completed = completed
        self.breathePaceRaw = breathePaceRaw
        self.easePatternRaw = easePatternRaw
    }

    /// Display name including Meditate / Burst when relevant.
    var modeName: String {
        let base = StimulationMode(rawValue: modeRaw)?.name ?? modeRaw
        if isMeditatePace { return "\(base) · Meditate" }
        if isEaseBurst { return "\(base) · Burst" }
        return base
    }

    private var isMeditatePace: Bool {
        breathePaceRaw == BreathePace.meditate.rawValue
            && (modeRaw == StimulationMode.calm.rawValue
                || modeRaw == StimulationMode.meditation.rawValue)
    }

    /// Legacy headache already reads "Ease burst". Do not append again.
    private var isEaseBurst: Bool {
        easePatternRaw == EasePattern.burst.rawValue
            && modeRaw == StimulationMode.painRelief.rawValue
    }
}

/// On-device session log (privacy-first; caps size).
enum SessionHistory {
    static let storageKey = "history.sessions"
    static let maxEntries = 40

    static func load(defaults: UserDefaults = .standard) -> [SessionRecord] {
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([SessionRecord].self, from: data)) ?? []
    }

    static func append(
        mode: StimulationMode,
        durationSeconds: Int,
        strength: Int,
        completed: Bool,
        breathePace: BreathePace? = nil,
        easePattern: EasePattern? = nil,
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) {
        var items = load(defaults: defaults)
        let record = SessionRecord(
            endedAt: now,
            modeRaw: mode.rawValue,
            durationSeconds: max(0, durationSeconds),
            strength: max(1, min(9, strength)),
            completed: completed,
            breathePaceRaw: storedPace(mode: mode, pace: breathePace),
            easePatternRaw: storedPattern(mode: mode, pattern: easePattern)
        )
        items.insert(record, at: 0)
        if items.count > maxEntries {
            items = Array(items.prefix(maxEntries))
        }
        save(items, defaults: defaults)
    }

    /// Pace is stored only for a breath mode. Other modes keep a nil pace.
    private static func storedPace(mode: StimulationMode, pace: BreathePace?) -> String? {
        guard mode.usesBreathingGuide || mode == .meditation else { return nil }
        return (pace ?? .calm).rawValue
    }

    /// Pattern is stored only for Ease. Other modes keep a nil pattern.
    private static func storedPattern(mode: StimulationMode, pattern: EasePattern?) -> String? {
        guard mode == .painRelief || mode == .headache else { return nil }
        return (pattern ?? .wave).rawValue
    }

    private static func save(_ items: [SessionRecord], defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: storageKey)
        }
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey)
    }

    static func count(defaults: UserDefaults = .standard) -> Int {
        load(defaults: defaults).count
    }

    /// Completed sessions whose end date falls in the current calendar week.
    static func completedThisWeek(defaults: UserDefaults = .standard, now: Date = Date(), calendar: Calendar = .current) -> Int {
        completedThisWeek(from: load(defaults: defaults), now: now, calendar: calendar)
    }

    static func completedThisWeek(
        from sessions: [SessionRecord],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        sessions.filter {
            $0.completed && calendar.isDate($0.endedAt, equalTo: now, toGranularity: .weekOfYear)
        }.count
    }

    /// Total active minutes logged this calendar week (any stop or complete).
    static func minutesThisWeek(defaults: UserDefaults = .standard, now: Date = Date(), calendar: Calendar = .current) -> Int {
        minutesThisWeek(from: load(defaults: defaults), now: now, calendar: calendar)
    }

    static func minutesThisWeek(
        from sessions: [SessionRecord],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        let secs = sessions
            .filter { calendar.isDate($0.endedAt, equalTo: now, toGranularity: .weekOfYear) }
            .reduce(0) { $0 + max(0, $1.durationSeconds) }
        return secs / 60
    }

    /// Consecutive calendar days (ending today or yesterday) with ≥1 completed session.
    static func currentStreak(defaults: UserDefaults = .standard, now: Date = Date(), calendar: Calendar = .current) -> Int {
        streak(from: load(defaults: defaults), now: now, calendar: calendar)
    }

    /// Streak from an in-memory list (sheet/strip — no extra UserDefaults read).
    static func streak(
        from sessions: [SessionRecord],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        let completedDays: Set<Date> = Set(
            sessions
                .filter(\.completed)
                .map { calendar.startOfDay(for: $0.endedAt) }
        )
        guard !completedDays.isEmpty else { return 0 }

        let today = calendar.startOfDay(for: now)
        // Streak can start from today or yesterday (grace if not done yet today)
        var cursor = today
        if !completedDays.contains(today) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                  completedDays.contains(yesterday) else { return 0 }
            cursor = yesterday
        }

        var n = 0
        while completedDays.contains(cursor) {
            n += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return n
    }
}
