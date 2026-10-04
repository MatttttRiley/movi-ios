import SwiftUI

// MARK: - Liquid Glass (iOS 26+), graceful fallback on older iOS
//
// The app compiles against the iOS 26 SDK but keeps a deployment target of
// iOS 16. Every glass surface below checks availability at runtime and falls
// back to a translucent material on older systems.

/// Groups glass elements so they merge like liquid (iOS 26+).
/// Falls back to plain content on older iOS; the caller owns layout.
struct MoviGlassGroup<Content: View>: View {
    let spacing: CGFloat
    let content: Content

    init(spacing: CGFloat = 10, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

extension View {
    /// Glass capsule chrome for secondary buttons (My List, Download, …).
    /// The label keeps its own padding/font; this only swaps the chrome.
    @ViewBuilder
    func moviGlassCapsule() -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            self.background(Color.white.opacity(0.15), in: Capsule())
        }
    }

    /// Red-tinted glass chrome for the primary Play button.
    @ViewBuilder
    func moviPlayChrome() -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular.tint(.moviAccent).interactive(),
                             in: .rect(cornerRadius: 12))
        } else {
            self.background(Color.moviAccent,
                            in: RoundedRectangle(cornerRadius: 8))
        }
    }

    /// Glass panel for cards/sheets. Falls back to ultra-thin material.
    @ViewBuilder
    func moviGlassPanel(cornerRadius: CGFloat = 16) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.ultraThinMaterial,
                            in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}
