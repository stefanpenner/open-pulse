import Foundation
import Testing
@testable import OpenPulse

@MainActor
private func makeVM() -> (SessionViewModel, MockDeviceTransport) {
    let defaults = UserDefaults(suiteName: "test.devicemode.\(UUID().uuidString)")!
    let mock = MockDeviceTransport()
    let vm = testVM(defaults: defaults, ble: mock)
    mock.becomeReady()
    return (vm, mock)
}

@MainActor
private func startCustom(_ vm: SessionViewModel) {
    vm.selectMode(.custom)
    vm.strength = 5
    vm.start()
}

@Suite("Device mode report")
struct DeviceModeSessionTests {
    @Test("Mode is nil until seen, set by a report, cleared on drop")
    @MainActor func publishesMode() {
        let (_, mock) = makeVM()
        #expect(mock.deviceMode == nil)
        mock.reportMode("mode:D")
        #expect(mock.deviceMode == .bilateral)
        mock.isReady = false
        mock.isConnected = false
        mock.dropLink()
        #expect(mock.deviceMode == nil)
    }

    @Test("Idle with stim on arms pending off and sends off")
    @MainActor func idleOnArmsOff() {
        let (vm, mock) = makeVM()
        mock.reset()
        #expect(!vm.pendingDeactivate)
        mock.reportMode("mode:A")
        #expect(vm.pendingDeactivate)
        #expect(mock.commands.contains("0\n"))
    }

    @Test("Idle mode:0 clears pending off when no write is outstanding")
    @MainActor func idleOffClears() {
        let (vm, mock) = makeVM()
        mock.reportMode("mode:A")
        #expect(vm.pendingDeactivate)
        mock.reportMode("mode:0")
        #expect(!vm.pendingDeactivate)
    }

    @Test("Idle mode:0 keeps pending off while a write is outstanding")
    @MainActor func idleOffKeptWhileWriting() {
        let (vm, mock) = makeVM()
        mock.reportMode("mode:A")
        mock.setPendingWrites(true)
        mock.reportMode("mode:0")
        #expect(vm.pendingDeactivate)
    }

    @Test("Running mode:0 never clears pending off")
    @MainActor func runningOffKeepsFlag() {
        let (vm, mock) = makeVM()
        startCustom(vm)
        #expect(vm.pendingDeactivate)
        mock.reportMode("mode:0")
        #expect(vm.pendingDeactivate)
        #expect(vm.isRunning)
    }

    @Test("Running mismatch reasserts the program on the next tick, session stays")
    @MainActor func runningMismatchReasserts() {
        let (vm, mock) = makeVM()
        startCustom(vm)
        mock.reset()
        mock.reportMode("mode:0")
        #expect(mock.commands.isEmpty, "report alone sends nothing")
        vm.tick()
        #expect(vm.isRunning)
        #expect(mock.commands.first == "0\n")
        #expect(mock.commands.contains("D\n"))
    }

    @Test("Running match does nothing")
    @MainActor func runningMatchQuiet() {
        let (vm, mock) = makeVM()
        startCustom(vm)
        mock.reportMode("mode:D")
        mock.reset()
        vm.tick()
        #expect(mock.commands.isEmpty)
    }

    @Test("A mismatch while writes are outstanding is ignored")
    @MainActor func runningMismatchIgnoredWhileWriting() {
        let (vm, mock) = makeVM()
        startCustom(vm)
        mock.setPendingWrites(true)
        mock.reportMode("mode:0")
        mock.setPendingWrites(false)
        mock.reset()
        vm.tick()
        #expect(mock.commands.isEmpty)
    }
}
