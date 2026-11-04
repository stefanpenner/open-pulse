---- MODULE JoyConTapper ----
\* Joy-Con tapper vs phone haptics. Reduced from JoyConTapper (Swift),
\* JoyConHaptics, and SessionAmbientAudio.sync.
\*
\* Controllers the app can see: "L" single left, "R" single right, "P" combined pair.
\* A controller with no haptics, or a pair with no handle localities, is never seen.
\* Single Joy-Cons take their own side first. A pair fills a side left empty.
\* An engine that fails or stops marks its controller failed. The phone takes the side.
\* Failed clears on a connect or the next session start.
\*
\* Policy that must hold while the session plays with haptics on:
\*   Each side has exactly one player: the phone or one Joy-Con.
\*   Nothing taps when the session is not playing or haptics are off.
\*   A disconnect or a failure hands the side back to the phone.
\*   A Joy-Con plays only when the Joy-Con setting is on.
\*
\* Mutants (each must fail in its own .cfg):
\*   RecomputeOnLoss FALSE: a disconnect or failure keeps the old outputs.
\*   PhoneSkipsCovered FALSE: the phone taps every side, even a covered one.
\*   FailedHandsBack FALSE: a failed controller still claims its side.

EXTENDS FiniteSets

CONSTANTS RecomputeOnLoss, PhoneSkipsCovered, FailedHandsBack

VARIABLES
  haptics,   \* Haptic taps setting
  joyCon,    \* Use Joy-Con setting
  playing,   \* session runs: not paused, not in background
  conn,      \* controllers connected and usable
  failed,    \* connected controllers whose engine failed
  phone,     \* sides the phone taps now
  joy        \* sides the Joy-Cons tap now

vars == <<haptics, joyCon, playing, conn, failed, phone, joy>>

Sides == {"l", "r"}
Kinds == {"L", "R", "P"}

\* Sides a set of controllers covers. Single Joy-Cons first. A pair fills what is left.
CoverOf(c) ==
  (IF "L" \in c \/ "P" \in c THEN {"l"} ELSE {}) \cup
  (IF "R" \in c \/ "P" \in c THEN {"r"} ELSE {})

\* Controllers that may claim a side.
LiveOf(c, f) == IF FailedHandsBack THEN c \ f ELSE c

TypeOK ==
  /\ haptics \in BOOLEAN
  /\ joyCon \in BOOLEAN
  /\ playing \in BOOLEAN
  /\ conn \subseteq Kinds
  /\ failed \subseteq conn
  /\ phone \subseteq Sides
  /\ joy \subseteq Sides

\* Each side has one player while tapping.
InvOneOwner ==
  (playing /\ haptics) => (phone \cup joy = Sides /\ phone \cap joy = {})

InvQuiet == ~(playing /\ haptics) => (phone = {} /\ joy = {})

InvJoyOnlyIfOn == joy # {} => joyCon

\* Every Joy-Con side maps to a connected, working controller.
InvJoyBacked == joy \subseteq CoverOf(conn \ failed)

Init ==
  /\ haptics = FALSE /\ joyCon = FALSE /\ playing = FALSE
  /\ conn = {} /\ failed = {}
  /\ phone = {} /\ joy = {}

\* Recompute outputs from the new inputs.
Reapply(h, j, p, c, f) ==
  LET tap == p /\ h
      nj  == IF tap /\ j THEN CoverOf(LiveOf(c, f)) ELSE {}
      np  == IF tap THEN (IF PhoneSkipsCovered THEN Sides \ nj ELSE Sides) ELSE {}
  IN  /\ phone' = np /\ joy' = nj

SetHaptics(b) ==
  /\ haptics' = b /\ UNCHANGED <<joyCon, playing, conn, failed>>
  /\ Reapply(b, joyCon, playing, conn, failed)

SetJoyCon(b) ==
  /\ joyCon' = b /\ UNCHANGED <<haptics, playing, conn, failed>>
  /\ Reapply(haptics, b, playing, conn, failed)

\* A session start retries every failed engine.
Play ==
  /\ ~playing /\ playing' = TRUE /\ failed' = {}
  /\ UNCHANGED <<haptics, joyCon, conn>>
  /\ Reapply(haptics, joyCon, TRUE, conn, {})

Halt ==
  /\ playing /\ playing' = FALSE
  /\ UNCHANGED <<haptics, joyCon, conn, failed>>
  /\ Reapply(haptics, joyCon, FALSE, conn, failed)

Connect(k) ==
  /\ k \notin conn /\ conn' = conn \cup {k} /\ failed' = {}
  /\ UNCHANGED <<haptics, joyCon, playing>>
  /\ Reapply(haptics, joyCon, playing, conn \cup {k}, {})

Disconnect(k) ==
  /\ k \in conn /\ conn' = conn \ {k} /\ failed' = failed \ {k}
  /\ UNCHANGED <<haptics, joyCon, playing>>
  /\ IF RecomputeOnLoss
       THEN Reapply(haptics, joyCon, playing, conn \ {k}, failed \ {k})
       ELSE UNCHANGED <<phone, joy>>

\* An engine stops or fails to start while it plays.
EngineFail(k) ==
  /\ k \in conn /\ k \notin failed /\ joy # {}
  /\ failed' = failed \cup {k}
  /\ UNCHANGED <<haptics, joyCon, playing, conn>>
  /\ IF RecomputeOnLoss
       THEN Reapply(haptics, joyCon, playing, conn, failed \cup {k})
       ELSE UNCHANGED <<phone, joy>>

Next ==
  \/ \E b \in BOOLEAN : SetHaptics(b) \/ SetJoyCon(b)
  \/ Play \/ Halt
  \/ \E k \in Kinds : Connect(k) \/ Disconnect(k) \/ EngineFail(k)

Spec == Init /\ [][Next]_vars

====
