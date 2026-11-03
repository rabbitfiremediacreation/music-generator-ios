import SwiftUI

/// Aufnahmeknopf wie in der Web-App: dunkler Kreis mit Mikrofon in der Farbe der Wortmarke.
/// Gedrückt halten = aufnehmen; dabei wird er rot, außen füllt sich ein Ring bis 30 s, in der Mitte zählt die Sekunde.
/// Mit VoiceOver: einmal aktivieren = Start (nach der Ansage), noch einmal = Stopp.
struct RecordButton: View {
    let recorder: IdeaRecorder
    private let size: CGFloat = 52
    private let red = Color(hex: 0xff5252)

    var body: some View {
        let on = recorder.phase == .recording
        ZStack {
            Circle().fill(on ? Color(hex: 0x2a1517) : Theme.panel)
                .overlay(Circle().stroke(on ? red : Theme.border))
            if on {
                Circle().stroke(red.opacity(0.2), lineWidth: 3).padding(-6)
                Circle().trim(from: 0, to: min(1, recorder.seconds / IdeaRecorder.maxSeconds))
                    .stroke(red, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90)).padding(-6)
                Text("\(Int(recorder.seconds))")
                    .font(.system(size: 16, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color(hex: 0xff6b6b))
            } else if recorder.phase == .analyzing {
                ProgressView().tint(Theme.muted)
            } else {
                Image(systemName: "mic").font(.system(size: 21, weight: .medium)).foregroundStyle(Theme.logoText)
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(on ? 0.94 : 1)
        .animation(.easeOut(duration: 0.1), value: on)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !recorder.held, recorder.phase == .idle else { return }
                    recorder.held = true
                    Task { await recorder.start() }
                }
                .onEnded { _ in recorder.stop() }
        )
        .sensoryFeedback(.impact(weight: .medium), trigger: on)
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Idee aufnehmen")
        .accessibilityValue(on ? "Aufnahme läuft, \(Int(recorder.seconds)) Sekunden" : "")
        .accessibilityHint("Gedrückt halten, 5 bis 30 Sekunden. Summen, Pfeifen, Singen. Beschreibung, Tempo und Tonart werden übernommen.")
        .accessibilityAction {
            if on { recorder.stop(); return }
            UIAccessibility.post(notification: .announcement, argument: "Aufnahme beginnt gleich. Zum Beenden noch einmal aktivieren.")
            Task {
                try? await Task.sleep(for: .seconds(1.8))   // erst ansagen, dann das Mikrofon öffnen
                await recorder.start(toggle: true)
            }
        }
    }
}
