---------------------------- MODULE FocusDuty ----------------------------
\* Focus mode: 30s on / 30s off left-channel duty cycle.
\* Proves pure elapsed → stim phase, independent of edge memory.

EXTENDS Naturals

CONSTANTS MaxElapsed

ASSUME MaxElapsed \in Nat /\ MaxElapsed > 0

VARIABLES elapsed, stimOn, wasOn

Cycle == 60
OnLen  == 30

ShouldOn(e) == (e % Cycle) < OnLen

TypeOK ==
  /\ elapsed \in 0..MaxElapsed
  /\ stimOn \in BOOLEAN
  /\ wasOn \in BOOLEAN

Init ==
  /\ elapsed = 0
  /\ stimOn = FALSE
  /\ wasOn = FALSE

Tick ==
  /\ elapsed < MaxElapsed
  /\ LET want == ShouldOn(elapsed)
     IN /\ stimOn' = want
        /\ wasOn' = want
        /\ elapsed' = elapsed + 1

Done ==
  /\ elapsed = MaxElapsed
  /\ UNCHANGED <<elapsed, stimOn, wasOn>>

Next == Tick \/ Done

Spec == Init /\ [][Next]_<<elapsed, stimOn, wasOn>>

\* After each tick, stim matches pure phase for the second just applied
InvStimMatchesPure ==
  elapsed = 0 \/ stimOn = ShouldOn(elapsed - 1)

\* Off half of every minute is never stimulating
InvOffHalfClean ==
  elapsed > 0 =>
    LET pos == (elapsed - 1) % Cycle
    IN pos >= OnLen => ~stimOn

=============================================================================
