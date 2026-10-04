import SwiftUI

extension Color {
    init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt64(h, radix: 16) else { return nil }
        self.init(
            red: Double((v >> 16) & 0xff) / 255.0,
            green: Double((v >> 8) & 0xff) / 255.0,
            blue: Double(v & 0xff) / 255.0
        )
    }

    static let moviBackground = Color(red: 0.04, green: 0.04, blue: 0.07)
    static let moviCard = Color(red: 0.10, green: 0.10, blue: 0.14)
    static let moviAccent = Color(red: 0.90, green: 0.16, blue: 0.22)
}

// MARK: - Poster image

struct AsyncPoster: View {
    let url: String?
    let width: CGFloat
    var cornerRadius: CGFloat = 8

    var body: some View {
        Group {
            if let url, let u = URL(string: url) {
                AsyncImage(url: u) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    case .failure:
                        placeholder
                    case .empty:
                        Color.moviCard
                    @unknown default:
                        Color.moviCard
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: width, height: width * 1.5)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    private var placeholder: some View {
        ZStack {
            Color.moviCard
            Image(systemName: "film")
                .foregroundColor(.white.opacity(0.25))
                .font(.title)
        }
    }
}

// MARK: - Cards & rows

struct PosterCard: View {
    let item: HomeItem
    let width: CGFloat = 112

    var body: some View {
        Group {
            if let dest = item.destination {
                NavigationLink(value: dest) {
                    cardContent
                }
            } else {
                cardContent
            }
        }
        .buttonStyle(.plain)
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottom) {
                AsyncPoster(url: item.posterUrl, width: width)
                if let p = item.progress {
                    ProgressView(value: p)
                        .tint(.red)
                        .padding(.horizontal, 6)
                        .padding(.bottom, 6)
                }
            }
            Text(item.title)
                .font(.caption)
                .lineLimit(1)
                .foregroundColor(.white.opacity(0.9))
                .frame(width: width, alignment: .leading)
            if item.kind == "episode", let sn = item.seasonNo, let en = item.episodeNo {
                Text("S\(sn) E\(en)")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
            } else if let y = item.year {
                Text("\(y)")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .frame(width: width)
    }
}

struct HomeRowView: View {
    let row: HomeRow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(row.title)
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(row.items) { item in
                        PosterCard(item: item)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - Backdrop banner

struct BackdropBanner: View {
    let imageUrl: String?
    let height: CGFloat = 300

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let imageUrl, let u = URL(string: imageUrl) {
                    AsyncImage(url: u) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFill()
                        default:
                            Color.moviCard
                        }
                    }
                } else {
                    Color.moviCard
                }
            }
            .frame(height: height)
            .clipped()
            LinearGradient(
                colors: [.clear, .clear, Color.moviBackground.opacity(0.9)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: height)
        }
    }
}
