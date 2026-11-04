import Foundation
import Testing
@testable import OpenPulse

@Suite("DeviceInfoParser")
struct DeviceInfoParserTests {
    @Test("Firmware reply")
    func firmware() {
        #expect(DeviceInfoParser.parse("fw:1.1.22") == .firmware("1.1.22"))
    }

    @Test("Firmware reply with space and line end")
    func firmwareSpaced() {
        #expect(DeviceInfoParser.parse("fw: 1.1.22\r\n") == .firmware("1.1.22"))
    }

    @Test("Name reply")
    func name() {
        #expect(DeviceInfoParser.parse("Pulsetto_ST_02\n") == .name("Pulsetto_ST_02"))
    }

    @Test("Other replies are not device info")
    func otherReplies() {
        #expect(DeviceInfoParser.parse("Batt: 3.95") == nil)
        #expect(DeviceInfoParser.parse("mode:3") == nil)
        #expect(DeviceInfoParser.parse("") == nil)
        #expect(DeviceInfoParser.parse("fw:") == nil)
        #expect(DeviceInfoParser.parse("fw:   \n") == nil)
        #expect(DeviceInfoParser.parse("Pulsetto:x") == nil)
        #expect(DeviceInfoParser.parse("\u{0}\u{1}junk") == nil)
        #expect(DeviceInfoParser.parse("fw:" + String(repeating: "9", count: 100)) == nil)
    }

    @Test("Footer text joins the known parts")
    func footer() {
        #expect(DeviceInfoParser.footer(name: "Pulsetto_ST_02", firmware: "1.1.22") == "Pulsetto_ST_02 · firmware 1.1.22")
        #expect(DeviceInfoParser.footer(name: nil, firmware: "1.1.22") == "firmware 1.1.22")
        #expect(DeviceInfoParser.footer(name: "Pulsetto_ST_02", firmware: nil) == "Pulsetto_ST_02")
        #expect(DeviceInfoParser.footer(name: nil, firmware: nil) == nil)
    }
}
