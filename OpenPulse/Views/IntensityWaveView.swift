import SwiftUI

struct IntensityWaveView: View {
    let strength: Int
    let effectiveStrength: Int?
    let accentColor: Color

    @State private var phase: Double = 0

    private var amplitude: Double {
        Double(effectiveStrength ?? strength) / 9.0
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let midY = size.height / 2
                let amp = amplitude * midY * 0.8

                var path = Path()
                path.move(to: CGPoint(x: 0, y: midY))

                let date = timeline.date.timeIntervalSinceReferenceDate
                let phaseOffset = date * 2.0

                for x in stride(from: 0, through: size.width, by: 1) {
                    let normalizedX = x / size.width
                    let angle = normalizedX * Double.pi * 4.0 + phaseOffset
                    let y = midY + amp * sin(angle)
                    path.addLine(to: CGPoint(x: x, y: y))
                }

                // Fill
                var fillPath = path
                fillPath.addLine(to: CGPoint(x: size.width, y: size.height))
                fillPath.addLine(to: CGPoint(x: 0, y: size.height))
                fillPath.closeSubpath()
                context.fill(fillPath, with: .color(accentColor.opacity(0.1)))

                // Stroke
                context.stroke(path, with: .color(accentColor.opacity(0.6)), lineWidth: 1.5)
            }
        }
        .frame(height: 48)
        .animation(.easeInOut(duration: 0.3), value: amplitude)
    }
}
