import Foundation

/// Which Joy-Con plays which side of the tapper. Pure: no GameController types.
enum JoyConTapper {
    enum Kind: Equatable { case left, right, pair }
    enum Part: Equatable { case whole, leftHandle, rightHandle }

    struct Candidate: Equatable {
        let id: Int
        let kind: Kind
        /// False when the controller has no haptics, or a pair cannot split its handles.
        var canTap = true
    }

    /// Which handle localities a controller supports.
    struct Handles: Equatable {
        let left: Bool
        let right: Bool
    }

    /// What the app taps now. Mirrors `Reapply` in specs/JoyConTapper.tla.
    struct Routing: Equatable {
        let phone: Set<BilateralTicks.Side>
        let plan: Plan
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

    /// The Joy-Con kind from the product category or the name. Nil for any other device.
    /// iOS 16+ reports the category "Nintendo Switch Joy-Con (L)", "(R)", or "(L/R)".
    /// Apple has no Joy-Con constant, so this reads the text. The category comes first.
    static func kind(name: String?, category: String?) -> Kind? {
        guard isJoyCon(name: name, category: category) else { return nil }
        return sideKind(category) ?? sideKind(name)
    }

    /// A Joy-Con with its tap ability, or nil for any other device.
    /// Order: the category, then the name, then the handle localities.
    /// The text is exact (SDL reads it). A single Joy-Con may list both handles, so localities alone could call it a pair.
    static func classify(name: String?, category: String?, haptics: Handles?) -> (kind: Kind, canTap: Bool)? {
        guard isJoyCon(name: name, category: category) else { return nil }
        let kind = sideKind(category) ?? sideKind(name) ?? localityKind(haptics)
        guard let kind else { return nil }
        guard let haptics else { return (kind, false) }
        // A pair taps by handle. Without both handles it would tap both sides at once.
        return (kind, kind != .pair || (haptics.left && haptics.right))
    }

    private static func isJoyCon(name: String?, category: String?) -> Bool {
        let text = [name, category].compactMap { $0 }.joined(separator: " ").lowercased()
        return ["joy-con", "joycon", "joy con"].contains(where: text.contains)
    }

    private static func sideKind(_ raw: String?) -> Kind? {
        guard let text = raw?.lowercased() else { return nil }
        if ["(l/r)", "l/r", "(l+r)", "pair"].contains(where: text.contains) { return .pair }
        if text.contains("(l)") || text.contains("left") || text.hasSuffix(" l") { return .left }
        if text.contains("(r)") || text.contains("right") || text.hasSuffix(" r") { return .right }
        return nil
    }

    /// One handle: that side. Both handles: a pair. None: no answer.
    private static func localityKind(_ haptics: Handles?) -> Kind? {
        switch (haptics?.left, haptics?.right) {
        case (true?, true?): .pair
        case (true?, _): .left
        case (_, true?): .right
        default: nil
        }
    }

    /// Who taps each side. Each side has one player while the session plays with haptics on.
    /// A controller that cannot tap, or whose engine failed, hands its side to the phone.
    static func route(
        haptics: Bool,
        joyCon: Bool,
        playing: Bool,
        candidates: [Candidate],
        failed: Set<Int>
    ) -> Routing {
        guard playing, haptics else { return Routing(phone: [], plan: Plan()) }
        let usable = candidates.filter { $0.canTap && !failed.contains($0.id) }
        let plan = joyCon ? plan(usable) : Plan()
        return Routing(phone: plan.phoneSides, plan: plan)
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
