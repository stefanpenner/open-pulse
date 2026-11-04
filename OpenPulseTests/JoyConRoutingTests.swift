import Testing
@testable import OpenPulse

// Mirrors specs/JoyConTapper.tla. TLC checks the design. These tests check the Swift.

@Suite("JoyConTapper classify and route")
struct JoyConRoutingTests {
    typealias T = JoyConTapper

    @Test("Apple's category string names the side (SDL: Nintendo Switch Joy-Con (L), (R), (L/R))")
    func realCategoryStrings() {
        let both = T.Handles(left: true, right: true)
        #expect(T.kind(name: "Joy-Con (L)", category: "Nintendo Switch Joy-Con (L)") == .left)
        #expect(T.kind(name: "Joy-Con (R)", category: "Nintendo Switch Joy-Con (R)") == .right)
        #expect(T.kind(name: "Joy-Con (L/R)", category: "Nintendo Switch Joy-Con (L/R)") == .pair)
        #expect(T.classify(name: "x", category: "Nintendo Switch Joy-Con (L/R)", haptics: both)?.kind == .pair)
    }

    @Test("Category beats a wrong name")
    func categoryFirst() {
        let h = T.Handles(left: false, right: false)
        #expect(T.classify(name: "Joy-Con (R)", category: "Nintendo Switch Joy-Con (L)", haptics: h)?.kind == .left)
    }

    @Test("Localities decide a side when the text has none")
    func localitiesFallback() {
        #expect(T.classify(name: "Joy-Con", category: "HID", haptics: .init(left: true, right: false))?.kind == .left)
        #expect(T.classify(name: "Joy-Con", category: "HID", haptics: .init(left: false, right: true))?.kind == .right)
        #expect(T.classify(name: "Joy-Con", category: "HID", haptics: .init(left: true, right: true))?.kind == .pair)
        #expect(T.classify(name: "Joy-Con", category: "HID", haptics: .init(left: false, right: false)) == nil)
        #expect(T.classify(name: "Joy-Con", category: nil, haptics: nil) == nil)
    }

    @Test("A non Joy-Con never classifies, even with both handles")
    func otherDevices() {
        let both = T.Handles(left: true, right: true)
        #expect(T.classify(name: "DualSense", category: "DualSense", haptics: both) == nil)
        #expect(T.classify(name: "Xbox Wireless Controller", category: "Xbox One", haptics: both) == nil)
    }

    @Test("No haptics: found, but it cannot tap")
    func noHaptics() {
        let c = T.classify(name: "Joy-Con (L)", category: nil, haptics: nil)
        #expect(c?.kind == .left)
        #expect(c?.canTap == false)
    }

    @Test("A pair without both handles cannot tap")
    func pairNeedsHandles() {
        #expect(T.classify(name: "Joy-Con (L/R)", category: nil, haptics: .init(left: true, right: false))?.canTap == false)
        #expect(T.classify(name: "Joy-Con (L/R)", category: nil, haptics: .init(left: true, right: true))?.canTap == true)
        #expect(T.classify(name: "Joy-Con (L)", category: nil, haptics: .init(left: false, right: false))?.canTap == true)
    }

    @Test("A Joy-Con that cannot tap leaves its side to the phone")
    func unableCandidate() {
        let r = T.route(haptics: true, joyCon: true, playing: true,
                        candidates: [.init(id: 0, kind: .left, canTap: false)], failed: [])
        #expect(r.plan.isEmpty)
        #expect(r.phone == [.left, .right])
    }

    @Test("A failed controller hands its side back")
    func failedHandsBack() {
        let c: [T.Candidate] = [.init(id: 0, kind: .left), .init(id: 1, kind: .right)]
        let r = T.route(haptics: true, joyCon: true, playing: true, candidates: c, failed: [1])
        #expect(r.plan.left != nil && r.plan.right == nil)
        #expect(r.phone == [.right])
    }

    /// The TLC model, run again here over every input.
    @Test("Each side has exactly one player. Nothing taps when idle")
    func exhaustive() {
        let kinds: [T.Kind] = [.left, .right, .pair]
        let sides: Set<BilateralTicks.Side> = [.left, .right]
        var cases = 0
        for haptics in [false, true] {
            for joyCon in [false, true] {
                for playing in [false, true] {
                    for mask in 0..<8 {
                        for failMask in 0..<8 {
                            for ableMask in 0..<8 {
                                let cands = kinds.enumerated().filter { mask & (1 << $0.offset) != 0 }
                                    .map { T.Candidate(id: $0.offset, kind: $0.element, canTap: ableMask & (1 << $0.offset) != 0) }
                                let failed = Set((0..<3).filter { failMask & (1 << $0) != 0 })
                                let r = T.route(haptics: haptics, joyCon: joyCon, playing: playing,
                                                candidates: cands, failed: failed)
                                cases += 1
                                if playing && haptics {
                                    #expect(r.phone.union(r.plan.covered) == sides)
                                    #expect(r.phone.isDisjoint(with: r.plan.covered))
                                } else {
                                    #expect(r.phone.isEmpty && r.plan.isEmpty)
                                }
                                if !joyCon { #expect(r.plan.isEmpty) }
                                for slot in [r.plan.left, r.plan.right].compactMap({ $0 }) {
                                    let c = cands.first { $0.id == slot.controller }
                                    #expect(c != nil && c!.canTap && !failed.contains(c!.id))
                                }
                            }
                        }
                    }
                }
            }
        }
        #expect(cases == 2 * 2 * 2 * 8 * 8 * 8)
    }
}

@Suite("JoyConPairing text")
struct JoyConPairingTests {
    typealias P = JoyConPairing

    @Test("Each side says connected or not found")
    func rows() {
        let none = P.rows(found: .init(), working: .init())
        #expect(none.map(\.text) == ["Left: not found", "Right: not found"])
        let pair = JoyConTapper.plan([.init(id: 0, kind: .pair)])
        let both = P.rows(found: pair, working: pair)
        #expect(both.map(\.text) == ["Left: connected", "Right: connected"])
        #expect(both.map(\.isReady) == [true, true])
    }

    @Test("A found Joy-Con that cannot tap says the phone taps that side")
    func cannotTap() {
        let found = JoyConTapper.plan([.init(id: 0, kind: .left)])
        let rows = P.rows(found: found, working: .init())
        #expect(rows[0].text == "Left: found, but it cannot tap. The phone taps this side.")
        #expect(rows[1].text == "Right: not found")
    }

    @Test("Accessibility labels read as full sentences")
    func labels() {
        let rows = P.rows(found: .init(), working: .init())
        #expect(rows[0].accessibilityLabel == "Left Joy-Con: not found")
    }

    @Test("Steps are three short lines")
    func steps() {
        #expect(P.steps.count == 3)
        #expect(P.steps.allSatisfy { $0.split(separator: " ").count <= 20 })
        #expect(P.settingsNote.contains("Bluetooth"))
    }

    @Test("Test button is off while a session plays or when nothing can tap")
    func testButton() {
        let pair = JoyConTapper.plan([.init(id: 0, kind: .pair)])
        #expect(P.canTestTaps(working: pair, sessionPlaying: false))
        #expect(!P.canTestTaps(working: pair, sessionPlaying: true))
        #expect(!P.canTestTaps(working: .init(), sessionPlaying: false))
    }
}
