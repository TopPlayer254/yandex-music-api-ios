import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var downloads: DownloadsStore
    @State private var query = ""
    @State private var showsAccount = false

    var body: some View {
        NavigationStack {
            List(catalog.searchResults) { track in
                TrackRow(
                    track: track,
                    isDownloaded: downloads.isDownloaded(track),
                    isDownloading: downloads.activeTrackIDs.contains(track.id),
                    play: { Task { await player.play(track, queue: catalog.searchResults) } },
                    toggleDownload: {
                        Task {
                            if downloads.isDownloaded(track) { await downloads.remove(track) }
                            else { await downloads.download(track, quality: player.preferredQuality) }
                        }
                    }
                )
            }
            .listStyle(.plain)
            .navigationTitle("Поиск")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Артисты, треки и альбомы")
            .onChange(of: query) { _, newValue in catalog.scheduleSearch(newValue) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    AccountToolbarButton(isPresented: $showsAccount)
                }
            }
            .sheet(isPresented: $showsAccount) { AccountView() }
            .overlay {
                if catalog.isSearching {
                    SearchLoadingPlaceholder()
                } else if query.isEmpty {
                    ContentUnavailableView("Найдите свою музыку", systemImage: "magnifyingglass", description: Text("Ищите по треку, артисту или альбому."))
                } else if catalog.searchResults.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
    }
}

private struct SearchLoadingPlaceholder: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0 ..< 5, id: \.self) { _ in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(.quaternary)
                        .frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Название трека")
                        Text("Исполнитель · Альбом").font(.subheadline)
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 7)
            }
        }
        .redacted(reason: .placeholder)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(uiColor: .systemBackground))
        .accessibilityLabel("Поиск музыки")
    }
}
