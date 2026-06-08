import SwiftUI
import AgentPetCore

/// Renders an imported spritesheet pet: cycles its frames and applies the same
/// mood motion and overlays as the built-in pets. Frame rate varies by mood
/// (faster while working) since image packs carry no per-mood data.
struct ImageSpriteView: View {
    /// Frames of the clip bound to the current mood (resolved by the caller).
    let frames: [NSImage]
    let mood: PetMood
    var size: CGFloat = 110
    var isMoving: Bool = false
    var direction: CGFloat = 1
    var isResting: Bool = false
    /// Animation speed multiplier: 1.0 = base rate, higher = faster frames.
    var speedRatio: CGFloat = 1.0

    var body: some View {
        if isResting {
            ZStack {
                MoodAccessories(mood: mood, t: 0, size: size)

                frameImage(at: 0)
                    .rotationEffect(.degrees(0), anchor: .bottom)
                    .scaleEffect(x: direction, y: 1, anchor: .bottom)
                    .offset(y: 0)
            }
            .frame(width: size, height: size)
        } else {
            let effectiveFps = fps * max(speedRatio, 1.0)
            let minInterval = 1.0 / min(effectiveFps * 2, 60.0)
            TimelineView(.animation(minimumInterval: minInterval)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let m = PetMotion.resolve(mood, t, isMoving: isMoving, direction: direction)

                ZStack {
                    MoodAccessories(mood: mood, t: t, size: size)

                    frameImage(at: t)
                        .rotationEffect(.degrees(m.rotation), anchor: .bottom)
                        .scaleEffect(x: m.scaleX, y: m.scaleY, anchor: .bottom)
                        .offset(y: m.offsetY)
                }
                .frame(width: size, height: size)
            }
        }
    }

    @ViewBuilder private func frameImage(at t: Double) -> some View {
        if frames.isEmpty {
            Image(systemName: "pawprint.fill").font(.system(size: 36))
        } else {
            let effectiveFps = fps * speedRatio
            let index = Int(t * effectiveFps) % frames.count
            Image(nsImage: frames[index])
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
        }
    }

    private var fps: Double {
        switch mood {
        case .working, .celebrate: return 8
        case .waiting: return 4
        default: return 3
        }
    }
}
