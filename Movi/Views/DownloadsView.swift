import SwiftUI

struct DownloadsView: View {
    @ObservedObject private var store = DownloadStore.shared
    @State private var playLocal: PlayLocal?

    var body: some View {
        ZStack {
            Color.moviBackground.ignoresSafeArea()
            if store.items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 44))
                        .foregroundColor(.white.opacity(0.3))
                    Text("No downloads yet.")
                        .foregroundColor(.white.opacity(0.6))
                    Text("Tap Download on any movie or episode to watch it offline.")
                        .font(.callout)
                        .foregroundColor(.white.opacity(0.4))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            } else {
                List {
                    ForEach(store.items) { item in
                        DownloadRow(
                            item: item,
                            onTap: {
                                if item.status == .done, let url = item.localURL {
                                    playLocal = PlayLocal(url: url)
                                } else if item.status == .failed {
                                    store.start(kind: item.kind, libraryId: item.libraryId,
                                                title: item.title, posterUrl: item.posterUrl)
                                }
                            },
                            onDelete: { store.delete(item) }
                        )
                        .listRowBackground(Color.moviBackground)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Downloads")
        .navigationBarTitleDisplayMode(.large)
        .fullScreenCover(item: $playLocal) { pl in
            PlayerView(url: pl.url, startAt: 0)
        }
        .alert("Download failed", isPresented: .constant(!store.lastError.isEmpty)) {
            Button("OK") { store.lastError = "" }
        } message: {
            Text(store.lastError)
        }
    }
}

private struct PlayLocal: Identifiable {
    let id = UUID()
    let url: URL
}

private struct DownloadRow: View {
    let item: DownloadItem
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                AsyncPoster(url: item.posterUrl, width: 64, cornerRadius: 6)
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(.headline)
                        .foregroundColor(.white)
                        .lineLimit(2)
                    if item.status == .downloading || item.status == .preparing {
                        ProgressView(value: item.progress)
                            .tint(.moviAccent)
                    }
                    Text(item.statusLabel)
                        .font(.caption)
                        .foregroundColor(item.status == .failed ? .red : .white.opacity(0.55))
                }
                Spacer()
                if item.status == .done {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Download button (detail pages, episode rows)

struct DownloadButton: View {
    let kind: String // "movie" | "episode"
    let libraryId: Int
    let title: String
    let posterUrl: String?
    var compact = false

    @ObservedObject private var store = DownloadStore.shared

    var body: some View {
        let existing = store.item(kind: kind, libraryId: libraryId)
        Button {
            if existing?.status == .failed {
                store.start(kind: kind, libraryId: libraryId, title: title, posterUrl: posterUrl)
            } else if existing == nil {
                store.start(kind: kind, libraryId: libraryId, title: title, posterUrl: posterUrl)
            }
        } label: {
            if compact {
                Image(systemName: icon(for: existing))
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.8))
            } else {
                Label(label(for: existing), systemImage: icon(for: existing))
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .moviGlassCapsule()
            }
        }
        .disabled(existing != nil && existing?.status != .failed)
    }

    private func icon(for existing: DownloadItem?) -> String {
        switch existing?.status {
        case .done: return "checkmark.circle.fill"
        case .failed: return "arrow.clockwise"
        case .preparing, .downloading: return "arrow.down.circle"
        case nil: return "arrow.down.circle"
        }
    }

    private func label(for existing: DownloadItem?) -> String {
        switch existing?.status {
        case .done: return "Downloaded"
        case .failed: return "Retry"
        case .preparing: return "Preparing…"
        case .downloading: return "Downloading…"
        case nil: return "Download"
        }
    }
}
