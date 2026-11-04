// UI review gallery. Builds the app, shoots each fixture state in the simulator,
// and joins the shots into one sheet.
//
//   swift scripts/uishot.swift <label> [--vs <base>] [--no-build] [state ...]
//
// Output: build/uishot/<label>/<state>.png and build/uishot/<label>.png.
// With --vs: build/uishot/<base>-vs-<label>.png, the base row above the new row.
import AppKit
import Foundation

let bundleID = "io.github.stefanpenner.OpenPulse"
let simName = "iPhone 17"
let allStates = ["idle", "bluetoothOff", "running", "paused", "settings", "history", "mode"]
let outDir = "build/uishot"
let scale: CGFloat = 1.0 / 3.0

struct Options {
    var label = ""
    var base: String?
    var build = true
    var states: [String] = []
}

func parse(_ args: [String]) -> Options {
    var o = Options()
    var it = args.makeIterator()
    while let a = it.next() {
        switch a {
        case "--vs": o.base = it.next()
        case "--no-build": o.build = false
        default: if o.label.isEmpty { o.label = a } else { o.states.append(a) }
        }
    }
    guard !o.label.isEmpty else { fail("usage: uishot <label> [--vs <base>] [--no-build] [state ...]") }
    if o.states.isEmpty { o.states = allStates }
    return o
}

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data((msg + "\n").utf8))
    exit(1)
}

@discardableResult
func run(_ args: String..., allowFail: Bool = false) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    try! p.run()
    let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    p.waitUntilExit()
    if p.terminationStatus != 0, !allowFail { fail("xcrun \(args.joined(separator: " ")) failed:\n\(out)") }
    return out
}

func prepareSimulator() {
    run("simctl", "boot", simName, allowFail: true)
    run("simctl", "bootstatus", simName, "-b")
    run("simctl", "status_bar", "booted", "override", "--time", "9:41",
        "--batteryLevel", "100", "--batteryState", "charged", "--cellularBars", "4", "--wifiBars", "3")
}

func buildAndInstall() {
    print("building…")
    run("xcodebuild", "build", "-project", "OpenPulse.xcodeproj", "-scheme", "OpenPulse",
        "-destination", "platform=iOS Simulator,name=\(simName)", "-derivedDataPath", "build/sim", "-quiet")
    run("simctl", "install", "booted", "build/sim/Build/Products/Debug-iphonesimulator/OpenPulse.app")
}

func shoot(_ states: [String], into dir: String) {
    try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    for state in states {
        run("simctl", "launch", "--terminate-running-process", "booted", bundleID, "-uiState", state)
        Thread.sleep(forTimeInterval: 2.5)
        run("simctl", "io", "booted", "screenshot", "\(dir)/\(state).png")
        print("  \(state)")
    }
}

// MARK: - Sheet

func image(_ path: String) -> NSImage? { NSImage(contentsOfFile: path) }

/// One row per label, one column per state, a caption above each shot.
func sheet(rows: [String], states: [String], to path: String) {
    let sample = rows.lazy.flatMap { r in states.lazy.compactMap { image("\(outDir)/\(r)/\($0).png") } }.first
    guard let sample else { fail("no shots for \(rows)") }
    let cell = NSSize(width: sample.size.width * scale, height: sample.size.height * scale)
    let gap: CGFloat = 16, caption: CGFloat = 28
    let width = CGFloat(states.count) * (cell.width + gap) + gap
    let rowHeight = caption + cell.height + gap
    let height = CGFloat(rows.count) * rowHeight + gap

    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor(white: 0.93, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    let font: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 16, weight: .semibold)]

    for (r, row) in rows.enumerated() {
        let top = height - gap - CGFloat(r) * rowHeight
        for (c, state) in states.enumerated() {
            let x = gap + CGFloat(c) * (cell.width + gap)
            ("\(row) · \(state)" as NSString).draw(at: NSPoint(x: x, y: top - caption + 6), withAttributes: font)
            image("\(outDir)/\(row)/\(state).png")?
                .draw(in: NSRect(x: x, y: top - caption - cell.height, width: cell.width, height: cell.height))
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print(path)
}

// MARK: - Main

let o = parse(Array(CommandLine.arguments.dropFirst()))
prepareSimulator()
if o.build { buildAndInstall() }
shoot(o.states, into: "\(outDir)/\(o.label)")
sheet(rows: [o.label], states: o.states, to: "\(outDir)/\(o.label).png")
if let base = o.base {
    sheet(rows: [base, o.label], states: o.states, to: "\(outDir)/\(base)-vs-\(o.label).png")
}
