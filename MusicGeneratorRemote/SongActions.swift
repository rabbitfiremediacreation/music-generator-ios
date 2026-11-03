import AVKit
import SwiftUI

/// Stern zum Bewerten, wie in der Web-App: gold = Favorit.
struct StarButton: View {
    @Environment(Library.self) private var library
    let song: Song
    var size: CGFloat = 20

    var body: some View {
        Button { Task { await library.toggleFavorite(song) } } label: {
            Image(systemName: song.favorite ? "star.fill" : "star")
                .font(.system(size: size))
                .foregroundStyle(song.favorite ? Theme.gold : Theme.muted)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.borderless)
        .sensoryFeedback(.selection, trigger: song.favorite)
        .accessibilityLabel(song.favorite ? "Favorit entfernen" : "Als Favorit markieren")
    }
}

/// Ordnerauswahl für einen Song: vorhandene Ordner, Unsortiert oder ein neuer Ordner.
struct FolderMenuItems: View {
    @Environment(Library.self) private var library
    let song: Song
    @Binding var newFolderFor: Song?

    var body: some View {
        Button { Task { await library.move(song, to: nil) } } label: {
            Label("Unsortiert", systemImage: song.folder_id == nil ? "checkmark" : "tray")
        }
        ForEach(library.folders?.folders ?? []) { f in
            Button { Task { await library.move(song, to: f.id) } } label: {
                Label(f.name, systemImage: song.folder_id == f.id ? "checkmark" : "folder")
            }
        }
        Divider()
        Button { newFolderFor = song } label: { Label("Neuer Ordner …", systemImage: "folder.badge.plus") }
    }
}

/// Fragt den Namen für einen neuen Ordner ab und verschiebt den Song hinein.
struct NewFolderAlert: ViewModifier {
    @Environment(Library.self) private var library
    @Binding var song: Song?
    @State private var name = ""

    func body(content: Content) -> some View {
        content.alert("Neuer Ordner", isPresented: Binding(get: { song != nil }, set: { if !$0 { song = nil } })) {
            TextField("Name", text: $name)
            Button("Abbrechen", role: .cancel) { name = "" }
            Button("Anlegen") {
                if let s = song { let n = name; Task { await library.moveToNewFolder(s, name: n) } }
                name = ""
            }
        } message: {
            Text("Der Song kommt gleich hinein.")
        }
    }
}

extension View {
    func newFolderAlert(for song: Binding<Song?>) -> some View { modifier(NewFolderAlert(song: song)) }
}

/// Umrandeter Knopf wie Stern und Ordner im großen Player.
struct PlayerToolButton<Label: View>: View {
    var active = false
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .font(.system(size: 20))
                .foregroundStyle(active ? Theme.gold : Theme.text)
                .frame(width: 54, height: 40)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(active ? Theme.gold : Theme.border))
        }
        .buttonStyle(.borderless)
    }
}

/// Wiedergabe auf Geräten im Netzwerk (AirPlay: HomePod, AirPlay-Lautsprecher, Apple TV, Mac).
struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = UIColor(Theme.text)
        v.activeTintColor = UIColor(Theme.gold)
        v.prioritizesVideoDevices = false
        return v
    }
    func updateUIView(_ v: AVRoutePickerView, context: Context) {}
}

/// Lädt den Song aufs iPhone; ein zweiter Tipp entfernt ihn nach Rückfrage wieder.
struct DownloadButton: View {
    @State private var downloads = Downloads.shared
    let song: Song
    @State private var confirmRemove = false
    @State private var error: String?

    var body: some View {
        let loaded = downloads.isLoaded(song)
        PlayerToolButton(active: loaded) {
            if loaded { confirmRemove = true; return }
            Task {
                do { try await downloads.download(song) } catch { self.error = error.localizedDescription }
            }
        } label: {
            if downloads.loading.contains(song.id) { ProgressView().tint(Theme.gold) }
            else { Image(systemName: loaded ? "arrow.down.circle.fill" : "arrow.down.circle") }
        }
        .accessibilityLabel(loaded ? "Auf dem iPhone, entfernen" : "Aufs iPhone laden")
        .confirmationDialog("Vom iPhone entfernen?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Vom iPhone entfernen", role: .destructive) { downloads.remove(song) }
        } message: {
            Text("Auf dem Mac bleibt der Song erhalten.")
        }
        .alert("Laden fehlgeschlagen", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: { Text(error ?? "") }
    }
}

/// Teilt die Audiodatei (Nachrichten, AirDrop, Mail …).
struct ShareButton: View {
    @State private var downloads = Downloads.shared
    let song: Song
    @State private var file: URL?
    @State private var error: String?

    var body: some View {
        PlayerToolButton {
            Task {
                do { file = try await downloads.fileForSharing(song) } catch { self.error = error.localizedDescription }
            }
        } label: {
            if downloads.loading.contains(song.id) && !downloads.isLoaded(song) { ProgressView().tint(Theme.gold) }
            else { Image(systemName: "square.and.arrow.up") }
        }
        .accessibilityLabel("Teilen")
        .sheet(item: Binding(get: { file.map(ShareFile.init) }, set: { if $0 == nil { file = nil } })) {
            ShareSheet(url: $0.url).presentationDetents([.medium, .large])
        }
        .alert("Teilen fehlgeschlagen", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: { Text(error ?? "") }
    }
}

private struct ShareFile: Identifiable { let url: URL; var id: URL { url } }

private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

/// Lautstärke der App als Balken wie die übrigen Regler.
struct VolumeBar: View {
    @Environment(Player.self) private var player

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill").foregroundStyle(Theme.muted)
            BubbleSlider(value: Binding(get: { player.volume * 100 }, set: { player.volume = $0 / 100 }),
                         range: 0...100, label: "Lautstärke")
            Image(systemName: "speaker.wave.3.fill").foregroundStyle(Theme.muted)
        }
    }
}
