------------------------ MODULE RespiratoryGate ------------------------
\* Respiratory-gated stimulation (Calm / Meditation engines).
\*
\* Purpose: prove the stim window is exactly [rampStart, stimEnd) mod cycle,
\* independent of edge-tracking memory. Spec is pure elapsed → stim.

EXTENDS Naturals

CONSTANTS
  Inhale,      \* seconds
  Hold,
  Exhale,
  Rest,
  RampLead,    \* activate this many seconds before hold
  MaxElapsed   \* model bound

ASSUME
  /\ Inhale \in Nat /\ Inhale > 0
  /\ Hold \in Nat
  /\ Exhale \in Nat /\ Exhale > 0
  /\ Rest \in Nat
  /\ RampLead \in Nat
  /\ RampLead <= Inhale
  /\ MaxElapsed \in Nat /\ MaxElapsed > 0

VARIABLES elapsed, stimActive, wasStimulating

CycleLength == Inhale + Hold + Exhale + Rest
RampStart   == Inhale - RampLead
StimEnd     == Inhale + Hold + Exhale

\* Pure function: stim should be on at this cycle position
ShouldStim(pos) ==
  /\ pos >= RampStart
  /\ pos < StimEnd

TypeOK ==
  /\ elapsed \in 0..MaxElapsed
  /\ stimActive \in BOOLEAN
  /\ wasStimulating \in BOOLEAN

Init ==
  /\ elapsed = 0
  /\ stimActive = FALSE
  /\ wasStimulating = FALSE

\* One second of session progress (edge-triggered memory like the Swift engine)
Tick ==
  /\ elapsed < MaxElapsed
  /\ LET pos == elapsed % CycleLength
         want == ShouldStim(pos)
     IN /\ stimActive' = want
        /\ wasStimulating' = want
        /\ elapsed' = elapsed + 1

\* Terminal stutter so TLC does not flag expected end-of-bound as deadlock
Done ==
  /\ elapsed = MaxElapsed
  /\ UNCHANGED <<elapsed, stimActive, wasStimulating>>

Next == Tick \/ Done

Spec == Init /\ [][Next]_<<elapsed, stimActive, wasStimulating>>

\* After every tick, stimActive matches pure ShouldStim at the *previous*
\* elapsed (the tick that just applied). At Init, elapsed=0 and stim=FALSE.
\* Post-tick: stimActive = ShouldStim((elapsed-1) % CycleLength) when elapsed > 0.
InvStimMatchesPure ==
  elapsed = 0
    \/ stimActive = ShouldStim((elapsed - 1) % CycleLength)

\* Stim only inside the designed window (using pure pos for current elapsed-1)
InvStimOnlyInWindow ==
  stimActive => ShouldStim((elapsed - 1) % CycleLength) \/ elapsed = 0

\* Never stim at pure pos before ramp or after stim end (at last applied second)
InvNoEarlyStim ==
  elapsed > 0 =>
    LET pos == (elapsed - 1) % CycleLength
    IN (pos < RampStart \/ pos >= StimEnd) => ~stimActive

=============================================================================
