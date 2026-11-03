import SwiftUI

/// Formular wie in der Web-App: Felder mit Würfeln, Balken-Regler, unten Versionen und „Generieren“.
struct GenerateView: View {
    @Environment(Library.self) private var library
    @State private var form = GenerateRequest()
    @State private var sending = false
    @State private var status: String?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    field("Titel", dice: "Zufälligen Titel würfeln", roll: { form.title = Dice.title() }) {
                        TextField("optional", text: $form.title).modifier(InputStyle())
                    }
                    field("Prompt", dice: "Zufälligen Prompt würfeln", roll: { form.prompt = Dice.prompt(instrumental: form.instrumental) }) {
                        TextField("nächtliche Autofahrt durch eine Neonstadt, langsam und hypnotisch", text: $form.prompt, axis: .vertical)
                            .lineLimit(2...6).modifier(InputStyle())
                    }
                    field("Stil", dice: "Zufälligen Stil würfeln", roll: { form.style = Dice.style(instrumental: form.instrumental) }) {
                        TextField("trip hop, dark, dub bass", text: $form.style, axis: .vertical)
                            .lineLimit(1...4).modifier(InputStyle())
                    }
                    field("Länge") {
                        BubbleSlider(value: $form.duration, range: 10...600, step: 5, label: "Länge", text: formatTime)
                        if form.duration > 300 {
                            Text("Lange Songs brauchen viel Zeit und Speicher.").font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                    field("BPM") {
                        // Ganz links = Auto: das Modell wählt das Tempo
                        BubbleSlider(value: Binding(get: { form.bpm == 0 ? 50 : form.bpm }, set: { form.bpm = $0 <= 50 ? 0 : $0 }),
                                     range: 50...200, label: "BPM",
                                     text: { $0 <= 50 ? "AUTO" : String(Int($0)) }, smallText: { $0 <= 50 })
                    }
                    lyrics
                    if let folders = library.folders?.folders, !folders.isEmpty {
                        field("Ordner") {
                            Picker("Ordner", selection: $form.folder_id) {
                                Text("Unsortiert").tag(String?.none)
                                ForEach(folders) { Text($0.name).tag(Optional($0.id)) }
                            }
                            .pickerStyle(.menu).tint(Theme.text)
                        }
                    }
                    genRow
                    if let status {
                        Text(status).font(.footnote).foregroundStyle(failed ? .red : Theme.muted)
                    }
                }
                .padding(18)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
                .padding(.horizontal, 12)
                .padding(.bottom, 24)
            }
            .background(Theme.bg)
            .navigationTitle("Erzeugen")
            .scrollDismissesKeyboard(.interactively)
        }
    }

    /// Gesang: aus = Instrumental; der Würfel lässt das Modell beim Generieren eigene Lyrics schreiben.
    private var lyrics: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("LYRICS").modifier(LabelStyle())
                Text(form.instrumental ? "[Instrumental]" : form.lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "automatisch" : "eigene")
                    .font(.caption).foregroundStyle(form.instrumental ? Theme.muted : Theme.gold)
                Spacer()
                DiceButton(label: "Lyrics automatisch schreiben lassen") {
                    form.instrumental = false
                    form.lyrics = ""
                }
            }
            Picker("Gesang", selection: $form.instrumental) {
                Text("Instrumental").tag(true)
                Text("Mit Gesang").tag(false)
            }
            .pickerStyle(.segmented)
            if !form.instrumental {
                HStack {
                    Text("SPRACHE").modifier(LabelStyle())
                    Spacer()
                    Picker("Sprache", selection: $form.vocal_language) {
                        ForEach(vocalLanguages, id: \.code) { Text($0.name).tag($0.code) }
                    }
                    .pickerStyle(.menu).tint(Theme.text)
                }
                TextField("Leer lassen: Das Modell schreibt die Lyrics beim Generieren.", text: $form.lyrics, axis: .vertical)
                    .lineLimit(3...12).modifier(InputStyle())
            }
        }
    }

    private var genRow: some View {
        HStack(spacing: 12) {
            BubbleSlider(value: Binding(get: { Double(form.variants) }, set: { form.variants = Int($0) }),
                         range: 1...10, label: "Versionen")
            Button(action: submit) {
                if sending { ProgressView().tint(Theme.logoText) } else { Text("GENERIEREN") }
            }
            .buttonStyle(AktionButtonStyle())
            .disabled(sending || (form.prompt.isEmpty && form.style.isEmpty))
            .opacity(form.prompt.isEmpty && form.style.isEmpty ? 0.5 : 1)
        }
        .padding(.top, 6)
    }

    private func field<C: View>(_ title: String, dice: String? = nil, roll: @escaping () -> Void = {},
                                @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title.uppercased()).modifier(LabelStyle())
                Spacer()
                if let dice { DiceButton(label: dice, action: roll) }
            }
            content()
        }
    }

    private func submit() {
        sending = true
        status = nil
        Task {
            defer { sending = false }
            do {
                let r = try await APIClient.current.generate(form)
                failed = false
                status = r.ids.count == 1 ? "Auftrag gesendet, der Mac rechnet." : "\(r.ids.count) Versionen in Auftrag gegeben, der Mac rechnet."
                await library.reload()
            } catch {
                failed = true
                status = error.localizedDescription
            }
        }
    }
}

/// Feldbeschriftung wie `.lbl` in der Web-App.
private struct LabelStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.font(.system(size: 12, weight: .semibold)).tracking(0.7).foregroundStyle(Theme.muted)
    }
}

/// Eingabefeld wie in der Web-App: dunkler Grund, feiner Rand.
private struct InputStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Theme.bg, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border))
    }
}
