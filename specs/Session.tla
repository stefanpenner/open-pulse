----------------------------- MODULE Session -----------------------------
\* OpenPulse session lifecycle — safety under pause, background, BLE drop.
\*
\* Purpose: ensure stimulation never outlives the planned session, and
\* that Idle always means "device should be off / pending off".
\*
\* Abstraction:
\*   phase  \in {Idle, Running, Paused}
\*   bg     — app backgrounded (only meaningful while Running)
\*   remaining — abstract seconds left (wall-clock model)
\*   connected — BLE link up
\*   stimActive — app believes device is stimulating
\*   pendingOff — must send deactivate when next connected

EXTENDS Naturals, FiniteSets

VARIABLES phase, bg, remaining, total, connected, stimActive, pendingOff

Phases == {"Idle", "Running", "Paused"}

TypeOK ==
  /\ phase \in Phases
  /\ bg \in BOOLEAN
  /\ remaining \in Nat
  /\ total \in Nat
  /\ connected \in BOOLEAN
  /\ stimActive \in BOOLEAN
  /\ pendingOff \in BOOLEAN

----------------------------------------------------------------------------
\* Init: clean idle, no link assumed

Init ==
  /\ phase = "Idle"
  /\ bg = FALSE
  /\ remaining = 0
  /\ total = 0
  /\ connected = FALSE
  /\ stimActive = FALSE
  /\ pendingOff = FALSE

----------------------------------------------------------------------------
\* Actions

Start ==
  /\ phase = "Idle"
  /\ remaining' = 3          \* small bound for model checking
  /\ total' = 3
  /\ phase' = "Running"
  /\ bg' = FALSE
  /\ stimActive' = TRUE      \* continuous modes; gated modes refined elsewhere
  /\ pendingOff' = FALSE
  /\ UNCHANGED connected

Pause ==
  /\ phase = "Running"
  /\ phase' = "Paused"
  /\ bg' = FALSE
  /\ stimActive' = FALSE
  /\ pendingOff' = IF connected THEN FALSE ELSE TRUE
  /\ UNCHANGED <<remaining, total, connected>>

Resume ==
  /\ phase = "Paused"
  /\ remaining > 0
  /\ phase' = "Running"
  /\ bg' = FALSE
  /\ stimActive' = TRUE
  /\ pendingOff' = FALSE
  /\ UNCHANGED <<remaining, total, connected>>

Stop ==
  /\ phase \in {"Running", "Paused"}
  /\ phase' = "Idle"
  /\ bg' = FALSE
  /\ remaining' = 0
  /\ total' = 0
  /\ stimActive' = FALSE
  /\ pendingOff' = IF connected THEN FALSE ELSE TRUE
  /\ UNCHANGED connected

\* Wall-clock tick (foreground countdown or BG BLE-wake recalculation)
Tick ==
  /\ phase = "Running"
  /\ remaining > 0
  /\ remaining' = remaining - 1
  /\ IF remaining' = 0
     THEN /\ phase' = "Idle"
          /\ bg' = FALSE
          /\ total' = 0
          /\ stimActive' = FALSE
          /\ pendingOff' = IF connected THEN FALSE ELSE TRUE
     ELSE /\ UNCHANGED <<phase, bg, total, stimActive, pendingOff>>
  /\ UNCHANGED connected

GoBackground ==
  /\ phase = "Running"
  /\ bg = FALSE
  /\ bg' = TRUE
  /\ UNCHANGED <<phase, remaining, total, connected, stimActive, pendingOff>>

GoForeground ==
  /\ phase = "Running"
  /\ bg = TRUE
  /\ bg' = FALSE
  /\ UNCHANGED <<phase, remaining, total, connected, stimActive, pendingOff>>

\* BLE drops; session may keep running but stim state unknown
BLEDrop ==
  /\ connected = TRUE
  /\ connected' = FALSE
  /\ stimActive' = FALSE
  /\ UNCHANGED <<phase, bg, remaining, total, pendingOff>>

\* BLE ready while session still has time — reprogram stim (code path after wall check passes)
BLEReadyReprogram ==
  /\ connected = FALSE
  /\ connected' = TRUE
  /\ phase = "Running"
  /\ remaining > 0
  /\ stimActive' = TRUE
  /\ pendingOff' = FALSE
  /\ UNCHANGED <<phase, bg, remaining, total>>

\* BLE ready but wall clock already past endsAt (stale remaining) — expire, never re-stim.
\* Models SessionViewModel ready sink: recalculateFromWallClock before resumeSessionOnDevice.
BLEReadyWallExpire ==
  /\ connected = FALSE
  /\ connected' = TRUE
  /\ phase = "Running"
  /\ remaining > 0
  /\ phase' = "Idle"
  /\ remaining' = 0
  /\ total' = 0
  /\ bg' = FALSE
  /\ stimActive' = FALSE
  /\ pendingOff' = FALSE
  /\ UNCHANGED << >>

\* BLE ready while idle/paused — flush durable pendingOff
BLEReadyFlush ==
  /\ connected = FALSE
  /\ connected' = TRUE
  /\ phase \in {"Idle", "Paused"}
  /\ stimActive' = FALSE
  /\ IF pendingOff = TRUE
     THEN pendingOff' = FALSE
     ELSE UNCHANGED pendingOff
  /\ UNCHANGED <<phase, bg, remaining, total>>

BLEReady == BLEReadyReprogram \/ BLEReadyWallExpire \/ BLEReadyFlush

\* Process killed / fully suspended past endsAt; revive → Idle.
\* If still linked, same-step off flush (Tick expire discipline);
\* if offline, durable pendingOff until BLEReady.
KillRestoreExpire ==
  /\ phase = "Running"
  /\ remaining > 0
  /\ phase' = "Idle"
  /\ remaining' = 0
  /\ total' = 0
  /\ bg' = FALSE
  /\ stimActive' = FALSE
  /\ pendingOff' = IF connected THEN FALSE ELSE TRUE
  /\ UNCHANGED connected

Next ==
  \/ Start
  \/ Pause
  \/ Resume
  \/ Stop
  \/ Tick
  \/ GoBackground
  \/ GoForeground
  \/ BLEDrop
  \/ BLEReady
  \/ KillRestoreExpire

Spec == Init /\ [][Next]_<<phase, bg, remaining, total, connected, stimActive, pendingOff>>

----------------------------------------------------------------------------
\* Safety invariants

\* Never both running and paused (single-enum discipline)
InvPhaseExclusive == phase \in Phases

\* Idle is clean: no remaining time, no active stim claim
InvIdleClean ==
  phase = "Idle" => (remaining = 0 /\ stimActive = FALSE)

\* Remaining never exceeds total while session active
InvRemainingBound ==
  phase \in {"Running", "Paused"} => remaining <= total

\* Background only while running
InvBGOnlyRunning ==
  bg => phase = "Running"

\* stimActive implies a live session (device should not be "on" from app POV when idle)
InvStimImpliesSession ==
  stimActive => phase = "Running"

\* If idle and connected, we never leave a pendingOff unresolved forever
\* (weaker form: idle+connected => ~pendingOff after BLEReady flush)
InvIdleConnectedFlushed ==
  (phase = "Idle" /\ connected) => pendingOff = FALSE

\* Safety goal: cannot claim stim when remaining is 0
InvNoStimWhenExpired ==
  remaining = 0 => stimActive = FALSE

\* KillRestoreExpire always leaves Idle + pendingOff (action postcondition;
\* InvIdleClean + InvNoStimWhenExpired still hold after that step)

=============================================================================
