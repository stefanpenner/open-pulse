# Open Pulse

<p align="center">
  <img src="icon.svg" width="128" height="128" alt="Open Pulse app icon">
</p>

An iOS app that controls a [Pulsetto](https://pulsetto.tech) neck-worn device over Bluetooth.

<p align="center">
  <img src="screenshot-home.png" width="280" alt="Home screen with duration and intensity controls">
</p>

## Why

The Pulsetto app needs an account and a subscription. Open Pulse is open source and private. It has no account, no subscription, no network access, and no tracking. It needs iOS 26 or later.

## What

- Six modes: Stressed, Anxious, Can't Sleep, Foggy, Aching, and Custom.
- A tapper that plays a tick-tock sound and haptic taps.
- Battery level and signal strength of the device.
- Session-end alerts and a Live Activity.
- Mindful Minutes written to Apple Health. The app does not read Health.

| Feeling | Default | Behavior |
|---------|---------|----------|
| Stressed | 6 min | Both sides, steady intensity |
| Anxious | 5 min | Paced breathing, gated by the exhale |
| Can't Sleep | 10 min | Rotating channels, fade-out |
| Foggy | 6 min | Left side, 30 s on and 30 s off |
| Aching | 8 min | Wave, or burst |

This app is not a medical treatment. Parameter notes and citations are in [research.md](research.md).

## How

Build:

```bash
xcodebuild -project OpenPulse.xcodeproj -scheme OpenPulse \
  -destination 'generic/platform=iOS' build
```

Run: open `OpenPulse.xcodeproj` in Xcode, choose a device, and press Run.

Test. Fast tests (pure logic, on the Mac, about 3 s). `Package.swift` lists the files.

```bash
swift test
```

All tests (on the simulator, about 1.5 s after the build). Build once, then run:

```bash
D='platform=iOS Simulator,name=iPhone 17'
xcodebuild build-for-testing -project OpenPulse.xcodeproj -scheme OpenPulse -destination "$D" -derivedDataPath build/sim -quiet
xcodebuild test-without-building -project OpenPulse.xcodeproj -scheme OpenPulse -destination "$D" -derivedDataPath build/sim
```

Make each view model in a test with `testVM(...)`. It uses fakes for ActivityKit, HealthKit,
notifications, and audio. The real services make slow sync calls to iOS.

Built on the work of [PulseLibre](https://github.com/jooray/PulseLibre) by Juraj Bednar, [hydrasparx/pulsetto](https://github.com/hydrasparx/pulsetto), and [pulse-libre](https://github.com/parallaxintelligencepartnership/pulse-libre).
License: [GLWTS](LICENSE).
