import Foundation
import Testing
@testable import OpenPulse

@Suite("BilateralTicks")
struct BilateralTicksTests {
    let rate = 44_100.0

    @Test("Beats alternate left, right, like tappers")
    func alternates() {
        #expect(BilateralTicks.side(beat: 0) == .left)
        #expect(BilateralTicks.side(beat: 1) == .right)
        #expect(BilateralTicks.side(beat: 2) == .left)
        #expect(BilateralTicks.side(beat: 3) == .right)
    }

    @Test("One loop holds a tick and a tock")
    func loopLength() {
        let loop = BilateralTicks.renderLoop(sampleRate: rate)
        let frames = Int(rate * BilateralTicks.beatSeconds) * 2
        #expect(loop.left.count == frames)
        #expect(loop.right.count == frames)
    }

    @Test("Tick plays only left in the first beat, tock only right in the second")
    func sidesStayApart() {
        let loop = BilateralTicks.renderLoop(sampleRate: rate)
        let half = loop.left.count / 2
        #expect(peak(loop.left[..<half]) > 0.05)
        #expect(peak(loop.right[..<half]) == 0)
        #expect(peak(loop.right[half...]) > 0.05)
        #expect(peak(loop.left[half...]) == 0)
    }

    @Test("Clicks stay soft and do not pop at the edges")
    func softEdges() {
        let loop = BilateralTicks.renderLoop(sampleRate: rate)
        #expect(peak(loop.left[...]) <= BilateralTicks.volume)
        #expect(abs(loop.left[0]) < 0.01)
        #expect(abs(loop.left.last!) < 0.0001)
        #expect(abs(loop.right.last!) < 0.0001)
    }

    @Test("Tick is higher than tock")
    func tickHigherThanTock() {
        let loop = BilateralTicks.renderLoop(sampleRate: rate)
        let half = loop.left.count / 2
        #expect(zeroCrossings(loop.left[..<half]) > zeroCrossings(loop.right[half...]))
    }

    private func peak(_ s: ArraySlice<Float>) -> Float {
        s.map(abs).max() ?? 0
    }

    private func zeroCrossings(_ s: ArraySlice<Float>) -> Int {
        zip(s, s.dropFirst()).filter { ($0 < 0) != ($1 < 0) && $0 != 0 && $1 != 0 }.count
    }
}
