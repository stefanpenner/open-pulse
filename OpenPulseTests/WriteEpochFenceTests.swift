import Foundation
import Testing
@testable import OpenPulse

@Suite("WriteEpochFence")
struct WriteEpochFenceTests {
    @Test("Begin then complete is accepted")
    func beginAccepts() {
        var fence = WriteEpochFence()
        fence.beginWrite()
        #expect(fence.acceptsCompletion)
        fence.finish()
        #expect(!fence.acceptsCompletion)
    }

    @Test("Invalidate rejects late completion for previous write")
    func invalidateRejectsStale() {
        var fence = WriteEpochFence()
        fence.beginWrite()
        #expect(fence.acceptsCompletion)
        fence.invalidate()
        #expect(!fence.acceptsCompletion, "Late didWrite after cleanup must not finish new work")
    }

    @Test("New begin after invalidate is accepted")
    func newWriteAfterInvalidate() {
        var fence = WriteEpochFence()
        fence.beginWrite()
        fence.invalidate()
        fence.beginWrite()
        #expect(fence.acceptsCompletion)
        fence.finish()
        #expect(!fence.acceptsCompletion)
    }

    @Test("Double invalidate stays rejected until begin")
    func doubleInvalidate() {
        var fence = WriteEpochFence()
        fence.beginWrite()
        fence.invalidate()
        fence.invalidate()
        #expect(!fence.acceptsCompletion)
        fence.beginWrite()
        #expect(fence.acceptsCompletion)
    }

    @Test("Old stamp does not finish the write that began after invalidate")
    func staleStampDoesNotFinishNewWrite() {
        var fence = WriteEpochFence()
        let old = fence.beginWrite()
        fence.invalidate()
        let new = fence.beginWrite()
        #expect(old != new)
        #expect(!fence.accepts(old), "late didWrite from the old generation must not finish the new write")
        #expect(fence.accepts(new))
        fence.finish()
        #expect(!fence.accepts(new))
    }
}
