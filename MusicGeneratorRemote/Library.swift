import Foundation
import Observation

/// Bibliothek und Warteschlange vom Mac; wird von Bibliothek und Erzeugen gemeinsam genutzt.
@MainActor @Observable
final class Library {
    var songs: [Song] = []
    var folders: FolderList?
    var queue: QueueState?
    var error: String?
    var loading = false

    var search = ""
    var favoritesOnly = false
    var folder = ""   // "" = alle, "none" = unsortiert, sonst Ordner-ID

    func reload() async {
        loading = true
        defer { loading = false }
        let api = APIClient.current
        do {
            async let s = api.songs(search: search, favorites: favoritesOnly, folder: folder)
            async let f = api.folders()
            async let q = api.queue()
            (songs, folders, queue) = try await (s, f, q)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Fragt die Warteschlange ab; ist ein Auftrag fertig geworden, wird die Liste neu geladen.
    func pollQueue() async {
        guard let q = try? await APIClient.current.queue() else { return }
        let wasBusy = (queue?.running.isEmpty == false) || (queue?.queued ?? 0) > 0
        let before = (queue?.running.first?.id, queue?.queued)
        queue = q
        if wasBusy && (before.0 != q.running.first?.id || before.1 != q.queued) { await reload() }
    }

    var busy: Bool { (queue?.running.isEmpty == false) || (queue?.queued ?? 0) > 0 }

    func toggleFavorite(_ song: Song) async {
        do {
            let updated = try await APIClient.current.setFavorite(song.id, !song.favorite)
            if let i = songs.firstIndex(where: { $0.id == song.id }) { songs[i].favorite = updated.favorite }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
