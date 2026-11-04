import Testing
@testable import OpenPulse

struct DeviceModeTests {
    @Test func parsesKnownCodes() {
        #expect(DeviceMode(report: "mode:0") == .off)
        #expect(DeviceMode(report: "mode:A") == .left)
        #expect(DeviceMode(report: "mode:C\r\n") == .right)
        #expect(DeviceMode(report: "mode: D") == .bilateral)
    }

    @Test func rejectsOtherText() {
        #expect(DeviceMode(report: "Batt:3.97") == nil)
        #expect(DeviceMode(report: "BR:100") == nil)
        #expect(DeviceMode(report: "mode:") == nil)
        #expect(DeviceMode(report: "mode:B") == nil)
        #expect(DeviceMode(report: "mode:00") == nil)
        #expect(DeviceMode(report: "") == nil)
    }

    @Test func idleOnArmsOff() {
        let a = ModeReportAction.decide(report: .bilateral, isRunning: false, expected: .off, pendingOff: false, quiet: false)
        #expect(a == .armOff)
    }

    @Test func idleOffClearsOnlyWhenQuietAndPending() {
        func d(_ pending: Bool, _ quiet: Bool) -> ModeReportAction {
            .decide(report: .off, isRunning: false, expected: .off, pendingOff: pending, quiet: quiet)
        }
        #expect(d(true, true) == .clearPendingOff)
        #expect(d(true, false) == .ignore)
        #expect(d(false, true) == .ignore)
    }

    @Test func runningMismatchReasserts() {
        func d(_ r: DeviceMode, _ quiet: Bool) -> ModeReportAction {
            .decide(report: r, isRunning: true, expected: .bilateral, pendingOff: true, quiet: quiet)
        }
        #expect(d(.off, true) == .reassert)
        #expect(d(.left, true) == .reassert)
        #expect(d(.bilateral, true) == .ignore)
        #expect(d(.off, false) == .ignore)
    }
}
