import Testing
@testable import OpenPulse

@Suite("LinkQuality")
struct LinkQualityTests {
    @Test("RSSI maps to three levels")
    func levels() {
        #expect(LinkQuality.level(rssi: -50) == .good)
        #expect(LinkQuality.level(rssi: -70) == .good)
        #expect(LinkQuality.level(rssi: -71) == .fair)
        #expect(LinkQuality.level(rssi: -85) == .fair)
        #expect(LinkQuality.level(rssi: -86) == .weak)
    }

    @Test("One bad sample does not flip the level")
    func medianIgnoresSpike() {
        var meter = LinkQualityMeter()
        for rssi in [-60, -62, -61, -95, -60] { _ = meter.add(rssi: rssi) }
        #expect(meter.add(rssi: -61) == .good)
    }

    @Test("A steady drop shows weak")
    func steadyDrop() {
        var meter = LinkQualityMeter()
        var last: LinkQuality?
        for rssi in [-60, -90, -91, -92, -93] { last = meter.add(rssi: rssi) }
        #expect(last == .weak)
    }

    @Test("127 means no reading and keeps the level")
    func unavailableIgnored() {
        var meter = LinkQualityMeter()
        #expect(meter.add(rssi: 127) == nil)
        _ = meter.add(rssi: -60)
        #expect(meter.add(rssi: 127) == .good)
    }

    @Test("Reset drops old samples")
    func resetClears() {
        var meter = LinkQualityMeter()
        _ = meter.add(rssi: -95)
        meter.reset()
        #expect(meter.add(rssi: -60) == .good)
    }

    @Test("Only weak has a hint, and each level has a label")
    func copy() {
        #expect(LinkQuality.weak.hint != nil)
        #expect(LinkQuality.good.hint == nil)
        #expect(LinkQuality.fair.hint == nil)
        #expect(Set([LinkQuality.good, .fair, .weak].map(\.label)).count == 3)
        #expect(LinkQuality.good.bars > LinkQuality.fair.bars)
        #expect(LinkQuality.fair.bars > LinkQuality.weak.bars)
    }
}
