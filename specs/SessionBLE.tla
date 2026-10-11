--------------------------- MODULE SessionBLE ---------------------------
\* Composition: session lifecycle ∥ BLE link readiness.
\* Purpose: never leave hardware stimulating when session is Idle,
\* and never claim stim when BLE is down.

EXTENDS Naturals

VARIABLES
  phase,        \* "Idle" | "Running" | "Paused"
  remaining,
  connected,
  ready,        \* ready => connected
  stimActive,   \* app believes device is stimulating
  pendingOff    \* must deactivate on next ready if idle/paused-offline

TypeOK ==
  /\ phase \in {"Idle", "Running", "Paused"}
  /\ remaining \in Nat
  /\ connected \in BOOLEAN
  /\ ready \in BOOLEAN
  /\ stimActive \in BOOLEAN
  /\ pendingOff \in BOOLEAN

Init ==
  /\ phase = "Idle"
  /\ remaining = 0
  /\ connected = FALSE
  /\ ready = FALSE
  /\ stimActive = FALSE
  /\ pendingOff = FALSE

----------------------------------------------------------------------------

Start ==
  /\ phase = "Idle"
  /\ ready = TRUE
  /\ phase' = "Running"
  /\ remaining' = 3
  /\ stimActive' = TRUE
  /\ pendingOff' = FALSE
  /\ UNCHANGED <<connected, ready>>

Pause ==
  /\ phase = "Running"
  /\ phase' = "Paused"
  /\ stimActive' = FALSE
  /\ pendingOff' = IF connected THEN FALSE ELSE TRUE
  /\ UNCHANGED <<remaining, connected, ready>>

Resume ==
  /\ phase = "Paused"
  /\ remaining > 0
  /\ ready = TRUE
  /\ phase' = "Running"
  /\ stimActive' = TRUE
  /\ pendingOff' = FALSE
  /\ UNCHANGED <<remaining, connected, ready>>

Stop ==
  /\ phase \in {"Running", "Paused"}
  /\ phase' = "Idle"
  /\ remaining' = 0
  /\ stimActive' = FALSE
  /\ pendingOff' = IF connected THEN FALSE ELSE TRUE
  /\ UNCHANGED <<connected, ready>>

Tick ==
  /\ phase = "Running"
  /\ remaining > 0
  /\ remaining' = remaining - 1
  /\ IF remaining' = 0
     THEN /\ phase' = "Idle"
          /\ stimActive' = FALSE
          /\ pendingOff' = IF connected THEN FALSE ELSE TRUE
     ELSE UNCHANGED <<phase, stimActive, pendingOff>>
  /\ UNCHANGED <<connected, ready>>

BLEDrop ==
  /\ connected = TRUE
  /\ connected' = FALSE
  /\ ready' = FALSE
  /\ stimActive' = FALSE
  /\ UNCHANGED <<phase, remaining, pendingOff>>

\* Link comes up; handshake completes to ready in same step (coarsened).
\* Split mirrors Session.tla expire-before-reprogram (R50).

BLEReadyReprogram ==
  /\ connected = FALSE
  /\ connected' = TRUE
  /\ ready' = TRUE
  /\ phase = "Running"
  /\ remaining > 0
  /\ stimActive' = TRUE
  /\ pendingOff' = FALSE
  /\ UNCHANGED <<phase, remaining>>

\* Wall past endsAt on ready — Idle, never claim stim
BLEReadyWallExpire ==
  /\ connected = FALSE
  /\ connected' = TRUE
  /\ ready' = TRUE
  /\ phase = "Running"
  /\ remaining > 0
  /\ phase' = "Idle"
  /\ remaining' = 0
  /\ stimActive' = FALSE
  /\ pendingOff' = FALSE

BLEReadyFlush ==
  /\ connected = FALSE
  /\ connected' = TRUE
  /\ ready' = TRUE
  /\ phase \in {"Idle", "Paused"}
  /\ stimActive' = FALSE
  /\ IF pendingOff
     THEN pendingOff' = FALSE
     ELSE UNCHANGED pendingOff
  /\ UNCHANGED <<phase, remaining>>

BLEReady == BLEReadyReprogram \/ BLEReadyWallExpire \/ BLEReadyFlush

Next ==
  \/ Start
  \/ Pause
  \/ Resume
  \/ Stop
  \/ Tick
  \/ BLEDrop
  \/ BLEReady

Spec == Init /\ [][Next]_<<phase, remaining, connected, ready, stimActive, pendingOff>>

----------------------------------------------------------------------------

InvReadyImpliesConnected == ready => connected

InvIdleClean ==
  phase = "Idle" => (remaining = 0 /\ stimActive = FALSE)

InvStimImpliesRunning ==
  stimActive => phase = "Running"

InvNoStimWhenDisconnected ==
  ~connected => ~stimActive

\* When idle and ready, pending off has been flushed
InvIdleReadyFlushed ==
  (phase = "Idle" /\ ready) => ~pendingOff

\* Cannot start-equivalent: stim never true while idle
InvNoZombieStim ==
  phase = "Idle" => ~stimActive

=============================================================================
