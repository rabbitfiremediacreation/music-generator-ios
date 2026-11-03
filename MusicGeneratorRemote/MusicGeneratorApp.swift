import SwiftUI

enum AppTab: Hashable { case library, generate, connection }

@main
struct MusicGeneratorApp: App {
    @State private var player = Player()
    @State private var library = Library()
    @State private var showPlayer = false
    @State private var tab = AppTab.library

    var body: some Scene {
        WindowGroup {
            TabView(selection: $tab) {
                LibraryView()
                    .tabItem { Label("Bibliothek", systemImage: "music.note.list") }
                    .tag(AppTab.library)
                GenerateView()
                    .tabItem { Label("Erzeugen", systemImage: "wand.and.stars") }
                    .tag(AppTab.generate)
                SettingsView()
                    .tabItem { Label("Verbindung", systemImage: "network") }
                    .tag(AppTab.connection)
            }
            .modifier(PlayerBar(showPlayer: $showPlayer))
            .sheet(isPresented: $showPlayer) { FullPlayer() }
            .onOpenURL { url in Task { await connect(url) } }
            .onAppear { library.onSongChanged = { [player] in player.refresh($0) } }
            .environment(player)
            .environment(library)
            .tint(Theme.brand)
            .preferredColorScheme(.dark)
        }
    }

    /// QR-Code aus der Web-App (Setup → Handy-Zugriff), mit der Kamera gescannt:
    /// übernimmt Schlüssel und die erste erreichbare Adresse (Name im Heimnetz, sonst IP).
    @MainActor
    private func connect(_ url: URL) async {
        guard url.scheme == "musicgenerator", url.host == "connect",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let token = items.first(where: { $0.name == "token" })?.value else { return }
        let candidates = ["server", "alt"].compactMap { name in items.first { $0.name == name }?.value }
        let d = UserDefaults.standard
        d.set(token, forKey: "token")
        var reached = false
        for server in candidates {
            d.set(server, forKey: "server")
            if (try? await APIClient.current.folders()) != nil { reached = true; break }
        }
        if !reached, let first = candidates.first { d.set(first, forKey: "server") }   // zum Nachbessern unter „Verbindung“
        await library.reload()
        tab = reached ? .library : .connection
    }
}

/// Ab iOS 26 sitzt die Abspielleiste als Zubehör über der Tab-Leiste, davor als Einschub am unteren Rand.
private struct PlayerBar: ViewModifier {
    @Environment(Player.self) private var player
    @Binding var showPlayer: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: player.current != nil) {
                MiniPlayer(compact: true) { showPlayer = true }
            }
        } else {
            content.safeAreaInset(edge: .bottom) {
                if player.current != nil {
                    MiniPlayer(compact: false) { showPlayer = true }.padding(.bottom, 52)
                }
            }
        }
    }
}
