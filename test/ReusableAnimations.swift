import SwiftUI

/// Horizontal XMB-inspired ribbons that can be placed in any SwiftUI view.
struct XMBWaveAnimation: View {
    var primaryColor: Color = .white
    var accentColor: Color = Color("LoginEntryBox")
    var speed: Double = 1
    var framesPerSecond: Double = 30

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / max(framesPerSecond, 1))) { timeline in
            Canvas { context, size in
                guard size.width > 0 else { return }

                let time = timeline.date.timeIntervalSinceReferenceDate * speed
                let steps = 48

                for layer in 0..<5 {
                    let amplitude = CGFloat(5 + (layer * 2))
                    let baseline = size.height * (0.22 + (CGFloat(layer) * 0.12))
                    let thickness = CGFloat(6 + (layer * 2))
                    let layerSpeed = 0.45 + (Double(layer) * 0.12)
                    let phaseOffset = Double(layer) * 1.7
                    var ribbon = Path()

                    func waveY(at x: CGFloat) -> CGFloat {
                        let progress = Double(x / size.width)
                        let primary = sin((progress * .pi * 2.2) + (time * layerSpeed) + phaseOffset)
                        let secondary = sin((progress * .pi * 4.1) - (time * layerSpeed * 0.65))
                        return baseline + (CGFloat(primary) * amplitude)
                            + (CGFloat(secondary) * amplitude * 0.28)
                    }

                    for step in 0...steps {
                        let x = size.width * CGFloat(step) / CGFloat(steps)
                        let point = CGPoint(x: x, y: waveY(at: x))

                        if step == 0 {
                            ribbon.move(to: point)
                        } else {
                            ribbon.addLine(to: point)
                        }
                    }

                    for step in stride(from: steps, through: 0, by: -1) {
                        let x = size.width * CGFloat(step) / CGFloat(steps)
                        ribbon.addLine(to: CGPoint(x: x, y: waveY(at: x) + thickness))
                    }
                    ribbon.closeSubpath()

                    let colors: [Color] = layer.isMultiple(of: 2)
                        ? [.clear, primaryColor.opacity(0.22), .clear]
                        : [.clear, accentColor.opacity(0.42), .clear]

                    context.fill(
                        ribbon,
                        with: .linearGradient(
                            Gradient(colors: colors),
                            startPoint: CGPoint(x: 0, y: baseline),
                            endPoint: CGPoint(x: size.width, y: baseline)
                        )
                    )
                }
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// Concentric ribbons whose edges ripple around a circle.
struct CircularRippleAnimation: View {
    var primaryColor: Color = .white
    var accentColor: Color = Color("LoginEntryBox")
    var speed: Double = 1.6
    var framesPerSecond: Double = 30
    var thicknessScale: CGFloat = 1

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / max(framesPerSecond, 1))) { timeline in
            Canvas { context, size in
                let diameter = min(size.width, size.height)
                guard diameter > 0 else { return }

                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let availableRadius = (diameter / 2) - 3
                let time = timeline.date.timeIntervalSinceReferenceDate * speed
                let steps = 96

                for layer in 0..<5 {
                    let radiusScale: CGFloat = [0.40, 0.52, 0.64, 0.76, 0.88][layer]
                    let baseRadius = availableRadius * radiusScale
                    let amplitude = CGFloat(0.45 + (Double(layer) * 0.08))
                    let thickness = CGFloat(7.5) * thicknessScale
                    let layerSpeed = 1.25 + (Double(layer) * 0.16)
                    let phaseOffset = Double(layer) * 1.15
                    var ribbon = Path()

                    func point(step: Int, edgeOffset: CGFloat) -> CGPoint {
                        let angle = (Double(step) / Double(steps)) * .pi * 2
                        let primaryRipple = sin((angle * 3) + (time * layerSpeed) + phaseOffset)
                        let secondaryRipple = sin((angle * 5) - (time * layerSpeed * 0.7))
                        let ripple = (CGFloat(primaryRipple) * amplitude)
                            + (CGFloat(secondaryRipple) * amplitude * 0.3)
                        let radius = baseRadius + ripple + edgeOffset

                        return CGPoint(
                            x: center.x + (CGFloat(cos(angle)) * radius),
                            y: center.y + (CGFloat(sin(angle)) * radius)
                        )
                    }

                    for step in 0...steps {
                        let outerPoint = point(step: step, edgeOffset: thickness / 2)
                        if step == 0 {
                            ribbon.move(to: outerPoint)
                        } else {
                            ribbon.addLine(to: outerPoint)
                        }
                    }

                    for step in stride(from: steps, through: 0, by: -1) {
                        ribbon.addLine(to: point(step: step, edgeOffset: -(thickness / 2)))
                    }
                    ribbon.closeSubpath()

                    let ringColor = layer.isMultiple(of: 2) ? primaryColor : accentColor
                    let gradientColors: [Color] = [
                        ringColor.opacity(0.62),
                        ringColor.opacity(0.90),
                        ringColor.opacity(0.68)
                    ]

                    context.fill(
                        ribbon,
                        with: .radialGradient(
                            Gradient(colors: gradientColors),
                            center: center,
                            startRadius: baseRadius - (thickness / 2) - amplitude,
                            endRadius: baseRadius + (thickness / 2) + amplitude
                        )
                    )
                }
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
