import SwiftUI

// MARK: - Design tokens (HIG: semantic colors, system type, real touch targets)
//
// No forced dark mode, no fixed font sizes, no white-on-dark text baked
// into every view. Views use system colors and text styles so Dynamic
// Type, Bold Text, Increase Contrast and both appearances just work.
// The single brand accent is used consistently; error red is reserved
// for actual errors, never for progress or decoration.

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

    static let moviAccent = Color(red: 0.90, green: 0.16, blue: 0.22)
}

// MARK: - Poster image

struct AsyncPoster: View {
    let url: String?
    let width: CGFloat
    var cornerRadius: CGFloat = 8
    var accessibilityLabel: String = "Poster"

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
                        Color(.secondarySystemBackground)
                    @unknown default:
                        Color(.secondarySystemBackground)
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: width, height: width * 1.5)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .accessibilityLabel(accessibilityLabel)
    }

    private var placeholder: some View {
        ZStack {
            Color(.secondarySystemBackground)
            Image(systemName: "film")
                .foregroundStyle(.secondary)
                .font(.title3)
        }
    }
}

// MARK: - Cards & rows

struct PosterCard: View {
    let item: TitleItem
    let kind: String
    let width: CGFloat = 112

    var body: some View {
        NavigationLink(value: Destination(kind: kind, id: item.id)) {
            cardContent
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottom) {
                AsyncPoster(url: item.poster, width: width, accessibilityLabel: item.title)
                if let p = item.progressFraction {
                    ProgressView(value: p)
                        .tint(.moviAccent)
                        .padding(.horizontal, 6)
                        .padding(.bottom, 6)
                }
            }
            Text(item.title)
                .font(.caption)
                .lineLimit(1)
                .frame(width: width, alignment: .leading)
            if let y = item.year {
                Text("\(y)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: width)
    }
}

struct HomeRowView: View {
    let title: String
    let items: [TitleItem]
    let kind: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(items) { item in
                        PosterCard(item: item, kind: kind)
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
    let fallbackPosterUrl: String?
    let height: CGFloat

    init(imageUrl: String?, fallbackPosterUrl: String?, height: CGFloat = 300) {
        self.imageUrl = imageUrl
        self.fallbackPosterUrl = fallbackPosterUrl
        self.height = height
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let imageUrl, let u = URL(string: imageUrl) {
                    AsyncImage(url: u) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFill()
                        default:
                            blurredFallback
                        }
                    }
                } else {
                    blurredFallback
                }
            }
            .frame(height: height)
            .clipped()
            LinearGradient(
                colors: [.clear, Color(.systemBackground).opacity(0.15), Color(.systemBackground).opacity(0.95)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: height)
        }
    }

    /// When a title has no backdrop, blur its poster behind the header
    /// instead of showing a flat empty card (the old hero bug).
    private var blurredFallback: some View {
        Group {
            if let fallbackPosterUrl, let u = URL(string: fallbackPosterUrl) {
                AsyncImage(url: u) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill().blur(radius: 24)
                    default:
                        Color(.secondarySystemBackground)
                    }
                }
            } else {
                Color(.secondarySystemBackground)
            }
        }
    }
}

// MARK: - Standard error / empty states (HIG: ContentUnavailableView)

struct ErrorStateView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Try Again", action: retry)
                .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
