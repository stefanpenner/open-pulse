import Testing
@testable import OpenPulse

@Suite("JoyConTapper")
struct JoyConTapperTests {
    typealias T = JoyConTapper

    @Test("Side comes from the controller name")
    func kindFromName() {
        #expect(T.kind(name: "Joy-Con (L)", category: nil) == .left)
        #expect(T.kind(name: "Joy-Con (R)", category: nil) == .right)
        #expect(T.kind(name: "Joy-Con (L/R)", category: nil) == .pair)
        #expect(T.kind(name: "Nintendo Switch Joy-Con Left", category: nil) == .left)
        #expect(T.kind(name: nil, category: "Joy-Con R") == .right)
    }

    @Test("Other controllers and unknown sides are not Joy-Cons")
    func kindRejects() {
        #expect(T.kind(name: "Pro Controller", category: nil) == nil)
        #expect(T.kind(name: "DualSense", category: "DualSense") == nil)
        #expect(T.kind(name: "Joy-Con", category: nil) == nil)
        #expect(T.kind(name: nil, category: nil) == nil)
    }

    @Test("Two single Joy-Cons: left plays left, right plays right")
    func twoSingles() {
        let plan = T.plan([.init(id: 0, kind: .right), .init(id: 1, kind: .left)])
        #expect(plan.left == .init(controller: 1, part: .whole))
        #expect(plan.right == .init(controller: 0, part: .whole))
        #expect(plan.phoneSides.isEmpty)
    }

    @Test("A combined pair uses its left and right handles")
    func pair() {
        let plan = T.plan([.init(id: 3, kind: .pair)])
        #expect(plan.left == .init(controller: 3, part: .leftHandle))
        #expect(plan.right == .init(controller: 3, part: .rightHandle))
        #expect(plan.phoneSides.isEmpty)
    }

    @Test("One Joy-Con covers its side. The phone keeps the other")
    func singleLeaves() {
        let left = T.plan([.init(id: 0, kind: .left)])
        #expect(left.left != nil && left.right == nil)
        #expect(left.phoneSides == [.right])
        let right = T.plan([.init(id: 0, kind: .right)])
        #expect(right.phoneSides == [.left])
    }

    @Test("A single Joy-Con beats a pair for its own side")
    func singlesFirst() {
        let plan = T.plan([.init(id: 0, kind: .pair), .init(id: 1, kind: .left)])
        #expect(plan.left == .init(controller: 1, part: .whole))
        #expect(plan.right == .init(controller: 0, part: .rightHandle))
    }

    @Test("No Joy-Con: the phone plays both sides")
    func none() {
        let plan = T.plan([])
        #expect(plan.isEmpty)
        #expect(plan.phoneSides == [.left, .right])
    }

    @Test("Status text names what is paired")
    func status() {
        #expect(T.status(T.plan([])) == "No Joy-Con found. Pair them in Bluetooth settings.")
        #expect(T.status(T.plan([.init(id: 0, kind: .pair)])) == "Left and right Joy-Con ready.")
        #expect(T.status(T.plan([.init(id: 0, kind: .left)])) == "Left Joy-Con ready. The phone taps the right beat.")
        #expect(T.status(T.plan([.init(id: 0, kind: .right)])) == "Right Joy-Con ready. The phone taps the left beat.")
    }

    @Test("Tap pattern for one side keeps only that side")
    func tapsForSides() {
        #expect(BilateralTicks.hapticTaps(for: [.left]).map(\.side) == [.left])
        #expect(BilateralTicks.hapticTaps(for: [.right]).map(\.side) == [.right])
        #expect(BilateralTicks.hapticTaps(for: [.left, .right]) == BilateralTicks.hapticTaps)
        #expect(BilateralTicks.hapticTaps(for: []).isEmpty)
    }
}
