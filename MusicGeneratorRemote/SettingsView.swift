import SwiftUI

enum Settings {
    /// Im Simulator erreicht die App den Mac unter 127.0.0.1.
    static let defaultServer = "http://127.0.0.1:8765"
}

struct SettingsView: View {
    @Environment(Library.self) private var library
    @AppStorage("server") private var server = Settings.defaultServer
    @AppStorage("token") private var token = ""
    @State private var result: String?
    @State private var ok = false
    @State private var testing = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("http://mein-mac.local:8765", text: $server)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Zugangsschlüssel", text: $token)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: {
                    Text("Mac")
                } footer: {
                    Text("Adresse und Zugangsschlüssel zeigt der Music Generator auf dem Mac unter Einstellungen → Handy.")
                }
                Section {
                    Button(action: test) {
                        HStack { Text("Verbindung testen"); Spacer(); if testing { ProgressView() } }
                    }
                    if let result {
                        Label(result, systemImage: ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(ok ? .green : .red)
                    }
                }
            }
            .navigationTitle("Verbindung")
        }
    }

    private func test() {
        testing = true
        result = nil
        Task {
            defer { testing = false }
            do {
                let api = APIClient.current
                _ = try await api.folders()   // prüft Adresse und Zugangsschlüssel
                ok = true
                result = "Verbunden"
                await library.reload()
            } catch {
                ok = false
                result = error.localizedDescription
            }
        }
    }
}
