import SwiftUI

/// Leiste über den Tabs; ein Tipp öffnet den großen Player.
struct MiniPlayer: View {
    @Environment(Player.self) private var player
    let compact: Bool   // true = im Zubehör-Feld von iOS 26, das Hintergrund und Rand selbst zeichnet
    let open: () -> Void

    var body: some View {
        if let song = player.current {
            let row = HStack(spacing: 16) {
                Image(systemName: "waveform").foregroundStyle(Theme.gold)
                Text(song.displayTitle).lineLimit(1)
                Spacer()
                StarButton(song: song, size: 17)
                Button { player.toggle() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title3)
                }
                Button { player.next() } label: { Image(systemName: "forward.fill") }
            }
            .foregroundStyle(Theme.text)
            .padding(.horizontal)
            .contentShape(Rectangle())
            .onTapGesture(perform: open)

            if compact {
                row
            } else {
                VStack(spacing: 0) {
                    ProgressView(value: player.duration > 0 ? min(player.position / player.duration, 1) : 0)
                    row.padding(.vertical, 10)
                }
                .background(.bar)
            }
        }
    }
}

struct FullPlayer: View {
    @Environment(Player.self) private var player
    @Environment(Library.self) private var library
    @State private var scrubbing: Double?
    @State private var newFolderFor: Song?

    var body: some View {
        VStack(spacing: 22) {
            Capsule().fill(Theme.border).frame(width: 40, height: 5).padding(.top, 8)
            if let song = player.current {
                Image(systemName: "waveform.circle.fill")
                    .resizable().scaledToFit().frame(width: 150)
                    .foregroundStyle(Theme.brand.gradient)
                    .padding(.top, 16)
                VStack(spacing: 6) {
                    Text(song.displayTitle).font(.title2.bold()).multilineTextAlignment(.center)
                    if song.title?.isEmpty == false {
                        Text(song.caption).font(.subheadline).foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center).lineLimit(3)
                    }
                }
                rating(song)
                BubbleSlider(value: Binding(get: { scrubbing ?? player.position }, set: { scrubbing = $0 }),
                             range: 0...max(player.duration, 1), label: "Position",
                             text: { formatTime($0) }) { editing in
                    if !editing, let s = scrubbing { player.seek(to: s); scrubbing = nil }
                }
                HStack(spacing: 48) {
                    Button { player.previous() } label: { Image(systemName: "backward.fill") }
                    Button { player.toggle() } label: {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 66)).foregroundStyle(Theme.logoText)
                    }
                    Button { player.next() } label: { Image(systemName: "forward.fill") }
                }
                .font(.title)
                .foregroundStyle(Theme.text)
                VolumeBar()
                HStack(spacing: 12) {
                    AirPlayButton()
                        .frame(width: 54, height: 40)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
                        .accessibilityLabel("Auf Gerät im Netzwerk abspielen")
                    DownloadButton(song: song)
                    ShareButton(song: song)
                }
                if let error = player.error { Text(error).foregroundStyle(.red).font(.footnote) }
                if let lyrics = song.visibleLyrics {
                    ScrollView {
                        Text(lyrics).font(.callout).foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .presentationDragIndicator(.hidden)
        .newFolderAlert(for: $newFolderFor)
    }

    /// Stern und Ordner nebeneinander: beim Hören gleich sortieren.
    private func rating(_ song: Song) -> some View {
        HStack(spacing: 12) {
            StarButton(song: song, size: 26)
                .frame(width: 54, height: 40)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(song.favorite ? Theme.gold : Theme.border))
            Menu {
                FolderMenuItems(song: song, newFolderFor: $newFolderFor)
            } label: {
                Label(library.folderName(song.folder_id), systemImage: "folder")
                    .lineLimit(1)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
            }
            .accessibilityLabel("Ordner: \(library.folderName(song.folder_id)), verschieben")
        }
    }
}
