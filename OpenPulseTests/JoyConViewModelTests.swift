import Foundation
import Testing
@testable import OpenPulse

@Suite("SessionViewModel — Joy-Con pairing card")
struct JoyConViewModelTests {
    @MainActor
    private func make(_ audio: NullAmbientAudio) -> SessionViewModel {
        let mock = MockDeviceTransport()
        mock.batteryPercentage = 80
        mock.batterySampleConfirmed = true
        let defaults = UserDefaults(suiteName: "test.joycon.vm.\(UUID().uuidString)")!
        return testVM(defaults: defaults, ble: mock, ambientAudio: audio)
    }

    @Test("The card watches for Joy-Cons only while it shows")
    @MainActor func previewFollowsCard() {
        let audio = NullAmbientAudio()
        let vm = make(audio)
        #expect(!audio.joyConPreview)
        vm.setJoyConPairingVisible(true)
        #expect(audio.joyConPreview)
        vm.setJoyConPairingVisible(false)
        #expect(!audio.joyConPreview)
    }

    @Test("Rows follow found and working Joy-Cons")
    @MainActor func rowsFollow() {
        let audio = NullAmbientAudio()
        let vm = make(audio)
        #expect(vm.joyConPairingRows.map(\.text) == ["Left: not found", "Right: not found"])
        let left = JoyConTapper.plan([.init(id: 0, kind: .left)])
        audio.setPlan(.init(), found: left)
        #expect(vm.joyConPairingRows[0].text.hasPrefix("Left: found, but it cannot tap"))
        audio.setPlan(left)
        #expect(vm.joyConPairingRows.map(\.text) == ["Left: connected", "Right: not found"])
    }

    @Test("Test taps reach the tapper when idle")
    @MainActor func testTapsIdle() {
        let audio = NullAmbientAudio()
        let vm = make(audio)
        audio.setPlan(JoyConTapper.plan([.init(id: 0, kind: .pair)]))
        #expect(vm.canTestJoyCon)
        vm.testJoyConTaps()
        #expect(audio.joyConTestCount == 1)
    }

    @Test("Test taps do nothing with no Joy-Con")
    @MainActor func testTapsNone() {
        let audio = NullAmbientAudio()
        let vm = make(audio)
        #expect(!vm.canTestJoyCon)
    }
}
