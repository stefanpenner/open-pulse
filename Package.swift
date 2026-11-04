// swift-tools-version: 6.2
// Fast tests: the pure logic of OpenPulse builds for macOS and runs with `swift test`.
// No simulator, no app build. The Xcode project still owns the app.
// The target is named OpenPulse so `@testable import OpenPulse` works in both builds.
import PackageDescription

let package = Package(
    name: "OpenPulseCore",
    platforms: [.macOS(.v26)],
    targets: [
        .target(
            name: "OpenPulse",
            path: "OpenPulse",
            sources: [
                "Models/AmbientAudioPolicy.swift",
                "Models/AutonomicState.swift",
                "Models/BLEConstants.swift",
                "Models/BilateralTicks.swift",
                "Models/DeviceInfoParser.swift",
                "Models/JoyConTapper.swift",
                "Models/LinkQuality.swift",
                "Models/BreathPhasePresentation.swift",
                "Models/LiveActivityPresentation.swift",
                "Models/ModeEngine.swift",
                "Models/SessionDurationOptions.swift",
                "Models/SessionHistory.swift",
                "Models/SessionSafety.swift",
                "Models/SoftStart.swift",
                "Models/StimulationMode.swift",
                "Services/MindfulMinutesStore.swift",
                "Services/SerialBLEWriteQueue.swift",
                "Services/SessionEndNotifier.swift",
                "Services/SessionReminderScheduler.swift",
                "Services/WriteEpochFence.swift",
                "Views/Theme.swift",
            ]
        ),
        .testTarget(
            name: "OpenPulseTests",
            dependencies: ["OpenPulse"],
            path: "OpenPulseTests",
            sources: [
                "BilateralTicksTests.swift",
                "DeviceInfoParserTests.swift",
                "JoyConTapperTests.swift",
                "LinkQualityTests.swift",
                "LiveActivityPresentationTests.swift",
                "MindfulSessionRangeTests.swift",
                "ModeEngineTests.swift",
                "SerialBLEWriteQueueTests.swift",
                "SessionHistoryTests.swift",
                "SessionSafetyTests.swift",
                "SoftStartTests.swift",
                "WriteEpochFenceTests.swift",
            ]
        ),
    ]
)
