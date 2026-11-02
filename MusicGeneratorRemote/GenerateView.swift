import SwiftUI

struct GenerateView: View {
    @Environment(Library.self) private var library
    @State private var form = GenerateRequest()
    @State private var sending = false
    @State private var status: String?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Idee") {
                    TextField("Worum geht es im Song?", text: $form.prompt, axis: .vertical).lineLimit(2...5)
                    TextField("Stil, z. B. synthwave, female vocals", text: $form.style, axis: .vertical).lineLimit(1...3)
                    TextField("Titel (optional)", text: $form.title)
                }
                Section("Gesang") {
                    Toggle("Instrumental", isOn: $form.instrumental)
                    if !form.instrumental {
                        Picker("Sprache", selection: $form.vocal_language) {
                            ForEach(vocalLanguages, id: \.code) { Text($0.name).tag($0.code) }
                        }
                        TextField("Lyrics, leer = erfindet das Modell", text: $form.lyrics, axis: .vertical)
                            .lineLimit(3...12)
                    }
                }
                Section("Länge und Versionen") {
                    LabeledContent("Länge", value: formatTime(form.duration))
                    Slider(value: $form.duration, in: 10...600, step: 5)
                    Stepper("Versionen: \(form.variants)", value: $form.variants, in: 1...10)
                    if let folders = library.folders?.folders, !folders.isEmpty {
                        Picker("Ordner", selection: $form.folder_id) {
                            Text("Unsortiert").tag(String?.none)
                            ForEach(folders) { Text($0.name).tag(Optional($0.id)) }
                        }
                    }
                }
                Section {
                    Button(action: submit) {
                        HStack {
                            Spacer()
                            if sending { ProgressView() } else { Text("Song erzeugen").bold() }
                            Spacer()
                        }
                    }
                    .disabled(sending || (form.prompt.isEmpty && form.style.isEmpty))
                    if let status {
                        Text(status).font(.footnote).foregroundStyle(failed ? .red : .secondary)
                    }
                }
            }
            .navigationTitle("Erzeugen")
            .scrollDismissesKeyboard(.interactively)
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
