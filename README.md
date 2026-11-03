# Music Generator für das iPhone

Die iPhone-App zum [Music Generator](https://github.com/rabbitfiremediacreation/music-generator): Du sitzt auf dem Sofa, der Mac rechnet. Die App zeigt deine Bibliothek, spielt Songs ab (auch per AirPlay), vergibt Sterne, sortiert in Ordner, lädt Songs aufs iPhone und gibt neue Songs in Auftrag, mit Würfeln, Reglern und dem Ideengeber (summen, pfeifen, singen) wie in der Web-App.

Die App rechnet nichts selbst. Sie spricht über dein Heimnetz mit dem Music Generator auf deinem Rechner:

- **Web-App** (Python): „Handy-Zugriff“ unter *Setup* einschalten, Port 8766.
- **Desktop-App**: „Handy-Zugriff“ in den Einstellungen, Port 8767 (sobald die Funktion in einer Version enthalten ist).

Beide zeigen einen QR-Code. Den scannst du mit der iPhone-Kamera, fertig. Kein Konto, kein Abo, keine Daten verlassen dein Netz.

*English: an iPhone companion app for the Music Generator. It talks to the web app (port 8766) or the desktop app (port 8767) on your Mac over your home network; nothing is computed on the phone. Build it yourself with Xcode, see below.*

## Was du brauchst

- Einen **Mac mit Xcode** (ab Xcode 16, iOS 17 oder neuer auf dem iPhone).
- Eine **Apple-ID**. Die kostenlose reicht: Die App läuft dann 7 Tage und muss danach einfach neu aufgespielt werden. Mit dem bezahlten Developer Program (99 €/Jahr) hält sie ein Jahr.
- Den Music Generator auf demselben Rechner oder im selben WLAN mit eingeschaltetem Handy-Zugriff.

Ohne Mac geht es nicht, Apple lässt keine App ohne Xcode aufs iPhone.

## Installation aufs iPhone

1. Repo laden:
   ```bash
   git clone https://github.com/rabbitfiremediacreation/music-generator-ios.git
   ```
2. `MusicGeneratorRemote.xcodeproj` in Xcode öffnen.
3. Links oben das Projekt anklicken, Reiter **Signing & Capabilities**: bei **Team** deine Apple-ID wählen (beim ersten Mal unter Xcode › Settings › Accounts anmelden). Xcode legt das Signing selbst an.
4. iPhone per Kabel anschließen, oben als Ziel auswählen, **▶︎ Run**.
5. Beim ersten Start sagt das iPhone „Nicht vertrauenswürdiger Entwickler“: Einstellungen › Allgemein › VPN & Geräteverwaltung › deine Apple-ID › Vertrauen. Ab iOS 16 außerdem einmalig den **Entwicklermodus** einschalten (Einstellungen › Datenschutz & Sicherheit › Entwicklermodus), das iPhone fragt danach.
6. Den QR-Code aus dem Music Generator mit der **Kamera-App** des iPhones scannen und auf den Hinweis tippen: Die App öffnet sich mit Adresse und Schlüssel. Alternativ beides von Hand unter *Einstellungen* in der App eintragen.

Wer lieber das Terminal nimmt: [xcodegen](https://github.com/yonaskolb/XcodeGen) erzeugt das Projekt aus `project.yml` (`xcodegen generate`); Team-ID dort eintragen oder in Xcode wählen.

## Von unterwegs

Die App ist fürs Heimnetz gebaut. Für Zugriff von außen eignet sich [Tailscale](https://tailscale.com) auf Mac und iPhone; dann die Tailscale-Adresse des Macs als Server eintragen. Den Handy-Zugriff nie direkt im Router freigeben.

## Aufbau

SwiftUI, iOS 17, keine Abhängigkeiten.

| Datei | Inhalt |
|---|---|
| `APIClient.swift` | Schnittstelle zum Music Generator (`/api/songs`, `/api/generate`, `/api/analyze` …), Bearer-Schlüssel |
| `Library.swift`, `LibraryView.swift` | Bibliothek, Sterne, Ordner, Warteschlange |
| `Player.swift`, `PlayerViews.swift`, `SongActions.swift` | Player, AirPlay, Lautstärke, Laden, Teilen |
| `GenerateView.swift`, `Dice.swift` | Erzeugen mit Würfeln und Reglern |
| `IdeaRecorder.swift`, `RecordButton.swift` | Ideengeber: Aufnahme, Pegel, Tonhöhe, Beschreibung |
| `Downloads.swift` | Songs aufs iPhone (Dateien-App › Music Generator) |
| `SettingsView.swift` | Serveradresse und Schlüssel |
| `Theme.swift` | Farben und Regler wie in der Web-App |

Adresse und Schlüssel bleiben auf dem iPhone und stehen in keinem Log.

## Lizenz

MIT, siehe [LICENSE](LICENSE). Entstanden mit Claude Code.
