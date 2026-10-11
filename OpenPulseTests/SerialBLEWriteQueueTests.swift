import Foundation
import Testing
@testable import OpenPulse

@Suite("SerialBLEWriteQueue")
struct SerialBLEWriteQueueTests {
    @Test("Enqueue program cmds then beginWrite starts single head")
    func singleFlightBegin() {
        var q = SerialBLEWriteQueue()
        q.enqueue("D\n")
        q.enqueue("5\n")
        #expect(q.inFlight == nil)
        #expect(q.waiting == ["D\n", "5\n"])

        let first = q.beginWrite()
        #expect(first == "D\n")
        #expect(q.inFlight == "D\n")
        #expect(q.waiting == ["5\n"])
        #expect(q.beginWrite() == nil, "Cannot start second while in-flight")
    }

    @Test("FinishWrite then next beginWrite")
    func finishThenNext() {
        var q = SerialBLEWriteQueue()
        q.enqueue("D\n")
        q.enqueue("5\n")
        _ = q.beginWrite()
        #expect(q.finishWrite() == "D\n")
        #expect(q.inFlight == nil)
        #expect(q.beginWrite() == "5\n")
    }

    @Test("Enqueue off purges waiting program cmds and sits at head")
    func offPurgesWaiting() {
        var q = SerialBLEWriteQueue()
        q.enqueue("D\n")
        q.enqueue("5\n")
        q.enqueue("0\n")
        #expect(q.waiting == ["0\n"])
        #expect(q.inFlight == nil)
    }

    @Test("cancelProgramWrites keeps in-flight, purges waiting only")
    func cancelDoesNotAbandonInFlight() {
        var q = SerialBLEWriteQueue()
        q.enqueue("D\n")
        q.enqueue("5\n")
        q.enqueue("Q\n")
        _ = q.beginWrite() // D in-flight
        #expect(q.inFlight == "D\n")

        q.cancelProgramWrites()
        #expect(q.inFlight == "D\n", "Single-flight: leave CB write alone")
        #expect(q.waiting.isEmpty)

        // Safety off enqueues behind current in-flight
        q.enqueue("0\n")
        #expect(q.waiting == ["0\n"])
        #expect(q.inFlight == "D\n")

        // Stale D completes — only then can off start
        #expect(q.finishWrite() == "D\n")
        #expect(q.beginWrite() == "0\n")
        #expect(q.inFlight == "0\n")
    }

    @Test("Off after cancel still single-flight")
    func stopWhileStrengthInFlight() {
        var q = SerialBLEWriteQueue()
        q.enqueue("5\n")
        _ = q.beginWrite()
        q.cancelProgramWrites()
        q.enqueue("0\n")
        // Must not start off until finish
        #expect(q.beginWrite() == nil)
        _ = q.finishWrite()
        #expect(q.beginWrite() == "0\n")
    }

    @Test("hasPendingProgramWrites ignores status queries after off")
    func pendingProgramExcludesStatus() {
        var q = SerialBLEWriteQueue()
        q.enqueue("0\n")
        q.enqueue("Q\n")
        q.enqueue("u\n")
        _ = q.beginWrite()
        #expect(q.inFlight == "0\n")
        #expect(!q.hasPendingProgramWrites)
        _ = q.finishWrite()
        #expect(!q.hasPendingProgramWrites, "Only status left")
        #expect(q.hasPending)
    }

    @Test("clear drops in-flight and waiting")
    func clearAll() {
        var q = SerialBLEWriteQueue()
        q.enqueue("D\n")
        _ = q.beginWrite()
        q.enqueue("5\n")
        q.clear()
        #expect(q.inFlight == nil)
        #expect(q.waiting.isEmpty)
        #expect(!q.hasPending)
    }
}
