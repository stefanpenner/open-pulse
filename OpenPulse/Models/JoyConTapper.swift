import Foundation

/// Which Joy-Con plays which side of the tapper. Pure: no GameController types.
enum JoyConTapper {
    enum Kind: Equatable { case left, right, pair }
    enum Part: Equatable { case whole, leftHandle, rightHandle }

    struct Candidate: Equatable {
        let id: Int
        let kind: Kind
    }

    struct Slot: Equatable {
        let controller: Int
        let part: Part
    }

    struct Plan: Equatable {
        var left: Slot?
        var right: Slot?

        var isEmpty: Bool { left == nil && right == nil }

        var covered: Set<BilateralTicks.Side> {
            var sides: Set<BilateralTicks.Side> = []
            if left != nil { sides.insert(.left) }
            if right != nil { sides.insert(.right) }
            return sides
        }

        /// Sides no Joy-Con covers. The phone taps these.
        var phoneSides: Set<BilateralTicks.Side> { Set([BilateralTicks.Side.left, .right]).subtracting(covered) }
    }

    /// The Joy-Con kind from the controller name or product category. Nil for any other device.
    /// Apple has no Joy-Con constant, so this reads the name text.
    static func kind(name: String?, category: String?) -> Kind? {
        let text = [name, category].compactMap { $0 }.joined(separator: " ").lowercased()
        guard text.contains("joy-con") || text.contains("joycon") || text.contains("joy con") else { return nil }
        if ["(l/r)", "l/r", "(l+r)", "pair"].contains(where: text.contains) { return .pair }
        if text.contains("(l)") || text.contains("left") || text.hasSuffix(" l") { return .left }
        if text.contains("(r)") || text.contains("right") || text.hasSuffix(" r") { return .right }
        return nil
    }

    /// Single Joy-Cons take their own side first. A pair fills any side left empty.
    static func plan(_ candidates: [Candidate]) -> Plan {
        var plan = Plan()
        plan.left = candidates.first { $0.kind == .left }.map { Slot(controller: $0.id, part: .whole) }
        plan.right = candidates.first { $0.kind == .right }.map { Slot(controller: $0.id, part: .whole) }
        guard let pair = candidates.first(where: { $0.kind == .pair }) else { return plan }
        plan.left = plan.left ?? Slot(controller: pair.id, part: .leftHandle)
        plan.right = plan.right ?? Slot(controller: pair.id, part: .rightHandle)
        return plan
    }

    static func status(_ plan: Plan) -> String {
        switch (plan.left != nil, plan.right != nil) {
        case (true, true): "Left and right Joy-Con ready."
        case (true, false): "Left Joy-Con ready. The phone taps the right beat."
        case (false, true): "Right Joy-Con ready. The phone taps the left beat."
        case (false, false): "No Joy-Con found. Pair them in Bluetooth settings."
        }
    }
}
