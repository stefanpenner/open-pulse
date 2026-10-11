--------------------------- MODULE SleepPhases ---------------------------
\* Sleep mode: 5 equal-length channel phases D→A→D→C→D over the session.
\* phaseLen is fixed at Init (matches app phaseLengthSeconds) so ±time does not rewind.
\* fadedFloor mirrors app fadeFloor — never re-raise comfort after protocol fade.

EXTENDS Naturals

CONSTANTS MaxElapsed, InitTotal

ASSUME
  /\ MaxElapsed \in Nat /\ MaxElapsed > 0
  /\ InitTotal \in Nat /\ InitTotal >= 5

VARIABLES elapsed, phaseIndex, totalDuration, phaseLen, lastFade, fadedFloor, baseStrength

PhaseOf(e, plen) ==
  IF plen = 0 THEN 0
  ELSE IF e \div plen > 4 THEN 4
  ELSE e \div plen

\* Fade: last 20% of live total — shallow then deep (−1 then −2), floor 1
FadeOf(e, total, base) ==
  LET fadeStart == (total * 4) \div 5 IN
  IF e < fadeStart \/ total <= fadeStart THEN base
  ELSE
    LET fadeLen == total - fadeStart
        fadeElapsed == e - fadeStart
        fadeMid == fadeLen \div 2
        step == IF fadeElapsed < fadeMid THEN 1 ELSE 2
        raw == IF base > step THEN base - step ELSE 1
    IN IF raw < 1 THEN 1 ELSE raw

\* Comfort: never re-raise past fadedFloor (extend mid-fade)
ComfortOf(e, total, base, floor) ==
  LET raw == FadeOf(e, total, base) IN
  IF floor > 0 /\ floor < base /\ floor < raw THEN floor ELSE raw

\* Update protocol floor when settled below base
NextFloor(comfort, base, floor) ==
  IF comfort < base
  THEN IF floor = 0 \/ comfort < floor THEN comfort ELSE floor
  ELSE floor

TypeOK ==
  /\ elapsed \in 0..MaxElapsed
  /\ phaseIndex \in 0..4
  /\ totalDuration \in InitTotal..(InitTotal + 60)
  /\ phaseLen = InitTotal \div 5
  /\ lastFade \in 0..9
  /\ fadedFloor \in 0..9
  /\ baseStrength = 5

Init ==
  /\ elapsed = 0
  /\ phaseIndex = 0
  /\ totalDuration = InitTotal
  /\ phaseLen = InitTotal \div 5
  /\ lastFade = 0
  /\ fadedFloor = 0
  /\ baseStrength = 5

Tick ==
  /\ elapsed < MaxElapsed
  /\ elapsed' = elapsed + 1
  /\ phaseIndex' = PhaseOf(elapsed, phaseLen)
  /\ LET comfort == ComfortOf(elapsed, totalDuration, baseStrength, fadedFloor) IN
       /\ lastFade' = comfort
       /\ fadedFloor' = NextFloor(comfort, baseStrength, fadedFloor)
  /\ UNCHANGED <<totalDuration, phaseLen, baseStrength>>

\* User +60s mid-session — phaseLen stays fixed
ExtendTotal ==
  /\ totalDuration = InitTotal
  /\ totalDuration' = InitTotal + 60
  /\ UNCHANGED <<elapsed, phaseIndex, phaseLen, lastFade, fadedFloor, baseStrength>>

Done ==
  /\ elapsed = MaxElapsed
  /\ UNCHANGED <<elapsed, phaseIndex, totalDuration, phaseLen, lastFade, fadedFloor, baseStrength>>

Next == Tick \/ ExtendTotal \/ Done

Spec == Init /\ [][Next]_<<elapsed, phaseIndex, totalDuration, phaseLen, lastFade, fadedFloor, baseStrength>>

InvPhaseInRange == phaseIndex \in 0..4

\* Phase uses fixed phaseLen, never live totalDuration÷5
InvPhaseMatchesPure ==
  elapsed = 0 \/ phaseIndex = PhaseOf(elapsed - 1, phaseLen)

\* Never re-raise above protocol floor once faded
InvNoReraise ==
  fadedFloor = 0 \/ lastFade <= fadedFloor

\* Floor never exceeds base
InvFloorAtMostBase ==
  fadedFloor <= baseStrength

\* phaseLen immutable after Init
InvPhaseLenFixed == phaseLen = InitTotal \div 5

=============================================================================
