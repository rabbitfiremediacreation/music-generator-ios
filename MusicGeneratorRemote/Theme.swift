import SwiftUI

/// Farben der Web-App (static/style.css): Gold = läuft/erledigt/Favorit, Blau = Fokus, Rot = Fehler.
enum Theme {
    static let bg = Color(hex: 0x0c0e12)
    static let panel = Color(hex: 0x1a1d24)
    static let border = Color(hex: 0x2a2e38)
    static let text = Color(hex: 0xeef0f4)
    static let muted = Color(hex: 0x8a90a0)
    static let accent = Color(hex: 0x6d8cff)
    static let gold = Color(hex: 0xd1a75c)
    static let brand = Color(hex: 0xb09f84)     // Füllung der Regler
    static let logoText = Color(hex: 0xddc8aa)
    static let knob = Color(hex: 0x111214)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xff) / 255, green: Double(hex >> 8 & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }
}

/// Regler wie in der Web-App: dicker Balken, Füllstand in Sand, runder Knopf mit dem Wert in der Mitte.
struct BubbleSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    let label: String
    var text: (Double) -> String = { String(Int($0)) }
    var smallText: (Double) -> Bool = { _ in false }   // „AUTO“ passt nur klein in den Knopf
    var onEditingChanged: (Bool) -> Void = { _ in }

    private let barHeight: CGFloat = 44
    private let knob: CGFloat = 46
    @State private var dragging = false

    var body: some View {
        GeometryReader { geo in
            let span = range.upperBound - range.lowerBound
            let p = span > 0 ? min(max((value - range.lowerBound) / span, 0), 1) : 0
            let x = (geo.size.width - knob) * p
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.bg).overlay(Capsule().stroke(Theme.border))
                    .frame(height: barHeight)
                Capsule().fill(Theme.brand)
                    .frame(width: x + knob / 2 + 1, height: barHeight)
                Circle().fill(Theme.knob)
                    .overlay(Circle().stroke(dragging ? Theme.accent : Theme.brand, lineWidth: 2))
                    .overlay(
                        Text(text(value))
                            .font(.system(size: smallText(value) ? 10 : 13, weight: .bold).monospacedDigit())
                            .tracking(smallText(value) ? 0.4 : 0)
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.6).lineLimit(1).padding(.horizontal, 3)
                    )
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                    .offset(x: x)
            }
            .frame(maxHeight: .infinity)
            // Senkrechtes Wischen bleibt beim Scrollen und verstellt nichts,
            // waagerechtes Ziehen verstellt, Antippen springt an die Stelle.
            .overlay(
                SliderTouchArea(
                    onTap: { x in
                        onEditingChanged(true)
                        value = position(x, width: geo.size.width)
                        onEditingChanged(false)
                    },
                    onDrag: { x, state in
                        switch state {
                        case .began:
                            dragging = true
                            onEditingChanged(true)
                            value = position(x, width: geo.size.width)
                        case .changed:
                            value = position(x, width: geo.size.width)
                        default:
                            dragging = false
                            onEditingChanged(false)
                        }
                    }
                )
            )
        }
        .frame(height: knob)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(text(value))
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: value = snap(value + step)
            case .decrement: value = snap(value - step)
            @unknown default: break
            }
            onEditingChanged(false)
        }
    }

    private func position(_ x: CGFloat, width: CGFloat) -> Double {
        let q = min(max((x - knob / 2) / max(width - knob, 1), 0), 1)
        return snap(range.lowerBound + q * (range.upperBound - range.lowerBound))
    }

    private func snap(_ v: Double) -> Double {
        let s = ((v - range.lowerBound) / step).rounded() * step + range.lowerBound
        return min(max(s, range.lowerBound), range.upperBound)
    }
}

/// Berührungsfläche der Regler. Mit UIKit, weil nur so ein senkrechtes Wischen sauber an die
/// umgebende ScrollView geht: Der Zieh-Erkenner startet nur, wenn die Bewegung eher waagerecht ist.
private struct SliderTouchArea: UIViewRepresentable {
    var onTap: (CGFloat) -> Void
    var onDrag: (CGFloat, UIGestureRecognizer.State) -> Void

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.delegate = context.coordinator
        v.addGestureRecognizer(pan)
        v.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:))))
        return v
    }

    func updateUIView(_ v: UIView, context: Context) { context.coordinator.parent = self }
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: SliderTouchArea
        init(_ parent: SliderTouchArea) { self.parent = parent }

        @objc func tap(_ g: UITapGestureRecognizer) { parent.onTap(g.location(in: g.view).x) }
        @objc func pan(_ g: UIPanGestureRecognizer) { parent.onDrag(g.location(in: g.view).x, g.state) }

        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let pan = g as? UIPanGestureRecognizer else { return true }
            let v = pan.velocity(in: pan.view)
            return abs(v.x) > abs(v.y)
        }
    }
}

/// Würfel-Knopf wie in der Web-App: umrandetes Kästchen, dreht sich beim Würfeln.
struct DiceButton: View {
    let label: String
    let action: () -> Void
    @State private var turns = 0.0

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.25)) { action() }
            withAnimation(.easeOut(duration: 0.35)) { turns += 1 }
        } label: {
            Image(systemName: "die.face.5")
                .font(.system(size: 17))
                .rotationEffect(.degrees(turns * 360))
                .foregroundStyle(Theme.muted)
                .frame(width: 38, height: 32)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .sensoryFeedback(.impact(weight: .light), trigger: turns)
        .accessibilityLabel(label)
    }
}

/// Knopf wie „Generieren“ in der Web-App: dunkler Verlauf, sandfarbene Schrift.
struct AktionButtonStyle: ButtonStyle {
    var strong = false   // Generieren-Leiste: goldener Rand, hellere Schrift

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold)).tracking(0.8)
            .foregroundStyle(strong ? Color(hex: 0xf0dcba) : Theme.logoText)
            .shadow(color: .black.opacity(0.65), radius: 1, y: 1)
            .padding(.horizontal, 22)
            .frame(height: 44)
            .background(
                LinearGradient(colors: configuration.isPressed ? [Color(hex: 0x2b2c2c), Color(hex: 0x3a3b3c)]
                                                               : [Color(hex: 0x434445), Color(hex: 0x2b2c2c)],
                               startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 6)
            )
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(strong ? Theme.gold : Theme.border))
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
