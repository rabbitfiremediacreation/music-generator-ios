import Accelerate
import AVFoundation
import Observation

/// Ideengeber wie in der Web-App (static/app.js, Abschnitt „Ideengeber“): Knopf gedrückt halten, 5 bis 30 Sekunden
/// summen, pfeifen oder singen. Die Aufnahme geht als WAV an `/api/analyze`; Tempo und Tonart kommen von dort,
/// die Beschreibung der Melodie messen wir selbst (Tonhöhenverlauf, Tempo der Töne, Bindung).
/// Die Melodie selbst wird nicht übernommen, das kann ACE-Step nicht.
@MainActor @Observable
final class IdeaRecorder {
    enum Phase { case idle, recording, analyzing }

    static let maxSeconds = 30.0
    static let minSeconds = 5.0

    private(set) var phase = Phase.idle
    private(set) var seconds = 0.0
    var message: String?
    var failed = false
    /// Finger liegt noch auf dem Knopf; wird er vor der Mikrofon-Freigabe losgelassen, startet nichts.
    var held = false

    /// Bekommt das Ergebnis der Analyse und die Messwerte der Melodie.
    var onResult: (AnalyzeResult, MelodyIdea) -> Void = { _, _ in }

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var started = Date()
    private let file = FileManager.default.temporaryDirectory.appendingPathComponent("idee.wav")

    func start(toggle: Bool = false) async {
        guard phase == .idle else { return }
        guard await AVAudioApplication.requestRecordPermission() else {
            fail("Kein Zugriff aufs Mikrofon. Erlauben unter Einstellungen › Apps › Music Generator.")
            return
        }
        guard held || toggle else { return }   // beim Nachfragen schon losgelassen
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
            try session.setActive(true)
            let r = try AVAudioRecorder(url: file, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
            ])
            guard r.record() else { throw RecorderError.start }
            recorder = r
        } catch {
            restoreSession()
            fail("Aufnahme ließ sich nicht starten.")
            return
        }
        phase = .recording
        message = nil
        started = Date()
        seconds = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func stop() {
        held = false
        guard phase == .recording, let recorder else { return }
        timer?.invalidate()
        timer = nil
        recorder.stop()
        self.recorder = nil
        restoreSession()
        let length = Date().timeIntervalSince(started)
        phase = .idle
        seconds = 0
        if length < Self.minSeconds {
            fail("Aufnahme zu kurz, bitte mindestens fünf Sekunden halten.")
            return
        }
        Task { await analyze() }
    }

    private func tick() {
        seconds = Date().timeIntervalSince(started)
        if seconds >= Self.maxSeconds { stop() }
    }

    private func analyze() async {
        phase = .analyzing
        failed = false
        message = "Aufnahme wird ausgewertet …"
        defer { phase = .idle }
        do {
            let (wav, mono, rate) = try Self.loadNormalized(file)
            let idea = MelodyIdea.measure(mono, rate: rate) ?? .neutral   // nichts Tonales gefunden: neutrale Werte
            let result = try await APIClient.current.analyze(wav: wav)
            onResult(result, idea)
            message = "Aufnahme analysiert: Beschreibung, Tempo und Tonart übernommen. Stil und Länge bestimmst du."
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func fail(_ text: String) {
        failed = true
        message = text
    }

    /// Zurück zur reinen Wiedergabe (Musik-App, AirPlay 2).
    private func restoreSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, policy: .longFormAudio)
    }

    /// Liest die Aufnahme, hebt leise Mikrofone auf -1 dB an (höchstens 20-fach) und schreibt sie als 16-Bit-WAV.
    private static func loadNormalized(_ url: URL) throws -> (Data, [Float], Double) {
        let f = try AVAudioFile(forReading: url)
        guard let buf = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length)) else {
            throw RecorderError.read
        }
        try f.read(into: buf)
        guard let ch = buf.floatChannelData else { throw RecorderError.read }
        let n = Int(buf.frameLength), rate = f.processingFormat.sampleRate
        let mono = Array(UnsafeBufferPointer(start: ch[0], count: n))
        let peak = mono.reduce(0) { max($0, abs($1)) }
        let gain = peak > 0 ? min(0.89 / peak, 20) : 1

        var wav = Data(capacity: 44 + n * 2)
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { wav.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { wav.append(contentsOf: $0) } }
        wav.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + n * 2))
        wav.append(contentsOf: Array("WAVEfmt ".utf8)); u32(16); u16(1); u16(1)
        u32(UInt32(rate)); u32(UInt32(rate) * 2); u16(2); u16(16)
        wav.append(contentsOf: Array("data".utf8)); u32(UInt32(n * 2))
        for s in mono {
            let v = max(-1, min(1, s * gain))
            u16(UInt16(bitPattern: Int16(v < 0 ? v * 32768 : v * 32767)))
        }
        return (wav, mono, rate)
    }

    private enum RecorderError: LocalizedError {
        case start, read
        var errorDescription: String? { self == .start ? "Aufnahme ließ sich nicht starten." : "Aufnahme ließ sich nicht lesen." }
    }
}

/// Antwort von `/api/analyze`.
struct AnalyzeResult: Decodable {
    var caption = ""
    var lyrics = ""
    var bpm: Double = 0
    var keyscale = ""
    var timesignature = ""
    var vocal_language = ""

    enum CodingKeys: String, CodingKey { case caption, lyrics, bpm, keyscale, timesignature, vocal_language }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        caption = (try? c.decode(String.self, forKey: .caption)) ?? ""
        lyrics = (try? c.decode(String.self, forKey: .lyrics)) ?? ""
        bpm = (try? c.decode(Double.self, forKey: .bpm)) ?? 0
        keyscale = (try? c.decode(String.self, forKey: .keyscale)) ?? ""
        // Takt kommt je nach Modell als Zahl oder Text
        timesignature = (try? c.decode(String.self, forKey: .timesignature))
            ?? (try? c.decode(Int.self, forKey: .timesignature)).map(String.init) ?? ""
        vocal_language = (try? c.decode(String.self, forKey: .vocal_language)) ?? ""
    }

    /// Nur echter Text außerhalb von [Strukturmarkern] zählt als Gesang.
    var hasVocals: Bool {
        !lyrics.replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Messwerte einer gesummten oder gepfiffenen Melodie (wie `measureMelody` in der Web-App).
struct MelodyIdea {
    var range: Double    // Tonumfang in Halbtönen
    var rate: Double     // Töne pro Sekunde
    var drift: Double    // Anstieg über die ganze Aufnahme in Halbtönen
    var legato: Double   // Anteil der klingenden Stellen mit fester Tonhöhe

    static let neutral = MelodyIdea(range: 5, rate: 2.5, drift: 0, legato: 0.8)

    /// Tonhöhe je Fenster mit YIN, 70 Hz (tiefe Stimme) bis 2,5 kHz (Pfeifen), auf etwa 16 kHz heruntergerechnet.
    static func measure(_ mono: [Float], rate: Double) -> MelodyIdea? {
        let step = max(1, Int((rate / 16000).rounded())), sr = rate / Double(step)
        let n = mono.count / step
        var x = [Float](repeating: 0, count: n)
        for i in 0..<n {
            var a: Float = 0
            for k in 0..<step { a += mono[i * step + k] }
            x[i] = a / Float(step)
        }
        let w = 1024, hop = 256, tauMin = Int((sr / 2500).rounded(.down)), tauMax = Int((sr / 70).rounded(.up))
        let peak = x.reduce(0) { max($0, abs($1)) }
        var frames: [(t: Double, pitch: Double?, loud: Bool)] = []
        var d = [Float](repeating: 1, count: tauMax + 1)
        x.withUnsafeBufferPointer { xp in
            guard let base = xp.baseAddress else { return }
            var start = 0
            while start + w + tauMax < n {
                var e: Float = 0
                vDSP_svesq(base + start, 1, &e, vDSP_Length(w))
                let loud = (e / Float(w)).squareRoot() > peak * 0.04
                var pitch: Double?
                if loud {
                    var run: Float = 0
                    for tau in 1...tauMax {
                        var sum: Float = 0
                        vDSP_distancesq(base + start, 1, base + start + tau, 1, &sum, vDSP_Length(w))
                        run += sum
                        d[tau] = run != 0 ? sum * Float(tau) / run : 1   // kumulierte mittlere normierte Differenz
                    }
                    var tau = tauMin
                    while tau < tauMax {
                        if d[tau] < 0.15 {
                            while tau + 1 < tauMax && d[tau + 1] < d[tau] { tau += 1 }
                            pitch = 69 + 12 * log2(sr / Double(tau) / 440)
                            break
                        }
                        tau += 1
                    }
                }
                frames.append((Double(start) / sr, pitch, loud))
                start += hop
            }
        }
        let voiced = frames.compactMap { f in f.pitch.map { (t: f.t, p: $0) } }
        guard voiced.count >= 10 else { return nil }
        let ps = voiced.map(\.p).sorted()
        func q(_ p: Double) -> Double { ps[Int((p * Double(ps.count - 1)).rounded(.down))] }
        // Tonwechsel: Sprung um mehr als einen Dreiviertelton gegenüber der laufenden Note
        var notes = 1.0, cur = voiced[0].p
        for v in voiced where abs(v.p - cur) > 0.75 { notes += 1; cur = v.p }
        let cnt = Double(voiced.count)
        let mt = voiced.reduce(0) { $0 + $1.t } / cnt, mp = voiced.reduce(0) { $0 + $1.p } / cnt
        let slope = voiced.reduce(0) { $0 + ($1.t - mt) * ($1.p - mp) } / max(1e-9, voiced.reduce(0) { $0 + ($1.t - mt) * ($1.t - mt) })
        let dur = Double(frames.count * hop) / sr
        return MelodyIdea(range: q(0.95) - q(0.05), rate: notes / dur, drift: slope * dur,
                          legato: cnt / Double(max(1, frames.filter(\.loud).count)))
    }

    private static let moods = ["magical", "mysterious", "whimsical", "dreamy", "melancholic", "nostalgic", "playful", "gentle", "tender", "hopeful", "haunting",
        "warm", "calm", "peaceful", "uplifting", "dark", "sad", "joyful", "epic", "triumphant", "eerie", "romantic", "serene", "wistful",
        "cheerful", "energetic", "intense", "bittersweet", "soothing", "somber", "lighthearted"]

    /// Prompt aus den Messwerten, dazu bis zu zwei Stimmungswörter aus der Beschreibung des Modells.
    func describe(caption: String, key: String) -> String {
        let minor = key.range(of: "minor", options: .caseInsensitive) != nil
        let pace = rate < 2 ? "slow" : rate < 3.5 ? "moderately paced" : "lively"
        let shape = drift < -2 ? "descending" : drift > 2 ? "rising" : "gently circling"
        let width = range < 5 ? "narrow" : range > 9 ? "wide" : "medium-range"
        let smooth = legato > 0.6   // Summen hat Atem- und Konsonantenlücken, 0,6 ist schon gebunden
        let like = rate < 2 && smooth ? (minor || drift < -2 ? "like a gentle lullaby or a film ballad theme" : "like a tender lullaby or a folk ballad")
            : rate < 3.5 ? (smooth ? "like a heartfelt ballad melody" : "like a simple folk tune")
            : smooth ? "like a soaring pop melody" : minor ? "like a driving, rhythmic theme" : "like a cheerful dance tune"
        let low = caption.lowercased()
        let found = Self.moods.filter { low.range(of: "\\b\($0)\\b", options: .regularExpression) != nil }.prefix(2)
        return "\(pace.prefix(1).uppercased() + pace.dropFirst()) melody with a \(width), \(shape) line and "
            + "\(smooth ? "smooth, flowing" : "detached, rhythmic") phrasing, \(like)"
            + (found.isEmpty ? "" : ", " + found.joined(separator: " and "))
    }
}
