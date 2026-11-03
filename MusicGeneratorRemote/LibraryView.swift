import SwiftUI

struct LibraryView: View {
    @Environment(Library.self) private var library
    @Environment(Player.self) private var player
    @State private var newFolderFor: Song?

    var body: some View {
        @Bindable var library = library
        NavigationStack {
            List {
                if library.busy { QueueRow().listRowBackground(Theme.panel) }
                if let error = library.error {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                        .listRowBackground(Theme.bg)
                }
                ForEach(library.songs) { song in
                    SongRow(song: song)
                        .contentShape(Rectangle())
                        .onTapGesture { if song.isPlayable { player.play(song, in: library.songs) } }
                        .swipeActions(edge: .leading) {
                            Button { Task { await library.toggleFavorite(song) } } label: {
                                Label("Favorit", systemImage: song.favorite ? "star.slash" : "star")
                            }.tint(Theme.gold)
                        }
                        .contextMenu {
                            Button { Task { await library.toggleFavorite(song) } } label: {
                                Label(song.favorite ? "Favorit entfernen" : "Favorit", systemImage: song.favorite ? "star.slash" : "star")
                            }
                            Menu { FolderMenuItems(song: song, newFolderFor: $newFolderFor) } label: {
                                Label("In Ordner verschieben", systemImage: "folder")
                            }
                        }
                        .listRowBackground(Theme.bg)
                }
                if library.songs.isEmpty && library.error == nil && !library.loading {
                    ContentUnavailableView("Keine Songs", systemImage: "music.note",
                                           description: Text("Hier erscheinen die Songs vom Mac."))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .newFolderAlert(for: $newFolderFor)
            .navigationTitle("Bibliothek")
            .searchable(text: $library.search, prompt: "Suchen")
            .onSubmit(of: .search) { Task { await library.reload() } }
            .onChange(of: library.search) { _, new in if new.isEmpty { Task { await library.reload() } } }
            .toolbar { filterMenu }
            .refreshable { await library.reload() }
            .task { await library.reload() }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(3))
                    await library.pollQueue()
                }
            }
        }
    }

    private var filterMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Toggle("Nur Favoriten", isOn: Binding(get: { library.favoritesOnly },
                                                      set: { library.favoritesOnly = $0; Task { await library.reload() } }))
                Picker("Ordner", selection: Binding(get: { library.folder },
                                                    set: { library.folder = $0; Task { await library.reload() } })) {
                    Text("Alle (\(library.folders?.all ?? 0))").tag("")
                    Text("Unsortiert (\(library.folders?.none ?? 0))").tag("none")
                    ForEach(library.folders?.folders ?? []) { f in Text("\(f.name) (\(f.count))").tag(f.id) }
                }
            } label: {
                Image(systemName: library.favoritesOnly || !library.folder.isEmpty
                      ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            }
        }
    }
}

private struct QueueRow: View {
    @Environment(Library.self) private var library

    var body: some View {
        HStack(spacing: 12) {
            ProgressView().tint(Theme.gold)
            VStack(alignment: .leading) {
                if let r = library.queue?.running.first {
                    Text("Wird erzeugt: \(r.message ?? "")").font(.subheadline.bold())
                    if let c = r.caption { Text(c).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
                if let n = library.queue?.queued, n > 0 {
                    Text(n == 1 ? "1 Song wartet" : "\(n) Songs warten").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct SongRow: View {
    @Environment(Player.self) private var player
    let song: Song

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(player.current?.id == song.id ? Theme.gold : Theme.muted)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.displayTitle).lineLimit(1).foregroundStyle(Theme.text)
                Text(subtitle).font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer()
            if song.isPlayable { StarButton(song: song, size: 18).frame(width: 36, height: 36) }
        }
        .opacity(song.isPlayable ? 1 : 0.5)
    }

    private var icon: String {
        if player.current?.id == song.id { return player.isPlaying ? "speaker.wave.2.fill" : "pause.fill" }
        switch song.status {
        case "done": return "play.circle"
        case "running", "queued": return "hourglass"
        case "error": return "exclamationmark.circle"
        default: return "xmark.circle"
        }
    }

    private var subtitle: String {
        switch song.status {
        case "done":
            let parts = [song.duration.map(formatTime), song.title?.isEmpty == false ? song.caption : nil]
            return parts.compactMap { $0 }.joined(separator: " · ")
        case "queued": return "wartet"
        case "running": return "wird erzeugt \(song.message ?? "")"
        case "error": return song.message ?? "Fehler"
        default: return "abgebrochen"
        }
    }
}
