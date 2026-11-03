import Foundation
import Observation

/// Songs, die auf dem iPhone liegen: im Dokumente-Ordner der App, sichtbar in der Dateien-App
/// unter „Auf meinem iPhone › Music Generator“. Geladene Songs spielen auch ohne Verbindung zum Mac.
@MainActor @Observable
final class Downloads {
    static let shared = Downloads()

    private(set) var files: [String: String]   // Song-ID → Dateiname im Dokumente-Ordner
    private(set) var loading: Set<String> = []
    private let key = "downloads"
    private let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    private init() {
        let saved = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        // Was in der Dateien-App gelöscht wurde, gilt nicht mehr als geladen
        let docs = docs
        files = saved.filter { FileManager.default.fileExists(atPath: docs.appendingPathComponent($0.value).path) }
    }

    func localURL(_ song: Song) -> URL? {
        files[song.id].map { docs.appendingPathComponent($0) }
    }

    func isLoaded(_ song: Song) -> Bool { localURL(song) != nil }

    /// Lädt den Song aufs iPhone, in dem Format, das in der Web-App unter Einstellungen gewählt ist (WAV oder MP3).
    @discardableResult
    func download(_ song: Song) async throws -> URL {
        if let url = localURL(song) { return url }
        let (tmp, suggested) = try await fetch(song)
        var name = suggested
        if FileManager.default.fileExists(atPath: docs.appendingPathComponent(name).path) {
            name = "\(song.id)_\(name)"
        }
        let dest = docs.appendingPathComponent(name)
        try FileManager.default.moveItem(at: tmp, to: dest)
        files[song.id] = name
        UserDefaults.standard.set(files, forKey: key)
        return dest
    }

    /// Datei zum Teilen: der geladene Song oder eine vorübergehende Kopie, die nicht als geladen gilt.
    func fileForSharing(_ song: Song) async throws -> URL {
        if let url = localURL(song) { return url }
        let (tmp, name) = try await fetch(song)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("share", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)   // nur die zuletzt geteilte Datei behalten
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(name)
        try FileManager.default.moveItem(at: tmp, to: dest)
        return dest
    }

    private func fetch(_ song: Song) async throws -> (URL, String) {
        loading.insert(song.id)
        defer { loading.remove(song.id) }
        let api = APIClient.current
        var req = URLRequest(url: try api.url("api/songs/\(song.id)/audio", query: [.init(name: "download", value: "true")]),
                             timeoutInterval: 120)
        api.headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        let (tmp, resp) = try await URLSession.shared.download(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw APIError.http(code, "") }
        return (tmp, resp.suggestedFilename ?? "\(song.id).wav")
    }

    func remove(_ song: Song) {
        guard let url = localURL(song) else { return }
        try? FileManager.default.removeItem(at: url)
        files[song.id] = nil
        UserDefaults.standard.set(files, forKey: key)
    }
}
