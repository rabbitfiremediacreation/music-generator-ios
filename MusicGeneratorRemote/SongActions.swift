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
