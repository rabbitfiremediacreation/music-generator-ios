import Foundation

/// Ein Song aus der Bibliothek der Web-App (`GET /api/songs`).
struct Song: Codable, Identifiable, Equatable {
    struct Meta: Codable, Equatable {
        var duration: Double?
        var bpm: Double?
        var keyscale: String?
        var vocal_language: String?
    }

    let id: String
    var title: String?
    var caption: String
    var lyrics: String?
    var status: String
    var message: String?
    var favorite: Bool
    var letter: String?
    var url: String?
    var folder_id: String?
    var created_at: String
    var result_meta: Meta?

    var displayTitle: String {
        let base = (title?.isEmpty == false ? title! : caption)
        return letter?.isEmpty == false ? "\(base) \(letter!)" : base
    }

    var isPlayable: Bool { status == "done" && url != nil }
    var duration: Double? { result_meta?.duration }

    /// Lyrics zum Anzeigen; reine Instrumentals haben keine.
    var visibleLyrics: String? {
        guard let l = lyrics?.trimmingCharacters(in: .whitespacesAndNewlines), !l.isEmpty,
              l != "[Instrumental]" else { return nil }
        return l
    }
}

struct Folder: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var count: Int
}

struct FolderList: Codable {
    var folders: [Folder]
    var all: Int
    var none: Int
}

struct QueueState: Codable {
    struct Running: Codable { let id: String; let message: String?; let caption: String? }
    var running: [Running]
    var queued: Int
}

/// Auftrag für `POST /api/generate`, Feldnamen wie im Formular der Web-App.
struct GenerateRequest: Encodable {
    var prompt = ""
    var style = ""
    var lyrics = ""
    var instrumental = true
    var title = ""
    var duration: Double = 90
    var vocal_language = "en"
    var variants = 2
    var folder_id: String?
}

struct GenerateResponse: Decodable { let group_id: String; let ids: [String] }

/// Gesangssprachen wie in der Web-App (Code → Anzeigename).
let vocalLanguages: [(code: String, name: String)] = [
    ("en", "Englisch"), ("de", "Deutsch"), ("fr", "Französisch"), ("es", "Spanisch"), ("it", "Italienisch"),
    ("pt", "Portugiesisch"), ("ja", "Japanisch"), ("ko", "Koreanisch"), ("zh", "Chinesisch"), ("ru", "Russisch"),
]

func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    let s = Int(seconds.rounded())
    return "\(s / 60):" + String(format: "%02d", s % 60)
}
