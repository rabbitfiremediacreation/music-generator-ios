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

    /// Wird nach jeder Änderung an einem Song aufgerufen, damit der Player die neue Fassung übernimmt.
    var onSongChanged: (Song) -> Void = { _ in }

    func toggleFavorite(_ song: Song) async {
        await change { try await APIClient.current.setFavorite(song.id, !song.favorite) }
    }

    func move(_ song: Song, to folder: String?) async {
        await change { try await APIClient.current.setFolder(song.id, folder) }
        // Passt der Song nicht mehr zum Ordnerfilter, verschwindet er aus der Liste
        if !self.folder.isEmpty, (folder ?? "none") != self.folder { songs.removeAll { $0.id == song.id } }
        folders = try? await APIClient.current.folders()
    }

    /// Legt einen Ordner an und verschiebt den Song hinein.
    func moveToNewFolder(_ song: Song, name: String) async {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            let f = try await APIClient.current.createFolder(name)
            await move(song, to: f.id)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func folderName(_ id: String?) -> String {
        guard let id else { return "Unsortiert" }
        return folders?.folders.first { $0.id == id }?.name ?? "Unsortiert"
    }

    private func change(_ call: () async throws -> Song) async {
        do {
            let updated = try await call()
            if let i = songs.firstIndex(where: { $0.id == updated.id }) { songs[i] = updated }
            onSongChanged(updated)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
