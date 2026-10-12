import Foundation
import UIKit
import Combine

@MainActor
final class SessionViewModel: ObservableObject {
    @Published var timerMinutes = StimulationMode.stressRelief.defaultDurationMinutes
    @Published var strength = StimulationMode.stressRelief.defaultStrength
    @Published var isRunning = false
    @Published var isPaused = false
    @Published var remainingSeconds = 0

    // Mode support — Still shell defaults to Stress (not Custom)
    @Published var selectedMode: StimulationMode = .stressRelief
    @Published var selectedFeeling: AutonomicState? = .stressed
    /// Breathe pace (Calm vs Meditate cycle). Surface only for Breathe mode.
    @Published var breathePace: BreathePace = .calm
    /// Ease pattern (Wave vs Burst). Surface only for Ease mode.
    @Published var easePattern: EasePattern = .wave
    @Published var stimulationActive = false
    @Published var effectiveStrength: Int? = nil
    @Published var breathingPhase: BreathingPhase? = nil
    @Published var modeStatus: String = ""
    @Published var activeChannel: ActiveChannel = .off
    /// Newest-first local session log (privacy-first, no cloud).
    @Published private(set) var recentSessions: [SessionRecord] = []
    /// Opt-in Apple Health Mindful Minutes (write-only).
    @Published var mindfulMinutesEnabled: Bool = false
    /// Opt-in local notification when session ends in background (privacy-first).
    @Published var sessionEndAlertsEnabled: Bool = false
    /// Opt-in morning/evening local reminders (no streak shame).
    @Published var sessionRemindersEnabled: Bool = false
    /// Opt-in local ambient pad during sessions (bundled only — no streaming).
    @Published var ambientMusicEnabled: Bool = false
    /// System denied notifications while toggle is on (Still honesty).
    @Published private(set) var sessionEndAlertsDenied: Bool = false
    /// Brief post-session message for wellness micro-feedback (cleared by UI).
    @Published var completionBanner: String?
    /// Bumps only when user adjusts remaining time (±) — not wall-clock ticks.
    @Published private(set) var userAdjustedRemainingToken: UInt64 = 0

    /// Production: `BluetoothManager`. Tests: `MockDeviceTransport` (no CoreBluetooth).
    let ble: DeviceState
    /// Production: system local notifications. Tests: recording double.
    private let endNotifier: any SessionEndNotifying
    /// Production: HealthKit write-only. Tests: recording double.
    private let mindfulStore: any MindfulMinutesWriting
    /// Production: ActivityKit. Tests: recording double.
    private let liveActivity: any SessionLiveActivityPresenting
    /// Production: bundled ambient pad. Tests: null double.
    private let ambientAudio: any SessionAmbientAudioPlaying
    /// True after first auth fetch/callback for end alerts (avoids schedule-before-hydrate race).
    private var sessionEndAlertsAuthResolved = false
    /// Wall-clock start of the current run segment (legacy / restore fallback).
    private var sessionWallStart: Date?
    /// Open mindful segment start (closed on pause/stop).
    private var mindfulSegmentStart: Date?
    /// Completed active segments for multi-sample HealthKit writes (pause gaps omitted).
    private var mindfulSegments: [(start: Date, end: Date)] = []
    /// Custom mode: soft re-entry after pause (not mid-session BLE drop).
    private var customSoftOnNextResume = false
    /// Custom soft window begin (session elapsed) for local SoftStart steps.
    private var customSoftBeginElapsed: Int?

    // Computed
    var displayTime: String {
        let total = (isRunning || isPaused) ? remainingSeconds : timerMinutes * 60
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }

    var progress: Double {
        guard isRunning || isPaused, sessionTotalDuration > 0 else { return 0 }
        return 1.0 - Double(remainingSeconds) / Double(sessionTotalDuration)
    }

    /// Session may start only when idle, BLE ready, and pack not empty / mid-read (SessionBLE Start guard).
    var canStart: Bool {
        !isRunning && !isPaused && ble.isReady
            && !BatteryPresentation.blocksStart(
                percent: ble.batteryPercentage,
                isCharging: ble.isCharging,
                sampleConfirmed: ble.batterySampleConfirmed,
                secondsSinceReady: secondsSinceLinkReady
            )
    }

    /// User-facing reason Start is blocked (empty when canStart).
    var startBlockedReason: String? {
        guard !isRunning, !isPaused else { return nil }
        if ble.isBluetoothOff { return "Turn on Bluetooth" }
        if !ble.isConnected { return "Searching for device…" }
        if !ble.isReady { return "Connecting…" }
        if let batteryReason = BatteryPresentation.startBlockedReason(
            percent: ble.batteryPercentage,
            isCharging: ble.isCharging,
            sampleConfirmed: ble.batterySampleConfirmed,
            secondsSinceReady: secondsSinceLinkReady
        ) {
            return batteryReason
        }
        return nil
    }

    /// Wall seconds since current ready edge (nil when not ready).
    /// Public for SessionActionBridge Start battery-gate parity with `canStart`.
    var secondsSinceLinkReady: TimeInterval? {
        guard ble.isReady, let at = linkReadyAt else { return nil }
        return max(0, now().timeIntervalSince(at))
    }

    /// Same battery Start gate as `canStart` (Shortcuts / Island / drainPending).
    var blocksStartForBattery: Bool {
        BatteryPresentation.blocksStart(
            percent: ble.batteryPercentage,
            isCharging: ble.isCharging,
            sampleConfirmed: ble.batterySampleConfirmed,
            secondsSinceReady: secondsSinceLinkReady
        )
    }

    /// Planned or active session length in seconds (for progress UI).
    var sessionDurationSeconds: Int {
        if isRunning || isPaused, sessionTotalDuration > 0 {
            return sessionTotalDuration
        }
        return max(60, timerMinutes * 60)
    }

    private var countdownTimer: Timer?
    private var keepaliveTask: Task<Void, Never>?
    private var statusPollTimer: Timer?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var isInBackground = false
    private var cancellables = Set<AnyCancellable>()

    private var engine: ModeEngine?
    private var sessionTotalDuration = 0
    private var elapsed: Int { sessionTotalDuration - remainingSeconds }

    // Wall-clock tracking (internal for testability)
    var sessionStartDate: Date?
    var accumulatedPauseTime: TimeInterval = 0
    private var pauseStartDate: Date?
    var backgroundEntryDate: Date?
    /// When BLE last became ready — battery-unknown grace for Start gate.
    private(set) var linkReadyAt: Date?
    /// When mid-run link dropped — offline auto-pause timer.
    private(set) var offlineSince: Date?
    /// Clock inject for grace / offline tests; production uses wall clock.
    var now: () -> Date = { Date() }
    private var batteryGraceRefreshTask: Task<Void, Never>?
    private var offlineAutoPauseTask: Task<Void, Never>?
    /// False until disk restore finishes. The ready publisher emits on subscribe.
    private var acceptsLinkReady = false

    /// When session ends/pauses while disconnected, send deactivate on next ready.
    /// Backed by UserDefaults so process death cannot leave hardware stim on.
    /// `@Published` so PendingOffBanner dismisses as soon as off ACK lands.
    @Published private(set) var pendingDeactivate = false {
        didSet {
            AppPreferences.setPendingDeactivate(pendingDeactivate, defaults: defaults)
            if pendingDeactivate {
                startPendingOffRetryLoop()
            } else {
                stopPendingOffRetryLoop()
            }
        }
    }
    /// Bumps only when hardware off is confirmed via write success (haptic trigger).
    @Published private(set) var deviceOffConfirmedToken: UInt64 = 0
    private var backgroundWatchTask: Task<Void, Never>?
    private var backgroundPingTask: Task<Void, Never>?
    private var pendingOffRetryTask: Task<Void, Never>?
    /// Last elapsed second fed to the engine — large jumps need absolute reassert.
    private var lastTickElapsed: Int?
    /// Min wall gap (seconds) before absolute off+reprogram. Must exceed 5s watch + 10s BLE ping
    /// so normal background polls do not blip stim every few seconds.
    static let absoluteReassertMinGapSeconds = 15

    init(
        defaults: UserDefaults = .standard,
        ble: DeviceState = BluetoothManager(),
        endNotifier: (any SessionEndNotifying)? = nil,
        mindfulStore: (any MindfulMinutesWriting)? = nil,
        liveActivity: (any SessionLiveActivityPresenting)? = nil,
        ambientAudio: (any SessionAmbientAudioPlaying)? = nil,
        now: @escaping () -> Date = { Date() }
    ) {
        self.now = now
        self.defaults = defaults
        self.ble = ble
        self.endNotifier = endNotifier ?? SystemSessionEndNotifier()
        self.mindfulStore = mindfulStore ?? MindfulMinutesStore()
        self.liveActivity = liveActivity ?? SessionLiveActivityController()
        self.ambientAudio = ambientAudio ?? SessionAmbientAudio()
        // Restore durable pending-off before didSet wiring via direct assign after load
        if let last = AppPreferences.lastStrength(defaults: defaults) {
            strength = last
        }
        recentSessions = SessionHistory.load(defaults: defaults)
        // Load without re-writing (set after property exists)
        // Note: pendingDeactivate didSet will re-persist same value — fine.
        pendingDeactivate = AppPreferences.pendingDeactivate(defaults: defaults)
        customChannelCommand = AppPreferences.customChannel(defaults: defaults)
        debugActiveChannel = customChannelCommand == "0" ? "0" : customChannelCommand
        mindfulMinutesEnabled = AppPreferences.mindfulMinutesEnabled(defaults: defaults)
        sessionEndAlertsEnabled = AppPreferences.sessionEndAlertsEnabled(defaults: defaults)
        sessionRemindersEnabled = AppPreferences.sessionRemindersEnabled(defaults: defaults)
        ambientMusicEnabled = AppPreferences.ambientMusicEnabled(defaults: defaults)
        // Off → resolved (no schedule). On → wait for fetch before any schedule.
        sessionEndAlertsAuthResolved = !sessionEndAlertsEnabled
        // Cold launch: hydrate denied before BG schedule (async on device)
        if sessionEndAlertsEnabled {
            refreshSessionEndAlertAuthorization()
        }
        // Rebuild quiet reminders if still opted in (idempotent)
        if sessionRemindersEnabled {
            SessionReminderScheduler.reschedule(
                enabled: true,
                morningHour: AppPreferences.sessionReminderMorningHour(defaults: defaults),
                eveningHour: AppPreferences.sessionReminderEveningHour(defaults: defaults)
            )
        }
        // Callback is already @MainActor (DeviceState) — no extra Task hop
        ble.onDisconnect = { [weak self] in
            self?.handleDisconnect()
        }

        // Use BLE notifications as a trigger to send keepalive + schedule next query.
        // This works in background because iOS delivers BLE notifications to bluetooth-central apps.
        ble.onNotification = { [weak self] in
            self?.handleBLENotification()
        }

        ble.onWriteFailed = { [weak self] cmd in
            guard let self else { return }
            guard SessionSafety.isDeactivateCommand(cmd) else { return }
            if self.isRunning {
                // Mid-session duty-cycle off failed — absolute reassert when ready
                if self.ble.isReady {
                    self.reassertDeviceStateAfterFailedOff()
                }
                // If link is down, ready sink always calls resumeSessionOnDevice()
            } else {
                // Idle/paused safety off failed — keep durable pending + retry
                self.pendingDeactivate = true
                if self.ble.isReady {
                    self.flushPendingDeactivateIfNeeded()
                }
            }
        }

        ble.onWriteSucceeded = { [weak self] cmd in
            guard let self else { return }
            // Confirmed off while idle — clear sticky pending even if status Q/u still queued
            guard SessionSafety.shouldClearPendingDeactivate(
                command: cmd,
                isRunning: self.isRunning,
                hasPendingProgramWrites: self.ble.hasPendingProgramWrites
            ) else { return }
            let wasPending = self.pendingDeactivate
            self.pendingDeactivate = false
            if wasPending, !self.isRunning {
                // Success haptic only for idle/paused HW off — not start/resume lead-0
                self.deviceOffConfirmedToken &+= 1
            }
            // Battery/charge after safety off ACK (not interleaved with off)
            if wasPending, self.ble.isReady {
                self.queryStatus()
            }
            // Refresh Island/lock screen while paused (no timer ticks to push LA)
            if wasPending, self.isRunning || self.isPaused {
                self.pushLiveActivity()
            }
            // Completed LA linger: clear "turning device off" after HW off ACK
            if wasPending, !self.isRunning, !self.isPaused {
                self.liveActivity.noteHardwareOffConfirmed()
            }
        }

        // Nested ObservableObject — forward synchronously (already MainActor)
        ble.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
                self?.considerEmptyBatteryPause()
            }
            .store(in: &cancellables)

        // Battery sample / charge changes (published) — mid-session empty safety
        ble.$batteryPercentage
            .combineLatest(ble.$batterySampleConfirmed, ble.$isCharging)
            .sink { [weak self] _, _, _ in
                self?.considerEmptyBatteryPause()
            }
            .store(in: &cancellables)

        // Restart keepalive/poll when connection comes back
        ble.$isReady
            .removeDuplicates()
            .sink { [weak self] ready in
                guard let self, self.acceptsLinkReady else { return }
                self.handleLinkReady(ready)
            }
            .store(in: &cancellables)

        // Already ready at init (mocks) — seed grace clock. Do not clear disk yet.
        if ble.isReady {
            linkReadyAt = now()
            scheduleBatteryGraceRefresh()
        }

        restoreSessionIfNeeded()
        acceptsLinkReady = true
        // The subscribe event ran before restore and was ignored.
        // Running + ready already programmed inside restore. Do not program again.
        if ble.isReady {
            if isRunning {
                settleReadyAfterRestore()
            } else {
                handleLinkReady(true)
            }
        }
        // Cold launch: durable HW-off may outlive session clear — arm retry when ready
        if PendingOffPolicy.shouldFlushOnReady(
            pendingDeactivate: pendingDeactivate,
            isLinkReady: ble.isReady,
            isRunning: isRunning
        ) {
            flushPendingDeactivateIfNeeded()
            startPendingOffRetryLoop()
        } else if pendingDeactivate {
            startPendingOffRetryLoop()
        }
    }

    /// Link was already ready when restore programmed a running session.
    /// Clear a short offline clock. Do not send a second program.
    private func settleReadyAfterRestore() {
        offlineAutoPauseTask?.cancel()
        offlineAutoPauseTask = nil
        let action = SessionLinkSafety.readyAfterDrop(
            isRunning: isRunning,
            offlineSince: offlineSince,
            now: now()
        )
        if case .pause(let freeze) = action {
            applyOfflineFreezePause(freeze: freeze, linkReady: true)
        } else {
            setOfflineSince(nil)
        }
        if linkReadyAt == nil {
            linkReadyAt = now()
            scheduleBatteryGraceRefresh()
        }
        startStatusPoll()
    }

    /// `@Published` emits in willSet, so `ble.isReady` is still the previous value here.
    /// Use `ready`. The first event is ignored until restore has read the offline clock.
    private func handleLinkReady(_ ready: Bool) {
        if ready {
            let action = SessionLinkSafety.readyAfterDrop(
                isRunning: isRunning,
                offlineSince: offlineSince,
                now: now()
            )
            offlineAutoPauseTask?.cancel()
            offlineAutoPauseTask = nil
            if case .pause(let freeze) = action {
                applyOfflineFreezePause(freeze: freeze, linkReady: true)
            } else {
                setOfflineSince(nil)
            }
            if linkReadyAt == nil {
                linkReadyAt = now()
                scheduleBatteryGraceRefresh()
            }
            startStatusPoll()
            if isRunning {
                // Wall-expire BEFORE reprogram — avoids zombie stim after
                // suspend past endsAt (Session.tla InvNoStimWhenExpired)
                recalculateFromWallClock(
                    absoluteIfJumped: false,
                    advanceEngine: false,
                    linkReady: true
                )
                guard isRunning else {
                    flushPendingDeactivateIfNeeded(linkReady: true)
                    return
                }
                resumeSessionOnDevice(linkReady: true)
            } else {
                flushPendingDeactivateIfNeeded(linkReady: true)
                startPendingOffRetryLoop()
            }
        } else {
            linkReadyAt = nil
            batteryGraceRefreshTask?.cancel()
            batteryGraceRefreshTask = nil
            if isRunning {
                if offlineSince == nil {
                    setOfflineSince(now())
                    scheduleOfflineAutoPause()
                    pendingDeactivate = true
                }
                noteLinkLostWhileRunning()
            }
        }
    }

    /// After unknown/unconfirmed-battery grace, refresh Start UI (canStart may flip true).
    private func scheduleBatteryGraceRefresh() {
        batteryGraceRefreshTask?.cancel()
        let grace = BatteryPresentation.unknownGraceSeconds
        batteryGraceRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(grace + 0.05))
            guard let self, !Task.isCancelled else { return }
            guard self.ble.isReady else { return }
            // Still blocked only if sample never confirmed (or still nil empty path)
            guard !self.ble.batterySampleConfirmed || self.ble.batteryPercentage == nil else { return }
            self.objectWillChange.send()
        }
    }

    /// After long mid-run offline, auto-pause so late reconnect never surprise-stim.
    /// Sleeps only the *remaining* delay (process restore must not re-wait full 90s).
    private func scheduleOfflineAutoPause() {
        offlineAutoPauseTask?.cancel()
        let secondsOffline = offlineSince.map { now().timeIntervalSince($0) }
        let delay = SessionLinkSafety.remainingAutoPauseDelay(secondsOffline: secondsOffline)
        offlineAutoPauseTask = Task { @MainActor [weak self] in
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay + 0.05))
            }
            guard let self, !Task.isCancelled else { return }
            self.considerOfflineAutoPause()
        }
    }

    /// Pure + clock: pause running session after offline threshold (testable).
    func considerOfflineAutoPause() {
        let seconds: TimeInterval? = offlineSince.map { now().timeIntervalSince($0) }
        guard SessionLinkSafety.shouldAutoPause(
            isRunning: isRunning,
            isLinkReady: ble.isReady,
            secondsOffline: seconds
        ) else { return }
        guard let offlineSince else { return }
        let freeze = SessionLinkSafety.autoPauseFreezeDate(offlineSince: offlineSince)
        offlineAutoPauseTask?.cancel()
        offlineAutoPauseTask = nil
        applyOfflineFreezePause(freeze: freeze, linkReady: false)
    }

    /// Long drop meets a live link, or the auto-pause timer wakes late.
    /// Pause at the freeze instant. Practice stops at the threshold.
    private func applyOfflineFreezePause(freeze: Date, linkReady: Bool) {
        if let start = sessionStartDate {
            let active = freeze.timeIntervalSince(start) - accumulatedPauseTime
            let elapsedSeconds = max(0, Int(active))
            let rem = sessionTotalDuration - elapsedSeconds
            if rem <= 0 {
                setOfflineSince(nil)
                stop(reason: .completed)
                return
            }
            remainingSeconds = rem
        }
        pause(linkReady: linkReady)
        pauseStartDate = freeze
        persistSession()
        pushLiveActivity()
    }

    /// Confirmed empty pack mid-session → pause + durable off (comfort/safety).
    func considerEmptyBatteryPause() {
        guard SessionSafety.shouldPauseForEmptyBattery(
            isRunning: isRunning,
            batteryPercent: ble.batteryPercentage,
            isCharging: ble.isCharging,
            sampleConfirmed: ble.batterySampleConfirmed
        ) else { return }
        pause()
    }

    /// Wipe local session log (privacy-first; never cloud).
    func clearSessionHistory() {
        SessionHistory.clear(defaults: defaults)
        recentSessions = []
    }

    // MARK: - Mode Selection

    func selectMode(_ mode: StimulationMode) {
        guard !isRunning, !isPaused else { return }
        selectedMode = mode
        selectedFeeling = nil
        timerMinutes = mode.defaultDurationMinutes
        // Keep user's last comfortable intensity (official app parity); fall back to mode default.
        strength = AppPreferences.lastStrength(defaults: defaults) ?? mode.defaultStrength
        // Reset advanced options when switching primary modes (unless landing on same family)
        if !mode.usesBreathingGuide {
            breathePace = .calm
        }
        if mode != .painRelief && mode != .headache {
            easePattern = .wave
        }
    }

    func selectFeeling(_ state: AutonomicState) {
        guard !isRunning, !isPaused else { return }
        selectMode(state.primaryMode)
        selectedFeeling = state
        breathePace = state == .scattered ? .meditate : .calm
        easePattern = state == .headachy ? .burst : .wave
        if state == .learning || state == .scattered {
            timerMinutes = 10
        }
    }

    /// Map legacy raw modes onto Still primary + pace/pattern.
    /// - Returns: true if mode/feeling/options changed (caller should re-persist).
    @discardableResult
    private func normalizeLegacyModeOptions() -> Bool {
        let beforeMode = selectedMode
        let beforeFeeling = selectedFeeling
        let beforePace = breathePace
        let beforePattern = easePattern

        switch selectedMode {
        case .learn:
            selectedMode = .focus
            if selectedFeeling == nil { selectedFeeling = .foggy }
        case .nausea:
            selectedMode = .stressRelief
            if selectedFeeling == nil { selectedFeeling = .stressed }
        case .meditation:
            selectedMode = .calm
            breathePace = .meditate
            if selectedFeeling == nil { selectedFeeling = .anxious }
        case .headache:
            selectedMode = .painRelief
            easePattern = .burst
            if selectedFeeling == nil { selectedFeeling = .hurting }
        default:
            break
        }
        // Feeling-driven options when feeling present
        if let feeling = selectedFeeling {
            switch feeling {
            case .scattered: breathePace = .meditate
            case .headachy: easePattern = .burst
            case .anxious: if breathePace != .meditate { breathePace = .calm }
            case .hurting: if easePattern != .burst { easePattern = .wave }
            default: break
            }
            // Title honesty: drop feeling when it disagrees with engine mode
            if feeling.primaryMode != selectedMode {
                selectedFeeling = nil
            }
        }
        return beforeMode != selectedMode
            || beforeFeeling != selectedFeeling
            || beforePace != breathePace
            || beforePattern != easePattern
    }

    /// Engine for current mode + Breathe/Ease options.
    func resolveEngine() -> ModeEngine? {
        selectedMode.makeEngine(breathePace: breathePace, easePattern: easePattern)
    }

    /// Local minutes logged today (Still “minutes today” line).
    var minutesToday: Int {
        let cal = Calendar.current
        let secs = recentSessions
            .filter { cal.isDateInToday($0.endedAt) }
            .reduce(0) { $0 + max(0, $1.durationSeconds) }
        return secs / 60
    }

    /// Display title — always engine mode (honesty after restore/normalize).
    var sessionTitle: String {
        selectedMode.name
    }

    // MARK: - Actions

    func start() {
        guard canStart else { return }

        armRunningClock()
        resetCustomSoftWindow()
        beginMindfulWindow()

        bindSessionEngine()
        if engine == nil {
            programCustomStart()
        } else {
            programEngineStart()
        }

        endNotifier.cancel()
        startCountdown()
        startKeepalive()
        persistSession()
        pushLiveActivity(start: true)
        syncAmbientAudio()
    }

    /// One clock for the run (`now`), including tests.
    private func armRunningClock() {
        isRunning = true
        sessionTotalDuration = min(timerMinutes, BLEConstants.maxSessionMinutes) * 60
        remainingSeconds = sessionTotalDuration
        UIApplication.shared.isIdleTimerDisabled = true
        sessionStartDate = now()
        sessionWallStart = sessionStartDate
        accumulatedPauseTime = 0
        pauseStartDate = nil
        backgroundEntryDate = nil
        lastTickElapsed = nil
    }

    /// Custom eases in on first start when strength warrants. Other modes stay settled.
    private func resetCustomSoftWindow() {
        customSoftOnNextResume = selectedMode == .custom && SoftStart.isNeeded(target: strength)
        customSoftBeginElapsed = nil
    }

    private func beginMindfulWindow() {
        mindfulSegments = []
        mindfulSegmentStart = sessionStartDate
    }

    /// Sleep phase anchor before any ±time. Comfort seed comes from the program, not a prior run.
    private func bindSessionEngine() {
        engine = resolveEngine()
        defaults.removeObject(forKey: PersistKey.phaseLengthSeconds)
        defaults.removeObject(forKey: PersistKey.lastComfortStrength)
        defaults.removeObject(forKey: PersistKey.userStrengthFloor)
        persistPhaseScheduleIfNeeded()
    }

    private func programEngineStart() {
        guard var engine else { return }
        let commands = engine.start(baseStrength: strength, totalDuration: sessionTotalDuration)
        self.engine = engine
        sendStartProgram(commands)
        processTick()
        applyEngineStartFallback()
    }

    /// Pure off is not a start. Bilateral is the intentional custom channel.
    private func programCustomStart() {
        if customChannelCommand == "0" {
            customChannelCommand = "D"
        }
        sendStartProgram(customReconnectCommands())
        applyCustomChannelFlagsFromCommand()
        debugActiveChannel = customChannelCommand
        applyCustomStartStatus()
    }

    /// Pending off stays set until the lead-0 write succeeds.
    private func sendStartProgram(_ commands: [String]) {
        if ble.isReady {
            ble.cancelProgramWrites()
        }
        sendSessionCommands(commandsWithLeadingOff(commands))
    }

    /// Lead with absolute off unless the program already starts off.
    private func commandsWithLeadingOff(_ commands: [String]) -> [String] {
        var commands = commands
        if !commands.contains(BLEConstants.deactivateCommand),
           !commands.contains(where: { $0.hasPrefix("0") }) {
            commands.insert(BLEConstants.deactivateCommand, at: 0)
        }
        return commands
    }

    /// Breath modes with no phase yet start on inhale, stim off.
    /// An empty engine tick still shows channel and ease-in.
    private func applyEngineStartFallback() {
        if selectedMode.usesBreathingGuide {
            guard breathingPhase == nil else { return }
            stimulationActive = false
            activeChannel = .off
            breathingPhase = .inhale(progress: 0)
            modeStatus = "Inhale"
            return
        }
        guard modeStatus.isEmpty || modeStatus == "Starting" else { return }
        if selectedMode == .focus || selectedMode == .learn {
            stimulationActive = true
            activeChannel = .left
            modeStatus = SoftStart.isNeeded(target: strength) ? "Left channel · Easing in" : "Starting"
            return
        }
        stimulationActive = true
        activeChannel = .bilateral
        if SoftStart.isNeeded(target: strength) {
            modeStatus = "Bilateral · Easing in"
            effectiveStrength = SoftStart.initialStrength(target: strength)
        } else {
            modeStatus = "Starting"
        }
    }

    private func applyCustomStartStatus() {
        if SoftStart.isNeeded(target: strength), customSoftBeginElapsed != nil {
            modeStatus = "Custom · Easing in"
            effectiveStrength = SoftStart.initialStrength(target: strength)
        } else {
            modeStatus = "Custom · \(customChannelCommand == "0" ? "Off" : "Manual")"
        }
    }

    /// One status path for app UI + Live Activity (pending / offline / phase).
    var sessionStatusText: String {
        LiveActivityPresentation.statusLine(
            isPaused: isPaused,
            isRunning: isRunning,
            pendingDeviceOff: pendingDeactivate,
            modeStatus: modeStatus,
            modeName: selectedMode.name,
            isLinkReady: ble.isReady
        )
    }



    private func pushLiveActivity(start: Bool = false, isLinkReady: Bool? = nil) {
        let status = sessionStatusText
        // Optional override: ready-false sink may race; callers can force link honesty
        let linkReady = isLinkReady ?? ble.isReady
        if start {
            liveActivity.start(
                mode: selectedMode,
                totalSeconds: sessionTotalDuration,
                remainingSeconds: remainingSeconds,
                statusText: status,
                stimulationActive: stimulationActive,
                pendingDeviceOff: pendingDeactivate,
                isPaused: isPaused,
                isLinkReady: linkReady
            )
        } else {
            liveActivity.update(
                remainingSeconds: remainingSeconds,
                totalSeconds: sessionTotalDuration,
                isPaused: isPaused,
                statusText: status,
                stimulationActive: stimulationActive,
                pendingDeviceOff: pendingDeactivate,
                isLinkReady: linkReady
            )
        }
    }

    enum StopReason: Equatable {
        case user
        case completed
    }

    /// Facts captured before stop clears the run. Island copy must not see the re-armed off flag.
    private struct StopSnapshot {
        let reason: StopReason
        let mode: StimulationMode
        let strength: Int
        let planned: Int
        let elapsedActive: Int
        let liveActivityPendingOff: Bool
        let historicalEnd: Date?
    }

    func stop(reason: StopReason = .user) {
        guard isRunning || isPaused else { return }

        let end = stopSnapshot(reason: reason)
        retireActiveRun()
        closeMindfulForStop(end)

        clearSessionClocks()
        clearStimulationState()
        stopRunLoops(reason: reason)
        clearPersistedSession()

        requestDeviceOff(andQueryStatus: false)
        endLiveActivity(end)
        ambientAudio.stop(fade: true)

        recordSessionHistory(end)
        saveMindfulForStop(end)
        clearMindfulWindow()
        if end.reason == .completed {
            completionBanner = "Session complete · \(end.mode.name)"
        }
    }

    private func stopSnapshot(reason: StopReason) -> StopSnapshot {
        let planned = sessionTotalDuration
        let start = sessionStartDate
        let pause = accumulatedPauseTime
        return StopSnapshot(
            reason: reason,
            mode: selectedMode,
            strength: strength,
            planned: planned,
            elapsedActive: max(0, planned - remainingSeconds),
            liveActivityPendingOff: isRunning || pendingDeactivate,
            historicalEnd: start.map {
                $0.addingTimeInterval(TimeInterval(planned) + pause)
            }
        )
    }

    private func retireActiveRun() {
        isRunning = false
        isPaused = false
        remainingSeconds = 0
        sessionTotalDuration = 0
        UIApplication.shared.isIdleTimerDisabled = false
        isInBackground = false
        endBackgroundTaskIfNeeded()
        backgroundWatchTask?.cancel()
        backgroundWatchTask = nil
        backgroundPingTask?.cancel()
        backgroundPingTask = nil
    }

    /// Completed practice ends at the planned instant, not at a late stop.
    private func closeMindfulForStop(_ end: StopSnapshot) {
        if end.reason == .completed, let hist = end.historicalEnd {
            closeMindfulSegment(at: min(Date(), hist))
        } else {
            closeMindfulSegment()
        }
    }

    private func clearSessionClocks() {
        sessionStartDate = nil
        accumulatedPauseTime = 0
        pauseStartDate = nil
        backgroundEntryDate = nil
        lastTickElapsed = nil
    }

    private func clearStimulationState() {
        customSoftOnNextResume = false
        customSoftBeginElapsed = nil
        engine = nil
        stimulationActive = false
        effectiveStrength = nil
        breathingPhase = nil
        activeChannel = .off
        debugActiveChannel = ""
        modeStatus = ""
    }

    /// A completed stop keeps the end alert. A user stop cancels it.
    private func stopRunLoops(reason: StopReason) {
        stopCountdown()
        stopKeepalive()
        if reason != .completed {
            endNotifier.cancel()
        }
    }

    private func endLiveActivity(_ end: StopSnapshot) {
        liveActivity.end(
            reason: end.reason == .completed ? .completed : .user,
            modeName: end.mode.name,
            pendingDeviceOff: end.liveActivityPendingOff
        )
    }

    private func recordSessionHistory(_ end: StopSnapshot) {
        AppPreferences.saveLastStrength(end.strength, defaults: defaults)
        guard end.planned > 0 else { return }
        let loggedDuration = end.reason == .completed ? end.planned : end.elapsedActive
        SessionHistory.append(
            mode: end.mode,
            durationSeconds: loggedDuration,
            strength: end.strength,
            completed: end.reason == .completed,
            breathePace: breathePace,
            easePattern: easePattern,
            defaults: defaults
        )
        recentSessions = SessionHistory.load(defaults: defaults)
    }

    private func saveMindfulForStop(_ end: StopSnapshot) {
        guard end.reason == .completed || end.elapsedActive >= 60 else { return }
        let mindfulEnd = (end.reason == .completed ? end.historicalEnd : nil) ?? Date()
        let duration = end.reason == .completed ? end.planned : end.elapsedActive
        saveMindfulMinutesIfEnabled(
            mode: end.mode,
            durationSeconds: duration,
            end: min(Date(), mindfulEnd)
        )
    }

    private func clearMindfulWindow() {
        sessionWallStart = nil
        mindfulSegments = []
        mindfulSegmentStart = nil
    }

    /// Island / Siri Stop while idle — re-assert durable HW off (no active session).
    func requestHardwareOffIfIdle() {
        guard !isRunning, !isPaused else { return }
        requestDeviceOff(andQueryStatus: false)
    }

    func clearCompletionBanner() {
        completionBanner = nil
    }

    /// Enable/disable HealthKit Mindful Minutes writes (prompts system auth when turning on).
    func setMindfulMinutesEnabled(_ enabled: Bool) {
        mindfulMinutesEnabled = enabled
        AppPreferences.setMindfulMinutesEnabled(enabled, defaults: defaults)
        guard enabled else { return }
        Task {
            try? await mindfulStore.requestAuthorization()
        }
    }

    /// Opt-in local alert when a session ends while backgrounded (no network).
    func setSessionEndAlertsEnabled(_ enabled: Bool) {
        sessionEndAlertsEnabled = enabled
        AppPreferences.setSessionEndAlertsEnabled(enabled, defaults: defaults)
        if enabled {
            // Block schedule until auth callback (denied race)
            sessionEndAlertsAuthResolved = false
            endNotifier.requestAuthorizationIfNeeded { [weak self] granted in
                guard let self else { return }
                self.sessionEndAlertsDenied = !granted
                self.sessionEndAlertsAuthResolved = true
                if granted, self.isInBackground {
                    self.scheduleSessionEndAlertIfNeeded()
                }
            }
        } else {
            sessionEndAlertsDenied = false
            sessionEndAlertsAuthResolved = true
            endNotifier.cancel()
        }
    }

    /// Opt-in bundled ambient pad during sessions (local only — no streaming).
    func setAmbientMusicEnabled(_ enabled: Bool) {
        ambientMusicEnabled = enabled
        AppPreferences.setAmbientMusicEnabled(enabled, defaults: defaults)
        syncAmbientAudio()
    }

    /// Keep optional ambience in sync with session / scene (never required for stim).
    private func syncAmbientAudio() {
        ambientAudio.sync(
            enabled: ambientMusicEnabled,
            isRunning: isRunning,
            isPaused: isPaused,
            isInBackground: isInBackground
        )
    }

    /// Opt-in local morning/evening “when ready” reminders (no guilt, no tracking).
    func setSessionRemindersEnabled(_ enabled: Bool) {
        sessionRemindersEnabled = enabled
        AppPreferences.setSessionRemindersEnabled(enabled, defaults: defaults)
        let morning = AppPreferences.sessionReminderMorningHour(defaults: defaults)
        let evening = AppPreferences.sessionReminderEveningHour(defaults: defaults)
        if enabled {
            endNotifier.requestAuthorizationIfNeeded { [weak self] granted in
                guard let self else { return }
                if granted {
                    SessionReminderScheduler.reschedule(
                        enabled: true,
                        morningHour: morning,
                        eveningHour: evening
                    )
                } else {
                    self.sessionRemindersEnabled = false
                    AppPreferences.setSessionRemindersEnabled(false, defaults: self.defaults)
                    SessionReminderScheduler.reschedule(enabled: false, morningHour: morning, eveningHour: evening)
                }
            }
        } else {
            SessionReminderScheduler.reschedule(enabled: false, morningHour: morning, eveningHour: evening)
        }
    }

    /// Refresh system notification permission (settings sheet onAppear).
    func refreshSessionEndAlertAuthorization() {
        guard sessionEndAlertsEnabled else {
            sessionEndAlertsDenied = false
            sessionEndAlertsAuthResolved = true
            return
        }
        endNotifier.fetchCanDeliver { [weak self] canDeliver in
            guard let self else { return }
            self.sessionEndAlertsDenied = !canDeliver
            self.sessionEndAlertsAuthResolved = true
            // Cold BG restore may have deferred schedule until auth resolved
            if canDeliver, self.isInBackground, self.isRunning, !self.isPaused {
                self.scheduleSessionEndAlertIfNeeded()
            }
        }
    }

    private func scheduleSessionEndAlertIfNeeded() {
        guard sessionEndAlertsEnabled, isRunning, !isPaused else {
            endNotifier.cancel()
            return
        }
        // Wait for auth hydrate — never schedule with stale denied=false
        guard sessionEndAlertsAuthResolved else {
            endNotifier.cancel()
            return
        }
        // Honesty: do not schedule when system already denied (iOS would drop silently)
        guard !sessionEndAlertsDenied else {
            endNotifier.cancel()
            return
        }
        guard let start = sessionStartDate, sessionTotalDuration > 0 else {
            endNotifier.cancel()
            return
        }
        // Wall endsAt = start + total + accumulated pauses (pause not active while running)
        let endsAt = start.addingTimeInterval(TimeInterval(sessionTotalDuration) + accumulatedPauseTime)
        endNotifier.schedule(
            endsAt: endsAt,
            modeName: selectedMode.name,
            enabled: true,
            now: Date()
        )
    }

    private func openMindfulSegment(at date: Date = Date()) {
        if mindfulSegmentStart == nil {
            mindfulSegmentStart = date
            // Persist open segment for crash recovery
            if isRunning || isPaused {
                defaults.set(date.timeIntervalSince1970, forKey: PersistKey.mindfulSegmentStart)
            }
        }
    }

    private func closeMindfulSegment(at date: Date = Date()) {
        guard let start = mindfulSegmentStart else { return }
        if date > start {
            mindfulSegments.append((start: start, end: date))
        }
        mindfulSegmentStart = nil
        if isRunning || isPaused {
            // Keep closed segments durable until session ends
            let segs: [[Double]] = mindfulSegments.map {
                [$0.start.timeIntervalSince1970, $0.end.timeIntervalSince1970]
            }
            if let data = try? JSONEncoder().encode(segs) {
                defaults.set(data, forKey: PersistKey.mindfulSegments)
            }
            defaults.removeObject(forKey: PersistKey.mindfulSegmentStart)
        }
    }

    /// Multi-segment Health samples when available; else end-anchored active duration.
    private func saveMindfulMinutesIfEnabled(mode: StimulationMode, durationSeconds: Int, end: Date = Date()) {
        guard mindfulMinutesEnabled else { return }
        guard mode.usesBreathingGuide || mode == .meditation || mode == .calm else { return }

        let ranges = MindfulSessionRange.resolve(
            segments: mindfulSegments,
            activeSeconds: durationSeconds,
            end: end
        )
        guard !ranges.isEmpty else { return }
        Task {
            for range in ranges {
                try? await mindfulStore.saveSession(start: range.start, end: range.end)
            }
        }
    }

    func pause(linkReady: Bool? = nil) {
        guard isRunning else { return }
        isPaused = true
        isRunning = false
        // Offline auto-pause (or user pause) ends the reconnect-running window
        setOfflineSince(nil)
        offlineAutoPauseTask?.cancel()
        offlineAutoPauseTask = nil

        // Close mindful segment so pause wall-time is not claimed as practice
        closeMindfulSegment()

        // Duty engines: next on soft-starts after pause (comfort)
        if var engine {
            engine.notePaused()
            self.engine = engine
        } else {
            // Custom has no engine — soft strength on next resume
            customSoftOnNextResume = true
        }

        // Record pause start for wall-clock tracking
        pauseStartDate = now()

        stopCountdown()
        stopKeepalive()
        // Pause is not complete — cancel end alert so LA pause can't fire false "Session complete"
        endNotifier.cancel()
        // Allow screen sleep while paused (important for sleep sessions)
        UIApplication.shared.isIdleTimerDisabled = false

        // Deactivate device only when fully ready; else pending for next ready
        requestDeviceOff(andQueryStatus: false, linkReady: linkReady)

        // Clear mode transient state but keep engine
        stimulationActive = false
        effectiveStrength = nil
        breathingPhase = nil
        activeChannel = .off
        modeStatus = "Paused"
        persistSession()
        pushLiveActivity()
        syncAmbientAudio()
    }

    /// Resume requires a ready BLE link so we can reprogram the device (SessionBLE).
    var canResume: Bool {
        isPaused && ble.isReady
    }

    func resume() {
        guard isPaused else { return }
        // Without ready link, stay paused and wait for reconnect sink to re-arm.
        guard ble.isReady else { return }
        isPaused = false
        isRunning = true
        // Do not clear pendingDeactivate here — lead-0 ACK clears durable off

        // Accumulate paused duration
        if let pauseStart = pauseStartDate {
            accumulatedPauseTime += now().timeIntervalSince(pauseStart)
            pauseStartDate = nil
        }

        // Wall-clock only — absolute program path below (no double edge)
        recalculateFromWallClock(absoluteIfJumped: false, advanceEngine: false)
        // stop() may have been called if expired
        guard isRunning else { return }

        // New mindful segment after resume (pause gap excluded)
        openMindfulSegment()

        // Same absolute path as foreground/ready (lead 0 + soft-after-pause)
        resumeSessionOnDevice()

        startCountdown()
        startKeepalive()
        UIApplication.shared.isIdleTimerDisabled = true
        persistSession()
        pushLiveActivity()
        syncAmbientAudio()
        // LA pause/resume may skip scene phase — re-arm end alert if still backgrounded
        if isInBackground {
            scheduleSessionEndAlertIfNeeded()
        }
    }

    private func applyCustomChannelFlagsFromCommand() {
        if customChannelCommand == "0" {
            stimulationActive = false
            activeChannel = .off
            return
        }
        stimulationActive = true
        switch customChannelCommand {
        case "A": activeChannel = .left
        case "C": activeChannel = .right
        default: activeChannel = .bilateral
        }
    }

    /// Send deactivate if a prior stop/pause/expire happened while offline / not ready.
    /// Idempotent off send while pending. Durable flag clears only on confirmed write success
    /// (when idle/paused) or Start/Resume reprogram.
    func flushPendingDeactivateIfNeeded(linkReady: Bool? = nil) {
        let ready = linkReady ?? ble.isReady
        guard pendingDeactivate, ready else { return }
        ble.sendCommand(BLEConstants.deactivateCommand)
    }

    /// Retry off every few seconds while idle/paused + ready + pending.
    private func startPendingOffRetryLoop() {
        pendingOffRetryTask?.cancel()
        guard pendingDeactivate else { return }
        pendingOffRetryTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.pendingDeactivate else { return }
                // Never spam off during an active session (duty-cycle uses absolute reassert)
                if !self.isRunning, self.ble.isReady {
                    self.flushPendingDeactivateIfNeeded()
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func stopPendingOffRetryLoop() {
        pendingOffRetryTask?.cancel()
        pendingOffRetryTask = nil
    }

    /// After a failed off while session still running, re-program absolute phase (not edge-only).
    private func reassertDeviceStateAfterFailedOff() {
        // Single reprogram path — same as reconnect resume
        resumeSessionOnDevice()
    }

    /// Prefer ready link for off command; otherwise queue pending off.
    /// Always leaves pending true so process death after send still re-offs on next ready.
    private func requestDeviceOff(andQueryStatus: Bool, linkReady: Bool? = nil) {
        pendingDeactivate = true
        let ready = linkReady ?? ble.isReady
        if ready {
            // Drop queued channel/strength so they cannot re-enable after off
            ble.cancelProgramWrites()
            ble.sendCommand(BLEConstants.deactivateCommand)
            if andQueryStatus { queryStatus() }
        }
    }

    @Published var debugActiveChannel: String = ""
    /// Last custom channel command ("A","B","C","D","0") for reconnect + process kill.
    private(set) var customChannelCommand: String = "D" {
        didSet {
            AppPreferences.saveCustomChannel(customChannelCommand, defaults: defaults)
        }
    }

    func sendDebugCommand(_ cmd: String) {
        // Only while running with a ready link — never flip UI off without a real write path
        guard isRunning, ble.isReady else { return }
        ble.sendCommand(cmd + "\n")
        debugActiveChannel = cmd
        switch cmd {
        case "0":
            stimulationActive = false
            activeChannel = .off
            customChannelCommand = "0"
            debugActiveChannel = "0"
        case "A":
            stimulationActive = true
            activeChannel = .left
            customChannelCommand = "A"
            ble.sendCommand(BLEConstants.strengthCommand(strength))
        case "C":
            stimulationActive = true
            activeChannel = .right
            customChannelCommand = "C"
            ble.sendCommand(BLEConstants.strengthCommand(strength))
        case "B", "D":
            stimulationActive = true
            activeChannel = .bilateral
            customChannelCommand = cmd
            ble.sendCommand(BLEConstants.strengthCommand(strength))
        default:
            if cmd != "0" {
                ble.sendCommand(BLEConstants.strengthCommand(strength))
            }
        }
    }

    /// Reprogram custom channel after pause/reconnect. OFF stays off; otherwise restore last channel.
    /// After user pause: soft-start. Mid soft: continue ladder (no full-strength spike).
    /// Settled mid-session: absolute full strength.
    private func customReconnectCommands() -> [String] {
        if customChannelCommand == "0" {
            customSoftOnNextResume = false
            customSoftBeginElapsed = nil
            return [BLEConstants.deactivateCommand]
        }
        let channel = customChannelCommand.isEmpty ? "D" : customChannelCommand
        if customSoftOnNextResume {
            customSoftOnNextResume = false
            customSoftBeginElapsed = elapsed
            let initial = SoftStart.initialStrength(target: strength)
            return [channel + "\n", BLEConstants.strengthCommand(initial)]
        }
        // Continue soft ladder across reconnect / absolute reassert (R51 comfort)
        if let begin = customSoftBeginElapsed {
            let local = max(0, elapsed - begin)
            if SoftStart.isComplete(elapsed: local, target: strength) {
                clearCustomSoftBegin(durable: true)
                effectiveStrength = nil
                return [channel + "\n", BLEConstants.strengthCommand(strength)]
            }
            let step = SoftStart.strength(atElapsed: local, target: strength)
            effectiveStrength = step
            return [channel + "\n", BLEConstants.strengthCommand(step)]
        }
        return [channel + "\n", BLEConstants.strengthCommand(strength)]
    }

    /// Clear Custom soft window in memory and (when durable) defaults — avoid kill undercut after raise.
    private func clearCustomSoftBegin(durable: Bool) {
        customSoftBeginElapsed = nil
        guard durable else { return }
        defaults.removeObject(forKey: PersistKey.customSoftBeginElapsed)
    }

    /// Live Activity / Island fired endsAt — wall-expire only; never stop early.
    func honorLiveActivitySessionEnd() {
        guard isRunning || isPaused else { return }
        if isRunning {
            recalculateFromWallClock(absoluteIfJumped: false, advanceEngine: false)
            // stop(.completed) already ran if wall past
            return
        }
        // Paused: complete only if wall clock past planned end (inject `now` for tests).
        // Unstamped pause (pauseStart nil) cannot prove wall past — match unbound refuse.
        if pauseStartDate == nil {
            return
        }
        if LiveActivityEndPolicy.shouldCompleteSession(
            now: now(),
            start: sessionStartDate,
            totalDurationSeconds: sessionTotalDuration,
            accumulatedPause: accumulatedPauseTime,
            pauseStart: pauseStartDate,
            isPaused: true
        ) {
            stop(reason: .completed)
        }
    }

    /// Rehydrate Custom soft window after process kill if still within ease-in.
    private func restoreCustomSoftBeginIfNeeded(defaults d: UserDefaults) {
        guard selectedMode == .custom else {
            customSoftBeginElapsed = nil
            return
        }
        guard d.object(forKey: PersistKey.customSoftBeginElapsed) != nil else {
            customSoftBeginElapsed = nil
            return
        }
        let begin = d.integer(forKey: PersistKey.customSoftBeginElapsed)
        guard SoftStart.isNeeded(target: strength) else {
            customSoftBeginElapsed = nil
            return
        }
        let local = max(0, elapsed - begin)
        if SoftStart.isComplete(elapsed: local, target: strength) {
            customSoftBeginElapsed = nil
        } else {
            customSoftBeginElapsed = begin
        }
    }

    func increaseTimer() {
        if isRunning || isPaused {
            adjustRemainingTime(by: 60)
        } else {
            guard timerMinutes < BLEConstants.maxSessionMinutes else { return }
            timerMinutes += 1
        }
        if isInBackground { scheduleSessionEndAlertIfNeeded() }
    }

    func decreaseTimer() {
        if isRunning || isPaused {
            adjustRemainingTime(by: -60)
        } else {
            guard timerMinutes > 1 else { return }
            timerMinutes -= 1
        }
        if isInBackground { scheduleSessionEndAlertIfNeeded() }
    }

    private func adjustRemainingTime(by seconds: Int) {
        // Minus at/below floor must not extend time (max(60, remaining-60) trap)
        if seconds < 0, remainingSeconds <= 60 { return }
        let maxTotal = BLEConstants.maxSessionMinutes * 60
        let newRemaining = max(60, min(maxTotal, remainingSeconds + seconds))
        let delta = newRemaining - remainingSeconds
        guard delta != 0 else { return }
        remainingSeconds = newRemaining
        sessionTotalDuration = min(maxTotal, sessionTotalDuration + delta)
        // Keep total consistent with remaining + elapsed
        if sessionTotalDuration < remainingSeconds {
            sessionTotalDuration = remainingSeconds
        }
        userAdjustedRemainingToken &+= 1
        persistSession()
        // Keep Dynamic Island progress correct when total changes
        if isRunning || isPaused {
            pushLiveActivity()
        }
        if isInBackground {
            scheduleSessionEndAlertIfNeeded()
        }
    }

    /// Enqueue a full program. Serial withResponse queue owns ordering;
    /// stop/pause uses `cancelProgramWrites` (waiting only — never dual withResponse).
    private func sendSessionCommands(_ commands: [String]) {
        guard !commands.isEmpty else { return }
        ble.sendCommands(commands)
    }

    func setStrength(_ value: Int) {
        let clamped = max(1, min(9, value))
        // Slider release / reassert same value must not pin mid-fade or re-write BLE
        guard clamped != strength else {
            if isRunning || isPaused {
                defaults.set(clamped, forKey: PersistKey.strength)
            }
            return
        }
        let previousBase = strength
        strength = clamped
        AppPreferences.saveLastStrength(clamped, defaults: defaults)
        // Sync soft-start so later ease-in steps never undercut user-raised BLE
        if var engine {
            engine.noteUserStrength(clamped, previousBase: previousBase)
            self.engine = engine
            // Durable mid-fade user pin (0 if early nudge — auto-fade still allowed)
            let pin = engine.pinnedUserStrengthFloor()
            if pin > 0 {
                defaults.set(pin, forKey: PersistKey.userStrengthFloor)
            } else {
                defaults.removeObject(forKey: PersistKey.userStrengthFloor)
            }
        }
        // Custom soft window: mirror noteExternalStrength — stop ease, never undercut
        if customSoftBeginElapsed != nil {
            clearCustomSoftBegin(durable: true)
            if modeStatus.contains("Easing") {
                modeStatus = "Custom · Manual"
            }
        }
        // Persist base + soft snapshot (takeover floor) even when offline/rest
        if isRunning || isPaused {
            defaults.set(clamped, forKey: PersistKey.strength)
            persistSession() // durable soft userTakenOver / lastSent for kill restore
        }
        guard isRunning, ble.isReady, stimulationActive else {
            // Rest / offline: model updated; next on-edge / reconnect uses new base
            if isRunning || isPaused {
                pushLiveActivity()
            }
            return
        }
        // Clear soft/wave UI override once we reassert on device
        effectiveStrength = nil
        // Engine tick may reassert wave/fade strength; avoid base-then-wave spike
        applyUserStrengthToDevice(userBase: clamped)
        pushLiveActivity()
    }

    /// Mid-session intensity: tick first for mode-specific level; base only if tick had none.
    private func applyUserStrengthToDevice(userBase: Int) {
        guard var engine else {
            ble.sendCommand(BLEConstants.strengthCommand(userBase))
            return
        }
        let result = engine.tick(
            elapsed: elapsed,
            totalDuration: sessionTotalDuration,
            baseStrength: strength
        )
        self.engine = engine
        lastTickElapsed = elapsed
        let cmds = StrengthWritePolicy.bleCommands(
            userBase: userBase,
            tickCommands: result.commands
        )
        if !cmds.isEmpty {
            sendSessionCommands(cmds)
        }
        applyTickResult(result)
    }

    // MARK: - Wall-Clock Recalculation

    private func recalculateFromWallClock(
        absoluteIfJumped: Bool = false,
        advanceEngine: Bool = true,
        linkReady: Bool? = nil
    ) {
        guard let startDate = sessionStartDate else { return }

        // BG wake / timer: long offline while running → pause before reprogram.
        // A ready sink passes linkReady so willSet does not look offline.
        let ready = linkReady ?? ble.isReady
        if isRunning, !ready {
            considerOfflineAutoPause()
            guard isRunning else { return }
        }

        let wallNow = now()
        let totalElapsed = wallNow.timeIntervalSince(startDate)
        let activeElapsed = totalElapsed - accumulatedPauseTime
        let elapsedSeconds = Int(activeElapsed)
        let newRemaining = max(0, sessionTotalDuration - elapsedSeconds)

        if newRemaining <= 0 {
            stop(reason: .completed)
            return
        }

        remainingSeconds = newRemaining
        if advanceEngine {
            advanceEngineForElapsed(absoluteIfJumped: absoluteIfJumped)
        }
        if isRunning || isPaused {
            pushLiveActivity()
        }
    }

    /// Edge tick for normal 1s advances. Absolute reassert only on large wall gaps
    /// so 5s watch / 10s BLE ping do not blip continuous modes.
    /// Duty/breath/burst use a tighter gap while backgrounded (edge honesty).
    private func advanceEngineForElapsed(absoluteIfJumped: Bool) {
        let current = elapsed
        let gap = lastTickElapsed.map { abs(current - $0) } ?? 0
        let threshold = absoluteReassertThresholdSeconds
        let jumped = gap >= threshold
        if absoluteIfJumped, jumped, ble.isReady, isRunning {
            // Forced brief off — then absolute phase (A/0 + strength as needed)
            ble.cancelProgramWrites()
            ble.sendCommand(BLEConstants.deactivateCommand)
            resumeSessionOnDevice()
            return
        }
        processTick()
        lastTickElapsed = current
    }

    /// Continuous Stress: 15s (no blip on 5–10s polls).
    /// Edge modes in BG: just above keepalive so 10s BLE pings do not force off+reprogram.
    private var absoluteReassertThresholdSeconds: Int {
        if isInBackground, selectedMode.needsBackgroundEdgeHonesty {
            return Int(BLEConstants.keepaliveInterval) + 1 // 11 > 10s ping
        }
        return Self.absoluteReassertMinGapSeconds
    }

    // MARK: - Scene Phase

    func scenePhaseHandler(from oldPhase: Any, to newPhase: Any) {
        // Import SwiftUI's ScenePhase values via string comparison to avoid
        // importing SwiftUI in this ViewModel. The caller passes ScenePhase values.
        scenePhaseTransition(wentToBackground: "\(newPhase)" == "background",
                             returnedToForeground: "\(oldPhase)" == "background" && "\(newPhase)" != "background")
    }

    func handleBackgroundTransition() {
        scenePhaseTransition(wentToBackground: true, returnedToForeground: false)
    }

    func handleForegroundTransition() {
        scenePhaseTransition(wentToBackground: false, returnedToForeground: true)
    }

    private func scenePhaseTransition(wentToBackground: Bool, returnedToForeground: Bool) {
        if wentToBackground {
            guard isRunning else { return }
            isInBackground = true
            backgroundEntryDate = now()
            // Stop the countdown timer — it won't fire reliably in background.
            stopCountdown()
            persistSession()
            // Refresh Island before suspend: freezes endsAt if offline, locks remaining
            pushLiveActivity()
            // v1 ambience: no audio background mode — pause pad while away
            syncAmbientAudio()
            beginBackgroundTaskIfNeeded()
            startBackgroundExpiryWatch()
            // Kick off the BLE notification loop: send a battery query so the device
            // responds, which wakes us up (bluetooth-central), where we send keepalive
            // + another query, creating a self-sustaining cycle.
            scheduleBLEPing()
            scheduleSessionEndAlertIfNeeded()
        }

        if returnedToForeground {
            // Capture before clearing — short app-switch must not force lead-0 off
            // Use inject `now` (same clock as BG stamp) so tests and wall math agree
            let secondsInBackground = backgroundEntryDate.map { now().timeIntervalSince($0) }
            let wasOffline = offlineSince != nil || !ble.isReady
            isInBackground = false
            backgroundEntryDate = nil
            backgroundWatchTask?.cancel()
            backgroundWatchTask = nil
            endBackgroundTaskIfNeeded()
            endNotifier.cancel()
            // Resume pad if still running + opted in (even if session already ended while away)
            syncAmbientAudio()
            guard isRunning else { return }
            // Short switch + still linked: device kept running — do not blip with lead-0.
            // Long gap / offline: absolute reassert (duty honesty + comfort after drop).
            // Edge modes (duty/breath) use tighter gap while backgrounded.
            let reassertGap = TimeInterval(absoluteReassertThresholdSeconds)
            let reassert = SessionSafety.shouldReassertDeviceOnForeground(
                isLinkReady: ble.isReady,
                secondsInBackground: secondsInBackground,
                wasMarkedOffline: wasOffline,
                reassertAfterSeconds: reassertGap
            )
            // Wall remaining always. Catch up soft/phase without lead-0 when not reasserting;
            // reassert path processTicks via resumeSessionOnDevice.
            recalculateFromWallClock(absoluteIfJumped: false, advanceEngine: !reassert)
            // Only resume if the session is still active after recalculation.
            guard isRunning else { return }
            if reassert {
                resumeSessionOnDevice()
            } else {
                // Island + keepalive without cancel/off reprogram
                startKeepalive()
                pushLiveActivity()
            }
            // Restart UI countdown timer
            startCountdown()
        }
    }

    private func beginBackgroundTaskIfNeeded() {
        endBackgroundTaskIfNeeded()
        // Expiration must finish before return — unstructured Task may not run before suspend.
        // UIKit may call this on a background queue; never main.sync from main.
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "openpulse.session") { [weak self] in
            guard let self else { return }
            let expire: @MainActor () -> Void = {
                if self.isRunning {
                    self.recalculateFromWallClock(absoluteIfJumped: false, advanceEngine: false)
                }
                self.endBackgroundTaskIfNeeded()
            }
            if Thread.isMainThread {
                MainActor.assumeIsolated { expire() }
            } else {
                DispatchQueue.main.sync {
                    MainActor.assumeIsolated { expire() }
                }
            }
        }
    }

    private func endBackgroundTaskIfNeeded() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    /// Wall-clock expire even if BLE ping loop dies (Session.tla InvNoStimWhenExpired).
    /// Edge ticks only — never absolute reassert (5s poll would blip stim).
    private func startBackgroundExpiryWatch() {
        backgroundWatchTask?.cancel()
        backgroundWatchTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.isInBackground, self.isRunning else { return }
                // absolute only if gap ≥15s (threshold) — duty rest honesty without poll blips
                self.recalculateFromWallClock(absoluteIfJumped: true)
                if !self.isRunning { return }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    /// Send a battery query to provoke a device notification, which keeps us in the
    /// BLE wake-up loop while backgrounded.
    private func scheduleBLEPing() {
        guard isInBackground, isRunning, ble.isConnected else { return }
        ble.sendCommand(BLEConstants.batteryQueryCommand)
    }

    /// Called on every BLE TX notification. While backgrounded: expire if needed,
    /// absolute reassert on large elapsed jumps (duty rest honesty), keepalive, next ping.
    private func handleBLENotification() {
        guard isInBackground, isRunning else { return }

        // Wall-clock + engine advance (absolute only on large suspend gaps)
        recalculateFromWallClock(absoluteIfJumped: true)
        guard isRunning, ble.isConnected else { return }

        // Keepalive strength while stim is active (absolute path may have just programmed)
        if stimulationActive {
            let s = effectiveStrength ?? strength
            ble.sendCommand(BLEConstants.strengthCommand(s))
        }
        // Single-flight ping schedule (avoid UART storms from every TX notify)
        backgroundPingTask?.cancel()
        backgroundPingTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(BLEConstants.keepaliveInterval))
            guard !Task.isCancelled else { return }
            self?.scheduleBLEPing()
        }
    }

    // MARK: - Timers

    private func startCountdown() {
        stopCountdown()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Gap threshold ≥15s blocks 1s jitter; large stalls still absolute
                self.recalculateFromWallClock(absoluteIfJumped: true)
            }
        }
        // .common so scroll/tracking does not stall session edges
        RunLoop.main.add(timer, forMode: .common)
        countdownTimer = timer
    }

    /// Idle and paused do not program the device (stop race / stale timer).
    private func processTick() {
        guard isRunning else { return }

        touchLastAlive()
        if engine == nil {
            tickCustomProgram()
        } else {
            tickEngineProgram()
        }
    }

    private func tickEngineProgram() {
        guard var engine else { return }
        let result = engine.tick(
            elapsed: elapsed,
            totalDuration: sessionTotalDuration,
            baseStrength: strength
        )
        self.engine = engine
        lastTickElapsed = elapsed
        if ble.isReady, !result.commands.isEmpty {
            sendSessionCommands(result.commands)
        }
        applyTickResult(result)
    }

    private func tickCustomProgram() {
        if let command = stepCustomSoft(), ble.isReady, stimulationActive {
            ble.sendCommand(command)
        }
        lastTickElapsed = elapsed
    }

    /// Shared UI + durable comfort after an engine tick (timer or setStrength path).
    private func applyTickResult(_ result: ModeTickResult) {
        // Persist soft snapshot while easing; clear when settled (takeover already persisted on setStrength)
        if result.isEasing {
            persistSession()
        } else if defaults.data(forKey: PersistKey.softSnapshot) != nil,
                  engine?.softSnapshot() == nil {
            defaults.removeObject(forKey: PersistKey.softSnapshot)
        }
        // Durable comfort for Sleep restore — settled only (never soft-ease steps)
        if result.isStimulationActive {
            if result.isEasing {
                // Skip — soft steps must not become fadeFloor on kill
            } else if let comfort = result.effectiveStrength, comfort > 0 {
                persistComfortStrength(comfort)
            } else {
                persistComfortStrength(strength)
            }
        }

        // Never claim stim without a ready link (SessionBLE)
        if ble.isReady {
            stimulationActive = result.isStimulationActive
            activeChannel = result.activeChannel
            effectiveStrength = result.effectiveStrength
            breathingPhase = result.breathingPhase
            // Prefer short breath labels for Island / Still (Inhale·Hold·Exhale·Rest)
            if let phaseLabel = BreathPhasePresentation.statusText(phase: result.breathingPhase) {
                modeStatus = phaseLabel
            } else {
                modeStatus = result.statusText
            }
        } else {
            stimulationActive = false
            activeChannel = .off
            effectiveStrength = nil
            breathingPhase = result.breathingPhase
            modeStatus = isRunning
                ? "Reconnecting…"
                : result.statusText
        }
    }

    /// Next custom soft step, or full strength when the ease window closes.
    /// Nil when the window is idle or the step is unchanged. The caller sends it.
    private func stepCustomSoft() -> String? {
        guard let begin = customSoftBeginElapsed else { return nil }
        let local = max(0, elapsed - begin)
        let desired = SoftStart.strength(atElapsed: local, target: strength)
        if SoftStart.isComplete(elapsed: local, target: strength) {
            clearCustomSoftBegin(durable: true)
            effectiveStrength = nil
            if modeStatus.contains("Easing") {
                modeStatus = customChannelCommand == "0" ? "Custom · Off" : "Custom · Manual"
            }
            return BLEConstants.strengthCommand(strength)
        }
        guard effectiveStrength != desired else { return nil }
        effectiveStrength = desired
        return BLEConstants.strengthCommand(desired)
    }

    private func stopCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    private func startKeepalive() {
        stopKeepalive()
        keepaliveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(BLEConstants.keepaliveInterval))
                guard !Task.isCancelled, let self else { return }
                guard self.isRunning, self.ble.isReady else { continue }
                guard self.stimulationActive else { continue }
                let s = self.effectiveStrength ?? self.strength
                self.ble.sendCommand(BLEConstants.strengthCommand(s))
            }
        }
    }

    private func stopKeepalive() {
        keepaliveTask?.cancel()
        keepaliveTask = nil
    }

    private func startStatusPoll() {
        stopStatusPoll()
        statusPollTimer = Timer.scheduledTimer(withTimeInterval: BLEConstants.statusPollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.queryStatus()
            }
        }
    }

    private func stopStatusPoll() {
        statusPollTimer?.invalidate()
        statusPollTimer = nil
    }

    private func queryStatus() {
        ble.sendCommand(BLEConstants.batteryQueryCommand)
        ble.sendCommand(BLEConstants.chargingQueryCommand)
    }

    // MARK: - Reconnection

    private func handleDisconnect() {
        stopKeepalive()
        stopStatusPoll()
        // Program cancel is owned by BLE cancelProgramWrites + serial queue
        if isRunning {
            // Start offline clock; long outage → auto-pause (no surprise re-stim)
            if offlineSince == nil {
                setOfflineSince(now())
                scheduleOfflineAutoPause()
            }
            // Durable off intent immediately — process death before auto-pause still flushes
            pendingDeactivate = true
            noteLinkLostWhileRunning()
        } else {
            // Idle/paused: ensure next ready sends off
            pendingDeactivate = true
            // SessionBLE InvNoStimWhenDisconnected — don't claim stim without a link
            stimulationActive = false
            activeChannel = .off
            effectiveStrength = nil
            pushLiveActivity()
        }
        // Short blip: session keeps running; long offline: considerOfflineAutoPause
    }

    /// Mid-run link loss honesty (ready sink and/or disconnect).
    /// Clears stim claim, freezes LA countdown (endsAt nil via !isLinkReady), pushes Island.
    private func noteLinkLostWhileRunning() {
        guard isRunning else { return }
        stimulationActive = false
        activeChannel = .off
        effectiveStrength = nil
        modeStatus = "Reconnecting…"
        // Force link-down on LA even if published isReady races
        pushLiveActivity(isLinkReady: false)
    }

    /// Persist/clear mid-run offline clock (survives process kill).
    private func setOfflineSince(_ date: Date?) {
        offlineSince = date
        if let date {
            defaults.set(date.timeIntervalSince1970, forKey: PersistKey.offlineSince)
        } else {
            defaults.removeObject(forKey: PersistKey.offlineSince)
        }
    }

    private func resumeSessionOnDevice(linkReady: Bool? = nil) {
        let ready = linkReady ?? ble.isReady
        guard isRunning, remainingSeconds > 0 else {
            flushPendingDeactivateIfNeeded(linkReady: ready)
            return
        }

        // Absolute program: leading off then phase (comfort after offline/pause/gap).
        // Pending off clears only on lead-0 ACK (durable across process death).
        if ready {
            ble.cancelProgramWrites()
            ble.sendCommand(BLEConstants.deactivateCommand)
        }
        if var engine {
            let cmds = engine.reconnectCommands(
                elapsed: elapsed,
                totalDuration: sessionTotalDuration,
                baseStrength: strength
            )
            self.engine = engine
            sendSessionCommands(cmds)
            processTick()
        } else {
            // Custom mode — restore last channel (or stay off if user chose OFF)
            sendSessionCommands(customReconnectCommands())
            applyCustomChannelFlagsFromCommand()
            lastTickElapsed = elapsed
            // Soft after pause / first start / mid-soft reconnect — honest status
            // (effectiveStrength already set by customReconnectCommands when mid-soft)
            if customSoftBeginElapsed != nil, SoftStart.isNeeded(target: strength) {
                modeStatus = "Custom · Easing in"
                let begin = customSoftBeginElapsed!
                let local = max(0, elapsed - begin)
                let step = SoftStart.strength(atElapsed: local, target: strength)
                effectiveStrength = step < strength ? step : nil
            } else if customChannelCommand == "0" {
                modeStatus = "Custom · Off"
                effectiveStrength = nil
            } else {
                modeStatus = "Custom · Manual"
                effectiveStrength = nil
            }
        }

        startKeepalive()
        pushLiveActivity()
    }

    // MARK: - Session Persistence

    let defaults: UserDefaults
    private enum PersistKey {
        static let startDate = "session.startDate"
        static let totalDuration = "session.totalDuration"
        static let pauseTime = "session.accumulatedPauseTime"
        static let pauseStartDate = "session.pauseStartDate"
        static let isPaused = "session.isPaused"
        static let mode = "session.mode"
        static let feeling = "session.feeling"
        static let strength = "session.strength"
        static let breathePace = "session.breathePace"
        static let easePattern = "session.easePattern"
        /// Sleep phase length fixed at start so ±time survives process kill.
        static let phaseLengthSeconds = "session.phaseLengthSeconds"
        /// Last comfort / fade strength so reconnect after kill does not re-raise.
        static let lastComfortStrength = "session.lastComfortStrength"
        /// User raised mid-fade — holds across kill (separate from soft-complete at base).
        static let userStrengthFloor = "session.userStrengthFloor"
        static let mindfulSegments = "session.mindfulSegments"
        static let mindfulSegmentStart = "session.mindfulSegmentStart"
        /// Custom soft window begin (session elapsed) — survives process kill mid ease-in.
        static let customSoftBeginElapsed = "session.customSoftBeginElapsed"
        /// Engine soft snapshot (enabled/lastSent/begin) — process kill without undercut.
        static let softSnapshot = "session.softSnapshot"
        /// Wall time mid-run link dropped (durable auto-pause across process kill).
        static let offlineSince = "session.offlineSince"
        /// Last process-alive stamp (tick / BG / persist) — jetsam honesty without offlineSince.
        static let lastAlive = "session.lastAlive"
    }

    /// Touch durable last-alive for kill-restore freeze (R90).
    private func touchLastAlive(_ date: Date? = nil) {
        let stamp = date ?? now()
        defaults.set(stamp.timeIntervalSince1970, forKey: PersistKey.lastAlive)
    }

    private func persistSession() {
        let d = defaults
        d.set(sessionStartDate?.timeIntervalSince1970, forKey: PersistKey.startDate)
        d.set(sessionTotalDuration, forKey: PersistKey.totalDuration)
        d.set(accumulatedPauseTime, forKey: PersistKey.pauseTime)
        d.set(pauseStartDate?.timeIntervalSince1970, forKey: PersistKey.pauseStartDate)
        d.set(isPaused, forKey: PersistKey.isPaused)
        d.set(selectedMode.rawValue, forKey: PersistKey.mode)
        d.set(selectedFeeling?.rawValue, forKey: PersistKey.feeling)
        d.set(strength, forKey: PersistKey.strength)
        d.set(breathePace.rawValue, forKey: PersistKey.breathePace)
        d.set(easePattern.rawValue, forKey: PersistKey.easePattern)
        if isRunning || isPaused {
            d.set(now().timeIntervalSince1970, forKey: PersistKey.lastAlive)
        }
        if let softBegin = customSoftBeginElapsed {
            d.set(softBegin, forKey: PersistKey.customSoftBeginElapsed)
        } else {
            d.removeObject(forKey: PersistKey.customSoftBeginElapsed)
        }
        if var eng = engine, let snap = eng.softSnapshot(),
           let data = try? JSONEncoder().encode(snap) {
            d.set(data, forKey: PersistKey.softSnapshot)
            engine = eng
        } else {
            d.removeObject(forKey: PersistKey.softSnapshot)
        }
        // Mindful multi-segment honesty across process death
        let segs: [[Double]] = mindfulSegments.map {
            [$0.start.timeIntervalSince1970, $0.end.timeIntervalSince1970]
        }
        if let data = try? JSONEncoder().encode(segs) {
            d.set(data, forKey: PersistKey.mindfulSegments)
        }
        d.set(mindfulSegmentStart?.timeIntervalSince1970, forKey: PersistKey.mindfulSegmentStart)
    }

    private func clearPersistedSession() {
        let d = defaults
        for key in [PersistKey.startDate, PersistKey.totalDuration, PersistKey.pauseTime,
                    PersistKey.pauseStartDate, PersistKey.isPaused, PersistKey.mode,
                    PersistKey.feeling, PersistKey.strength,
                    PersistKey.breathePace, PersistKey.easePattern,
                    PersistKey.customSoftBeginElapsed, PersistKey.softSnapshot,
                    PersistKey.phaseLengthSeconds, PersistKey.lastComfortStrength,
                    PersistKey.userStrengthFloor,
                    PersistKey.mindfulSegments, PersistKey.mindfulSegmentStart,
                    PersistKey.offlineSince, PersistKey.lastAlive] {
            d.removeObject(forKey: key)
        }
        offlineSince = nil
    }

    /// Anchor Sleep phase length at session start (never rewrite on ±time).
    private func persistPhaseScheduleIfNeeded() {
        guard selectedMode == .sleep else { return }
        let d = defaults
        if d.integer(forKey: PersistKey.phaseLengthSeconds) <= 0 {
            d.set(max(1, sessionTotalDuration / 5), forKey: PersistKey.phaseLengthSeconds)
        }
    }

    /// Track last comfort strength so restore mid-fade cannot re-raise (only on change).
    private func persistComfortStrength(_ value: Int) {
        let clamped = max(1, min(9, value))
        if defaults.integer(forKey: PersistKey.lastComfortStrength) == clamped { return }
        defaults.set(clamped, forKey: PersistKey.lastComfortStrength)
    }

    private func seedEngineAnchorsFromDefaults(_ eng: inout ModeEngine) {
        let d = defaults
        let phaseLen = d.integer(forKey: PersistKey.phaseLengthSeconds)
        let comfort = d.integer(forKey: PersistKey.lastComfortStrength)
        let pin = d.integer(forKey: PersistKey.userStrengthFloor)
        eng.restoreAnchors(
            phaseLengthSeconds: phaseLen > 0 ? phaseLen : nil,
            lastComfortStrength: comfort > 0 ? comfort : nil,
            sessionStrength: strength,
            elapsed: elapsed,
            totalDuration: sessionTotalDuration,
            pinnedUserFloor: pin > 0 ? pin : nil
        )
    }

    private func loadMindfulSegmentsFromDefaults() {
        let d = defaults
        if let data = d.data(forKey: PersistKey.mindfulSegments),
           let segs = try? JSONDecoder().decode([[Double]].self, from: data) {
            mindfulSegments = segs.compactMap { pair in
                guard pair.count == 2 else { return nil }
                let start = Date(timeIntervalSince1970: pair[0])
                let end = Date(timeIntervalSince1970: pair[1])
                guard end > start else { return nil }
                return (start: start, end: end)
            }
        } else {
            mindfulSegments = []
        }
        if let ts = d.object(forKey: PersistKey.mindfulSegmentStart) as? TimeInterval {
            mindfulSegmentStart = Date(timeIntervalSince1970: ts)
        } else {
            mindfulSegmentStart = nil
        }
    }

    /// Wall timer finished while app was dead — same side-effects as stop(.completed)
    /// without a live engine: history, mindful minutes, banner, durable hardware off.
    private func finalizeExpiredSession(planned: Int, mode: StimulationMode, strengthSnapshot: Int) {
        // Snapshot before clear — late open must not write practice ending at "now"
        let startSnap = sessionStartDate
        let pauseSnap = accumulatedPauseTime
        let practiceEnd: Date = {
            if let start = startSnap {
                return start.addingTimeInterval(TimeInterval(planned) + pauseSnap)
            }
            return Date()
        }()
        closeMindfulSegment(at: min(Date(), practiceEnd))
        isRunning = false
        isPaused = false
        remainingSeconds = 0
        sessionTotalDuration = 0
        sessionStartDate = nil
        sessionWallStart = nil
        accumulatedPauseTime = 0
        pauseStartDate = nil
        backgroundEntryDate = nil
        lastTickElapsed = nil
        engine = nil
        stimulationActive = false
        effectiveStrength = nil
        breathingPhase = nil
        activeChannel = .off
        modeStatus = ""
        UIApplication.shared.isIdleTimerDisabled = false
        clearPersistedSession()
        // Same HW off path as stop(.completed) — cancel program writes + send when ready
        requestDeviceOff(andQueryStatus: false)
        // Expire always needs off — completed linger claims pending honestly
        liveActivity.end(
            reason: .completed,
            modeName: mode.name,
            pendingDeviceOff: true
        )

        AppPreferences.saveLastStrength(strengthSnapshot, defaults: defaults)
        if planned > 0 {
            SessionHistory.append(
                mode: mode,
                durationSeconds: planned,
                strength: strengthSnapshot,
                completed: true,
                breathePace: breathePace,
                easePattern: easePattern,
                defaults: defaults
            )
            recentSessions = SessionHistory.load(defaults: defaults)
        }
        if planned >= 60 {
            saveMindfulMinutesIfEnabled(
                mode: mode,
                durationSeconds: planned,
                end: min(Date(), practiceEnd)
            )
        }
        mindfulSegments = []
        mindfulSegmentStart = nil
        completionBanner = "Session complete · \(mode.name)"
    }

    private func restoreSessionIfNeeded() {
        let d = defaults
        guard let startTimestamp = d.object(forKey: PersistKey.startDate) as? TimeInterval else { return }

        let startDate = Date(timeIntervalSince1970: startTimestamp)
        let totalDuration = d.integer(forKey: PersistKey.totalDuration)
        guard totalDuration > 0 else { clearPersistedSession(); return }

        let pauseTime = d.double(forKey: PersistKey.pauseTime)
        let diskPaused = d.bool(forKey: PersistKey.isPaused)
        let diskPauseStart: Date? = (d.object(forKey: PersistKey.pauseStartDate) as? TimeInterval)
            .map { Date(timeIntervalSince1970: $0) }
        let offlineSinceDisk: Date? = (d.object(forKey: PersistKey.offlineSince) as? TimeInterval)
            .map { Date(timeIntervalSince1970: $0) }
        let lastAliveDisk: Date? = (d.object(forKey: PersistKey.lastAlive) as? TimeInterval)
            .map { Date(timeIntervalSince1970: $0) }

        // Restore mode/feeling
        if let modeRaw = d.string(forKey: PersistKey.mode),
           let mode = StimulationMode(rawValue: modeRaw) {
            selectedMode = mode
        }
        // Missing key must clear default .stressed — Custom/mode-only restore honesty (R47)
        if let feelingRaw = d.string(forKey: PersistKey.feeling),
           let feeling = AutonomicState(rawValue: feelingRaw) {
            selectedFeeling = feeling
        } else {
            selectedFeeling = nil
        }
        // Normalize legacy modes → primary + options (Still catalog)
        var needsModePersist = normalizeLegacyModeOptions()
        if let paceRaw = d.string(forKey: PersistKey.breathePace),
           let pace = BreathePace(rawValue: paceRaw) {
            breathePace = pace
        }
        if let patternRaw = d.string(forKey: PersistKey.easePattern),
           let pattern = EasePattern(rawValue: patternRaw) {
            easePattern = pattern
        }
        // Re-normalize after disk pace/pattern so feeling/mode stay aligned
        if normalizeLegacyModeOptions() { needsModePersist = true }
        // Corrupt / missing strength must stay in device UART range 1…9
        let rawStrength = d.integer(forKey: PersistKey.strength)
        if (StrengthPresentation.minLevel...StrengthPresentation.maxLevel).contains(rawStrength) {
            strength = rawStrength
        } else {
            strength = selectedMode.defaultStrength
        }

        // Restore wall-clock state
        sessionStartDate = startDate
        sessionTotalDuration = totalDuration
        accumulatedPauseTime = pauseTime

        let wallNow = now()
        let outcome = SessionRestorePolicy.resolve(
            now: wallNow,
            start: startDate,
            totalDurationSeconds: totalDuration,
            accumulatedPause: pauseTime,
            diskPaused: diskPaused,
            diskPauseStart: diskPauseStart,
            offlineSince: offlineSinceDisk,
            lastAlive: lastAliveDisk
        )

        if outcome.shouldFinalizeExpired {
            finalizeExpiredSession(planned: totalDuration, mode: selectedMode, strengthSnapshot: strength)
            return
        }

        if outcome.treatAsPaused {
            // Restore paused state — open pause from policy (freeze / disk / now unstamped)
            pauseStartDate = outcome.openPauseStart ?? wallNow
            if offlineSinceDisk != nil {
                defaults.removeObject(forKey: PersistKey.offlineSince)
                offlineSince = nil
            }
            remainingSeconds = outcome.remainingSeconds
            isPaused = true
            isRunning = false
            // Device should be off while paused; reassert on next ready if kill mid-pause
            pendingDeactivate = true
            engine = resolveEngine()
            // Preserve soft-after-pause across process kill
            if var eng = engine {
                seedEngineAnchorsFromDefaults(&eng)
                eng.notePaused()
                engine = eng
            } else if selectedMode == .custom {
                // Custom has no engine — same comfort contract as notePaused()
                customSoftOnNextResume = true
                customSoftBeginElapsed = nil
            }
            sessionWallStart = startDate
            sessionTotalDuration = totalDuration
            modeStatus = "Paused"
            // Closed segments only while paused (no open practice window)
            loadMindfulSegmentsFromDefaults()
            mindfulSegmentStart = nil
            // Paused restore — do not force screen awake
            UIApplication.shared.isIdleTimerDisabled = false
            pushLiveActivity(start: true)
            syncAmbientAudio()
            // Always durable after offline-freeze / unstamped-pause materialization:
            // clearing offlineSince without writing isPaused+pauseStart loses honesty
            // on the next process kill (R89).
            persistSession()
        } else {
            // Restore running state — recalculate from wall clock
            remainingSeconds = outcome.remainingSeconds
            isRunning = true
            sessionTotalDuration = totalDuration
            engine = resolveEngine()
            if var eng = engine {
                seedEngineAnchorsFromDefaults(&eng)
                // Soft window flag+lastSent (not wall-only rehydrate)
                if let data = d.data(forKey: PersistKey.softSnapshot),
                   let snap = try? JSONDecoder().decode(SoftStartSnapshot.self, from: data) {
                    eng.applySoftSnapshot(snap)
                }
                engine = eng
            }
            UIApplication.shared.isIdleTimerDisabled = true
            // Offline until ready — do not claim stim without a link
            stimulationActive = false
            activeChannel = .off
            sessionWallStart = startDate
            lastTickElapsed = nil

            // Hydrate short-blip offline clock if still offline after kill
            if let offlineTs = d.object(forKey: PersistKey.offlineSince) as? TimeInterval {
                setOfflineSince(Date(timeIntervalSince1970: offlineTs))
                scheduleOfflineAutoPause()
                pendingDeactivate = true
            }

            // Restore Custom soft window if still easing (process-kill mid soft)
            restoreCustomSoftBeginIfNeeded(defaults: d)

            // Ready programs once, while the soft snapshot is still on the engine.
            if ble.isReady {
                resumeSessionOnDevice()
            } else if var eng = engine {
                // Sync edge state for later ready/resume without soft re-ease
                _ = eng.reconnectCommands(
                    elapsed: elapsed,
                    totalDuration: sessionTotalDuration,
                    baseStrength: strength
                )
                self.engine = eng
                processTick()
            }
            if needsModePersist { persistSession() }
            // Restore durable mindful segments; open only if none was open
            loadMindfulSegmentsFromDefaults()
            if mindfulSegmentStart == nil {
                openMindfulSegment()
            }

            // Cold relaunch often starts already .background — onChange won't fire.
            // Only arm for true .background (not .inactive launch flash — R50 review).
            if UIApplication.shared.applicationState == .background {
                isInBackground = true
                backgroundEntryDate = Date()
                stopCountdown()
                beginBackgroundTaskIfNeeded()
                startBackgroundExpiryWatch()
                scheduleBLEPing()
                startKeepalive()
                // Scene onChange may not fire when launch is already backgrounded
                scheduleSessionEndAlertIfNeeded()
            } else {
                startCountdown()
                startKeepalive()
            }
            pushLiveActivity(start: true)
            syncAmbientAudio()
        }
    }
}
