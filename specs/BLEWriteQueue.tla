-------------------------- MODULE BLEWriteQueue --------------------------
\* Serial withResponse write queue:
\* - waiting holds not-yet-started commands only
\* - at most one in-flight
\* - off (0) purges non-off waiting cmds and sits at head

EXTENDS Naturals, Sequences

VARIABLES waiting, flying, cmd, pendingOff
\* flying: whether a write is in flight
\* cmd: 0 = off, 1 = other (meaningful only when flying)

TypeOK ==
  /\ waiting \in Seq({0, 1})
  /\ Len(waiting) <= 6
  /\ flying \in BOOLEAN
  /\ cmd \in {0, 1}
  /\ pendingOff \in BOOLEAN

Init ==
  /\ waiting = << >>
  /\ flying = FALSE
  /\ cmd = 1
  /\ pendingOff = FALSE

EnqueueOther ==
  /\ Len(waiting) < 6
  /\ waiting' = Append(waiting, 1)
  /\ UNCHANGED <<flying, cmd, pendingOff>>

EnqueueOff ==
  /\ pendingOff' = TRUE
  /\ LET purged == SelectSeq(waiting, LAMBDA c: c = 0)
     IN waiting' = IF purged = << >> THEN <<0>> ELSE purged
  /\ UNCHANGED <<flying, cmd>>

StartWrite ==
  /\ ~flying
  /\ Len(waiting) > 0
  /\ flying' = TRUE
  /\ cmd' = Head(waiting)
  /\ waiting' = Tail(waiting)
  /\ UNCHANGED pendingOff

FinishWriteOK ==
  /\ flying
  /\ flying' = FALSE
  /\ pendingOff' = IF cmd = 0 THEN FALSE ELSE pendingOff
  /\ UNCHANGED <<waiting, cmd>>

FinishWriteFail ==
  /\ flying
  /\ flying' = FALSE
  /\ pendingOff' = IF cmd = 0 THEN TRUE ELSE pendingOff
  /\ UNCHANGED <<waiting, cmd>>

Next ==
  \/ EnqueueOther
  \/ EnqueueOff
  \/ StartWrite
  \/ FinishWriteOK
  \/ FinishWriteFail

Spec == Init /\ [][Next]_<<waiting, flying, cmd, pendingOff>>

InvSingleFlight == flying \in BOOLEAN
InvWaitingBound == Len(waiting) <= 6

=============================================================================
