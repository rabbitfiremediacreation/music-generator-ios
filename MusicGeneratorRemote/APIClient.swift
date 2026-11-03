import Foundation

enum APIError: LocalizedError {
    case noServer
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .noServer: return "Keine Serveradresse eingestellt."
        case .http(401, _): return "Zugangsschlüssel fehlt oder ist falsch."
        case .http(let code, let detail): return detail.isEmpty ? "Fehler \(code)" : detail
        }
    }
}

/// Spricht mit der Web-App des Music Generator auf dem Mac.
struct APIClient {
    var baseURL: URL?
    var token: String

    static var current: APIClient {
        let d = UserDefaults.standard
        let raw = (d.string(forKey: "server") ?? Settings.defaultServer).trimmingCharacters(in: .whitespaces)
        return APIClient(baseURL: raw.isEmpty ? nil : URL(string: raw.hasPrefix("http") ? raw : "http://\(raw)"),
                         token: (d.string(forKey: "token") ?? "").trimmingCharacters(in: .whitespaces))
    }

    /// Header für jede Anfrage, auch fürs Streamen im Player.
    var headers: [String: String] {
        var h = ["X-Lang": "de"]
        if !token.isEmpty { h["Authorization"] = "Bearer \(token)" }
        return h
    }

    func url(_ path: String, query: [URLQueryItem] = []) throws -> URL {
        guard let base = baseURL else { throw APIError.noServer }
        var c = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { c.queryItems = query }
        return c.url!
    }

    private func send<T: Decodable>(_ method: String, _ path: String, query: [URLQueryItem] = [],
                                    body: Encodable? = nil) async throws -> T {
        var req = URLRequest(url: try url(path, query: query), timeoutInterval: 15)
        req.httpMethod = method
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(body)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
            throw APIError.http(code, detail ?? "")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func songs(search: String = "", favorites: Bool = false, folder: String = "") async throws -> [Song] {
        var q: [URLQueryItem] = []
        if !search.isEmpty { q.append(.init(name: "q", value: search)) }
        if favorites { q.append(.init(name: "favorites", value: "true")) }
        if !folder.isEmpty { q.append(.init(name: "folder", value: folder)) }
        return try await send("GET", "api/songs", query: q)
    }

    func folders() async throws -> FolderList { try await send("GET", "api/folders") }
    func queue() async throws -> QueueState { try await send("GET", "api/queue") }

    func generate(_ r: GenerateRequest) async throws -> GenerateResponse {
        try await send("POST", "api/generate", body: r)
    }

    func setFavorite(_ id: String, _ on: Bool) async throws -> Song {
        struct P: Encodable { let favorite: Bool }
        return try await send("PATCH", "api/songs/\(id)", body: P(favorite: on))
    }

    /// Verschiebt einen Song; `nil` = unsortiert.
    func setFolder(_ id: String, _ folder: String?) async throws -> Song {
        struct P: Encodable {
            let folder_id: String?
            func encode(to e: Encoder) throws {   // null mitschicken, sonst ignoriert der Server das Feld
                var c = e.container(keyedBy: CodingKeys.self)
                try c.encode(folder_id, forKey: .folder_id)
            }
            enum CodingKeys: String, CodingKey { case folder_id }
        }
        return try await send("PATCH", "api/songs/\(id)", body: P(folder_id: folder))
    }

    func createFolder(_ name: String) async throws -> Folder {
        struct P: Encodable { let name: String }
        struct R: Decodable { let id: String; let name: String }
        let r: R = try await send("POST", "api/folders", body: P(name: name))
        return Folder(id: r.id, name: r.name, count: 0)
    }

    /// Schickt eine Aufnahme an die Analyse des Modells (Beschreibung, Tempo, Tonart, Takt).
    func analyze(wav: Data) async throws -> AnalyzeResult {
        let boundary = "mg-\(UUID().uuidString)"
        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"audio\"; filename=\"Aufnahme.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8))
        body.append(wav)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var req = URLRequest(url: try url("api/analyze"), timeoutInterval: 180)   // die Analyse dauert eine Weile
        req.httpMethod = "POST"
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let (data, resp) = try await URLSession.shared.upload(for: req, from: body)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
            throw APIError.http(code, detail ?? "")
        }
        return try JSONDecoder().decode(AnalyzeResult.self, from: data)
    }

    func health() async throws -> [String: AnyDecodable] { try await send("GET", "api/health") }

    func audioURL(_ song: Song) throws -> URL { try url("api/songs/\(song.id)/audio") }
}

/// Nimmt beliebiges JSON an, wenn nur der Erfolg zählt.
struct AnyDecodable: Decodable {
    init(from decoder: Decoder) throws {}
}
