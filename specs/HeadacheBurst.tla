-------------------------- MODULE HeadacheBurst --------------------------
\* Headache mode: 120s on / 30s off bilateral bursts (gammaCore-inspired).

EXTENDS Naturals

CONSTANTS MaxElapsed

ASSUME MaxElapsed \in Nat /\ MaxElapsed > 0

VARIABLES elapsed, stimOn

Cycle == 150
OnLen  == 120

ShouldOn(e) == (e % Cycle) < OnLen

TypeOK ==
  /\ elapsed \in 0..MaxElapsed
  /\ stimOn \in BOOLEAN

Init ==
  /\ elapsed = 0
  /\ stimOn = FALSE

Tick ==
  /\ elapsed < MaxElapsed
  /\ stimOn' = ShouldOn(elapsed)
  /\ elapsed' = elapsed + 1

Done ==
  /\ elapsed = MaxElapsed
  /\ UNCHANGED <<elapsed, stimOn>>

Next == Tick \/ Done

Spec == Init /\ [][Next]_<<elapsed, stimOn>>

InvStimMatchesPure ==
  elapsed = 0 \/ stimOn = ShouldOn(elapsed - 1)

InvPauseWindowOff ==
  elapsed > 0 =>
    LET pos == (elapsed - 1) % Cycle
    IN pos >= OnLen => ~stimOn

=============================================================================
