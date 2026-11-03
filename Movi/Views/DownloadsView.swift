import SwiftUI

struct DownloadsView: View {
    @ObservedObject private var store = DownloadStore.shared
    @State private var playLocal: PlayLocal?

    var body: some View {
        Group {
            if store.items.isEmpty {
                if #available(iOS 17, *) {
                    ContentUnavailableView(
                        "No Downloads Yet",
                        systemImage: "arrow.down.circle",
                        description: Text("Tap Download on any movie or episode to watch it offline.")
                    )
                } else {
                    Text("No downloads yet. Tap Download on any movie or episode to watch it offline.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
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
                                    store.retry(item)
                                }
                            },
                            onDelete: { store.delete(item) }
                        )
                    }
                }
                .listStyle(.plain)
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
                AsyncPoster(url: item.posterUrl, width: 64, cornerRadius: 6, accessibilityLabel: item.title)
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(2)
                    if item.status == .downloading || item.status == .preparing {
                        ProgressView(value: item.progress)
                            .tint(.moviAccent)
                    }
                    Text(item.statusLabel)
                        .font(.caption)
                        .foregroundStyle(item.status == .failed ? .red : .secondary)
                }
                Spacer()
                if item.status == .done {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
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
        .accessibilityLabel("\(item.title), \(item.statusLabel)")
    }
}

// MARK: - Download button (detail pages, episode rows)

struct DownloadButton: View {
    let kind: String // "movie" | "episode"
    let libraryId: Int
    let title: String
    let posterUrl: String?
    let streamUrl: String?
    var compact = false

    @ObservedObject private var store = DownloadStore.shared

    var body: some View {
        let existing = store.item(kind: kind, libraryId: libraryId)
        Button {
            if existing?.status == .failed {
                store.retry(existing!)
            } else if existing == nil {
                store.start(kind: kind, libraryId: libraryId, title: title, posterUrl: posterUrl, streamUrl: streamUrl)
            }
        } label: {
            if compact {
                Image(systemName: icon(for: existing))
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, minHeight: 44)
            } else {
                Label(label(for: existing), systemImage: icon(for: existing))
            }
        }
        .buttonStyle(compact ? .plain : .bordered)
        .disabled((existing != nil && existing?.status != .failed) || streamUrl == nil || streamUrl?.isEmpty == true)
        .accessibilityLabel(label(for: existing) + " " + title)
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
