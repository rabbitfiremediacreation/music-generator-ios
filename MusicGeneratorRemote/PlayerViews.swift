import SwiftUI

/// Leiste über den Tabs; ein Tipp öffnet den großen Player.
struct MiniPlayer: View {
    @Environment(Player.self) private var player
    let compact: Bool   // true = im Zubehör-Feld von iOS 26, das Hintergrund und Rand selbst zeichnet
    let open: () -> Void

    var body: some View {
        if let song = player.current {
            let row = HStack(spacing: 14) {
                Image(systemName: "waveform").foregroundStyle(.orange)
                Text(song.displayTitle).lineLimit(1)
                Spacer()
                Button { player.toggle() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title3)
                }
                Button { player.next() } label: { Image(systemName: "forward.fill") }
            }
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
    @State private var scrubbing: Double?

    var body: some View {
        VStack(spacing: 24) {
            Capsule().fill(.secondary).frame(width: 40, height: 5).padding(.top, 8)
            if let song = player.current {
                Image(systemName: "waveform.circle.fill")
                    .resizable().scaledToFit().frame(width: 160)
                    .foregroundStyle(.orange.gradient)
                    .padding(.top, 24)
                VStack(spacing: 6) {
                    Text(song.displayTitle).font(.title2.bold()).multilineTextAlignment(.center)
                    if song.title?.isEmpty == false {
                        Text(song.caption).font(.subheadline).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center).lineLimit(3)
                    }
                }
                VStack(spacing: 4) {
                    Slider(value: Binding(get: { scrubbing ?? player.position }, set: { scrubbing = $0 }),
                           in: 0...max(player.duration, 1)) { editing in
                        if !editing, let s = scrubbing { player.seek(to: s); scrubbing = nil }
                    }
                    HStack {
                        Text(formatTime(scrubbing ?? player.position))
                        Spacer()
                        Text(formatTime(player.duration))
                    }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                HStack(spacing: 48) {
                    Button { player.previous() } label: { Image(systemName: "backward.fill") }
                    Button { player.toggle() } label: {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 64))
                    }
                    Button { player.next() } label: { Image(systemName: "forward.fill") }
                }
                .font(.title)
                if let error = player.error { Text(error).foregroundStyle(.red).font(.footnote) }
                if let lyrics = song.visibleLyrics {
                    ScrollView { Text(lyrics).font(.callout).frame(maxWidth: .infinity, alignment: .leading) }
                } else {
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 24)
        .presentationDragIndicator(.hidden)
    }
}
