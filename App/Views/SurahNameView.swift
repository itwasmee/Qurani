import SwiftUI
import QuraniKit

/// Canonical Style-B surah name: ringed medallion number + Uthmanic Amiri name
/// with transliteration beneath. Reused by now-playing / mix in later plans.
struct SurahNameView: View {
    let number: Int
    let nameAr: String
    let translit: String
    let tokens: Tokens
    var playing: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .font(.custom("Noto Naskh Arabic", size: 12.5).weight(.bold))
                .frame(width: 26, height: 26)
                .overlay(Circle().stroke(playing ? tokens.accent : tokens.muted.opacity(0.5), lineWidth: 1.4))
                .foregroundStyle(playing ? tokens.accent : tokens.muted)
                .offset(y: 1)   // optical centering (matches mockup padding-top:4px)
            VStack(alignment: .trailing, spacing: 1) {
                Text(nameAr).font(.custom("Amiri Quran", size: 18)).foregroundStyle(tokens.text)
                Text(translit).font(.system(size: 10)).foregroundStyle(tokens.muted)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .environment(\.layoutDirection, .rightToLeft)
            if playing { EqualizerDots(color: tokens.accent) }
        }
    }
}

/// 3-bar bouncing equalizer shown next to the active row / name.
struct EqualizerDots: View {
    let color: Color
    @State private var up = false
    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<3, id: \.self) { i in
                Capsule().fill(color).frame(width: 2.6, height: up ? (i == 1 ? 6 : 12) : (i == 1 ? 12 : 6))
            }
        }
        .frame(height: 13)
        .animation(.easeInOut(duration: 0.5).repeatForever(), value: up)
        .onAppear { up = true }
    }
}
