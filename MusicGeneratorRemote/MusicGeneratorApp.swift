import SwiftUI

@main
struct MusicGeneratorApp: App {
    @State private var player = Player()
    @State private var library = Library()
    @State private var showPlayer = false

    var body: some Scene {
        WindowGroup {
            TabView {
                LibraryView()
                    .tabItem { Label("Bibliothek", systemImage: "music.note.list") }
                GenerateView()
                    .tabItem { Label("Erzeugen", systemImage: "wand.and.stars") }
                SettingsView()
                    .tabItem { Label("Verbindung", systemImage: "network") }
            }
            .modifier(PlayerBar(showPlayer: $showPlayer))
            .sheet(isPresented: $showPlayer) { FullPlayer() }
            .environment(player)
            .environment(library)
            .tint(.orange)
        }
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
