# Open Pulse

<p align="center">
  <img src="icon.svg" width="128" height="128" alt="Open Pulse app icon">
</p>

An iOS app for the [Pulsetto](https://pulsetto.tech) neck device. Version 0.9. Needs iOS 26.

<p align="center">
  <img src="screenshot-home.png" width="280" alt="Home screen with duration and intensity controls">
</p>

## Why

The official app needs an account and an online login. When you are offline, or when its login service is down, you may not be able to use the device.

Open Pulse is an open alternative. It talks to the device directly over Bluetooth. It needs no account and no internet. It sends no data off the phone.

Open Pulse also adds a tapper: a left-right tick-tock sound, phone taps, or both. You can turn it on to run during the session, with the stimulation.

Open Pulse is not made by or affiliated with Pulsetto. Pulsetto is a trademark of its owner.

## How

Run: open `OpenPulse.xcodeproj` in Xcode and press Run.

Test on the Mac (fast):

```bash
swift test
```

Test on the simulator (all tests):

```bash
D='platform=iOS Simulator,name=iPhone 17'
xcodebuild build-for-testing -project OpenPulse.xcodeproj -scheme OpenPulse -destination "$D" -derivedDataPath build/sim -quiet
xcodebuild test-without-building -project OpenPulse.xcodeproj -scheme OpenPulse -destination "$D" -derivedDataPath build/sim
```

## Credits

Inspired by [PulseLibre](https://github.com/jooray/PulseLibre) by Juraj Bednar, [hydrasparx/pulsetto](https://github.com/hydrasparx/pulsetto), and [pulse-libre](https://github.com/parallaxintelligencepartnership/pulse-libre). Their reverse engineering of the device protocol made this app possible. License: [GLWTS](LICENSE).
