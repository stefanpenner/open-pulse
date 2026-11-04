---- MODULE PendingOff ----
\* Pending-off vs pack stim. Reduced from SessionViewModel + SerialBLEWriteQueue.
\*
\* Assumption: the pack keeps the last accepted program until it accepts off.
\* A withResponse success means the pack applied that command.
\* The app never reads a stim bit. hw is the pack, not a Swift field.
\*
\* Policy that must hold:
\*   Arm pending before a program can apply.
\*   A running off-ACK does not clear pending. The next tick can send stim.
\*   Idle or pause clears only when off succeeded and no program remains.
\*   Stop, pause, and expire set pending before the write.
\*   A link drop sets pending.
\*   A clean kill keeps phase, pending, and hw. It cannot send.
\*   A paused restore forces pending. A running restore keeps the armed flag.
\*
\* AckClearsWhileProg TRUE is the old running-clear bug.
\* ArmBeforeProg FALSE is the old missing-arm bug.

EXTENDS Integers, Sequences

CONSTANTS StopSetsPending, DropSetsPending, AckClearsWhileProg, ArmBeforeProg

VARIABLES
  phase,     \* "Idle" | "Run" | "Pause"
  ready,     \* UART up and the process is alive
  pending,   \* durable "send off" flag
  hw,        \* pack is stimulating
  alive,     \* process exists
  offline,   \* link dropped while this process was alive
  waiting,   \* not-yet-started commands. "Off" is only at the head.
  fly,       \* "None" | "Off" | "Prog"
  applied    \* pack applied fly; the host has not observed it yet

vars == <<phase, ready, pending, hw, alive, offline, waiting, fly, applied>>

Phase == {"Idle", "Run", "Pause"}
Cmd == {"Off", "Prog"}

HasProg(q) == \E i \in 1..Len(q) : q[i] = "Prog"

TypeOK ==
  /\ phase \in Phase
  /\ ready \in BOOLEAN
  /\ pending \in BOOLEAN
  /\ hw \in BOOLEAN
  /\ alive \in BOOLEAN
  /\ offline \in BOOLEAN
  /\ fly \in ({"None"} \cup Cmd)
  /\ applied \in BOOLEAN
  /\ waiting \in Seq(Cmd)
  /\ Len(waiting) <= 2
  /\ \A i \in 1..Len(waiting) : waiting[i] = "Off" => i = 1
  /\ applied => fly \in Cmd
  /\ ready => alive
  /\ ~alive => ~ready

\* Idle or paused, flag clear ⇒ pack is off.
InvCover ==
  (phase \in {"Idle", "Pause"} /\ ~pending) => ~hw

\* A link drop in this process arms the flag. A clean kill does not.
InvOfflineArms == offline => pending

\* Phone-shaped residue: flag set, pack still on, no live UART.
Residue ==
  /\ phase \in {"Idle", "Pause"}
  /\ pending
  /\ hw
  /\ ~ready

\* Bait. The bait cfg must fail. Residue stays reachable.
InvNoResidue == ~Residue

\* Dead process, pack still on, flag clear.
\* Holds when pending is armed before stim and a running off-ACK does not clear it.
InvDeadHwFlag == (~alive /\ hw) => pending

Init ==
  /\ phase = "Idle"
  /\ ready = FALSE
  /\ pending = FALSE
  /\ hw = FALSE
  /\ alive = TRUE
  /\ offline = FALSE
  /\ waiting = <<>>
  /\ fly = "None"
  /\ applied = FALSE

\* Start arms the flag before the lead-off or the program can apply.
Start ==
  /\ alive
  /\ phase = "Idle"
  /\ phase' = "Run"
  /\ pending' = IF ArmBeforeProg THEN TRUE ELSE pending
  /\ waiting' = IF ready THEN <<"Off", "Prog">> ELSE waiting
  /\ UNCHANGED <<ready, hw, alive, offline, fly, applied>>

\* Stop, expire, or idle re-off. Code sets pending before the write.
Stop ==
  /\ alive
  /\ phase' = "Idle"
  /\ pending' = IF StopSetsPending THEN TRUE ELSE pending
  /\ waiting' = IF ready THEN <<"Off">> ELSE waiting
  /\ UNCHANGED <<ready, hw, alive, offline, fly, applied>>

Pause ==
  /\ alive
  /\ phase = "Run"
  /\ phase' = "Pause"
  /\ pending' = IF StopSetsPending THEN TRUE ELSE pending
  /\ waiting' = IF ready THEN <<"Off">> ELSE waiting
  /\ UNCHANGED <<ready, hw, alive, offline, fly, applied>>

\* Resume, reconnect, or the long-gap reassert. Arms before the new program.
Reprogram ==
  /\ alive
  /\ ready
  /\ phase = "Run"
  /\ pending' = IF ArmBeforeProg THEN TRUE ELSE pending
  /\ waiting' = <<"Off", "Prog">>
  /\ UNCHANGED <<phase, ready, hw, alive, offline, fly, applied>>

\* Idle or paused retry. Running does not use this loop.
Flush ==
  /\ alive
  /\ ready
  /\ pending
  /\ phase \in {"Idle", "Pause"}
  /\ fly = "None"
  /\ ~applied
  /\ waiting' = <<"Off">>
  /\ UNCHANGED <<phase, ready, pending, hw, alive, offline, fly, applied>>

Pump ==
  /\ alive
  /\ ready
  /\ fly = "None"
  /\ ~applied
  /\ Len(waiting) > 0
  /\ fly' = Head(waiting)
  /\ waiting' = Tail(waiting)
  /\ UNCHANGED <<phase, ready, pending, hw, alive, offline, applied>>

\* Pack accepts the in-flight write. The host has not seen it yet.
DeviceApply ==
  /\ fly \in Cmd
  /\ ~applied
  /\ applied' = TRUE
  /\ hw' = (fly = "Prog")
  /\ UNCHANGED <<phase, ready, pending, alive, offline, waiting, fly>>

\* Host sees success. finishWrite runs before the flag check, then pump.
\* A running off-ACK clears only when AckClearsWhileProg (the old bug).
HostAck ==
  /\ alive
  /\ ready
  /\ applied
  /\ LET clear ==
       fly = "Off" /\ (
         (phase # "Run" /\ ~HasProg(waiting))
         \/ (phase = "Run" /\ AckClearsWhileProg))
     IN pending' = IF clear THEN FALSE ELSE pending
  /\ fly' = "None"
  /\ applied' = FALSE
  /\ UNCHANGED <<phase, ready, hw, alive, offline, waiting>>

\* Host sees failure. The pack did not apply the write.
\* A failed off while running reasserts off, then the program, and arms the flag.
\* A failed off while idle or paused keeps the flag and sends off again.
HostNack ==
  /\ alive
  /\ ready
  /\ fly \in Cmd
  /\ ~applied
  /\ IF fly = "Off" /\ phase = "Run" THEN
       /\ waiting' = <<"Off", "Prog">>
       /\ pending' = IF ArmBeforeProg THEN TRUE ELSE pending
     ELSE IF fly = "Off" THEN
       /\ waiting' = <<"Off">>
       /\ pending' = TRUE
     ELSE
       /\ waiting' = waiting
       /\ pending' = pending
  /\ fly' = "None"
  /\ UNCHANGED <<phase, ready, hw, alive, offline, applied>>

\* Host misses a success. The pack already applied it. The flag stays.
LostAck ==
  /\ alive
  /\ ready
  /\ applied
  /\ fly' = "None"
  /\ applied' = FALSE
  /\ UNCHANGED <<phase, ready, pending, hw, alive, offline, waiting>>

DropKeep ==
  /\ alive
  /\ ready
  /\ ready' = FALSE
  /\ offline' = TRUE
  /\ waiting' = <<>>
  /\ fly' = "None"
  /\ applied' = FALSE
  /\ pending' = IF DropSetsPending THEN TRUE ELSE pending
  /\ UNCHANGED <<phase, hw, alive>>

\* The in-flight write lands as the link dies. The host does not see it.
DropApply ==
  /\ alive
  /\ ready
  /\ fly \in Cmd
  /\ ready' = FALSE
  /\ offline' = TRUE
  /\ hw' = (fly = "Prog")
  /\ waiting' = <<>>
  /\ fly' = "None"
  /\ applied' = FALSE
  /\ pending' = IF DropSetsPending THEN TRUE ELSE pending
  /\ UNCHANGED <<phase, alive>>

\* Process death. Disk keeps phase, pending, hw, and offline.
Kill ==
  /\ alive
  /\ alive' = FALSE
  /\ ready' = FALSE
  /\ waiting' = <<>>
  /\ fly' = "None"
  /\ applied' = FALSE
  /\ UNCHANGED <<phase, pending, hw, offline>>

\* Relaunch inside the auto-pause gap. Running row. Flag is whatever disk had.
LaunchRun ==
  /\ ~alive
  /\ phase = "Run"
  /\ alive' = TRUE
  /\ ready' = FALSE
  /\ UNCHANGED <<phase, pending, hw, offline, waiting, fly, applied>>

\* Relaunch past the gap, or a paused row. Code forces the flag.
LaunchPause ==
  /\ ~alive
  /\ phase \in {"Run", "Pause"}
  /\ alive' = TRUE
  /\ phase' = "Pause"
  /\ pending' = TRUE
  /\ ready' = FALSE
  /\ offline' = FALSE
  /\ UNCHANGED <<hw, waiting, fly, applied>>

LaunchIdle ==
  /\ ~alive
  /\ phase = "Idle"
  /\ alive' = TRUE
  /\ ready' = FALSE
  /\ UNCHANGED <<phase, pending, hw, offline, waiting, fly, applied>>

\* Link up. A running session arms the flag before the program is queued.
BecomeReady ==
  /\ alive
  /\ ~ready
  /\ fly = "None"
  /\ ~applied
  /\ ready' = TRUE
  /\ offline' = FALSE
  /\ pending' = IF phase = "Run" /\ ArmBeforeProg THEN TRUE ELSE pending
  /\ waiting' =
       IF phase = "Run" THEN <<"Off", "Prog">>
       ELSE IF pending THEN <<"Off">>
       ELSE <<>>
  /\ UNCHANGED <<phase, hw, alive, fly, applied>>

Next ==
  \/ Start
  \/ Stop
  \/ Pause
  \/ Reprogram
  \/ Flush
  \/ Pump
  \/ DeviceApply
  \/ HostAck
  \/ HostNack
  \/ LostAck
  \/ DropKeep
  \/ DropApply
  \/ Kill
  \/ LaunchRun
  \/ LaunchPause
  \/ LaunchIdle
  \/ BecomeReady

Spec == Init /\ [][Next]_vars
====
