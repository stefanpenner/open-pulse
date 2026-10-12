import SwiftUI

struct IntensityWaveView: View {
    let strength: Int
    let effectiveStrength: Int?
    let accentColor: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var waveHeight: CGFloat = 48

    private var amplitude: Double {
        Double(effectiveStrength ?? strength) / 9.0
    }

    var body: some View {
        Group {
            if reduceMotion {
                // Static curve — no continuous TimelineView animation
                waveCanvas(phaseOffset: 0)
            } else {
                // Calm motion budget (R46): slower than gadget UI — still.softStart feel
                TimelineView(.animation) { timeline in
                    let date = timeline.date.timeIntervalSinceReferenceDate
                    waveCanvas(phaseOffset: date * 1.15)
                }
            }
        }
        .frame(height: waveHeight)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: amplitude)
        .accessibilityLabel(
            SessionDurationOptions.activeIntensityAccessibility(
                effective: effectiveStrength ?? strength,
                target: strength
            )
        )
    }

    private func waveCanvas(phaseOffset: Double) -> some View {
        Canvas { context, size in
            let midY = size.height / 2
            let amp = amplitude * midY * 0.8

            var path = Path()
            path.move(to: CGPoint(x: 0, y: midY))

            for x in stride(from: 0, through: size.width, by: 1) {
                let normalizedX = x / size.width
                let angle = normalizedX * Double.pi * 4.0 + phaseOffset
                let y = midY + amp * sin(angle)
                path.addLine(to: CGPoint(x: x, y: y))
            }

            var fillPath = path
            fillPath.addLine(to: CGPoint(x: size.width, y: size.height))
            fillPath.addLine(to: CGPoint(x: 0, y: size.height))
            fillPath.closeSubpath()
            context.fill(fillPath, with: .color(accentColor.opacity(0.1)))
            context.stroke(path, with: .color(accentColor.opacity(0.6)), lineWidth: 1.5)
        }
    }
}
